import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:path_provider/path_provider.dart';

/// Aves 4-mode layout engine
enum AvesTileLayout {
  mosaic(label: '马赛克', icon: Icons.auto_awesome_mosaic_outlined),
  grid(label: '网格', icon: Icons.grid_on_rounded),
  list(label: '列表', icon: Icons.table_rows_outlined),
  calendar(label: '日历', icon: Icons.calendar_month_outlined);

  final String label;
  final IconData icon;
  const AvesTileLayout({required this.label, required this.icon});
}

/// Aves 4-mode sectioning (grouping) engine
enum AvesSectionMode {
  byAlbum(label: '按相册', icon: Icons.photo_album_outlined),
  byMonth(label: '按月份', icon: Icons.calendar_view_month_rounded),
  byDay(label: '按天', icon: Icons.calendar_today_outlined),
  none(label: '不区分', icon: Icons.close_rounded);

  final String label;
  final IconData icon;
  const AvesSectionMode({required this.label, required this.icon});

  GroupAssetsBy get toTimelineGroupBy => switch (this) {
    AvesSectionMode.byMonth => GroupAssetsBy.month,
    AvesSectionMode.byDay => GroupAssetsBy.day,
    AvesSectionMode.none => GroupAssetsBy.none,
    AvesSectionMode.byAlbum => GroupAssetsBy.day,
  };
}

/// Aves 6-mode sorting engine
enum AvesSortMode {
  byDate(label: '按日期', icon: Icons.calendar_today_outlined),
  byTitle(label: '按相册和项目标题', icon: Icons.text_snippet_outlined),
  byPath(label: '按路径', icon: Icons.account_tree_outlined),
  bySize(label: '按大小', icon: Icons.data_usage_rounded),
  byRating(label: '按评分', icon: Icons.star_border_rounded),
  byDuration(label: '按时长', icon: Icons.timelapse_rounded);

  final String label;
  final IconData icon;
  const AvesSortMode({required this.label, required this.icon});
}

/// Customizable Viewer Quick Action Buttons (matching Aves Quick Actions Editor)
enum AvesViewerAction {
  edit(label: '编辑', icon: Icons.edit_outlined),
  rotateScreen(label: '旋转屏幕', icon: Icons.screen_rotation_outlined),
  favorite(label: '加为收藏', icon: Icons.favorite_border_rounded),
  addToAlbum(label: '添加到相册', icon: Icons.add_to_photos_outlined),
  share(label: '分享', icon: Icons.share_outlined),
  delete(label: '删除', icon: Icons.delete_outline_rounded),
  tag(label: '管理标签', icon: Icons.sell_outlined),
  map(label: '地图定位', icon: Icons.map_outlined),
  metadata(label: '查看元数据', icon: Icons.info_outline_rounded),
  upload(label: '上传备份', icon: Icons.cloud_upload_outlined),
  copyLink(label: '复制分享链接', icon: Icons.link_rounded);

  final String label;
  final IconData icon;
  const AvesViewerAction({required this.label, required this.icon});
}

/// Customizable Bottom Floating Dock Destinations (matching Aves Bottom Dock)
enum AvesDockItem {
  allPhotos(label: '媒体集', icon: Icons.collections_outlined),
  videos(label: '视频', icon: Icons.movie_creation_outlined),
  favorites(label: '收藏', icon: Icons.favorite_border_rounded),
  albums(label: '相册', icon: Icons.bookmarks_outlined),
  tags(label: '标签树', icon: Icons.label_outline_rounded),
  statistics(label: '全景统计', icon: Icons.pie_chart_outline_rounded),
  map(label: '地图', icon: Icons.map_outlined),
  trash(label: '回收站', icon: Icons.delete_outline_rounded),
  settings(label: '自定义设置', icon: Icons.settings_outlined),
  aspectToggle(label: '缩放/比例', icon: Icons.aspect_ratio_rounded);

  final String label;
  final IconData icon;
  const AvesDockItem({required this.label, required this.icon});
}

class AvesViewSettings {
  final AvesTileLayout tileLayout;
  final AvesSectionMode sectionMode;
  final AvesSortMode sortMode;
  final bool isSortAscending;

  /// Supports 1 (100% full screen width) to 8 (dense micro thumbnails)
  final int columnCount;

  /// Row height in List layout (scalable via pinch-to-zoom from 72 to 220)
  final double listRowExtent;
  final bool showLayoutControlBar;
  final bool showTitleSearchBar;
  final String titleSearchQuery;
  final bool showHdrAndFormatBadges;
  final bool useAvesFloatingDock;

  /// Aves `enableBlurEffect`：悬浮栏背后的实时磨砂。低端机可关掉换性能。
  final bool enableBlurEffect;
  final List<AvesViewerAction> visibleViewerActions;
  final List<AvesDockItem> visibleDockItems;
  final Set<String> pinnedAlbumIds;
  final String defaultHomeMode;

  const AvesViewSettings({
    this.tileLayout = AvesTileLayout.mosaic,
    this.sectionMode = AvesSectionMode.byDay,
    this.sortMode = AvesSortMode.byDate,
    this.isSortAscending = false,
    this.columnCount = 4,
    this.listRowExtent = 104.0,
    this.showLayoutControlBar = true,
    this.showTitleSearchBar = false,
    this.titleSearchQuery = '',
    this.showHdrAndFormatBadges = true,
    this.useAvesFloatingDock = true,
    this.enableBlurEffect = true,
    this.visibleViewerActions = const [
      AvesViewerAction.edit,
      AvesViewerAction.rotateScreen,
      AvesViewerAction.favorite,
      AvesViewerAction.addToAlbum,
      AvesViewerAction.share,
      AvesViewerAction.tag,
      AvesViewerAction.metadata,
      AvesViewerAction.delete,
    ],
    this.visibleDockItems = const [
      AvesDockItem.allPhotos,
      AvesDockItem.videos,
      AvesDockItem.favorites,
      AvesDockItem.albums,
      AvesDockItem.tags,
      AvesDockItem.statistics,
      AvesDockItem.trash,
      AvesDockItem.settings,
      AvesDockItem.aspectToggle,
    ],
    this.pinnedAlbumIds = const <String>{},
    this.defaultHomeMode = 'unified',
  });

  List<AvesViewerAction> get availableViewerActions =>
      AvesViewerAction.values.where((action) => !visibleViewerActions.contains(action)).toList();

  List<AvesDockItem> get availableDockItems =>
      AvesDockItem.values.where((item) => !visibleDockItems.contains(item)).toList();

  AvesViewSettings copyWith({
    AvesTileLayout? tileLayout,
    AvesSectionMode? sectionMode,
    AvesSortMode? sortMode,
    bool? isSortAscending,
    int? columnCount,
    double? listRowExtent,
    bool? showLayoutControlBar,
    bool? showTitleSearchBar,
    String? titleSearchQuery,
    bool? showHdrAndFormatBadges,
    bool? useAvesFloatingDock,
    bool? enableBlurEffect,
    List<AvesViewerAction>? visibleViewerActions,
    List<AvesDockItem>? visibleDockItems,
    Set<String>? pinnedAlbumIds,
    String? defaultHomeMode,
  }) {
    return AvesViewSettings(
      tileLayout: tileLayout ?? this.tileLayout,
      sectionMode: sectionMode ?? this.sectionMode,
      sortMode: sortMode ?? this.sortMode,
      isSortAscending: isSortAscending ?? this.isSortAscending,
      columnCount: (columnCount ?? this.columnCount).clamp(1, 8),
      listRowExtent: (listRowExtent ?? this.listRowExtent).clamp(72.0, 220.0),
      showLayoutControlBar: showLayoutControlBar ?? this.showLayoutControlBar,
      showTitleSearchBar: showTitleSearchBar ?? this.showTitleSearchBar,
      titleSearchQuery: titleSearchQuery ?? this.titleSearchQuery,
      showHdrAndFormatBadges: showHdrAndFormatBadges ?? this.showHdrAndFormatBadges,
      useAvesFloatingDock: useAvesFloatingDock ?? this.useAvesFloatingDock,
      enableBlurEffect: enableBlurEffect ?? this.enableBlurEffect,
      visibleViewerActions: visibleViewerActions ?? this.visibleViewerActions,
      visibleDockItems: visibleDockItems ?? this.visibleDockItems,
      pinnedAlbumIds: pinnedAlbumIds ?? this.pinnedAlbumIds,
      defaultHomeMode: defaultHomeMode ?? this.defaultHomeMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'tileLayout': tileLayout.name,
    'sectionMode': sectionMode.name,
    'sortMode': sortMode.name,
    'isSortAscending': isSortAscending,
    'columnCount': columnCount,
    'listRowExtent': listRowExtent,
    'showLayoutControlBar': showLayoutControlBar,
    'showTitleSearchBar': showTitleSearchBar,
    'showHdrAndFormatBadges': showHdrAndFormatBadges,
    'useAvesFloatingDock': useAvesFloatingDock,
    'enableBlurEffect': enableBlurEffect,
    'visibleViewerActions': visibleViewerActions.map((e) => e.name).toList(),
    'visibleDockItems': visibleDockItems.map((e) => e.name).toList(),
    'pinnedAlbumIds': pinnedAlbumIds.toList(),
    'defaultHomeMode': defaultHomeMode,
  };

  factory AvesViewSettings.fromJson(Map<String, dynamic> json) {
    AvesTileLayout parseLayout(String? v) =>
        AvesTileLayout.values.firstWhere((e) => e.name == v, orElse: () => AvesTileLayout.mosaic);
    AvesSectionMode parseSection(String? v) =>
        AvesSectionMode.values.firstWhere((e) => e.name == v, orElse: () => AvesSectionMode.byDay);
    AvesSortMode parseSort(String? v) =>
        AvesSortMode.values.firstWhere((e) => e.name == v, orElse: () => AvesSortMode.byDate);

    final rawViewer = (json['visibleViewerActions'] as List?)?.whereType<String>().toList();
    final viewerActions = rawViewer != null && rawViewer.isNotEmpty
        ? rawViewer.map((n) => AvesViewerAction.values.where((e) => e.name == n).firstOrNull).nonNulls.toList()
        : null;

    final rawDock = (json['visibleDockItems'] as List?)?.whereType<String>().toList();
    final dockItems = rawDock != null && rawDock.isNotEmpty
        ? rawDock.map((n) => AvesDockItem.values.where((e) => e.name == n).firstOrNull).nonNulls.toList()
        : null;

    final rawPinned = (json['pinnedAlbumIds'] as List?)?.whereType<String>().toSet();

    return AvesViewSettings(
      tileLayout: parseLayout(json['tileLayout'] as String?),
      sectionMode: parseSection(json['sectionMode'] as String?),
      sortMode: parseSort(json['sortMode'] as String?),
      isSortAscending: json['isSortAscending'] as bool? ?? false,
      columnCount: ((json['columnCount'] as num?)?.toInt() ?? 4).clamp(1, 8),
      listRowExtent: ((json['listRowExtent'] as num?)?.toDouble() ?? 104.0).clamp(72.0, 220.0),
      showLayoutControlBar: json['showLayoutControlBar'] as bool? ?? true,
      showTitleSearchBar: json['showTitleSearchBar'] as bool? ?? false,
      showHdrAndFormatBadges: json['showHdrAndFormatBadges'] as bool? ?? true,
      useAvesFloatingDock: json['useAvesFloatingDock'] as bool? ?? true,
      enableBlurEffect: json['enableBlurEffect'] as bool? ?? true,
      visibleViewerActions: viewerActions ?? const AvesViewSettings().visibleViewerActions,
      visibleDockItems: dockItems ?? const AvesViewSettings().visibleDockItems,
      pinnedAlbumIds: rawPinned ?? const <String>{},
      defaultHomeMode: json['defaultHomeMode'] as String? ?? 'unified',
    );
  }

  /// Sorts a list of [BaseAsset] according to the current [sortMode] and [isSortAscending].
  List<BaseAsset> sortAssets(List<BaseAsset> input) {
    var filtered = input;
    if (titleSearchQuery.trim().isNotEmpty) {
      final q = titleSearchQuery.trim().toLowerCase();
      filtered = input.where((a) => a.name.toLowerCase().contains(q)).toList();
    }
    if (filtered.length <= 1 && sortMode == AvesSortMode.byDate && !isSortAscending) {
      return filtered;
    }
    final list = List<BaseAsset>.of(filtered);
    final dir = isSortAscending ? 1 : -1;
    list.sort((a, b) {
      final cmp = switch (sortMode) {
        AvesSortMode.byDate => a.createdAt.compareTo(b.createdAt),
        AvesSortMode.byTitle => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        AvesSortMode.byPath => '${a.storage.name}/${a.name}'.toLowerCase().compareTo(
          '${b.storage.name}/${b.name}'.toLowerCase(),
        ),
        AvesSortMode.bySize => ((a.width ?? 0) * (a.height ?? 0)).compareTo((b.width ?? 0) * (b.height ?? 0)),
        AvesSortMode.byRating => (a.isFavorite ? 1 : 0).compareTo(b.isFavorite ? 1 : 0),
        AvesSortMode.byDuration => (a.durationMs ?? 0).compareTo(b.durationMs ?? 0),
      };
      if (cmp != 0) {
        return cmp * dir;
      }
      return a.createdAt.compareTo(b.createdAt) * dir;
    });
    return list;
  }
}

class AvesSettingsNotifier extends StateNotifier<AvesViewSettings> {
  AvesSettingsNotifier() : super(const AvesViewSettings()) {
    unawaited(_loadFromDisk());
  }

  static const _fileName = 'aves_enhanced_settings_v1.json';

  Future<File?> _getSettingsFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final file = await _getSettingsFile();
      if (file != null && file.existsSync()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          state = AvesViewSettings.fromJson(decoded);
        }
      }
    } catch (_) {
      // Keep default settings if file cannot be read
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _getSettingsFile();
      if (file != null) {
        await file.writeAsString(jsonEncode(state.toJson()));
      }
    } catch (_) {}
  }

  void setTileLayout(AvesTileLayout layout) {
    state = state.copyWith(tileLayout: layout);
    unawaited(_saveToDisk());
  }

  void setSectionMode(AvesSectionMode mode) {
    state = state.copyWith(sectionMode: mode);
    unawaited(_saveToDisk());
  }

  void setSortMode(AvesSortMode mode) {
    state = state.copyWith(sortMode: mode);
    unawaited(_saveToDisk());
  }

  void toggleSortDirection() {
    state = state.copyWith(isSortAscending: !state.isSortAscending);
    unawaited(_saveToDisk());
  }

  void setColumnCount(int count) {
    final clamped = count.clamp(1, 8);
    if (clamped == state.columnCount) {
      return;
    }
    state = state.copyWith(columnCount: clamped);
    unawaited(_saveToDisk());
  }

  void cycleColumnCount() {
    // Cycles: 4 -> 2 -> 1 (Full width) -> 6 -> 4
    final next = switch (state.columnCount) {
      4 => 2,
      2 => 1,
      1 => 6,
      _ => 4,
    };
    setColumnCount(next);
  }

  void setListRowExtent(double extent) {
    final clamped = extent.clamp(72.0, 220.0);
    if ((clamped - state.listRowExtent).abs() < 1.0) {
      return;
    }
    state = state.copyWith(listRowExtent: clamped);
    unawaited(_saveToDisk());
  }

  void toggleLayoutControlBar() {
    state = state.copyWith(showLayoutControlBar: !state.showLayoutControlBar);
    unawaited(_saveToDisk());
  }

  void toggleTitleSearchBar() {
    final next = !state.showTitleSearchBar;
    state = state.copyWith(showTitleSearchBar: next, titleSearchQuery: next ? state.titleSearchQuery : '');
    unawaited(_saveToDisk());
  }

  void setTitleSearchQuery(String query) {
    state = state.copyWith(titleSearchQuery: query);
  }

  void toggleHdrBadges() {
    state = state.copyWith(showHdrAndFormatBadges: !state.showHdrAndFormatBadges);
    unawaited(_saveToDisk());
  }

  void toggleBlurEffect() {
    state = state.copyWith(enableBlurEffect: !state.enableBlurEffect);
  }

  void toggleAvesFloatingDock() {
    state = state.copyWith(useAvesFloatingDock: !state.useAvesFloatingDock);
    unawaited(_saveToDisk());
  }

  void setDefaultHomeMode(String mode) {
    state = state.copyWith(defaultHomeMode: mode);
    unawaited(_saveToDisk());
  }

  bool isAlbumPinned(String albumId) => state.pinnedAlbumIds.contains(albumId);

  void togglePinAlbum(String albumId) {
    final next = Set<String>.of(state.pinnedAlbumIds);
    if (next.contains(albumId)) {
      next.remove(albumId);
    } else {
      next.add(albumId);
    }
    state = state.copyWith(pinnedAlbumIds: next);
    unawaited(_saveToDisk());
  }

  void reorderViewerActions(int oldIndex, int newIndex) {
    final list = List<AvesViewerAction>.of(state.visibleViewerActions);
    var targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }
    final item = list.removeAt(oldIndex);
    list.insert(targetIndex, item);
    state = state.copyWith(visibleViewerActions: list);
    unawaited(_saveToDisk());
  }

  void addViewerAction(AvesViewerAction action) {
    if (state.visibleViewerActions.contains(action)) {
      return;
    }
    state = state.copyWith(visibleViewerActions: [...state.visibleViewerActions, action]);
    unawaited(_saveToDisk());
  }

  void removeViewerAction(AvesViewerAction action) {
    if (state.visibleViewerActions.length <= 1) {
      return;
    }
    state = state.copyWith(visibleViewerActions: state.visibleViewerActions.where((a) => a != action).toList());
    unawaited(_saveToDisk());
  }

  void reorderDockItems(int oldIndex, int newIndex) {
    final list = List<AvesDockItem>.of(state.visibleDockItems);
    var targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }
    final item = list.removeAt(oldIndex);
    list.insert(targetIndex, item);
    state = state.copyWith(visibleDockItems: list);
    unawaited(_saveToDisk());
  }

  void addDockItem(AvesDockItem item) {
    if (state.visibleDockItems.contains(item)) {
      return;
    }
    state = state.copyWith(visibleDockItems: [...state.visibleDockItems, item]);
    unawaited(_saveToDisk());
  }

  void removeDockItem(AvesDockItem item) {
    if (state.visibleDockItems.length <= 2) {
      return;
    }
    state = state.copyWith(visibleDockItems: state.visibleDockItems.where((a) => a != item).toList());
    unawaited(_saveToDisk());
  }

  void resetToDefaults() {
    state = const AvesViewSettings();
    unawaited(_saveToDisk());
  }
}

final avesSettingsProvider = StateNotifierProvider<AvesSettingsNotifier, AvesViewSettings>(
  (ref) => AvesSettingsNotifier(),
);
