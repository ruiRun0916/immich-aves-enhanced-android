import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/actions/action.dart';
import 'package:immich_mobile/presentation/actions/delete.action.dart';
import 'package:immich_mobile/presentation/actions/edit_asset.action.dart';
import 'package:immich_mobile/presentation/actions/favorite.action.dart';
import 'package:immich_mobile/presentation/actions/restore.action.dart';
import 'package:immich_mobile/presentation/actions/share.action.dart';
import 'package:immich_mobile/presentation/actions/tag.action.dart';
import 'package:immich_mobile/presentation/actions/upload.action.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/add_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/ocr_toggle_button.widget.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/asset_viewer/video_controls.dart';
import 'package:immich_ui/immich_ui.dart';

List<Widget> _actionColumnButtons(BuildContext context, WidgetRef ref, List<ActionBuilder> actions) => actions
    .map((a) => a.create(context, ref))
    .nonNulls
    .map<ImmichColumnButton>(
      (item) => .new(icon: item.icon, label: item.label, onPressed: item.onAction, onLongPress: item.onSecondaryAction),
    )
    .toList(growable: false);

class ViewerBottomBar extends ConsumerStatefulWidget {
  const ViewerBottomBar({super.key});

  @override
  ConsumerState<ViewerBottomBar> createState() => _ViewerBottomBarState();
}

class _ViewerBottomBarState extends ConsumerState<ViewerBottomBar> {
  bool _isLandscapeForced = false;

  Future<void> _toggleOrientation() async {
    _isLandscapeForced = !_isLandscapeForced;
    if (_isLandscapeForced) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  @override
  void dispose() {
    if (_isLandscapeForced) {
      unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = ref.watch(assetViewerProvider.select((s) => s.currentAsset));
    if (asset == null) {
      return const SizedBox.shrink();
    }

    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);
    final showingDetails = ref.watch(assetViewerProvider.select((s) => s.showingDetails));
    final isInLockedView = ref.watch(inLockedViewProvider);
    final isInTrash = ref.watch(timelineServiceProvider).origin == TimelineOrigin.trash;
    final visibleActions = ref.watch(avesSettingsProvider.select((s) => s.visibleViewerActions));

    final originalTheme = context.themeData;

    final actions = <Widget>[];
    if (isInTrash) {
      actions.addAll(
        _actionColumnButtons(context, ref, const [
          RestoreAction(source: .viewer),
          ShareAction(source: .viewer),
          DeleteAction(source: .viewer),
        ]),
      );
    } else if (isInLockedView) {
      actions.addAll(
        _actionColumnButtons(context, ref, const [
          ShareAction(source: .viewer),
          DeleteAction(source: .viewer),
        ]),
      );
    } else {
      for (final act in visibleActions) {
        switch (act) {
          case AvesViewerAction.edit:
            actions.addAll(_actionColumnButtons(context, ref, const [EditAssetAction(source: .viewer)]));
          case AvesViewerAction.rotateScreen:
            actions.add(
              ImmichColumnButton(
                icon: Icons.screen_rotation_outlined,
                label: '旋转',
                onPressed: _toggleOrientation,
              ),
            );
          case AvesViewerAction.favorite:
            actions.addAll(_actionColumnButtons(context, ref, const [FavoriteAction(source: .viewer)]));
          case AvesViewerAction.addToAlbum:
            if (asset.hasRemote) {
              actions.add(ImmichColorOverride(color: null, child: AddActionButton(originalTheme: originalTheme)));
            }
          case AvesViewerAction.share:
            actions.addAll(_actionColumnButtons(context, ref, const [ShareAction(source: .viewer)]));
          case AvesViewerAction.delete:
            actions.addAll(_actionColumnButtons(context, ref, const [DeleteAction(source: .viewer)]));
          case AvesViewerAction.tag:
            if (asset.hasRemote) {
              actions.addAll(_actionColumnButtons(context, ref, const [TagAction(source: .viewer)]));
            }
          case AvesViewerAction.map:
            actions.add(
              ImmichColumnButton(
                icon: Icons.map_outlined,
                label: '地图',
                onPressed: () => context.pushRoute(MapRoute()),
              ),
            );
          case AvesViewerAction.metadata:
            actions.add(
              ImmichColumnButton(
                icon: Icons.info_outline_rounded,
                label: '信息',
                onPressed: () => ref.read(assetViewerProvider.notifier).setShowingDetails(true),
              ),
            );
          case AvesViewerAction.upload:
            actions.addAll(
              _actionColumnButtons(context, ref, const [UploadAction(source: .viewer, showProgress: true)]),
            );
          case AvesViewerAction.copyLink:
            actions.addAll(_actionColumnButtons(context, ref, const [ShareAction(source: .viewer)]));
        }
      }
    }

    return AnimatedSwitcher(
      duration: Durations.short4,
      child: showingDetails
          ? const SizedBox.shrink()
          : Theme(
              data: context.themeData.copyWith(
                iconTheme: const IconThemeData(size: ImmichIconSize.md, color: Colors.white),
                textTheme: context.themeData.textTheme.copyWith(
                  labelLarge: context.themeData.textTheme.labelLarge?.copyWith(color: Colors.white),
                ),
              ),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black54, Colors.black26, Colors.transparent],
                            stops: [0.0, 0.7, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (asset.isImage) OcrToggleButton(asset: asset),
                          if (asset.isVideo) VideoControls(videoPlayerName: asset.id),
                          if (!isReadonlyModeEnabled)
                            ImmichColorOverride(
                              color: Colors.white,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    for (final w in actions)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: w,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
