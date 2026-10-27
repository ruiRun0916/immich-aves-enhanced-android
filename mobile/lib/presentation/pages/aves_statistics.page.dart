import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/data/db/main/database.dart';
import 'package:immich_mobile/data/store.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/search/advanced_filter_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/tag/tag_explorer.widget.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/search/advanced_filter.provider.dart';
import 'package:intl/intl.dart';

class AvesFormatCount {
  final String format;
  final int count;
  final Color color;
  final bool isVideo;

  const AvesFormatCount({
    required this.format,
    required this.count,
    required this.color,
    this.isVideo = false,
  });
}

class AvesRankItem {
  final String label;
  final String? leadingEmoji;
  final int count;

  const AvesRankItem({
    required this.label,
    required this.count,
    this.leadingEmoji,
  });
}

class AvesGalleryStats {
  final int totalAssets;
  final int totalImages;
  final int totalVideos;
  final int totalSizeBytes;
  final int totalDurationSeconds;
  final int geotaggedCount;
  final int favoriteCount;
  final List<AvesFormatCount> imageFormats;
  final List<AvesFormatCount> videoFormats;
  final Map<int, int> countsByYear;
  final List<AvesRankItem> topCountries;
  final List<AvesRankItem> topCities;
  final List<AvesRankItem> topCameras;

  const AvesGalleryStats({
    required this.totalAssets,
    required this.totalImages,
    required this.totalVideos,
    required this.totalSizeBytes,
    required this.totalDurationSeconds,
    required this.geotaggedCount,
    required this.favoriteCount,
    required this.imageFormats,
    required this.videoFormats,
    required this.countsByYear,
    required this.topCountries,
    required this.topCities,
    required this.topCameras,
  });

  double get geotaggedRatio => totalAssets > 0 ? (geotaggedCount / totalAssets).clamp(0.0, 1.0) : 0.0;
}

final avesStatsScopeProvider = StateProvider<MediaSourceScope>((ref) => MediaSourceScope.all);

final avesGalleryStatsProvider = FutureProvider.autoDispose<AvesGalleryStats>((ref) async {
  final db = ref.watch(driftProvider);
  final scope = ref.watch(avesStatsScopeProvider);
  return _computeAvesGalleryStats(db, scope);
});

Future<AvesGalleryStats> _computeAvesGalleryStats(Drift db, MediaSourceScope scope) async {
  int totalImages = 0;
  int totalVideos = 0;
  int totalSizeBytes = 0;
  int totalDurationSeconds = 0;
  int geotaggedCount = 0;
  int favoriteCount = 0;

  final imgFormatCounts = <String, int>{};
  final vidFormatCounts = <String, int>{};
  final yearCounts = <int, int>{};
  final countryCounts = <String, int>{};
  final cityCounts = <String, int>{};
  final cameraCounts = <String, int>{};

  final seenChecksums = <String>{};

  void recordNameAndType(String name, AssetType type, DateTime createdAt, int durationSec, bool isFav) {
    if (isFav) {
      favoriteCount++;
    }
    totalDurationSeconds += durationSec;
    final yr = createdAt.toLocal().year;
    if (yr >= 1970 && yr <= 2100) {
      yearCounts[yr] = (yearCounts[yr] ?? 0) + 1;
    }

    final ext = name.contains('.') ? name.split('.').last.toUpperCase() : '';
    if (type == AssetType.video || const {'MP4', 'MOV', 'MKV', 'WEBM', 'AVI', '3GP'}.contains(ext)) {
      totalVideos++;
      final fmt = switch (ext) {
        'MP4' || 'M4V' => 'MP4',
        'MOV' => 'MOV',
        'MKV' => 'MKV',
        'WEBM' => 'WEBM',
        _ => 'MP4/视频',
      };
      vidFormatCounts[fmt] = (vidFormatCounts[fmt] ?? 0) + 1;
    } else {
      totalImages++;
      final fmt = switch (ext) {
        'JPG' || 'JPEG' => 'JPEG',
        'HEIC' || 'HEIF' => 'HEIC',
        'PNG' => 'PNG',
        'GIF' => 'GIF',
        'WEBP' => 'WEBP',
        'DNG' || 'CR2' || 'CR3' || 'NEF' || 'ARW' || 'ORF' || 'RW2' || 'RAF' => 'RAW',
        'AVIF' => 'AVIF',
        'SVG' => 'SVG',
        'TIF' || 'TIFF' => 'TIFF',
        _ => 'JPEG',
      };
      imgFormatCounts[fmt] = (imgFormatCounts[fmt] ?? 0) + 1;
    }
  }

  if (scope == MediaSourceScope.all || scope == MediaSourceScope.serverOnly) {
    final query = db.remoteAssetEntity.select().join([
      leftOuterJoin(
        db.remoteExifEntity,
        db.remoteExifEntity.assetId.equalsExp(db.remoteAssetEntity.id),
      ),
    ])..where(db.remoteAssetEntity.deletedAt.isNull());

    final rows = await query.get();
    for (final row in rows) {
      final asset = row.readTable(db.remoteAssetEntity);
      final exif = row.readTableOrNull(db.remoteExifEntity);
      seenChecksums.add(asset.checksum);

      recordNameAndType(
        asset.name,
        asset.type,
        asset.createdAt,
        ((asset.durationMs ?? 0) / 1000).round(),
        asset.isFavorite,
      );

      if (exif != null) {
        if (exif.fileSize != null && exif.fileSize! > 0) {
          totalSizeBytes += exif.fileSize!;
        }
        if (exif.latitude != null &&
            exif.longitude != null &&
            exif.latitude != 0 &&
            exif.longitude != 0) {
          geotaggedCount++;
        }
        final country = exif.country?.trim();
        if (country != null && country.isNotEmpty) {
          countryCounts[country] = (countryCounts[country] ?? 0) + 1;
        }
        final city = exif.city?.trim() ?? exif.state?.trim();
        if (city != null && city.isNotEmpty) {
          cityCounts[city] = (cityCounts[city] ?? 0) + 1;
        }
        final model = exif.model?.trim();
        if (model != null && model.isNotEmpty) {
          final make = exif.make?.trim();
          final camLabel = (make != null && make.isNotEmpty && !model.toLowerCase().startsWith(make.toLowerCase()))
              ? '$make $model'
              : model;
          cameraCounts[camLabel] = (cameraCounts[camLabel] ?? 0) + 1;
        }
      }
    }
  }

  if (scope == MediaSourceScope.all || scope == MediaSourceScope.localOnly) {
    final localRows = await db.localAssetEntity.select().get();
    for (final local in localRows) {
      if (scope == MediaSourceScope.all && local.checksum != null && seenChecksums.contains(local.checksum)) {
        continue;
      }
      final localDurationSec = ((local.durationMs ?? 0) / 1000).round();
      recordNameAndType(
        local.name,
        local.type,
        local.createdAt,
        localDurationSec,
        local.isFavorite,
      );
      if (local.latitude != null &&
          local.longitude != null &&
          local.latitude != 0 &&
          local.longitude != 0) {
        geotaggedCount++;
      }
      // Estimate local size if not synced with remote EXIF
      final pixels = (local.width ?? 1920) * (local.height ?? 1080);
      final estBytes = local.type == AssetType.video
          ? math.max(2 * 1024 * 1024, localDurationSec * 900 * 1024)
          : (pixels * 0.42).round();
      totalSizeBytes += estBytes;
    }
  }

  const imagePalette = <String, Color>{
    'JPEG': Color(0xFF5C6BC0),
    'HEIC': Color(0xFF26A69A),
    'PNG': Color(0xFFFFCA28),
    'GIF': Color(0xFFAB47BC),
    'WEBP': Color(0xFF42A5F5),
    'RAW': Color(0xFFEF5350),
    'AVIF': Color(0xFF66BB6A),
    'SVG': Color(0xFFFF7043),
    'TIFF': Color(0xFF8D6E63),
  };

  const videoPalette = <String, Color>{
    'MP4': Color(0xFF7E57C2),
    'MOV': Color(0xFF29B6F6),
    'MKV': Color(0xFFFFA726),
    'WEBM': Color(0xFF66BB6A),
    'MP4/视频': Color(0xFF7E57C2),
  };

  final sortedImgFormats = imgFormatCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final sortedVidFormats = vidFormatCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  List<AvesRankItem> topFromMap(Map<String, int> map, {bool withCountryFlag = false, int limit = 8}) {
    final entries = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) {
      return AvesRankItem(
        label: e.key,
        count: e.value,
        leadingEmoji: withCountryFlag ? _countryFlagForName(e.key) : null,
      );
    }).toList();
  }

  return AvesGalleryStats(
    totalAssets: totalImages + totalVideos,
    totalImages: totalImages,
    totalVideos: totalVideos,
    totalSizeBytes: totalSizeBytes,
    totalDurationSeconds: totalDurationSeconds,
    geotaggedCount: geotaggedCount,
    favoriteCount: favoriteCount,
    imageFormats: [
      for (final e in sortedImgFormats)
        AvesFormatCount(
          format: e.key,
          count: e.value,
          color: imagePalette[e.key] ?? const Color(0xFF78909C),
        ),
    ],
    videoFormats: [
      for (final e in sortedVidFormats)
        AvesFormatCount(
          format: e.key,
          count: e.value,
          color: videoPalette[e.key] ?? const Color(0xFF7E57C2),
          isVideo: true,
        ),
    ],
    countsByYear: Map.fromEntries(
      yearCounts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
    topCountries: topFromMap(countryCounts, withCountryFlag: true),
    topCities: topFromMap(cityCounts),
    topCameras: topFromMap(cameraCounts),
  );
}

String _countryFlagForName(String country) {
  final lower = country.toLowerCase();
  if (lower.contains('china') || lower.contains('中国') || lower.contains('中华人民共和国')) {
    return '🇨🇳';
  }
  if (lower.contains('japan') || lower.contains('日本')) {
    return '🇯🇵';
  }
  if (lower.contains('united states') || lower.contains('usa') || lower.contains('美国')) {
    return '🇺🇸';
  }
  if (lower.contains('thailand') || lower.contains('泰国')) {
    return '🇹🇭';
  }
  if (lower.contains('korea') || lower.contains('韩国')) {
    return '🇰🇷';
  }
  if (lower.contains('singapore') || lower.contains('新加坡')) {
    return '🇸🇬';
  }
  if (lower.contains('malaysia') || lower.contains('马来西亚')) {
    return '🇲🇾';
  }
  if (lower.contains('france') || lower.contains('法国')) {
    return '🇫🇷';
  }
  if (lower.contains('germany') || lower.contains('德国')) {
    return '🇩🇪';
  }
  if (lower.contains('united kingdom') || lower.contains('uk') || lower.contains('英国')) {
    return '🇬🇧';
  }
  if (lower.contains('australia') || lower.contains('澳大利亚')) {
    return '🇦🇺';
  }
  if (lower.contains('canada') || lower.contains('加拿大')) {
    return '🇨🇦';
  }
  if (lower.contains('italy') || lower.contains('意大利')) {
    return '🇮🇹';
  }
  if (lower.contains('spain') || lower.contains('西班牙')) {
    return '🇪🇸';
  }
  if (lower.contains('switzerland') || lower.contains('瑞士')) {
    return '🇨🇭';
  }
  return '🌍';
}

Future<void> openAvesStatisticsScreen(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const AvesStatisticsScreen(),
    ),
  );
}

/// Aves-inspired Panoramic Media Collection Statistics Screen (`统计`)
class AvesStatisticsScreen extends ConsumerWidget {
  const AvesStatisticsScreen({super.key});

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 MB';
    }
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) {
      return '0 分钟';
    }
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (days > 0) {
      return '$days 天 $hours 小时 $minutes 分钟';
    }
    if (hours > 0) {
      return '$hours 小时 $minutes 分钟';
    }
    return '$minutes 分钟 ${totalSeconds % 60} 秒';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(avesStatsScopeProvider);
    final statsAsync = ref.watch(avesGalleryStatsProvider);
    final tagsAsync = ref.watch(Store.tags.all());
    final numFmt = NumberFormat.decimalPattern();

    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
        actions: [
          IconButton(
            tooltip: '刷新统计',
            onPressed: () => ref.invalidate(avesGalleryStatsProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          // Scope Switcher
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: SegmentedButton<MediaSourceScope>(
              segments: const [
                ButtonSegment(
                  value: MediaSourceScope.all,
                  icon: Icon(Icons.dynamic_feed_rounded, size: 16),
                  label: Text('全部媒体'),
                ),
                ButtonSegment(
                  value: MediaSourceScope.serverOnly,
                  icon: Icon(Icons.cloud_outlined, size: 16),
                  label: Text('服务器图库'),
                ),
                ButtonSegment(
                  value: MediaSourceScope.localOnly,
                  icon: Icon(Icons.smartphone_rounded, size: 16),
                  label: Text('本地图库'),
                ),
              ],
              selected: {scope},
              onSelectionChanged: (sel) {
                ref.read(avesStatsScopeProvider.notifier).state = sel.first;
              },
            ),
          ),
          Expanded(
            child: statsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('统计计算出错: $err')),
              data: (stats) {
                final tags = tagsAsync.valueOrNull ?? const [];

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    // 1. Dual Ring Charts (Images & Videos)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _AvesRingChartWidget(
                          icon: Icons.photo_outlined,
                          totalCount: stats.totalImages,
                          label: '张照片',
                          segments: stats.imageFormats,
                        ),
                        _AvesRingChartWidget(
                          icon: Icons.movie_creation_outlined,
                          totalCount: stats.totalVideos,
                          label: '个视频',
                          segments: stats.videoFormats,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Format Breakdown List
                    for (final fmt in [...stats.imageFormats, ...stats.videoFormats])
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          final ext = fmt.format == 'JPEG'
                              ? 'jpg'
                              : fmt.format == 'RAW'
                              ? 'dng'
                              : fmt.format.toLowerCase();
                          ref.read(advancedMediaFilterProvider.notifier).update(
                                AdvancedMediaFilter(
                                  sourceScope: scope,
                                  fileFormats: {ext},
                                ),
                              );
                          unawaited(openAdvancedFilterBrowser(context, openSheetImmediately: false));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: fmt.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  fmt.format,
                                  style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(
                                numFmt.format(fmt.count),
                                style: context.textTheme.bodyMedium?.copyWith(
                                  color: context.colorScheme.onSurfaceVariant,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    // 2. Year Timeline Chart (matching Aves Year histogram)
                    if (stats.countsByYear.isNotEmpty) ...[
                      _AvesYearTimelineSection(
                        countsByYear: stats.countsByYear,
                        onYearTap: (year) {
                          ref.read(advancedMediaFilterProvider.notifier).update(
                                AdvancedMediaFilter(
                                  sourceScope: scope,
                                  takenAfter: DateTime(year, 1, 1),
                                  takenBefore: DateTime(year, 12, 31, 23, 59, 59),
                                ),
                              );
                          unawaited(openAdvancedFilterBrowser(context, openSheetImmediately: false));
                        },
                      ),
                      const SizedBox(height: 24),
                    ],

                    // 3. Key Metrics Table (Total Size, Total Duration, Location %)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _buildMetricRow(
                            context,
                            label: '总大小',
                            value: _formatBytes(stats.totalSizeBytes),
                          ),
                          const Divider(height: 20),
                          _buildMetricRow(
                            context,
                            label: '总时长',
                            value: _formatDuration(stats.totalDurationSeconds),
                          ),
                          const Divider(height: 20),
                          Row(
                            children: [
                              SizedBox(
                                width: 84,
                                child: Text(
                                  '位置',
                                  style: context.textTheme.bodyMedium?.copyWith(
                                    color: context.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(6),
                                            child: LinearProgressIndicator(
                                              value: stats.geotaggedRatio,
                                              minHeight: 8,
                                              backgroundColor: context.colorScheme.surfaceContainerHighest,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          '${(stats.geotaggedRatio * 100).round()}%',
                                          style: context.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${numFmt.format(stats.geotaggedCount)} 项包含 GPS 坐标',
                                      style: context.textTheme.bodySmall?.copyWith(
                                        color: context.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // 4. Top Countries
                    _buildRankingSection(
                      context,
                      title: '国家',
                      icon: Icons.public_rounded,
                      items: stats.topCountries,
                      totalReference: math.max(1, stats.geotaggedCount),
                      emptyHint: '同步服务器地理编码后将自动显示国家分布',
                      onItemTap: (item) {
                        ref.read(advancedMediaFilterProvider.notifier).update(
                              AdvancedMediaFilter(
                                sourceScope: scope,
                                textQuery: item.label,
                              ),
                            );
                        unawaited(openAdvancedFilterBrowser(context, openSheetImmediately: false));
                      },
                    ),

                    const SizedBox(height: 24),

                    // 5. Top Places / Cities
                    _buildRankingSection(
                      context,
                      title: '地点',
                      icon: Icons.place_outlined,
                      items: stats.topCities,
                      totalReference: math.max(1, stats.geotaggedCount),
                      emptyHint: '暂无城市/地点元数据记录',
                      onItemTap: (item) {
                        ref.read(advancedMediaFilterProvider.notifier).update(
                              AdvancedMediaFilter(
                                sourceScope: scope,
                                textQuery: item.label,
                              ),
                            );
                        unawaited(openAdvancedFilterBrowser(context, openSheetImmediately: false));
                      },
                    ),

                    const SizedBox(height: 24),

                    // 6. Top Camera Models
                    _buildRankingSection(
                      context,
                      title: '相机与设备',
                      icon: Icons.camera_alt_outlined,
                      items: stats.topCameras,
                      totalReference: math.max(1, stats.totalAssets),
                      emptyHint: '暂无相机 EXIF 型号记录',
                      onItemTap: (item) {
                        ref.read(advancedMediaFilterProvider.notifier).update(
                              AdvancedMediaFilter(
                                sourceScope: scope,
                                cameraModel: item.label,
                              ),
                            );
                        unawaited(openAdvancedFilterBrowser(context, openSheetImmediately: false));
                      },
                    ),

                    const SizedBox(height: 24),

                    // 7. Server Tags Section
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '标签 (${tags.length})',
                            style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => openTagExplorerScreen(context),
                          icon: const Icon(Icons.account_tree_outlined, size: 16),
                          label: const Text('管理标签树'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (tags.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        alignment: Alignment.center,
                        child: Text(
                          '暂无标签',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colorScheme.outline,
                          ),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in tags)
                            ActionChip(
                              avatar: Icon(Icons.label_outline_rounded, size: 16, color: context.colorScheme.primary),
                              label: Text(tag.value),
                              onPressed: () => openTagExplorerScreen(context),
                            ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(BuildContext context, {required String label, required String value}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildRankingSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<AvesRankItem> items,
    required int totalReference,
    required String emptyHint,
    required void Function(AvesRankItem item) onItemTap,
  }) {
    final numFmt = NumberFormat.decimalPattern();
    final maxCount = items.isEmpty ? 1 : math.max(1, items.first.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                emptyHint,
                style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.outline),
              ),
            ),
          )
        else
          for (final item in items)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onItemTap(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                child: Row(
                  children: [
                    if (item.leadingEmoji != null) ...[
                      Text(item.leadingEmoji!, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                    ] else ...[
                      Icon(icon, size: 18, color: context.colorScheme.primary),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: 4,
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (item.count / maxCount).clamp(0.04, 1.0),
                          minHeight: 6,
                          backgroundColor: context.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 54,
                      child: Text(
                        numFmt.format(item.count),
                        textAlign: TextAlign.right,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _AvesRingChartWidget extends StatelessWidget {
  final IconData icon;
  final int totalCount;
  final String label;
  final List<AvesFormatCount> segments;

  const _AvesRingChartWidget({
    required this.icon,
    required this.totalCount,
    required this.label,
    required this.segments,
  });

  @override
  Widget build(BuildContext context) {
    final numFmt = NumberFormat.decimalPattern();
    return SizedBox(
      width: 148,
      height: 148,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _AvesRingChartPainter(
                segments: segments,
                emptyColor: context.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: context.colorScheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(
                numFmt.format(totalCount),
                style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                label,
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvesRingChartPainter extends CustomPainter {
  final List<AvesFormatCount> segments;
  final Color emptyColor;

  const _AvesRingChartPainter({required this.segments, required this.emptyColor});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 14.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2 + 4);
    final total = segments.fold<int>(0, (s, item) => s + item.count);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    if (total <= 0) {
      paint.color = emptyColor;
      canvas.drawArc(arcRect, 0, math.pi * 2, false, paint);
      return;
    }

    double startAngle = -math.pi / 2;
    const gapRadians = 0.03;
    for (final seg in segments) {
      final sweep = (seg.count / total) * (math.pi * 2);
      paint.color = seg.color;
      canvas.drawArc(
        arcRect,
        startAngle,
        math.max(0.02, sweep - (segments.length > 1 ? gapRadians : 0)),
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _AvesRingChartPainter oldDelegate) {
    return oldDelegate.segments != segments;
  }
}

class _AvesYearTimelineSection extends StatelessWidget {
  final Map<int, int> countsByYear;
  final void Function(int year) onYearTap;

  const _AvesYearTimelineSection({
    required this.countsByYear,
    required this.onYearTap,
  });

  @override
  Widget build(BuildContext context) {
    final years = countsByYear.keys.toList()..sort();
    final minYear = years.first;
    final maxYear = years.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 120,
          width: double.infinity,
          child: CustomPaint(
            painter: _AvesYearTimelinePainter(
              countsByYear: countsByYear,
              lineColor: context.colorScheme.primary,
              axisColor: context.colorScheme.outlineVariant,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$minYear', style: context.textTheme.labelSmall),
            if (maxYear - minYear >= 4)
              Text('${(minYear + maxYear) ~/ 2}', style: context.textTheme.labelSmall),
            Text('$maxYear', style: context.textTheme.labelSmall),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final e in countsByYear.entries.toList().reversed.take(10))
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${e.key}年 (${e.value})'),
                    onPressed: () => onYearTap(e.key),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvesYearTimelinePainter extends CustomPainter {
  final Map<int, int> countsByYear;
  final Color lineColor;
  final Color axisColor;

  const _AvesYearTimelinePainter({
    required this.countsByYear,
    required this.lineColor,
    required this.axisColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (countsByYear.isEmpty) {
      return;
    }

    final years = countsByYear.keys.toList()..sort();
    final minY = years.first;
    final maxY = math.max(minY + 1, years.last);
    final maxCount = math.max(1, countsByYear.values.fold<int>(0, math.max));

    final bottomY = size.height - 6;
    final chartHeight = bottomY - 10;

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, bottomY), Offset(size.width, bottomY), axisPaint);

    final path = Path();
    final fillPath = Path();
    final span = math.max(1, maxY - minY);

    Offset? firstPt;
    Offset? lastPt;

    for (int y = minY; y <= maxY; y++) {
      final c = countsByYear[y] ?? 0;
      final x = ((y - minY) / span) * size.width;
      final py = bottomY - (c / maxCount) * chartHeight;
      final pt = Offset(x, py);
      if (firstPt == null) {
        firstPt = pt;
        path.moveTo(pt.dx, pt.dy);
        fillPath.moveTo(pt.dx, bottomY);
        fillPath.lineTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
        fillPath.lineTo(pt.dx, pt.dy);
      }
      lastPt = pt;
    }

    if (lastPt != null) {
      fillPath.lineTo(lastPt.dx, bottomY);
      fillPath.close();

      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.35),
            lineColor.withValues(alpha: 0.03),
          ],
        ).createShader(Offset.zero & size);
      canvas.drawPath(fillPath, fillPaint);

      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = lineColor;
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AvesYearTimelinePainter oldDelegate) {
    return oldDelegate.countsByYear != countsByYear || oldDelegate.lineColor != lineColor;
  }
}
