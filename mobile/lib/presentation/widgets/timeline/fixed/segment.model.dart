import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.page.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail_tile.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/fixed/row.dart';
import 'package:immich_mobile/presentation/widgets/timeline/header.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/segment.model.dart';
import 'package:immich_mobile/presentation/widgets/timeline/segment_builder.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.state.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline_drag_region.dart';
import 'package:immich_mobile/providers/asset_viewer/is_motion_video_playing.provider.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/infrastructure/current_album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:intl/intl.dart';

class FixedSegment extends Segment {
  final double tileHeight;
  final int columnCount;
  final double mainAxisExtend;
  final AvesTileLayout tileLayout;
  final double maxWidth;

  const FixedSegment({
    required super.firstIndex,
    required super.lastIndex,
    required super.startOffset,
    required super.endOffset,
    required super.firstAssetIndex,
    required super.bucket,
    required this.tileHeight,
    required this.columnCount,
    this.tileLayout = AvesTileLayout.mosaic,
    this.maxWidth = 0,
    required super.headerExtent,
    required super.spacing,
    required super.header,
  }) : assert(tileHeight != 0),
       mainAxisExtend = tileHeight + spacing;

  @override
  double indexToLayoutOffset(int index) {
    final relativeIndex = index - gridIndex;
    return relativeIndex < 0 ? startOffset : gridOffset + (mainAxisExtend * relativeIndex);
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    final adjustedOffset = scrollOffset - gridOffset;
    if (!adjustedOffset.isFinite || adjustedOffset < 0) {
      return firstIndex;
    }
    return gridIndex + (adjustedOffset / mainAxisExtend).floor();
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    final adjustedOffset = scrollOffset - gridOffset;
    if (!adjustedOffset.isFinite || adjustedOffset < 0) {
      return firstIndex;
    }
    return gridIndex + (adjustedOffset / mainAxisExtend).ceil() - 1;
  }

  @override
  Widget builder(BuildContext context, int index) {
    final rowIndexInSegment = index - (firstIndex + 1);
    final assetIndex = rowIndexInSegment * columnCount;
    final assetCount = bucket.assetCount;
    final numberOfAssets = math.min(columnCount, assetCount - assetIndex);

    if (index == firstIndex) {
      if (header == HeaderType.none || headerExtent <= 0) {
        return const SizedBox.shrink();
      }
      return TimelineHeader(bucket: bucket, header: header, height: headerExtent, assetOffset: firstAssetIndex);
    }

    return _FixedSegmentRow(
      assetIndex: firstAssetIndex + assetIndex,
      assetCount: numberOfAssets,
      tileHeight: tileHeight,
      spacing: spacing,
      columnCount: columnCount,
      tileLayout: tileLayout,
      maxWidth: maxWidth,
    );
  }
}

class _FixedSegmentRow extends ConsumerWidget {
  final int assetIndex;
  final int assetCount;
  final double tileHeight;
  final double spacing;
  final int columnCount;
  final AvesTileLayout tileLayout;
  final double maxWidth;

  const _FixedSegmentRow({
    required this.assetIndex,
    required this.assetCount,
    required this.tileHeight,
    required this.spacing,
    required this.columnCount,
    required this.tileLayout,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timelineService = ref.watch(timelineServiceProvider);
    final hasCustomSort = ref.watch(
      avesSettingsProvider.select(
        (s) => s.sortMode != AvesSortMode.byDate || s.isSortAscending || s.titleSearchQuery.isNotEmpty,
      ),
    );

    if (timelineService.hasRange(assetIndex, assetCount)) {
      var assets = timelineService.getAssets(assetIndex, assetCount);
      if (hasCustomSort) {
        assets = ref.read(avesSettingsProvider).sortAssets(assets);
      }
      return _buildAssetRow(context, assets, timelineService);
    }

    // Purposefully created outside of the FutureBuilder so it's created only once
    late final assetsFuture = timelineService.loadAssets(assetIndex, assetCount);
    return _DeferredRowLoader(
      key: ValueKey(assetIndex),
      placeholder: _buildPlaceholder,
      builder: (context) => FutureBuilder<List<BaseAsset>>(
        future: assetsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData) {
            return _buildPlaceholder(context);
          }
          var assets = snapshot.requireData;
          if (hasCustomSort) {
            assets = ref.read(avesSettingsProvider).sortAssets(assets);
          }
          return _buildAssetRow(context, assets, timelineService);
        },
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final effectiveW = maxWidth > 0 ? maxWidth : MediaQuery.sizeOf(context).width;
    final cellW = tileLayout == AvesTileLayout.list
        ? effectiveW
        : (effectiveW - spacing * (columnCount - 1)) / columnCount;
    return SegmentBuilder.buildPlaceholder(
      context,
      tileLayout == AvesTileLayout.list ? 1 : assetCount,
      size: Size(cellW, tileHeight),
      spacing: spacing,
    );
  }

  Widget _buildAssetRow(
    BuildContext context,
    List<BaseAsset> assets,
    TimelineService timelineService,
  ) {
    if (assets.isEmpty) {
      return SizedBox(height: tileHeight);
    }

    final effectiveRowWidth = maxWidth > 0 ? maxWidth : MediaQuery.sizeOf(context).width;

    // Aves List Layout (single column with thumbnail on left and metadata on right)
    if (tileLayout == AvesTileLayout.list) {
      final asset = assets.first;
      return TimelineDragRegion(
        child: TimelineRow(
          height: tileHeight,
          widths: [effectiveRowWidth],
          spacing: spacing,
          textDirection: Directionality.of(context),
          children: [
            TimelineAssetIndexWrapper(
              assetIndex: assetIndex,
              segmentIndex: 0,
              child: _AvesListAssetTile(
                key: ValueKey(Object.hash(asset.heroTag, assetIndex, 'list')),
                asset: asset,
                assetIndex: assetIndex,
                rowWidth: effectiveRowWidth,
                rowHeight: tileHeight,
              ),
            ),
          ],
        ),
      );
    }

    final baseCellWidth = (effectiveRowWidth - spacing * (columnCount - 1)) / columnCount;
    final widths = List<double>.filled(assets.length, baseCellWidth);

    // Aves Mosaic Layout: Justified aspect-ratio distribution
    if (tileLayout == AvesTileLayout.mosaic) {
      if (columnCount == 1) {
        widths[0] = effectiveRowWidth;
      } else {
        final aspectRatios = assets.map((e) {
          final w = (e.width ?? 0) > 0 ? e.width!.toDouble() : 4.0;
          final h = (e.height ?? 0) > 0 ? e.height!.toDouble() : 3.0;
          return (w / h).clamp(0.48, 2.35);
        }).toList();

        final availableRowWidth = effectiveRowWidth - spacing * (assets.length - 1);
        final sumRatios = aspectRatios.sum;

        if (assets.length == columnCount && sumRatios > 0) {
          // Full row: distribute 100% of availableRowWidth proportionally by aspect ratio
          for (int i = 0; i < assets.length; i++) {
            widths[i] = availableRowWidth * (aspectRatios[i] / sumRatios);
          }
        } else {
          // Trailing partial row: size by natural aspect ratio, scaled down only if exceeding row width
          final naturalWidths = aspectRatios.map((ar) => tileHeight * ar).toList();
          final naturalSum = naturalWidths.sum;
          if (naturalSum > availableRowWidth && naturalSum > 0) {
            for (int i = 0; i < assets.length; i++) {
              widths[i] = availableRowWidth * (naturalWidths[i] / naturalSum);
            }
          } else {
            for (int i = 0; i < assets.length; i++) {
              widths[i] = naturalWidths[i];
            }
          }
        }
      }
    }

    final children = [
      for (int i = 0; i < assets.length; i++)
        TimelineAssetIndexWrapper(
          assetIndex: assetIndex + i,
          segmentIndex: 0,
          child: _AssetTileWidget(
            key: ValueKey(Object.hash(assets[i].heroTag, assetIndex + i, timelineService.hashCode)),
            asset: assets[i],
            assetIndex: assetIndex + i,
            size: Size(widths[i], tileHeight),
          ),
        ),
    ];

    return TimelineDragRegion(
      child: TimelineRow(
        height: tileHeight,
        widths: widths,
        spacing: spacing,
        textDirection: Directionality.of(context),
        children: children,
      ),
    );
  }
}

/// Lock to displaying placeholders while the timeline is quickly scrolling
class _DeferredRowLoader extends ConsumerStatefulWidget {
  final WidgetBuilder placeholder;
  final WidgetBuilder builder;

  const _DeferredRowLoader({super.key, required this.placeholder, required this.builder});

  @override
  ConsumerState<_DeferredRowLoader> createState() => _DeferredRowLoaderState();
}

class _DeferredRowLoaderState extends ConsumerState<_DeferredRowLoader> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && ref.watch(timelineStateProvider.select((state) => state.recommendDeferredLoading))) {
      return widget.placeholder(context);
    }

    _isLoading = true;
    return widget.builder(context);
  }
}

String? _detectAvesFormatBadge(BaseAsset asset) {
  if (asset.isMotionPhoto) {
    return 'LIVE';
  }
  final name = asset.name;
  final dotIdx = name.lastIndexOf('.');
  if (dotIdx == -1 || dotIdx == name.length - 1) {
    return null;
  }
  final ext = name.substring(dotIdx + 1).toUpperCase();
  return switch (ext) {
    'DNG' || 'CR2' || 'CR3' || 'NEF' || 'ARW' || 'ORF' || 'RW2' || 'RAF' => 'RAW',
    'HEIC' || 'HEIF' || 'JXL' => 'HDR',
    'AVIF' => 'AVIF',
    'GIF' => 'GIF',
    'SVG' => 'SVG',
    'TIF' || 'TIFF' => 'TIFF',
    _ => null,
  };
}

class _AssetTileWidget extends ConsumerWidget {
  final BaseAsset asset;
  final int assetIndex;
  final Size size;

  const _AssetTileWidget({super.key, required this.asset, required this.assetIndex, required this.size});

  Future _handleOnTap(
    BuildContext ctx,
    WidgetRef ref,
    int assetIndex,
    BaseAsset asset,
    int? heroOffset,
    Size remoteSize,
  ) async {
    final multiSelectState = ref.read(multiSelectProvider);

    if (multiSelectState.forceEnable || multiSelectState.isEnabled) {
      ref.read(multiSelectProvider.notifier).toggleAssetSelection(asset);
    } else {
      await ref.read(timelineServiceProvider).loadAssets(assetIndex, 1);
      if (!ctx.mounted) {
        return;
      }

      ref.read(isPlayingMotionVideoProvider.notifier).playing = false;
      AssetViewer.setAsset(ref, asset, thumbnailSize: remoteSize);
      unawaited(
        ctx.pushRoute(
          AssetViewerRoute(
            initialIndex: assetIndex,
            timelineService: ref.read(timelineServiceProvider),
            heroOffset: heroOffset,
            currentAlbum: ref.read(currentRemoteAlbumProvider),
          ),
        ),
      );
    }
  }

  void _handleOnLongPress(WidgetRef ref, BaseAsset asset) {
    final multiSelectState = ref.read(multiSelectProvider);
    if (multiSelectState.isEnabled || multiSelectState.forceEnable) {
      return;
    }

    ref.read(hapticFeedbackProvider.notifier).heavyImpact();
    ref.read(multiSelectProvider.notifier).toggleAssetSelection(asset);
  }

  bool _getLockSelectionStatus(WidgetRef ref) {
    final lockSelectionAssets = ref.read(multiSelectProvider.select((state) => state.lockedSelectionAssets));

    if (lockSelectionAssets.isEmpty) {
      return false;
    }

    return lockSelectionAssets.any((a) => a == asset);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remoteSize = size * MediaQuery.devicePixelRatioOf(context);
    final heroOffset = TabsRouterScope.of(context)?.controller.activeIndex ?? 0;

    final lockSelection = _getLockSelectionStatus(ref);
    final showStorageIndicator = ref.watch(timelineArgsProvider.select((args) => args.showStorageIndicator));
    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);
    final showStackIndicator = ref.watch(timelineServiceProvider).origin != TimelineOrigin.trash;
    final showBadges = ref.read(avesSettingsProvider).showHdrAndFormatBadges;
    final badgeLabel = showBadges && size.width >= 68 ? _detectAvesFormatBadge(asset) : null;

    Widget tile = ThumbnailTile(
      asset,
      remoteSize: remoteSize,
      lockSelection: lockSelection,
      showStorageIndicator: showStorageIndicator,
      showStackIndicator: showStackIndicator,
      heroOffset: heroOffset,
    );

    if (badgeLabel != null) {
      tile = Stack(
        fit: StackFit.expand,
        children: [
          tile,
          Positioned(
            left: 5,
            bottom: 5,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 0.8),
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => lockSelection ? null : _handleOnTap(context, ref, assetIndex, asset, heroOffset, remoteSize),
        onLongPress: () => lockSelection || isReadonlyModeEnabled ? null : _handleOnLongPress(ref, asset),
        child: tile,
      ),
    );
  }
}

/// Aves-style single-column detailed List Row (Left thumbnail + Right metadata)
class _AvesListAssetTile extends ConsumerWidget {
  final BaseAsset asset;
  final int assetIndex;
  final double rowWidth;
  final double rowHeight;

  const _AvesListAssetTile({
    super.key,
    required this.asset,
    required this.assetIndex,
    required this.rowWidth,
    required this.rowHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbWidth = math.min(rowWidth * 0.45, rowHeight * 1.22);
    final thumbSize = Size(thumbWidth, rowHeight);
    final remoteSize = thumbSize * MediaQuery.devicePixelRatioOf(context);
    final heroOffset = TabsRouterScope.of(context)?.controller.activeIndex ?? 0;
    final showStorageIndicator = ref.watch(timelineArgsProvider.select((args) => args.showStorageIndicator));
    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);

    final dateStr = DateFormat('yyyy年MM月dd日 • HH:mm').format(asset.createdAt.toLocal());
    final ext = asset.name.contains('.') ? asset.name.split('.').last.toUpperCase() : (asset.isVideo ? 'VIDEO' : 'IMG');
    final dimStr = (asset.width != null && asset.height != null && asset.width! > 0)
        ? '${asset.width} × ${asset.height} • $ext'
        : ext;

    return RepaintBoundary(
      child: Material(
        color: context.colorScheme.surface,
        child: InkWell(
          onTap: () async {
            final multiSelectState = ref.read(multiSelectProvider);
            if (multiSelectState.forceEnable || multiSelectState.isEnabled) {
              ref.read(multiSelectProvider.notifier).toggleAssetSelection(asset);
              return;
            }
            await ref.read(timelineServiceProvider).loadAssets(assetIndex, 1);
            if (!context.mounted) {
              return;
            }
            ref.read(isPlayingMotionVideoProvider.notifier).playing = false;
            AssetViewer.setAsset(ref, asset, thumbnailSize: remoteSize);
            unawaited(
              context.pushRoute(
                AssetViewerRoute(
                  initialIndex: assetIndex,
                  timelineService: ref.read(timelineServiceProvider),
                  heroOffset: heroOffset,
                  currentAlbum: ref.read(currentRemoteAlbumProvider),
                ),
              ),
            );
          },
          onLongPress: isReadonlyModeEnabled
              ? null
              : () {
                  final multiSelectState = ref.read(multiSelectProvider);
                  if (multiSelectState.isEnabled || multiSelectState.forceEnable) {
                    return;
                  }
                  ref.read(hapticFeedbackProvider.notifier).heavyImpact();
                  ref.read(multiSelectProvider.notifier).toggleAssetSelection(asset);
                },
          child: SizedBox(
            width: rowWidth,
            height: rowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: thumbWidth,
                  height: rowHeight,
                  child: ThumbnailTile(
                    asset,
                    remoteSize: remoteSize,
                    showStorageIndicator: showStorageIndicator,
                    showStackIndicator: true,
                    heroOffset: heroOffset,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          asset.name,
                          maxLines: rowHeight >= 110 ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 13,
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                dateStr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: context.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.data_usage_rounded,
                              size: 13,
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                dimStr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: context.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (asset.isFavorite)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.favorite_rounded, size: 14, color: Colors.redAccent),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
