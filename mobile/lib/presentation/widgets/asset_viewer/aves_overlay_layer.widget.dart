import 'dart:async';
import 'dart:ui' as ui;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/aves_media_metadata.model.dart';
import 'package:immich_mobile/infrastructure/repositories/unified_media_aves.repository.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/aves_histogram.widget.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/providers/aves_overlay.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

/// Aves 式查看器叠加层。
///
/// 它**不是**一个整屏遮罩，而是一组浮在照片上的半透明胶囊/卡片：
/// 顶部信息、右上小地图、右侧缩放倍率、底部胶片条、以及可选的直方图。
/// 每一项都由「叠加层」设置单独控制，全部关掉就是纯净看图。
class AvesAssetOverlay extends ConsumerWidget {
  final BaseAsset asset;
  final int index;
  final int total;
  final double zoom;

  /// 底部胶片条要显示的素材（可空，为空则不渲染胶片条）。
  final List<BaseAsset>? filmstripAssets;
  final ValueChanged<int>? onFilmstripTap;

  /// [filmstripAssets] 在整条时间线里的起始下标。
  /// 胶片条只取当前页前后一小段，所以列表下标和绝对下标不是一回事。
  final int filmstripStart;

  /// 由外部控制显隐（点按画面切换）。
  final bool visible;

  /// 底部额外留白，用来避开查看器自带的底栏。
  final double bottomPadding;

  const AvesAssetOverlay({
    super.key,
    required this.asset,
    required this.index,
    required this.total,
    required this.zoom,
    this.filmstripAssets,
    this.onFilmstripTap,
    this.filmstripStart = 0,
    this.visible = true,
    this.bottomPadding = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(avesOverlayProvider);
    final meta = ref.watch(avesAssetMetadataProvider(asset)).valueOrNull;
    final safeTop = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    final showFilmstrip = settings.showFilmstrip && (filmstripAssets?.isNotEmpty ?? false);
    final bottomInset =
        (showFilmstrip ? 78.0 + safeBottom : 16.0 + safeBottom) + bottomPadding;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Stack(
          children: [
            if (settings.showInfo ||
                settings.effectiveShootingDetails ||
                settings.effectiveDescription)
              Positioned(
                top: safeTop + 8,
                left: 12,
                right: 12,
                child: _OverlayInfoCard(
                  asset: asset,
                  meta: meta,
                  index: index,
                  total: total,
                  showInfo: settings.showInfo,
                  showShootingDetails: settings.effectiveShootingDetails,
                  showRatingAndTags: settings.effectiveRatingAndTags,
                  showDescription: settings.effectiveDescription,
                ),
              ),

            if (settings.showMiniMap && (meta?.hasValidGps ?? false))
              Positioned(
                top: safeTop + 8,
                right: 12,
                child: _OverlayMiniMap(meta: meta!, asset: asset),
              ),

            if (settings.showZoomLevel)
              Positioned(
                right: 12,
                bottom: bottomInset + 8,
                child: _OverlayGlassPill(
                  child: Text(
                    '${(zoom * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),

            if (settings.histogram != AvesHistogramMode.none)
              Positioned(
                left: 12,
                bottom: bottomInset + 8,
                child: _OverlayGlassCard(
                  padding: const EdgeInsets.all(6),
                  child: AvesHistogram(asset: asset, mode: settings.histogram),
                ),
              ),

            if (showFilmstrip)
              Positioned(
                left: 0,
                right: 0,
                bottom: safeBottom + 10 + bottomPadding,
                child: AvesOverlayFilmstrip(
                  assets: filmstripAssets!,
                  currentIndex: index - filmstripStart,
                  onTap: onFilmstripTap == null
                      ? null
                      : (localIndex) => onFilmstripTap!(localIndex + filmstripStart),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 顶部信息卡：序号 + 文件名 / 日期 + 分辨率 / 拍摄参数 / 地点 / 描述。
class _OverlayInfoCard extends StatelessWidget {
  final BaseAsset asset;
  final AvesMediaMetadata? meta;
  final int index;
  final int total;
  final bool showInfo;
  final bool showShootingDetails;
  final bool showRatingAndTags;
  final bool showDescription;

  const _OverlayInfoCard({
    required this.asset,
    required this.meta,
    required this.index,
    required this.total,
    required this.showInfo,
    required this.showShootingDetails,
    required this.showRatingAndTags,
    required this.showDescription,
  });

  @override
  Widget build(BuildContext context) {
    final date = asset.createdAt.toLocal();
    final dateText = DateFormat('yyyy年M月d日 · HH:mm').format(date);

    // 拍摄参数按 Aves 的排版挤在一行：f/2.4  1/833  2.6 mm  ISO51
    final shootingParts = <String>[
      if (meta?.fNumber != null) meta!.fNumber!,
      if (meta?.exposureTime != null) meta!.exposureTime!,
      if (meta?.focalLength != null) meta!.focalLength!,
      if (meta?.iso != null && meta!.iso! > 0) 'ISO${meta!.iso}',
    ];

    final resolution = meta?.formattedResolution ??
        (asset.width != null && asset.height != null ? '${asset.width} × ${asset.height}' : null);

    final location = meta?.formattedLocationName ??
        [meta?.city, meta?.state, meta?.country].whereType<String>().where((e) => e.isNotEmpty).join('，');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _OverlayGlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showInfo) ...[
                  Row(
                    children: [
                      Text(
                        '${index + 1}/$total',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          asset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.white54),
                      const SizedBox(width: 5),
                      Text(
                        dateText,
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                      if (resolution != null) ...[
                        const SizedBox(width: 10),
                        Text(
                          resolution,
                          style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                        ),
                      ],
                    ],
                  ),
                ],
                if (showShootingDetails && shootingParts.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.camera_rounded, size: 12, color: Colors.white54),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          shootingParts.join('   '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ],
                if (showInfo && location.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.place_rounded, size: 12, color: Colors.white54),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ],
                if (showRatingAndTags && (asset.isFavorite || (meta?.rating ?? 0) > 0)) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (asset.isFavorite) ...[
                        const Icon(Icons.favorite_rounded, size: 12, color: Color(0xFFFF7A8B)),
                        const SizedBox(width: 4),
                        const Text('已收藏', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                        const SizedBox(width: 10),
                      ],
                      if ((meta?.rating ?? 0) > 0)
                        for (var i = 0; i < 5; i++)
                          Icon(
                            i < (meta?.rating ?? 0) ? Icons.star_rounded : Icons.star_border_rounded,
                            size: 12,
                            color: i < (meta?.rating ?? 0) ? const Color(0xFFFFC857) : Colors.white38,
                          ),
                    ],
                  ),
                ],
                if (showDescription && (meta?.description?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 6),
                  Text(
                    meta!.description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ),
        // 右上角留给小地图，信息卡不铺满整行。
        if (meta?.hasValidGps ?? false) const SizedBox(width: 76),
      ],
    );
  }
}

/// 小地图占位：Aves 这里是一张真地图贴图，嵌入式地图在查看器里代价太高，
/// 所以做成「定位胶囊」——显示城市名，点一下进全屏地图。
class _OverlayMiniMap extends StatelessWidget {
  final AvesMediaMetadata meta;
  final BaseAsset asset;

  const _OverlayMiniMap({required this.meta, required this.asset});

  @override
  Widget build(BuildContext context) {
    final label = meta.city?.isNotEmpty == true
        ? meta.city!
        : (meta.state?.isNotEmpty == true ? meta.state! : '地图');

    return GestureDetector(
      onTap: () => unawaited(
        context.pushRoute(MapRoute(initialLocation: LatLng(meta.latitude!, meta.longitude!))),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.map_outlined, size: 30, color: Colors.white.withValues(alpha: 0.22)),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.place_rounded, size: 16, color: Color(0xFFFF7A8B)),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部胶片条（Aves「显示缩略图」）。
class AvesOverlayFilmstrip extends StatelessWidget {
  final List<BaseAsset> assets;
  final int currentIndex;
  final ValueChanged<int>? onTap;

  static const double _itemExtent = 46;

  const AvesOverlayFilmstrip({
    super.key,
    required this.assets,
    required this.currentIndex,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (assets.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: _itemExtent + 16,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: assets.length,
        itemBuilder: (context, i) {
          final selected = i == currentIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
            child: GestureDetector(
              onTap: onTap == null ? null : () => onTap!(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _itemExtent,
                height: _itemExtent,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white.withValues(alpha: 0.18),
                    width: selected ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Thumbnail.fromAsset(asset: assets[i], fit: BoxFit.cover),
                    if (assets[i].isVideo)
                      const Center(
                        child: Icon(Icons.play_circle_fill_rounded, size: 16, color: Colors.white70),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 统一的「深色磨砂小卡片」。
class _OverlayGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _OverlayGlassCard({required this.child, this.padding = const EdgeInsets.fromLTRB(11, 9, 11, 9)});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.40),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _OverlayGlassPill extends StatelessWidget {
  final Widget child;

  const _OverlayGlassPill({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.40),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: child,
        ),
      ),
    );
  }
}
