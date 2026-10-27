import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/events.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/pages/aves_statistics.page.dart';
import 'package:immich_mobile/presentation/pages/search/paginated_search.provider.dart';
import 'package:immich_mobile/presentation/widgets/common/aves_blurred_surface.widget.dart';
import 'package:immich_mobile/presentation/widgets/settings/aves_customization_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/tag/tag_explorer.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/aves_floating_dock_slider.widget.dart';
import 'package:immich_mobile/providers/aves_scroll_chrome.provider.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/memory.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/search/search_input_focus.provider.dart';
import 'package:immich_mobile/providers/tab.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/routing/router.dart';

@RoutePage()
class TabShellPage extends ConsumerStatefulWidget {
  const TabShellPage({super.key});

  @override
  ConsumerState<TabShellPage> createState() => _TabShellPageState();
}

class _TabShellPageState extends ConsumerState<TabShellPage> {
  @override
  Widget build(BuildContext context) {
    final isScreenLandscape = context.orientation == Orientation.landscape;
    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);
    // 多选时玻璃条会被摘掉，底部留白也要同步取消，否则会多出一条空白
    final isMultiSelect = ref.watch(multiSelectProvider.select((s) => s.isEnabled));

    final tabs = <_AvesTabSpec>[
      _AvesTabSpec(label: context.t.photos, icon: Icons.photo_library_outlined, selectedIcon: Icons.photo_library),
      _AvesTabSpec(
        label: context.t.search,
        icon: Icons.search_rounded,
        selectedIcon: Icons.search,
        enabled: !isReadonlyModeEnabled,
      ),
      _AvesTabSpec(
        label: context.t.albums,
        icon: Icons.photo_album_outlined,
        selectedIcon: Icons.photo_album_rounded,
        enabled: !isReadonlyModeEnabled,
      ),
      _AvesTabSpec(
        label: context.t.library$,
        icon: Icons.space_dashboard_outlined,
        selectedIcon: Icons.space_dashboard_rounded,
        enabled: !isReadonlyModeEnabled,
      ),
    ];

    final navigationDestinations = [
      for (final tab in tabs)
        NavigationDestination(
          label: tab.label,
          icon: Icon(tab.icon),
          selectedIcon: Icon(tab.selectedIcon, color: context.primaryColor),
          enabled: tab.enabled,
        ),
    ];

    Widget navigationRail(TabsRouter tabsRouter) {
      return NavigationRail(
        destinations: navigationDestinations
            .map(
              (e) => NavigationRailDestination(
                icon: e.icon,
                label: Text(e.label),
                selectedIcon: e.selectedIcon,
                disabled: !e.enabled,
              ),
            )
            .toList(),
        onDestinationSelected: (index) => _onNavigationSelected(tabsRouter, index, ref),
        selectedIndex: tabsRouter.activeIndex,
        labelType: NavigationRailLabelType.all,
        groupAlignment: 0.0,
      );
    }

    return AutoTabsRouter(
      routes: const [MainTimelineRoute(), SearchRoute(), AlbumsRoute(), LibraryRoute()],
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (context, child, animation) => FadeTransition(opacity: animation, child: child),
      builder: (context, child) {
        final tabsRouter = AutoTabsRouter.of(context);
        return PopScope(
          canPop: tabsRouter.activeIndex == 0,
          onPopInvokedWithResult: (didPop, _) => !didPop ? tabsRouter.setActiveIndex(0) : null,
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            // Aves 的 `AvesScaffold(extendBody: true)`：内容一直铺到屏幕底部，
            // 悬浮栏是浮在内容之上的一块玻璃，而不是切掉一条。
            // 内容需要自己让位，所以下面给子树注入等量的 bottom padding。
            extendBody: true,
            body: isScreenLandscape
                ? Row(
                    children: [
                      navigationRail(tabsRouter),
                      const VerticalDivider(),
                      Expanded(child: child),
                    ],
                  )
                : MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      padding: MediaQuery.paddingOf(context).copyWith(
                        bottom:
                            MediaQuery.paddingOf(context).bottom +
                            (isMultiSelect
                                ? 0
                                : _BottomNavigationBar.totalHeight(MediaQuery.paddingOf(context).bottom)),
                      ),
                    ),
                    child: child,
                  ),
            bottomNavigationBar: _BottomNavigationBar(tabsRouter: tabsRouter, tabs: tabs),
          ),
        );
      },
    );
  }
}

void _onNavigationSelected(TabsRouter router, int index, WidgetRef ref) {
  // 换 tab 时玻璃条必须回来：它在照片页可能正被滚动手势收起，
  // 若带着隐藏状态切走，用户会找不到导航入口。
  ref.read(avesChromeHideProvider).value = 0;

  // On Photos page menu tapped
  if (router.activeIndex == kPhotoTabIndex && index == kPhotoTabIndex) {
    EventStream.shared.emit(const ScrollToTopEvent());
  }

  if (index == kPhotoTabIndex) {
    ref.invalidate(memoryLaneProvider);
  }

  if (router.activeIndex != kSearchTabIndex && index == kSearchTabIndex) {
    ref.read(searchPreFilterProvider.notifier).clear();
  }

  // On Search page tapped
  if (router.activeIndex == kSearchTabIndex && index == kSearchTabIndex) {
    ref.read(searchInputFocusProvider).requestFocus();
  }

  // Album page
  if (index == kAlbumTabIndex) {
    unawaited(ref.read(remoteAlbumProvider.notifier).refresh());
  }

  ref.read(hapticFeedbackProvider.notifier).selectionClick();
  router.setActiveIndex(index);
  ref.read(tabProvider.notifier).state = TabEnum.values[index];
}

/// 底栏里一个 tab 的静态描述（图标 / 标签 / 是否可用）
class _AvesTabSpec {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool enabled;

  const _AvesTabSpec({required this.label, required this.icon, required this.selectedIcon, this.enabled = true});
}

/// Aves 风格底栏。
///
/// Aves 只有**一条**底栏（`AppBottomNavBar`），里面是 9 个图标，没有第二排。
/// 这里把 Immich 的 4 个 tab 和原来独立的「悬浮快捷 dock」合并进同一条玻璃：
/// `[照片][搜索][相册][库] | [视频][收藏][标签][统计]...`
/// —— 这样底部只有一块浮岛，视觉密度和 Aves 一致。
///
/// 玻璃配方完全照 `AvesFloatingBar`：圆角 8 + `dividerColor` 1px 前景描边
/// + sigma 4 磨砂 + 0.85 底色；外边距 `left/right 8, top 8, bottom max(8, safeBottom+4)`。
class _BottomNavigationBar extends ConsumerStatefulWidget {
  const _BottomNavigationBar({required this.tabsRouter, required this.tabs});

  final List<_AvesTabSpec> tabs;
  final TabsRouter tabsRouter;

  /// 玻璃条内容高度（对齐 Aves 的 `kBottomNavigationBarHeight = 56`）
  static const double contentHeight = 56;

  /// 对齐 Aves `AppBottomNavBar.getMargin`
  static EdgeInsets margin(double safeBottom) =>
      EdgeInsets.only(left: 8, top: 8, right: 8, bottom: math.max(8, safeBottom + 4));

  static double totalHeight(double safeBottom) => contentHeight + margin(safeBottom).vertical;

  @override
  ConsumerState createState() => _BottomNavigationBarState();
}

class _BottomNavigationBarState extends ConsumerState<_BottomNavigationBar> {
  bool hideNavigationBar = false;
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _eventSubscription = EventStream.shared.listen<MultiSelectToggleEvent>(_onEvent);
  }

  void _onEvent(MultiSelectToggleEvent event) {
    setState(() {
      hideNavigationBar = event.isEnabled;
    });
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    super.dispose();
  }

  /// 原来悬浮 dock 的点击行为，合并进底栏后原样保留。
  void _onDockItem(BuildContext context, AvesDockItem item) {
    final notifier = ref.read(avesSettingsProvider.notifier);
    final settings = ref.read(avesSettingsProvider);
    final router = widget.tabsRouter;

    switch (item) {
      case AvesDockItem.allPhotos:
        if (settings.tileLayout == AvesTileLayout.calendar) {
          notifier.setTileLayout(AvesTileLayout.mosaic);
        }
        if (settings.sectionMode == AvesSectionMode.byAlbum) {
          notifier.setSectionMode(AvesSectionMode.byDay);
        }
        router.setActiveIndex(0);
      case AvesDockItem.videos:
        unawaited(context.pushRoute(const VideoRoute()));
      case AvesDockItem.favorites:
        unawaited(context.pushRoute(const FavoriteRoute()));
      case AvesDockItem.albums:
        router.setActiveIndex(2);
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
  }

  @override
  Widget build(BuildContext context) {
    final isScreenLandscape = context.orientation == Orientation.landscape;

    if (isScreenLandscape || hideNavigationBar) {
      return const SizedBox.shrink();
    }

    final safeBottom = MediaQuery.paddingOf(context).bottom;
    const radius = BorderRadius.all(Radius.circular(8));
    final theme = Theme.of(context);
    final settings = ref.watch(avesSettingsProvider);
    // Aves 底栏固定是 9 个图标；4 个 tab 之后最多再放 5 个快捷入口，
    // 再多就会把图标压到挤成一团。用户可在「自定义 → 自定义底栏」调整顺序。
    final dockItems = settings.useAvesFloatingDock
        ? settings.visibleDockItems.take(5).toList()
        : const <AvesDockItem>[];

    final items = <Widget>[
      for (var i = 0; i < widget.tabs.length; i++)
        _AvesNavItem(
          icon: widget.tabs[i].icon,
          selectedIcon: widget.tabs[i].selectedIcon,
          selected: widget.tabsRouter.activeIndex == i,
          enabled: widget.tabs[i].enabled,
          tooltip: widget.tabs[i].label,
          onTap: () => _onNavigationSelected(widget.tabsRouter, i, ref),
        ),
      for (final item in dockItems)
        _AvesNavItem(icon: item.icon, selected: false, tooltip: item.label, onTap: () => _onDockItem(context, item)),
    ];

    return AvesFloatingDockSlider(
      // 上滑时整条玻璃一起滑出屏幕 → 真全屏；下滑原路滑回
      height: _BottomNavigationBar.totalHeight(safeBottom),
      child: Padding(
        padding: _BottomNavigationBar.margin(safeBottom),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: radius,
          ),
          child: AvesBlurredRRect(
            borderRadius: radius,
            child: Material(
              color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.85),
              child: MediaQuery.removePadding(
                context: context,
                // 底部安全区已经算进外层 margin，这里不再重复占位
                removeBottom: true,
                child: SizedBox(
                  height: _BottomNavigationBar.contentHeight,
                  child: Row(children: [for (final item in items) Expanded(child: item)]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底栏里的单个图标：选中态只换图标 + 变主色（Aves 没有 M3 的胶囊指示器）
class _AvesNavItem extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final bool selected;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  const _AvesNavItem({
    required this.icon,
    this.selectedIcon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = !enabled
        ? scheme.onSurface.withValues(alpha: 0.28)
        : selected
        ? scheme.primary
        : scheme.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 22,
        child: Center(child: Icon(selected ? (selectedIcon ?? icon) : icon, size: 23, color: color)),
      ),
    );
  }
}
