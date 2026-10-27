import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/aves_media_metadata.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/infrastructure/repositories/local_media_aves.repository.dart';
import 'package:immich_mobile/pages/common/large_leading_tile.dart';
import 'package:immich_mobile/presentation/widgets/images/local_album_thumbnail.widget.dart';
import 'package:immich_mobile/presentation/widgets/search/advanced_filter_sheet.widget.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/search/advanced_filter.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/common/local_album_sliver_app_bar.dart';

@RoutePage()
class LocalAlbumsPage extends ConsumerStatefulWidget {
  const LocalAlbumsPage({super.key});

  @override
  ConsumerState<LocalAlbumsPage> createState() => _LocalAlbumsPageState();
}

class _LocalAlbumsPageState extends ConsumerState<LocalAlbumsPage> {
  LocalAlbumCategory _selectedCategory = LocalAlbumCategory.all;
  String _folderQuery = '';

  IconData _categoryIcon(LocalAlbumCategory category) {
    return switch (category) {
      LocalAlbumCategory.all => Icons.folder_copy_outlined,
      LocalAlbumCategory.camera => Icons.photo_camera_outlined,
      LocalAlbumCategory.screenshots => Icons.screenshot_outlined,
      LocalAlbumCategory.downloads => Icons.download_outlined,
      LocalAlbumCategory.videos => Icons.videocam_outlined,
      LocalAlbumCategory.other => Icons.folder_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final permAsync = ref.watch(localMediaPermissionStatusProvider);
    final localRepo = ref.watch(localMediaAvesRepositoryProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const LocalAlbumsSliverAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: context.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, size: 18, color: context.colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '本地图库模式 (只读保护 · MediaStore)',
                                style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () {
                                unawaited(
                                  ref
                                      .read(advancedFilteredAssetsProvider.notifier)
                                      .applyFilter(
                                        const AdvancedMediaFilter(sourceScope: MediaSourceScope.localOnly),
                                      ),
                                );
                                unawaited(openAdvancedFilterBrowser(context));
                              },
                              icon: const Icon(Icons.filter_alt_outlined, size: 16),
                              label: const Text('筛选本地媒体'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        permAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (status) {
                            return Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    switch (status) {
                                      MediaPermissionStatus.grantedFull || MediaPermissionStatus.notApplicable =>
                                        '权限状态: 已授予完整本地照片与视频读取权限 (默认只读，不会自动上传或删除文件)',
                                      MediaPermissionStatus.grantedPartial =>
                                        '权限状态: Android 部分照片访问授权 (仅可浏览已勾选照片)',
                                      MediaPermissionStatus.denied => '权限状态: 未授予本地媒体读取权限',
                                      MediaPermissionStatus.restricted => '权限状态: 系统受限访问',
                                    },
                                    style: context.textTheme.bodySmall?.copyWith(
                                      color: status == MediaPermissionStatus.grantedPartial
                                          ? Colors.amber.shade800
                                          : context.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (status == MediaPermissionStatus.grantedPartial)
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                                    onPressed: () async {
                                      await localRepo.presentLimitedPhotoPicker();
                                      ref.invalidate(localMediaPermissionStatusProvider);
                                      ref.invalidate(localAlbumProvider);
                                    },
                                    child: const Text('管理授权照片'),
                                  )
                                else if (status == MediaPermissionStatus.denied)
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                                    onPressed: () async {
                                      await localRepo.checkPermissionStatus(requestIfNeeded: true);
                                      ref.invalidate(localMediaPermissionStatusProvider);
                                      ref.invalidate(localAlbumProvider);
                                    },
                                    child: const Text('请求权限'),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (v) => setState(() => _folderQuery = v.trim()),
                    decoration: InputDecoration(
                      hintText: '搜索本地文件夹 (如 Camera, Screenshots, Download, WeiXin)...',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: LocalAlbumCategory.values.map((category) {
                        final selected = _selectedCategory == category;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: Icon(_categoryIcon(category), size: 16),
                            label: Text(category.label),
                            selected: selected,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setState(() => _selectedCategory = category),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _AlbumList(
            selectedCategory: _selectedCategory,
            folderQuery: _folderQuery,
          ),
        ],
      ),
    );
  }
}

class _AlbumList extends ConsumerWidget {
  final LocalAlbumCategory selectedCategory;
  final String folderQuery;

  const _AlbumList({
    required this.selectedCategory,
    required this.folderQuery,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(localAlbumProvider);

    return albums.when(
      loading: () => const SliverToBoxAdapter(
        child: Center(
          child: Padding(padding: EdgeInsets.all(20.0), child: CircularProgressIndicator()),
        ),
      ),
      error: (error, stack) => SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              'Error loading albums: $error, stack: $stack',
              style: TextStyle(color: context.colorScheme.error),
            ),
          ),
        ),
      ),
      data: (albums) {
        final filtered = albums.where((album) {
          if (folderQuery.isNotEmpty && !album.name.toLowerCase().contains(folderQuery.toLowerCase())) {
            return false;
          }
          if (selectedCategory != LocalAlbumCategory.all &&
              LocalMediaRepository.categorizeAlbum(album) != selectedCategory) {
            return false;
          }
          return true;
        }).toList();

        if (filtered.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Text(
                  albums.isEmpty ? context.t.no_albums_yet : '当前分类下暂无匹配的本地文件夹',
                  style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.all(18.0),
          sliver: SliverList.builder(
            itemBuilder: (_, index) {
              final album = filtered[index];
              final category = LocalMediaRepository.categorizeAlbum(album);
              final categoryBadge = switch (category) {
                LocalAlbumCategory.all => '全部',
                LocalAlbumCategory.camera => '相机',
                LocalAlbumCategory.screenshots => '截图',
                LocalAlbumCategory.downloads => '下载',
                LocalAlbumCategory.videos => '视频',
                LocalAlbumCategory.other => '文件夹',
              };

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: LargeLeadingTile(
                  leadingPadding: const EdgeInsets.only(right: 16),
                  leading: SizedBox(width: 80, height: 80, child: LocalAlbumThumbnail(albumId: album.id)),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          album.name,
                          style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          categoryBadge,
                          style: context.textTheme.labelSmall?.copyWith(
                            color: context.colorScheme.onSecondaryContainer,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '${context.t.items_count(count: album.assetCount)} · 本地 MediaStore',
                    style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceSecondary),
                  ),
                  onTap: () => context.pushRoute(LocalTimelineRoute(album: album)),
                ),
              );
            },
            itemCount: filtered.length,
          ),
        );
      },
    );
  }
}
