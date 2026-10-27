import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.page.dart';
import 'package:immich_mobile/presentation/widgets/images/local_album_thumbnail.widget.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail_tile.widget.dart';
import 'package:immich_mobile/providers/asset_viewer/is_motion_video_playing.provider.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:intl/intl.dart';

class _CalendarDayEntry {
  final DateTime date;
  final int assetCount;
  final int firstAssetIndex;

  const _CalendarDayEntry({
    required this.date,
    required this.assetCount,
    required this.firstAssetIndex,
  });
}

class _CalendarMonthGroup {
  final int year;
  final int month;
  final Map<int, _CalendarDayEntry> dayMap;

  const _CalendarMonthGroup({
    required this.year,
    required this.month,
    required this.dayMap,
  });

  int get totalAssets => dayMap.values.fold<int>(0, (s, d) => s + d.assetCount);
}

/// Aves-style Monthly Calendar Grid View (`布局 · 日历`)
///
/// Displays monthly cards with Mon-Sun headers, day cells with representative
/// cover thumbnails, top-left day number, and bottom-left asset count badge.
class AvesCalendarSliverList extends ConsumerWidget {
  final List<Bucket> buckets;

  const AvesCalendarSliverList({super.key, required this.buckets});

  List<_CalendarMonthGroup> _buildMonthGroups(bool isAscending) {
    final monthMap = <String, Map<int, _CalendarDayEntry>>{};
    final monthOrder = <({int year, int month})>[];

    int runningAssetIndex = 0;
    for (final bucket in buckets) {
      if (bucket is TimeBucket && bucket.assetCount > 0) {
        final d = bucket.date.toLocal();
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        var days = monthMap[key];
        if (days == null) {
          days = <int, _CalendarDayEntry>{};
          monthMap[key] = days;
          monthOrder.add((year: d.year, month: d.month));
        }
        final existing = days[d.day];
        if (existing == null) {
          days[d.day] = _CalendarDayEntry(
            date: DateTime(d.year, d.month, d.day),
            assetCount: bucket.assetCount,
            firstAssetIndex: runningAssetIndex,
          );
        } else {
          days[d.day] = _CalendarDayEntry(
            date: existing.date,
            assetCount: existing.assetCount + bucket.assetCount,
            firstAssetIndex: existing.firstAssetIndex,
          );
        }
      }
      runningAssetIndex += bucket.assetCount;
    }

    final groups = [
      for (final m in monthOrder)
        _CalendarMonthGroup(
          year: m.year,
          month: m.month,
          dayMap: monthMap['${m.year}-${m.month.toString().padLeft(2, '0')}'] ?? const {},
        ),
    ];

    if (isAscending) {
      return groups.reversed.toList();
    }
    return groups;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAscending = ref.watch(avesSettingsProvider.select((s) => s.isSortAscending));
    final groups = _buildMonthGroups(isAscending);

    if (groups.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month_outlined, size: 52, color: context.colorScheme.outline),
              const SizedBox(height: 12),
              Text('暂无可按日历展示的媒体项目', style: context.textTheme.bodyLarge),
            ],
          ),
        ),
      );
    }

    return SliverList.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        return _AvesMonthCalendarCard(group: groups[index]);
      },
    );
  }
}

class _AvesMonthCalendarCard extends ConsumerWidget {
  final _CalendarMonthGroup group;

  const _AvesMonthCalendarCard({required this.group});

  static const _weekDays = ['一', '二', '三', '四', '五', '六', '日'];

  String _formatMonthTitle() {
    final now = DateTime.now();
    if (group.year == now.year && group.month == now.month) {
      return '本月';
    }
    const cnMonths = ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'];
    final mName = cnMonths[(group.month - 1).clamp(0, 11)];
    if (group.year == now.year) {
      return mName;
    }
    return '${group.year}年 $mName';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstDayOfMonth = DateTime(group.year, group.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(group.year, group.month);
    // DateTime.weekday: Mon=1 .. Sun=7 -> 0-based offset: weekday - 1
    final leadingEmptyCells = firstDayOfMonth.weekday - 1;
    final totalCells = ((leadingEmptyCells + daysInMonth) / 7.0).ceil() * 7;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Text(
                  _formatMonthTitle(),
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.colorScheme.secondaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '共 ${group.totalAssets} 项',
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Weekday header row (Mon - Sun)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                for (final wd in _weekDays)
                  Expanded(
                    child: Center(
                      child: Text(
                        wd,
                        style: context.textTheme.labelMedium?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 2.5,
              crossAxisSpacing: 2.5,
              childAspectRatio: 0.88,
            ),
            itemCount: totalCells,
            itemBuilder: (context, cellIdx) {
              final dayNum = cellIdx - leadingEmptyCells + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const SizedBox.shrink();
              }
              final entry = group.dayMap[dayNum];
              return _AvesCalendarDayCell(
                year: group.year,
                month: group.month,
                day: dayNum,
                entry: entry,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AvesCalendarDayCell extends ConsumerWidget {
  final int year;
  final int month;
  final int day;
  final _CalendarDayEntry? entry;

  const _AvesCalendarDayCell({
    required this.year,
    required this.month,
    required this.day,
    required this.entry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayEntry = entry;
    if (dayEntry == null || dayEntry.assetCount <= 0) {
      return Container(
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: context.colorScheme.outlineVariant.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
        padding: const EdgeInsets.all(4),
        alignment: Alignment.topLeft,
        child: Text(
          '$day',
          style: context.textTheme.labelSmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
          ),
        ),
      );
    }

    final timelineService = ref.watch(timelineServiceProvider);
    final cachedAsset = timelineService.getAssetSafe(dayEntry.firstAssetIndex);

    return GestureDetector(
      onTap: () => _openDayAssetsSheet(context, ref, timelineService, dayEntry),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cachedAsset != null)
              ThumbnailTile(
                cachedAsset,
                remoteSize: const Size(160, 160),
                showStorageIndicator: false,
                showStackIndicator: false,
              )
            else
              FutureBuilder<BaseAsset?>(
                future: timelineService.getAssetAsync(dayEntry.firstAssetIndex),
                builder: (context, snapshot) {
                  final asset = snapshot.data;
                  if (asset == null) {
                    return Container(color: context.colorScheme.surfaceContainerHigh);
                  }
                  return ThumbnailTile(
                    asset,
                    remoteSize: const Size(160, 160),
                    showStorageIndicator: false,
                    showStackIndicator: false,
                  );
                },
              ),
            // Subtle top-left and bottom-left gradient for legibility
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.42),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.48),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            // Day number at top-left
            Positioned(
              top: 3,
              left: 4,
              child: Text(
                '$day',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
                ),
              ),
            ),
            // Asset count pill badge at bottom-left (matching Aves Calendar screenshot)
            Positioned(
              bottom: 3,
              left: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 0.8),
                ),
                child: Text(
                  '${dayEntry.assetCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDayAssetsSheet(
    BuildContext context,
    WidgetRef ref,
    TimelineService timelineService,
    _CalendarDayEntry dayEntry,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => _DayAssetsSheetContent(
          dayEntry: dayEntry,
          timelineService: timelineService,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _DayAssetsSheetContent extends ConsumerWidget {
  final _CalendarDayEntry dayEntry;
  final TimelineService timelineService;
  final ScrollController scrollController;

  const _DayAssetsSheetContent({
    required this.dayEntry,
    required this.timelineService,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateTitle = DateFormat('yyyy年MM月dd日 EEEE', 'zh_CN').format(dayEntry.date);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              const Icon(Icons.event_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateTitle,
                      style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '当天共拍摄/记录 ${dayEntry.assetCount} 项媒体',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(avesSettingsProvider.notifier).setTileLayout(AvesTileLayout.mosaic);
                },
                icon: const Icon(Icons.auto_awesome_mosaic_outlined, size: 16),
                label: const Text('切回瀑布流'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<BaseAsset>>(
            future: timelineService.loadAssets(dayEntry.firstAssetIndex, dayEntry.assetCount),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final assets = snapshot.requireData;
              return GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(6),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: assets.length,
                itemBuilder: (context, idx) {
                  final asset = assets[idx];
                  final globalIndex = dayEntry.firstAssetIndex + idx;
                  return GestureDetector(
                    onTap: () {
                      ref.read(isPlayingMotionVideoProvider.notifier).playing = false;
                      AssetViewer.setAsset(ref, asset, thumbnailSize: const Size(300, 300));
                      unawaited(
                        context.pushRoute(
                          AssetViewerRoute(
                            initialIndex: globalIndex,
                            timelineService: timelineService,
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: ThumbnailTile(
                        asset,
                        remoteSize: const Size(300, 300),
                        showStorageIndicator: true,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Aves-style Section by Album Sliver (`分区 · 按相册`)
///
/// Groups Remote Albums and Local Device Folders into Pinned (`钉选`) and Regular (`普通`) sections.
class AvesAlbumSectionSliverList extends ConsumerWidget {
  const AvesAlbumSectionSliverList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remoteAlbums = ref.watch(remoteAlbumProvider.select((s) => s.albums));
    final localAlbumsAsync = ref.watch(localAlbumProvider);
    final pinnedIds = ref.watch(avesSettingsProvider.select((s) => s.pinnedAlbumIds));
    final isAscending = ref.watch(avesSettingsProvider.select((s) => s.isSortAscending));

    final localAlbums = localAlbumsAsync.valueOrNull ?? const <LocalAlbum>[];

    final sortedRemote = List<RemoteAlbum>.of(remoteAlbums)
      ..sort((a, b) => isAscending ? a.name.compareTo(b.name) : b.assetCount.compareTo(a.assetCount));
    final sortedLocal = List<LocalAlbum>.of(localAlbums)
      ..sort((a, b) => isAscending ? a.name.compareTo(b.name) : b.assetCount.compareTo(a.assetCount));

    final pinnedRemote = sortedRemote.where((a) => pinnedIds.contains('remote_${a.id}') || pinnedIds.contains(a.id)).toList();
    final regularRemote = sortedRemote.where((a) => !pinnedIds.contains('remote_${a.id}') && !pinnedIds.contains(a.id)).toList();
    final pinnedLocal = sortedLocal.where((a) => pinnedIds.contains('local_${a.id}') || pinnedIds.contains(a.id)).toList();
    final regularLocal = sortedLocal.where((a) => !pinnedIds.contains('local_${a.id}') && !pinnedIds.contains(a.id)).toList();

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      sliver: SliverList.list(
        children: [
          if (pinnedRemote.isNotEmpty || pinnedLocal.isNotEmpty) ...[
            _buildSectionHeader(context, Icons.push_pin_rounded, '钉选相册 (${pinnedRemote.length + pinnedLocal.length})'),
            const SizedBox(height: 8),
            _buildAlbumWrap(context, ref, pinnedRemote, pinnedLocal, isPinned: true),
            const SizedBox(height: 18),
          ],
          if (regularRemote.isNotEmpty) ...[
            _buildSectionHeader(context, Icons.cloud_done_outlined, '服务器相册 (${regularRemote.length})'),
            const SizedBox(height: 8),
            _buildAlbumWrap(context, ref, regularRemote, const [], isPinned: false),
            const SizedBox(height: 18),
          ],
          if (regularLocal.isNotEmpty) ...[
            _buildSectionHeader(context, Icons.folder_special_outlined, '本地设备文件夹 (${regularLocal.length})'),
            const SizedBox(height: 8),
            _buildAlbumWrap(context, ref, const [], regularLocal, isPinned: false),
          ],
          if (remoteAlbums.isEmpty && localAlbums.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text('暂无相册或文件夹分组', style: context.textTheme.bodyLarge),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildAlbumWrap(
    BuildContext context,
    WidgetRef ref,
    List<RemoteAlbum> remotes,
    List<LocalAlbum> locals, {
    required bool isPinned,
  }) {
    final screenW = MediaQuery.sizeOf(context).width;
    final cols = screenW > 600 ? 3 : 2;
    final cardWidth = (screenW - 24 - (cols - 1) * 10) / cols;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final album in remotes)
          _AvesAlbumCard(
            width: cardWidth,
            title: album.name,
            subtitle: '${album.assetCount} 项 · 云端相册',
            badgeIcon: Icons.cloud_outlined,
            isPinned: isPinned,
            onTap: () => context.pushRoute(RemoteAlbumRoute(album: album)),
            onTogglePin: () => ref.read(avesSettingsProvider.notifier).togglePinAlbum(album.id),
            cover: album.thumbnailAssetId != null
                ? Thumbnail.remote(remoteId: album.thumbnailAssetId!, thumbhash: '', fit: BoxFit.cover)
                : ColoredBox(
                    color: context.colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.photo_album_outlined, color: context.colorScheme.outline),
                  ),
          ),
        for (final local in locals)
          _AvesAlbumCard(
            width: cardWidth,
            title: local.name,
            subtitle: '${local.assetCount} 项 · 本地文件夹',
            badgeIcon: _localIconForName(local.name),
            isPinned: isPinned,
            onTap: () => context.pushRoute(LocalTimelineRoute(album: local)),
            onTogglePin: () => ref.read(avesSettingsProvider.notifier).togglePinAlbum('local_${local.id}'),
            cover: LocalAlbumThumbnail(albumId: local.id),
          ),
      ],
    );
  }

  IconData _localIconForName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('camera') || lower.contains('dcim') || lower.contains('相机')) {
      return Icons.photo_camera_outlined;
    }
    if (lower.contains('screen') || lower.contains('截图') || lower.contains('截屏')) {
      return Icons.screenshot_outlined;
    }
    if (lower.contains('download') || lower.contains('下载')) {
      return Icons.download_rounded;
    }
    return Icons.folder_outlined;
  }
}

class _AvesAlbumCard extends StatelessWidget {
  final double width;
  final String title;
  final String subtitle;
  final IconData badgeIcon;
  final bool isPinned;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final Widget cover;

  const _AvesAlbumCard({
    required this.width,
    required this.title,
    required this.subtitle,
    required this.badgeIcon,
    required this.isPinned,
    required this.onTap,
    required this.onTogglePin,
    required this.cover,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onTogglePin,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPinned
                ? context.colorScheme.primary.withValues(alpha: 0.45)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: width * 0.68,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  cover,
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(badgeIcon, size: 14, color: Colors.white),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: onTogglePin,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: isPinned
                              ? context.colorScheme.primary
                              : Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

