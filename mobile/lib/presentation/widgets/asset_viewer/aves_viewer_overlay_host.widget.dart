import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/aves_overlay_layer.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/aves_viewer_bridge.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/aves_overlay.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';

/// 把 Aves 叠加层挂到 Immich 查看器上。
///
/// 它读三样东西：当前资产（`assetViewerProvider`）、当前页序号（时间线服务）、
/// 实时缩放倍率（`avesViewerZoomProvider`），然后把渲染完全交给 [AvesAssetOverlay]。
/// 打开「相片详情」时整层隐藏，避免和详情面板打架。
class AvesViewerOverlayHost extends ConsumerStatefulWidget {
  const AvesViewerOverlayHost({super.key});

  @override
  ConsumerState<AvesViewerOverlayHost> createState() => _AvesViewerOverlayHostState();
}

class _AvesViewerOverlayHostState extends ConsumerState<AvesViewerOverlayHost> {
  /// 「打开时显示」关掉后，叠加层默认不出场；用户点一下画面才唤出来。
  bool _revealedByUser = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(avesOverlayProvider);
    final state = ref.watch(assetViewerProvider);
    final asset = state.currentAsset;

    ref.listen(assetViewerProvider.select((s) => s.showingControls), (_, next) {
      if (next && !_revealedByUser) {
        setState(() => _revealedByUser = true);
      }
    });

    if (asset == null || state.showingDetails) {
      return const SizedBox.shrink();
    }

    final service = ref.watch(timelineServiceProvider);
    final index = service.getIndex(asset.heroTag) ?? 0;
    final total = service.totalAssets;
    final strip = ref.watch(avesFilmstripProvider(index)).valueOrNull;

    final visible = state.showingControls && (settings.showOnOpen || _revealedByUser);

    return ValueListenableBuilder<double>(
      valueListenable: ref.watch(avesViewerZoomProvider),
      builder: (context, zoom, _) => AvesAssetOverlay(
        asset: asset,
        index: index,
        total: total,
        zoom: zoom,
        filmstripAssets: strip?.assets,
        filmstripStart: strip?.start ?? 0,
        onFilmstripTap: AvesViewerJumpBus.available ? AvesViewerJumpBus.jumpTo : null,
        visible: visible,
        // 查看器自带一条底栏（约 76），叠加层整体抬起来避让。
        bottomPadding: 76,
      ),
    );
  }
}
