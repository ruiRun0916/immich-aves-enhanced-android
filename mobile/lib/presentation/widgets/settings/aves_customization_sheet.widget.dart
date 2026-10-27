import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/pages/aves_overlay_settings.page.dart';
import 'package:immich_mobile/presentation/pages/aves_slideshow.page.dart';
import 'package:immich_mobile/presentation/pages/aves_slideshow_settings.page.dart';
import 'package:immich_mobile/providers/aves_overlay.provider.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';
import 'package:immich_mobile/providers/aves_slideshow.provider.dart';

Future<void> openAvesCustomizationScreen(BuildContext context, {int initialTab = 0}) async {
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => AvesCustomizationScreen(initialTab: initialTab)));
}

/// Aves-style Customization Center (`自定义设置 · 导航 / 缩略图 / 查看器 / 顶底栏 / 主页`)
///
/// Matches `Screenshot_2026-10-26-00-01-41-226` (Displayed vs Available Quick Action buttons)
/// and `Screenshot_2026-10-26-00-01-45-539` (Navigation, Thumbnails, Viewer settings).
class AvesCustomizationScreen extends ConsumerStatefulWidget {
  final int initialTab;

  const AvesCustomizationScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<AvesCustomizationScreen> createState() => _AvesCustomizationScreenState();
}

class _AvesCustomizationScreenState extends ConsumerState<AvesCustomizationScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: widget.initialTab.clamp(0, 4));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aves 界面与操作自定义'),
        actions: [
          TextButton.icon(
            onPressed: () {
              ref.read(avesSettingsProvider.notifier).resetToDefaults();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已恢复默认 Aves 布局与按钮配置'), duration: Duration(seconds: 2)));
            },
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('恢复默认'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.wallpaper_rounded, size: 18), text: '查看器按钮'),
            Tab(icon: Icon(Icons.dock_rounded, size: 18), text: '自定义底栏'),
            Tab(icon: Icon(Icons.home_outlined, size: 18), text: '主页与缩略图'),
            Tab(icon: Icon(Icons.slideshow_rounded, size: 18), text: '幻灯片'),
            Tab(icon: Icon(Icons.layers_outlined, size: 18), text: '叠加层'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ViewerQuickActionsEditorTab(),
          _BottomDockEditorTab(),
          _HomeAndThumbnailSettingsTab(),
          _SlideshowTab(),
          _OverlayTab(),
        ],
      ),
    );
  }
}

class _ViewerQuickActionsEditorTab extends ConsumerWidget {
  const _ViewerQuickActionsEditorTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(avesSettingsProvider);
    final notifier = ref.read(avesSettingsProvider.notifier);
    final visible = settings.visibleViewerActions;
    final available = settings.availableViewerActions;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('显示的按钮 (长按拖拽排序，点击移除)', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          '这些快捷操作会显示在照片查看器顶栏与快捷操作栏中',
          style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.colorScheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: SizedBox(
            height: 76,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: visible.length,
              // ignore: deprecated_member_use
              onReorder: notifier.reorderViewerActions,
              itemBuilder: (context, index) {
                final action = visible[index];
                return Padding(
                  key: ValueKey('vis_viewer_${action.name}'),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => notifier.removeViewerAction(action),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: context.colorScheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.colorScheme.outline.withValues(alpha: 0.45)),
                          ),
                          child: Icon(action.icon, size: 20, color: context.colorScheme.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(action.label, style: context.textTheme.labelSmall?.copyWith(fontSize: 10.5)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('可用按钮 (点击添加到显示栏)', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.colorScheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: available.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      '所有按钮均已添加到显示列表',
                      style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.outline),
                    ),
                  ),
                )
              : Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final action in available)
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => notifier.addViewerAction(action),
                        child: SizedBox(
                          width: 66,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: context.colorScheme.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: context.colorScheme.outlineVariant),
                                ),
                                child: Icon(action.icon, size: 20, color: context.colorScheme.primary),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                action.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: context.textTheme.labelSmall?.copyWith(fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _BottomDockEditorTab extends ConsumerStatefulWidget {
  const _BottomDockEditorTab();

  @override
  ConsumerState<_BottomDockEditorTab> createState() => _BottomDockEditorTabState();
}

class _BottomDockEditorTabState extends ConsumerState<_BottomDockEditorTab> {
  /// Aves 的「可用按钮」是分页的，这里按「媒体」和「工具」两页分组。
  static const _dockPages = <List<AvesDockItem>>[
    [AvesDockItem.allPhotos, AvesDockItem.videos, AvesDockItem.favorites, AvesDockItem.albums, AvesDockItem.tags],
    [AvesDockItem.statistics, AvesDockItem.map, AvesDockItem.trash, AvesDockItem.settings, AvesDockItem.aspectToggle],
  ];

  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(avesSettingsProvider);
    final notifier = ref.read(avesSettingsProvider.notifier);
    final visible = settings.visibleDockItems;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: Icon(Icons.dock_rounded, color: context.colorScheme.primary),
          title: const Text('底栏附加快捷入口'),
          subtitle: const Text('已合并进底部那条玻璃栏：4 个 tab 之后最多再加 5 个快捷图标（与 Aves 的 9 图标底栏一致）。关闭后底栏只保留 4 个 tab'),
          value: settings.useAvesFloatingDock,
          onChanged: (_) => notifier.toggleAvesFloatingDock(),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: Icon(Icons.blur_on_rounded, color: context.colorScheme.primary),
          title: const Text('玻璃磨砂效果'),
          subtitle: const Text('浮动顶栏与底栏背后的实时模糊（Aves 同名开关）。滚动掉帧时可以关掉，退回半透明纯色'),
          value: settings.enableBlurEffect,
          onChanged: (_) => notifier.toggleBlurEffect(),
        ),
        const Divider(height: 24),
        Text('显示的底栏图标 (长按拖拽排序，点击移除)', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.colorScheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: SizedBox(
            height: 76,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: visible.length,
              // ignore: deprecated_member_use
              onReorder: notifier.reorderDockItems,
              itemBuilder: (context, index) {
                final item = visible[index];
                return Padding(
                  key: ValueKey('vis_dock_${item.name}'),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => notifier.removeDockItem(item),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: context.colorScheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.colorScheme.outline.withValues(alpha: 0.45)),
                          ),
                          child: Icon(item.icon, size: 20, color: context.colorScheme.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(item.label, style: context.textTheme.labelSmall?.copyWith(fontSize: 10.5)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('可用按钮 (点击添加)', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.colorScheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  for (final item in _dockPages[_page])
                    _DockCandidateIcon(
                      item: item,
                      added: settings.visibleDockItems.contains(item),
                      onTap: () => notifier.addDockItem(item),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // Aves 用两个小圆点表示「可用按钮」有两页。
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _dockPages.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _page = i),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _page
                              ? context.colorScheme.primary
                              : context.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 「可用按钮」里的一个圆形候选项。已在底栏里的置灰且不可点（Aves 同款处理）。
class _DockCandidateIcon extends StatelessWidget {
  final AvesDockItem item;
  final bool added;
  final VoidCallback onTap;

  const _DockCandidateIcon({required this.item, required this.added, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final muted = context.colorScheme.onSurface.withValues(alpha: 0.32);
    final border = context.colorScheme.outlineVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: added ? null : onTap,
      child: SizedBox(
        width: 66,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: border),
              ),
              child: Icon(item.icon, size: 20, color: added ? muted : context.colorScheme.primary),
            ),
            const SizedBox(height: 5),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.textTheme.labelSmall?.copyWith(fontSize: 10.5, color: added ? muted : null),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeAndThumbnailSettingsTab extends ConsumerWidget {
  const _HomeAndThumbnailSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(avesSettingsProvider);
    final notifier = ref.read(avesSettingsProvider.notifier);

    const homeModes = <({String key, String title, String subtitle, IconData icon})>[
      (key: 'unified', title: '综合浏览 (云端 + 本地)', subtitle: '默认融合服务器与手机本地照片', icon: Icons.dynamic_feed_rounded),
      (key: 'serverOnly', title: '仅服务器图库', subtitle: '启动时默认仅展示 Immich 云端资产', icon: Icons.cloud_outlined),
      (key: 'localGallery', title: '仅本地图库 (MediaStore)', subtitle: '启动时直接进入手机本地相机与文件夹', icon: Icons.smartphone_rounded),
      (key: 'calendar', title: 'Aves 日历月历视图', subtitle: '启动时直接以月历方格展示每日照片分布', icon: Icons.calendar_month_outlined),
      (key: 'byAlbum', title: '按相册与文件夹分组', subtitle: '启动时按钉选相册与普通相册分组展示', icon: Icons.photo_album_outlined),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text('导航', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        // Aves「导航 → 主页」：一行摘要 + 点开单选弹窗，而不是把五个选项直接铺在页面上。
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: Icon(Icons.home_outlined, color: context.colorScheme.primary),
          title: const Text('主页'),
          subtitle: Text(
            homeModes.firstWhere(
              (m) => m.key == settings.defaultHomeMode,
              orElse: () => homeModes.first,
            ).title,
            style: context.textTheme.bodySmall,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final picked = await showAvesRadioDialog<String>(
              context: context,
              title: '主页',
              current: settings.defaultHomeMode,
              options: [for (final m in homeModes) (value: m.key, label: m.title)],
            );
            if (picked == null) {
              return;
            }
            notifier.setDefaultHomeMode(picked);
            if (picked == 'calendar') {
              notifier.setTileLayout(AvesTileLayout.calendar);
            } else if (picked == 'byAlbum') {
              notifier.setSectionMode(AvesSectionMode.byAlbum);
            }
          },
        ),
        const Divider(height: 28),
        Text('顶栏与缩略图覆盖层', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: const Icon(Icons.tune_rounded),
          title: const Text('显示 Aves 顶部布局控制栏'),
          subtitle: const Text('在媒体集顶部显示 [↕ 升序/降序] [布局] [排序] [分区] 快捷胶囊按钮'),
          value: settings.showLayoutControlBar,
          onChanged: (_) => notifier.toggleLayoutControlBar(),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: const Icon(Icons.filter_alt_outlined),
          title: const Text('显示标题快速搜索框'),
          subtitle: const Text('在布局栏下方常驻按文件名/标题实时过滤输入框'),
          value: settings.showTitleSearchBar,
          onChanged: (_) => notifier.toggleTitleSearchBar(),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: const Icon(Icons.hdr_on_rounded),
          title: const Text('缩略图显示 HDR / RAW / 格式角标'),
          subtitle: const Text('在缩略图左下角显示 HDR、RAW、GIF、AVIF、LIVE、360° 标识'),
          value: settings.showHdrAndFormatBadges,
          onChanged: (_) => notifier.toggleHdrBadges(),
        ),
        const Divider(height: 28),
        Text(
          '网格列数与缩放预设 (${settings.columnCount} 列${settings.columnCount == 1 ? ' · 单图全屏横宽' : ''})',
          style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
    );
  }
}

/// 「幻灯片」入口 tab：一眼看到当前节奏，点了就能放。
class _SlideshowTab extends ConsumerWidget {
  const _SlideshowTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(avesSlideshowProvider);
    final theme = Theme.of(context);

    final summary = <(String, String)>[
      ('过渡动画', settings.transition.label),
      ('时间间隔', '${settings.intervalSeconds} 秒'),
      ('播放顺序', settings.shuffle ? '随机' : '顺序'),
      ('重复播放', settings.repeat ? '开' : '关'),
      ('填充屏幕', settings.fillScreen ? '铺满裁切' : '完整显示'),
      ('动画缩放', settings.animateZoom ? '开' : '关'),
      ('视频', settings.videoPlayback.label),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('当前播放配置', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(
            children: [
              for (final (label, value) in summary)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                      Text(
                        value,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => unawaited(openAvesSlideshowFromTimeline(context, ref)),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('从最早一张开始播放'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AvesSlideshowSettingsPage()),
            ),
          ),
          icon: const Icon(Icons.tune_rounded),
          label: const Text('幻灯片设置'),
        ),
        const SizedBox(height: 16),
        Text(
          '幻灯片取当前时间线最多 500 张，按设定的间隔自动切换。'
          '播放中左右滑动可手动翻页，点一下画面收起控制栏。',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 「叠加层」入口 tab：常用开关直接摆在面上，冷门的进完整设置页。
class _OverlayTab extends ConsumerWidget {
  const _OverlayTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(avesOverlayProvider);
    final notifier = ref.read(avesOverlayProvider.notifier);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: Icon(Icons.visibility_outlined, color: theme.colorScheme.primary),
          title: const Text('打开时显示'),
          subtitle: const Text('进入查看器时叠加层自动展开'),
          value: settings.showOnOpen,
          onChanged: (_) => notifier.toggleShowOnOpen(),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: Icon(Icons.info_outline_rounded, color: theme.colorScheme.primary),
          title: const Text('显示信息'),
          subtitle: const Text('标题、日期、位置、分辨率'),
          value: settings.showInfo,
          onChanged: (_) => notifier.toggleInfo(),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: Icon(Icons.camera_rounded, color: theme.colorScheme.primary),
          title: const Text('显示拍摄详情'),
          subtitle: const Text('光圈 / 快门 / 焦段 / ISO'),
          value: settings.showShootingDetails,
          onChanged: (_) => notifier.toggleShootingDetails(),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: Icon(Icons.zoom_in_rounded, color: theme.colorScheme.primary),
          title: const Text('显示缩放级别'),
          subtitle: const Text('实时倍率徽章'),
          value: settings.showZoomLevel,
          onChanged: (_) => notifier.toggleZoomLevel(),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: Icon(Icons.view_carousel_outlined, color: theme.colorScheme.primary),
          title: const Text('显示缩略图'),
          subtitle: const Text('底部胶片条，点击可跳转'),
          value: settings.showFilmstrip,
          onChanged: (_) => notifier.toggleFilmstrip(),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AvesOverlaySettingsPage()),
            ),
          ),
          icon: const Icon(Icons.layers_outlined),
          label: const Text('完整叠加层设置'),
        ),
      ],
    );
  }
}
