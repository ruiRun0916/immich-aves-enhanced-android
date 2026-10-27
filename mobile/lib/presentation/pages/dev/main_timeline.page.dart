import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/aves_media_metadata.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/local_media_aves.repository.dart';
import 'package:immich_mobile/presentation/pages/aves_slideshow.page.dart';
import 'package:immich_mobile/presentation/pages/aves_statistics.page.dart';
import 'package:immich_mobile/presentation/widgets/feature_message/feature_message_dialog.widget.dart';
import 'package:immich_mobile/presentation/widgets/memory/memory_lane.widget.dart';
import 'package:immich_mobile/presentation/widgets/search/album_filter_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/aves_timeline_header.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/providers/album_media_filter.provider.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';
import 'package:immich_mobile/providers/feature_message.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/memory.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/search/advanced_filter.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/common/immich_sliver_app_bar.dart';

@RoutePage()
class MainTimelinePage extends ConsumerStatefulWidget {
  const MainTimelinePage({super.key});

  @override
  ConsumerState<MainTimelinePage> createState() => _MainTimelinePageState();
}

class _MainTimelinePageState extends ConsumerState<MainTimelinePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final service = ref.read(featureMessageServiceProvider);
      if (!service.shouldShow()) {
        return;
      }

      await service.markSeen();
      if (!mounted) {
        return;
      }

      await showFeatureMessageDialog(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasMemories = ref.watch(memoryLaneProvider.select((state) => state.value?.isNotEmpty ?? false));
    final browseMode = ref.watch(galleryBrowseModeProvider);
    final currentUserId = ref.watch(currentUserProvider.select((u) => u?.id));
    final showLayoutBar = ref.watch(avesSettingsProvider.select((s) => s.showLayoutControlBar));
    final avesSettings = ref.watch(avesSettingsProvider);

    final headerHeight = showLayoutBar ? 106.0 : 56.0;

    // Aves 结构：整条顶部栏（模式切换 + 布局胶囊栏）属于同一个 floating sliver。
    // 下滑任意距离 → snap 把整条顶部栏一次性弹出，不再是「必须滑到顶部」。
    final appBar = ImmichSliverAppBar(
      floating: true,
      pinned: false,
      snap: true,
      // Aves 顶栏是「文字标题 + 一排动作图标」。Immich 原来那个横版 logo
      // 会吃掉左侧三分之一宽度，右边就再塞不下任何图标了。
      title: _AvesTimelineTitle(mode: browseMode),
      // Aves 顶栏右侧是一排动作图标；这里补上 Aves 有而我们缺的两个
      actions: [
        IconButton(
          tooltip: '幻灯片播放',
          icon: const Icon(Icons.slideshow_rounded),
          onPressed: () => unawaited(openAvesSlideshowFromTimeline(context, ref)),
        ),
        IconButton(
          tooltip: '全景统计',
          icon: const Icon(Icons.pie_chart_outline_rounded),
          onPressed: () => unawaited(openAvesStatisticsScreen(context)),
        ),
        IconButton(
          tooltip: '地图',
          icon: const Icon(Icons.map_outlined),
          onPressed: () => unawaited(context.pushRoute(MapRoute())),
        ),
      ],
      bottom: AvesTimelineHeaderBottom(
        height: AvesTimelineHeaderBottom.computeHeight(avesSettings),
        browseMode: browseMode,
      ),
    );

    Widget content;
    if (browseMode == GalleryBrowseMode.serverOnly && currentUserId != null) {
      content = ProviderScope(
        key: ValueKey('server_gallery_$currentUserId'),
        overrides: [
          timelineServiceProvider.overrideWith((ref) {
            final service = ref.watch(timelineFactoryProvider).remoteAssets(currentUserId);
            ref.onDispose(service.dispose);
            return service;
          }),
        ],
        child: Timeline(
          appBar: appBar,
          topSliverWidget: hasMemories ? const SliverToBoxAdapter(child: MemoryLane()) : null,
          topSliverWidgetHeight: (hasMemories ? 200 : 0) + headerHeight,
          showStorageIndicator: true,
          trackScrollChrome: true,
        ),
      );
    } else if (browseMode == GalleryBrowseMode.localGallery) {
      content = _LocalGalleryTimelineView(appBar: appBar, headerHeight: headerHeight);
    } else {
      content = Timeline(
        appBar: appBar,
        topSliverWidget: hasMemories ? const SliverToBoxAdapter(child: MemoryLane()) : null,
        topSliverWidgetHeight: (hasMemories ? 200 : 0) + headerHeight,
        showStorageIndicator: true,
        trackScrollChrome: true,
      );
    }

    return content;
  }
}

class _LocalGalleryTimelineView extends ConsumerStatefulWidget {
  final Widget appBar;
  final double headerHeight;

  const _LocalGalleryTimelineView({required this.appBar, required this.headerHeight});

  @override
  ConsumerState<_LocalGalleryTimelineView> createState() => _LocalGalleryTimelineViewState();
}

class _LocalGalleryTimelineViewState extends ConsumerState<_LocalGalleryTimelineView> {
  LocalAlbumCategory? _selectedCategory;
  List<BaseAsset> _localAssets = const [];
  bool _isLoading = true;

  /// 本地图库模式下的就地筛选。资产已经整批在内存里（[_localAssets]），
  /// 所以直接内存过滤，不需要走任何服务端查询。
  AdvancedMediaFilter _localFilter = AdvancedMediaFilter.empty;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLocalAssets());
  }

  Future<void> _loadLocalAssets() async {
    setState(() => _isLoading = true);
    try {
      final localRepo = ref.read(localMediaAvesRepositoryProvider);
      if (_selectedCategory == null || _selectedCategory == LocalAlbumCategory.all) {
        final res = await localRepo.filterLocalAssets(
          const AdvancedMediaFilter(sourceScope: MediaSourceScope.localOnly),
          page: 1,
          pageSize: 500,
        );
        if (mounted) {
          setState(() {
            _localAssets = res.assets;
            _isLoading = false;
          });
        }
        return;
      }

      if (_selectedCategory == LocalAlbumCategory.videos) {
        final res = await localRepo.filterLocalAssets(
          const AdvancedMediaFilter(sourceScope: MediaSourceScope.localOnly, mediaType: AssetType.video),
          page: 1,
          pageSize: 500,
        );
        if (mounted) {
          setState(() {
            _localAssets = res.assets;
            _isLoading = false;
          });
        }
        return;
      }

      final albums = await ref.read(localAlbumProvider.future).catchError((_) => const <LocalAlbum>[]);
      final matchingAlbums = albums.where((a) => LocalMediaRepository.categorizeAlbum(a) == _selectedCategory).toList();
      final combined = <String, LocalAsset>{};
      for (final album in matchingAlbums) {
        final res = await localRepo.filterLocalAssets(
          AdvancedMediaFilter(sourceScope: MediaSourceScope.localOnly, albumId: album.id, isLocalAlbum: true),
          page: 1,
          pageSize: 300,
        );
        for (final asset in res.assets) {
          combined[asset.id] = asset;
        }
      }
      final sorted = combined.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (mounted) {
        setState(() {
          _localAssets = sorted;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final permAsync = ref.watch(localMediaPermissionStatusProvider);
    final localRepo = ref.watch(localMediaAvesRepositoryProvider);

    final topBanner = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_copy_outlined, size: 16, color: context.colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '本地图库 (MediaStore 只读模式 · 共 ${_localAssets.length} 项)',
                        style: context.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    permAsync.maybeWhen(
                      data: (status) => status == MediaPermissionStatus.grantedPartial
                          ? TextButton(
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: () async {
                                await localRepo.presentLimitedPhotoPicker();
                                ref.invalidate(localMediaPermissionStatusProvider);
                                unawaited(_loadLocalAssets());
                              },
                              child: const Text('管理部分授权'),
                            )
                          : const SizedBox.shrink(),
                      orElse: () => const SizedBox.shrink(),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => context.pushRoute(const LocalAlbumsRoute()),
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('按文件夹浏览'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('全部本地媒体'),
                        selected: _selectedCategory == null,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          setState(() => _selectedCategory = null);
                          unawaited(_loadLocalAssets());
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('相机 (Camera)'),
                        selected: _selectedCategory == LocalAlbumCategory.camera,
                        visualDensity: VisualDensity.compact,
                        onSelected: (v) {
                          setState(() => _selectedCategory = v ? LocalAlbumCategory.camera : null);
                          unawaited(_loadLocalAssets());
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('截图 (Screenshots)'),
                        selected: _selectedCategory == LocalAlbumCategory.screenshots,
                        visualDensity: VisualDensity.compact,
                        onSelected: (v) {
                          setState(() => _selectedCategory = v ? LocalAlbumCategory.screenshots : null);
                          unawaited(_loadLocalAssets());
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('下载 (Download)'),
                        selected: _selectedCategory == LocalAlbumCategory.downloads,
                        visualDensity: VisualDensity.compact,
                        onSelected: (v) {
                          setState(() => _selectedCategory = v ? LocalAlbumCategory.downloads : null);
                          unawaited(_loadLocalAssets());
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('视频 (Videos)'),
                        selected: _selectedCategory == LocalAlbumCategory.videos,
                        visualDensity: VisualDensity.compact,
                        onSelected: (v) {
                          setState(() => _selectedCategory = v ? LocalAlbumCategory.videos : null);
                          unawaited(_loadLocalAssets());
                        },
                      ),
                      const SizedBox(width: 10),
                      FilterChip(
                        avatar: Badge(
                          isLabelVisible: _localFilter.activeFilterCount > 0,
                          label: Text('${_localFilter.activeFilterCount}'),
                          child: const Icon(Icons.filter_alt_outlined, size: 16),
                        ),
                        label: const Text('筛选'),
                        selected: _localFilter.activeFilterCount > 0,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) async {
                          final result = await showAvesFilterSheet(context, initial: _localFilter);
                          if (result != null && mounted) {
                            setState(() => _localFilter = result);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (_isLoading) {
      return Scaffold(
        body: CustomScrollView(
          slivers: [
            widget.appBar,
            SliverToBoxAdapter(child: topBanner),
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
          ],
        ),
      );
    }

    final visibleAssets = filterAlbumAssets(_localAssets, _localFilter);

    return ProviderScope(
      key: ValueKey(
        'local_gallery_${_selectedCategory?.name ?? 'all'}_${visibleAssets.length}_${_localFilter.hashCode}',
      ),
      overrides: [
        timelineServiceProvider.overrideWith((ref) {
          final service = ref
              .watch(timelineFactoryProvider)
              .fromAssetsWithBuckets(visibleAssets, TimelineOrigin.localAlbum);
          ref.onDispose(service.dispose);
          return service;
        }),
      ],
      child: Timeline(
        appBar: widget.appBar,
        topSliverWidget: SliverToBoxAdapter(child: topBanner),
        topSliverWidgetHeight: widget.headerHeight,
        showStorageIndicator: true,
        trackScrollChrome: true,
      ),
    );
  }
}

/// Aves 式文字标题：24sp 粗体、轻微负字距（Aves 的 `AvesAppBarTitle` 也是这个规格）
class _AvesTimelineTitle extends StatelessWidget {
  final GalleryBrowseMode mode;

  const _AvesTimelineTitle({required this.mode});

  @override
  Widget build(BuildContext context) {
    final label = switch (mode) {
      GalleryBrowseMode.unified => '照片',
      GalleryBrowseMode.serverOnly => '云端照片',
      GalleryBrowseMode.localGallery => '本地照片',
    };

    return AnimatedOpacity(
      opacity: IconTheme.of(context).opacity ?? 1,
      duration: kThemeChangeDuration,
      child: Text(
        label,
        style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      ),
    );
  }
}
