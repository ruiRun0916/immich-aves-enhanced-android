import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/pages/aves_statistics.page.dart';
import 'package:immich_mobile/presentation/widgets/search/advanced_filter_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/search/album_filter_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/tag/tag_explorer.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/aves_control_bar.widget.dart';
import 'package:immich_mobile/providers/album_media_filter.provider.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';
import 'package:immich_mobile/providers/search/advanced_filter.provider.dart';

/// 综合浏览 / 服务器图库 / 本地图库
enum GalleryBrowseMode {
  unified(label: '综合浏览', shortLabel: '全部', icon: Icons.dynamic_feed_rounded),
  serverOnly(label: '服务器图库', shortLabel: '云端', icon: Icons.cloud_outlined),
  localGallery(label: '本地图库', shortLabel: '本地', icon: Icons.smartphone_rounded);

  final String label;

  /// 筛选栏里的极短标签 —— Aves 的 FilterBar 只用一两个汉字，
  /// 长标签会把整行撑满，那就又不是 Aves 了。
  final String shortLabel;
  final IconData icon;
  const GalleryBrowseMode({required this.label, required this.shortLabel, required this.icon});
}

final galleryBrowseModeProvider = StateProvider<GalleryBrowseMode>((ref) => GalleryBrowseMode.unified);

/// Aves 风格顶栏底栏（模式切换 + 布局胶囊栏）
///
/// 抄自 Aves `lib/widgets/collection/app_bar.dart` 的 `AvesAppBar(bottom: ...)`：
/// Aves 把「筛选栏 + LayoutBar + QueryBar」全部塞进**同一个** SliverPersistentHeader
/// 的 `bottom`，配合 `floating: true` → 反向滑动时整条一起浮回来。
///
/// 这里把它接到 Immich 的 `ImmichSliverAppBar.bottom` 上，并额外开启 snap，
/// 于是「下滑任意距离 → 松开 → 整条顶部栏瞬间弹出」，与 Aves 观感一致。
class AvesTimelineHeaderBottom extends ConsumerWidget implements PreferredSizeWidget {
  final double height;
  final GalleryBrowseMode browseMode;
  final AvesHeaderScope scope;

  /// 相册场景下用于「相册内筛选」的相册 ID（远程相册 id 或本地相册 id）
  final String? albumId;

  const AvesTimelineHeaderBottom({
    super.key,
    required this.height,
    required this.browseMode,
    this.scope = AvesHeaderScope.timeline,
    this.albumId,
  });

  /// Aves `LayoutBar.preferredHeight = AvesFilterChip.minChipHeight(48) + padding.vertical(12)`，
  /// 此处沿用「固定行高」策略，避免内容天然高度与 preferredSize 不一致导致溢出。
  static const double _chipsRowHeight = 56;
  static const double _controlBarHeight = 50;
  static const double _titleSearchHeight = 48;

  static double computeHeight(AvesViewSettings settings) {
    return _chipsRowHeight + _controlBarHeight + (settings.showTitleSearchBar ? _titleSearchHeight : 0);
  }

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: height,
      child: Column(
        children: [
          SizedBox(
            height: _chipsRowHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: scope.isAlbum
                  ? _AvesAlbumScopeChips(albumId: albumId, scope: scope)
                  : _AvesModeChips(browseMode: browseMode),
            ),
          ),
          // 标题搜索框由 AvesTimelineControlBar 自己渲染（Aves 的 QueryBar 等价物），
          // 这里用 Expanded 把它顶满剩余高度，不做二次包裹。
          Expanded(
            child: AvesTimelineControlBar(currentModeKey: scope.isAlbum ? 'album' : browseMode.name, scope: scope),
          ),
        ],
      ),
    );
  }
}

/// Aves `FilterBar` 等价物。
///
/// Aves 的筛选栏是一行**紧凑胶囊**（图标 + 极短文字，选中态用描边高亮），
/// 而不是 Immich 原来那种占满整行的 Material ChoiceChip。
/// 这里按 Aves 的密度重做：`[全部] [云端] [本地] [筛选·n]`，
/// 四个胶囊加起来通常只占屏幕六成宽。
class _AvesModeChips extends ConsumerWidget {
  final GalleryBrowseMode browseMode;

  const _AvesModeChips({required this.browseMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeFilter = ref.watch(advancedMediaFilterProvider);
    final filterCount = activeFilter.activeFilterCount;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          for (final mode in GalleryBrowseMode.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _AvesFilterPill(
                icon: mode.icon,
                label: mode.shortLabel,
                selected: browseMode == mode,
                onTap: () => ref.read(galleryBrowseModeProvider.notifier).state = mode,
              ),
            ),
          _AvesFilterPill(
            icon: Icons.tune_rounded,
            label: filterCount > 0 ? '筛选 · $filterCount' : '筛选',
            selected: filterCount > 0,
            onTap: () => openAdvancedFilterBrowser(context, openSheetImmediately: activeFilter.isEmpty),
          ),
        ],
      ),
    );
  }
}

/// 相册内的 chips 行。
///
/// 不再堆一排「标签 / 统计 / 自定义」（这些在 ⋮ 菜单里都有），
/// 只留**当前相册的筛选入口**——这才是 Aves 相册页顶部那行该有的东西。
class _AvesAlbumScopeChips extends ConsumerWidget {
  final String? albumId;
  final AvesHeaderScope scope;

  const _AvesAlbumScopeChips({required this.albumId, required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = albumId ?? '';
    // 远程相册的筛选是纯客户端内存过滤（albumAssetsProvider），可以直接生效；
    // 本地 MediaStore 相册走的是另一条分页查询，暂未接就地筛选，
    // 所以这里不放一个按了没反应的死按钮。
    final supportsFilter = scope == AvesHeaderScope.album;
    final filter = supportsFilter ? ref.watch(albumMediaFilterProvider(key)) : AdvancedMediaFilter.empty;
    final activeCount = filter.activeFilterCount;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (supportsFilter) ...[
            _AvesFilterPill(
              icon: Icons.filter_alt_outlined,
              label: activeCount > 0 ? '筛选 · $activeCount' : '筛选',
              selected: activeCount > 0,
              onTap: () => unawaited(showAlbumFilterSheet(context, ref, albumId: key)),
            ),
            if (activeCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _AvesFilterPill(
                  icon: Icons.filter_alt_off_rounded,
                  label: '清除',
                  selected: false,
                  onTap: () => ref.read(albumMediaFilterProvider(key).notifier).state = AdvancedMediaFilter.empty,
                ),
              ),
            const SizedBox(width: 6),
          ],
          _AvesFilterPill(
            icon: Icons.sell_outlined,
            label: '标签',
            selected: false,
            onTap: () => unawaited(openTagExplorerScreen(context)),
          ),
          const SizedBox(width: 6),
          _AvesFilterPill(
            icon: Icons.pie_chart_outline_rounded,
            label: '统计',
            selected: false,
            onTap: () => unawaited(openAvesStatisticsScreen(context)),
          ),
        ],
      ),
    );
  }
}

/// 一个紧凑的筛选胶囊：高度 34、圆角 17、描边、选中态用主色描边 + 淡填充。
/// 尺寸比 `_AvesDualIconPill`（38）还小一号，跟 Aves `FilterBar` 的观感对齐。
class _AvesFilterPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AvesFilterPill({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.10) : scheme.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline.withValues(alpha: 0.5),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(
                label,
                style: context.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
