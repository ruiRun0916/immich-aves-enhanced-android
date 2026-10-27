import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';

class _PinchPreviewState {
  final Offset focalPoint;
  final double currentExtent;
  final double minExtent;
  final double maxExtent;
  final int previewColumns;
  final AvesTileLayout layout;

  const _PinchPreviewState({
    required this.focalPoint,
    required this.currentExtent,
    required this.minExtent,
    required this.maxExtent,
    required this.previewColumns,
    required this.layout,
  });
}

/// High-fps decoupled pinch-to-zoom gesture detector & scale overlay.
///
/// Performance architecture:
/// 1. Uses a clean scale gesture recognizer that never interferes with single-finger vertical scroll physics.
/// 2. During active multi-finger pinch (`pointerCount >= 2`), shows a lightweight floating indicator pill.
/// 3. Zero full-screen raster repaints or heavy radial gradients during gesture.
/// 4. Commits the final column count (1 to 8) / row height on gesture release and preserves scroll anchor.
class TimelinePinchZoom extends ConsumerStatefulWidget {
  const TimelinePinchZoom({
    super.key,
    required this.onColumnCountWillChange,
    required this.child,
  });

  final VoidCallback onColumnCountWillChange;
  final Widget child;

  @override
  ConsumerState<TimelinePinchZoom> createState() => _TimelinePinchZoomState();
}

class _TimelinePinchZoomState extends ConsumerState<TimelinePinchZoom> {
  double _startExtent = 100.0;
  double _minExtent = 48.0;
  double _maxExtent = 400.0;
  bool _isPinching = false;
  ValueNotifier<_PinchPreviewState>? _previewNotifier;
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry
      ?..remove()
      ..dispose();
    _overlayEntry = null;
    _previewNotifier?.dispose();
    _previewNotifier = null;
    _isPinching = false;
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (details.pointerCount < 2) {
      return;
    }
    final avesSettings = ref.read(avesSettingsProvider);
    if (avesSettings.tileLayout == AvesTileLayout.calendar) {
      return;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth <= 0) {
      return;
    }

    _isPinching = true;
    if (avesSettings.tileLayout == AvesTileLayout.list) {
      _minExtent = 72.0;
      _maxExtent = 220.0;
      _startExtent = avesSettings.listRowExtent;
    } else {
      // Zooming from 8 columns up to 1 column (100% full screen width)
      _minExtent = screenWidth / 8.0;
      _maxExtent = screenWidth;
      final currentCols = avesSettings.columnCount.clamp(1, 8);
      _startExtent = screenWidth / currentCols;
    }

    final initialState = _PinchPreviewState(
      focalPoint: details.focalPoint,
      currentExtent: _startExtent,
      minExtent: _minExtent,
      maxExtent: _maxExtent,
      previewColumns: avesSettings.tileLayout == AvesTileLayout.list
          ? 1
          : (screenWidth / _startExtent).round().clamp(1, 8),
      layout: avesSettings.tileLayout,
    );

    _previewNotifier = ValueNotifier(initialState);
    _overlayEntry = OverlayEntry(
      builder: (ctx) => _AvesPinchScaleOverlay(notifier: _previewNotifier!),
    );
    Overlay.maybeOf(context)?.insert(_overlayEntry!);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      if (_isPinching) {
        _removeOverlay();
      }
      return;
    }

    final notifier = _previewNotifier;
    if (!_isPinching || notifier == null) {
      if ((details.scale - 1.0).abs() > 0.04) {
        _onScaleStart(
          ScaleStartDetails(
            focalPoint: details.focalPoint,
            localFocalPoint: details.localFocalPoint,
            pointerCount: details.pointerCount,
          ),
        );
      }
      return;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final scaledExtent = (_startExtent * details.scale).clamp(_minExtent, _maxExtent);
    final previewCols = notifier.value.layout == AvesTileLayout.list
        ? 1
        : (screenWidth / scaledExtent).round().clamp(1, 8);

    notifier.value = _PinchPreviewState(
      focalPoint: details.focalPoint,
      currentExtent: scaledExtent,
      minExtent: _minExtent,
      maxExtent: _maxExtent,
      previewColumns: previewCols,
      layout: notifier.value.layout,
    );
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final notifier = _previewNotifier;
    if (!_isPinching || notifier == null) {
      _removeOverlay();
      return;
    }

    final finalState = notifier.value;
    _removeOverlay();

    final avesNotifier = ref.read(avesSettingsProvider.notifier);
    final currentSettings = ref.read(avesSettingsProvider);

    if (finalState.layout == AvesTileLayout.list) {
      if ((finalState.currentExtent - currentSettings.listRowExtent).abs() > 2.0) {
        widget.onColumnCountWillChange();
        avesNotifier.setListRowExtent(finalState.currentExtent);
      }
    } else {
      final newCols = finalState.previewColumns.clamp(1, 8);
      if (newCols != currentSettings.columnCount) {
        widget.onColumnCountWillChange();
        avesNotifier.setColumnCount(newCols);
        unawaited(ref.read(settingsProvider).write(.timelineTilesPerRow, newCols));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        _CustomScaleGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_CustomScaleGestureRecognizer>(
              () => _CustomScaleGestureRecognizer(debugOwner: this),
              (_CustomScaleGestureRecognizer scale) {
                scale
                  ..onStart = _onScaleStart
                  ..onUpdate = _onScaleUpdate
                  ..onEnd = _onScaleEnd
                  ..dragStartBehavior = DragStartBehavior.start;
              },
            ),
      },
      child: widget.child,
    );
  }
}

class _CustomScaleGestureRecognizer extends ScaleGestureRecognizer {
  _CustomScaleGestureRecognizer({super.debugOwner});

  @override
  void rejectGesture(int pointer) {
    acceptGesture(pointer);
  }
}

class _AvesPinchScaleOverlay extends StatelessWidget {
  final ValueNotifier<_PinchPreviewState> notifier;

  const _AvesPinchScaleOverlay({required this.notifier});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: ValueListenableBuilder<_PinchPreviewState>(
          valueListenable: notifier,
          builder: (context, state, _) {
            final String badgeText;
            if (state.layout == AvesTileLayout.list) {
              badgeText = '列表高度 · ${state.currentExtent.round()} px';
            } else if (state.previewColumns == 1) {
              badgeText = '1 列 · 单图满屏横宽 (100%)';
            } else {
              badgeText = '${state.previewColumns} 列 · ${state.layout.label}视图';
            }

            return SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(state.layout.icon, size: 20, color: primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          badgeText,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
