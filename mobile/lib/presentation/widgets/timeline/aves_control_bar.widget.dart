import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/pages/aves_statistics.page.dart';
import 'package:immich_mobile/presentation/widgets/common/aves_blurred_surface.widget.dart';
import 'package:immich_mobile/presentation/widgets/settings/aves_customization_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/tag/tag_explorer.widget.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/routing/router.dart';

/// 顶栏出现的场景。相册页里「分区 · 按相册」无意义，需要按场景裁剪。
enum AvesHeaderScope {
  /// 主时间线（综合浏览 / 服务器图库 / 本地图库）
  timeline,

  /// 服务器相册详情页
  album,

  /// 本地相册（MediaStore 文件夹）详情页
  localAlbum;

  bool get isAlbum => this != AvesHeaderScope.timeline;
}

/// Shows the Aves "布局 (Layout)" modal dialog matching Screenshot_2026-10-26-00-00-17
Future<void> showAvesLayoutDialog(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final settings = ref.watch(avesSettingsProvider);
        final notifier = ref.read(avesSettingsProvider.notifier);

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Center(
            child: Text('布局', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(height: 1),
              for (final layout in AvesTileLayout.values)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: Icon(
                    settings.tileLayout == layout ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: settings.tileLayout == layout ? ctx.colorScheme.primary : ctx.colorScheme.outline,
                  ),
                  title: Text(layout.label),
                  trailing: Icon(layout.icon, color: ctx.colorScheme.onSurfaceVariant),
                  onTap: () {
                    notifier.setTileLayout(layout);
                    Navigator.of(ctx).pop();
                  },
                ),
              if (settings.tileLayout != AvesTileLayout.calendar && settings.tileLayout != AvesTileLayout.list) ...[
                const Divider(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.zoom_out_map_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          settings.columnCount == 1 ? '当前缩放：1 列 (单图全屏横宽)' : '当前列数：${settings.columnCount} 列 (支持双指自由缩放)',
                          style: ctx.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                Slider(
                  value: settings.columnCount.toDouble(),
                  min: 1,
                  max: 8,
                  divisions: 7,
                  label: settings.columnCount == 1 ? '1 列 (全屏横宽)' : '${settings.columnCount} 列',
                  onChanged: (v) => notifier.setColumnCount(v.round()),
                ),
              ],
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消'))],
        );
      },
    ),
  );
}

/// Shows the Aves "排序 (Sort)" modal dialog matching Screenshot_2026-10-26-00-00-19
Future<void> showAvesSortDialog(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final settings = ref.watch(avesSettingsProvider);
        final notifier = ref.read(avesSettingsProvider.notifier);

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Center(
            child: Text('排序', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(height: 1),
              for (final sort in AvesSortMode.values)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: Icon(
                    settings.sortMode == sort ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: settings.sortMode == sort ? ctx.colorScheme.primary : ctx.colorScheme.outline,
                  ),
                  title: Text(sort.label),
                  trailing: Icon(sort.icon, color: ctx.colorScheme.onSurfaceVariant),
                  onTap: () {
                    notifier.setSortMode(sort);
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消'))],
        );
      },
    ),
  );
}

/// Shows the Aves "分区 (Section)" modal dialog matching Screenshot_2026-10-26-00-00-22
Future<void> showAvesSectionDialog(
  BuildContext context,
  WidgetRef ref, {
  AvesHeaderScope scope = AvesHeaderScope.timeline,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final settings = ref.watch(avesSettingsProvider);
        final notifier = ref.read(avesSettingsProvider.notifier);
        // 相册内部不能再按「相册」分区，否则会渲染成所有相册的卡片墙
        final options = AvesSectionMode.values
            .where((mode) => scope.isAlbum == false || mode != AvesSectionMode.byAlbum)
            .toList(growable: false);

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Center(
            child: Text('分区', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(height: 1),
              for (final sec in options)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: Icon(
                    settings.sectionMode == sec ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: settings.sectionMode == sec ? ctx.colorScheme.primary : ctx.colorScheme.outline,
                  ),
                  title: Text(sec.label),
                  trailing: Icon(sec.icon, color: ctx.colorScheme.onSurfaceVariant),
                  onTap: () {
                    notifier.setSectionMode(sec);
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消'))],
        );
      },
    ),
  );
}

/// Aves Top Layout Control Pill Bar (`[↕] [布局 · 马赛克] [排序 · 日期] [分区 · 不区分]`)
///
/// Matches `Screenshot_2026-10-26-00-00-11` and `Screenshot_2026-10-26-00-19-33`.
class AvesTimelineControlBar extends ConsumerStatefulWidget {
  final String currentModeKey;
  final AvesHeaderScope scope;

  const AvesTimelineControlBar({super.key, this.currentModeKey = 'unified', this.scope = AvesHeaderScope.timeline});

  @override
  ConsumerState<AvesTimelineControlBar> createState() => _AvesTimelineControlBarState();
}

class _AvesTimelineControlBarState extends ConsumerState<AvesTimelineControlBar> {
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: ref.read(avesSettingsProvider).titleSearchQuery);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(avesSettingsProvider);
    final notifier = ref.read(avesSettingsProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (settings.showLayoutControlBar)
          // 严格对齐 Aves `LayoutBar`：`padding: EdgeInsets.only(top: 4, bottom: 8)` +
          // 行内 horizontal 4，胶囊各自独立浮着，外面**没有**统一的浮岛底板。
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  // 1. Sort Direction Toggle Circle ([↕])
                  _AvesCircleActionPill(
                    tooltip: settings.isSortAscending ? '当前：升序 (从旧到新)' : '当前：降序 (从新到旧)',
                    icon: settings.isSortAscending ? Icons.north_rounded : Icons.swap_vert_rounded,
                    isActive: settings.isSortAscending,
                    onTap: notifier.toggleSortDirection,
                  ),
                  const SizedBox(width: 8),

                  // 2. Layout Pill ([布局 · 马赛克/网格/列表/日历])
                  _AvesDualIconPill(
                    leftIcon: Icons.grid_view_rounded,
                    rightIcon: settings.tileLayout.icon,
                    onTap: () => showAvesLayoutDialog(context, ref),
                  ),
                  const SizedBox(width: 8),

                  // 3. Sort Pill ([排序 · 日期/标题/大小...])
                  _AvesDualIconPill(
                    leftIcon: Icons.sort_rounded,
                    rightIcon: settings.sortMode.icon,
                    label: settings.sortMode.label.replaceFirst('按', ''),
                    onTap: () => showAvesSortDialog(context, ref),
                  ),
                  const SizedBox(width: 8),

                  // 4. Section Pill ([分区 · 按天/按月/按相册/不区分])
                  _AvesDualIconPill(
                    leftIcon: Icons.view_agenda_outlined,
                    rightIcon: settings.sectionMode.icon,
                    onTap: () => showAvesSectionDialog(context, ref, scope: widget.scope),
                  ),
                  const SizedBox(width: 8),

                  // 5. Quick Column Zoom Cycle Pill (1 col full width <-> 4 col)
                  if (settings.tileLayout != AvesTileLayout.calendar && settings.tileLayout != AvesTileLayout.list)
                    _AvesDualIconPill(
                      leftIcon: Icons.aspect_ratio_rounded,
                      rightIcon: settings.columnCount == 1 ? Icons.crop_original_rounded : Icons.apps_rounded,
                      label: settings.columnCount == 1 ? '1列满屏' : '${settings.columnCount}列',
                      onTap: notifier.cycleColumnCount,
                    ),
                  const SizedBox(width: 8),

                  // 6. Panoramic Statistics Quick Entry (matching Aves pie/globe top icon)
                  _AvesCircleActionPill(
                    tooltip: '全景统计图表',
                    icon: Icons.pie_chart_outline_rounded,
                    onTap: () => openAvesStatisticsScreen(context),
                  ),
                  const SizedBox(width: 6),

                  // 7. Aves Overflow Menu (matching Screenshot_2026-10-26-00-00-24)
                  _AvesOverflowMenuButton(currentModeKey: widget.currentModeKey, scope: widget.scope),
                ],
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: notifier.toggleLayoutControlBar,
                  icon: const Icon(Icons.grid_view_rounded, size: 15),
                  label: Text('${settings.tileLayout.label} · ${settings.sectionMode.label} (显示布局栏)'),
                ),
                _AvesOverflowMenuButton(currentModeKey: widget.currentModeKey, scope: widget.scope),
              ],
            ),
          ),

        // Optional Title Quick Search Bar ("显示标题搜索框")
        if (settings.showTitleSearchBar)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            child: TextField(
              controller: _titleController,
              onChanged: notifier.setTitleSearchQuery,
              decoration: InputDecoration(
                isDense: true,
                hintText: '按文件名或标题实时筛选...',
                prefixIcon: const Icon(Icons.filter_alt_outlined, size: 18),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (settings.titleSearchQuery.isNotEmpty)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _titleController.clear();
                          notifier.setTitleSearchQuery('');
                        },
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '隐藏标题搜索框',
                      icon: const Icon(Icons.visibility_off_outlined, size: 18),
                      onPressed: notifier.toggleTitleSearchBar,
                    ),
                  ],
                ),
                filled: true,
                fillColor: context.colorScheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
          ),
      ],
    );
  }
}

class _AvesCircleActionPill extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _AvesCircleActionPill({required this.tooltip, required this.icon, this.isActive = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 38,
          decoration: BoxDecoration(
            color: isActive
                ? context.colorScheme.primaryContainer
                : context.colorScheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isActive ? context.colorScheme.primary : context.colorScheme.outline.withValues(alpha: 0.55),
              width: 1.1,
            ),
          ),
          child: Icon(
            icon,
            size: 19,
            color: isActive ? context.colorScheme.onPrimaryContainer : context.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Aves `LayoutBar` 里的胶囊：`[类别图标 · 当前值]`。
/// 当前值可以是图标（布局 / 分区），也可以是文字（排序）——
/// Aves 只在排序上显示文字，其余两项都是纯图标，所以整排比 Immich 原版窄很多。
class _AvesDualIconPill extends StatelessWidget {
  final IconData leftIcon;
  final IconData rightIcon;
  final String? label;
  final VoidCallback onTap;

  const _AvesDualIconPill({required this.leftIcon, required this.rightIcon, this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.colorScheme.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colorScheme.outline.withValues(alpha: 0.55), width: 1.1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(leftIcon, size: 17, color: context.colorScheme.onSurface),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Container(
                width: 3.5,
                height: 3.5,
                decoration: BoxDecoration(color: context.colorScheme.onSurfaceVariant, shape: BoxShape.circle),
              ),
            ),
            Icon(rightIcon, size: 17, color: context.colorScheme.primary),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(label!, style: context.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Matches Aves 3-dot menu (`更改布局`, `选择`, `隐藏布局栏`, `显示标题搜索框`, `设置为首页`, `地图`, `全景统计`, `自定义设置`)
class _AvesOverflowMenuButton extends ConsumerWidget {
  final String currentModeKey;
  final AvesHeaderScope scope;

  const _AvesOverflowMenuButton({required this.currentModeKey, this.scope = AvesHeaderScope.timeline});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(avesSettingsProvider);
    final notifier = ref.read(avesSettingsProvider.notifier);

    return PopupMenuButton<String>(
      tooltip: '更多 Aves 视图选项',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (value) {
        switch (value) {
          case 'layout':
            unawaited(showAvesLayoutDialog(context, ref));
          case 'select':
            final ms = ref.read(multiSelectProvider);
            if (ms.forceEnable || ms.isEnabled) {
              ref.read(multiSelectProvider.notifier).reset();
            } else {
              ref.read(multiSelectProvider.notifier).setForceEnable(true);
            }
          case 'toggle_layout_bar':
            notifier.toggleLayoutControlBar();
          case 'toggle_title_search':
            notifier.toggleTitleSearchBar();
          case 'set_home':
            notifier.setDefaultHomeMode(currentModeKey);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已将当前视图设置为默认首页'), duration: Duration(seconds: 2)));
          case 'stats':
            unawaited(openAvesStatisticsScreen(context));
          case 'map':
            unawaited(context.pushRoute(MapRoute()));
          case 'customize':
            unawaited(openAvesCustomizationScreen(context));
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'layout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.dashboard_customize_outlined),
            title: Text('更改布局'),
          ),
        ),
        const PopupMenuItem(
          value: 'select',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.select_all_rounded),
            title: Text('选择项目'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'toggle_layout_bar',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(settings.showLayoutControlBar ? Icons.grid_off_rounded : Icons.grid_on_rounded),
            title: Text(settings.showLayoutControlBar ? '隐藏布局栏' : '显示布局栏'),
          ),
        ),
        PopupMenuItem(
          value: 'toggle_title_search',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.filter_alt_outlined),
            title: Text(settings.showTitleSearchBar ? '隐藏标题搜索框' : '显示标题搜索框'),
          ),
        ),
        if (!scope.isAlbum)
          const PopupMenuItem(
            value: 'set_home',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.home_outlined),
              title: Text('设置为首页'),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'stats',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.pie_chart_outline_rounded),
            title: Text('全景统计'),
          ),
        ),
        const PopupMenuItem(
          value: 'map',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.map_outlined),
            title: Text('地图'),
          ),
        ),
        const PopupMenuItem(
          value: 'customize',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.tune_rounded),
            title: Text('自定义顶底栏与按钮'),
          ),
        ),
      ],
    );
  }
}

/// Aves Floating Bottom Dock Bar matching `Screenshot_2026-10-26-00-19-33`
/// (`[媒体集] [视频] [收藏] [相册] [标签] [统计] [回收站] [设置] [缩放/比例]`)
class AvesFloatingBottomDock extends ConsumerWidget {
  final VoidCallback? onSelectAllPhotos;

  /// 外边距。为 null 时按 Aves「贴在屏幕底部」的规则自动计算；
  /// 当它浮在 tab 玻璃条之上时，由调用方传入不含安全区的间距。
  final EdgeInsetsGeometry? margin;

  const AvesFloatingBottomDock({super.key, this.onSelectAllPhotos, this.margin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(avesSettingsProvider);
    if (!settings.useAvesFloatingDock || settings.visibleDockItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final notifier = ref.read(avesSettingsProvider.notifier);

    // 对齐 Aves `AppBottomNavBar.getMargin`：左右 8、上 8、下 max(8, safeBottom + 4)，
    // 圆角 8 + dividerColor 描边 + 磨砂 —— 与 `AvesFloatingBar` 完全一致的配方。
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final margin = this.margin ?? EdgeInsets.only(left: 8, top: 8, right: 8, bottom: math.max(8, safeBottom + 4));
    const radius = BorderRadius.all(Radius.circular(8));

    return Padding(
      padding: margin,
      child: DecoratedBox(
        // Aves 用 foregroundDecoration 让 1px 描边压在内容之上，避免被填充色盖住
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: radius,
        ),
        child: AvesBlurredRRect(
          borderRadius: radius,
          child: Material(
            color: context.colorScheme.surfaceContainerHigh.withValues(alpha: 0.85),
            child: SizedBox(
              height: 56,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in settings.visibleDockItems)
                      IconButton(
                        tooltip: item.label,
                        icon: Icon(item.icon, size: 24),
                        onPressed: () {
                          switch (item) {
                            case AvesDockItem.allPhotos:
                              if (settings.tileLayout == AvesTileLayout.calendar) {
                                notifier.setTileLayout(AvesTileLayout.mosaic);
                              }
                              if (settings.sectionMode == AvesSectionMode.byAlbum) {
                                notifier.setSectionMode(AvesSectionMode.byDay);
                              }
                              onSelectAllPhotos?.call();
                            case AvesDockItem.videos:
                              unawaited(context.pushRoute(const VideoRoute()));
                            case AvesDockItem.favorites:
                              unawaited(context.pushRoute(const FavoriteRoute()));
                            case AvesDockItem.albums:
                              final tabsRouter = AutoTabsRouter.of(context);
                              tabsRouter.setActiveIndex(2);
                            case AvesDockItem.tags:
                              unawaited(openTagExplorerScreen(context));
                            case AvesDockItem.statistics:
                              unawaited(openAvesStatisticsScreen(context));
                            case AvesDockItem.map:
                              unawaited(context.pushRoute(MapRoute()));
                            case AvesDockItem.trash:
                              unawaited(context.pushRoute(const TrashRoute()));
                            case AvesDockItem.settings:
                              unawaited(openAvesCustomizationScreen(context));
                            case AvesDockItem.aspectToggle:
                              notifier.cycleColumnCount();
                              final newCols = ref.read(avesSettingsProvider).columnCount;
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  duration: const Duration(milliseconds: 1100),
                                  content: Text(newCols == 1 ? '已切换至 1 列单图满屏横宽模式' : '已切换至 $newCols 列布局'),
                                ),
                              );
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
