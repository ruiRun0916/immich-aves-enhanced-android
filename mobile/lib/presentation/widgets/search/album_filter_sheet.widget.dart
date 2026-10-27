import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/album_media_filter.provider.dart';

/// 相册内「就地筛选」面板。
///
/// 有意做得比主界面那套全量高级筛选轻：只用相册里照片本身就能判定的条件，
/// 应用后立刻在当前相册里重建时间线，不跳转到任何结果页。
/// 打开精简筛选面板并返回结果（不绑定任何 album provider）。
///
/// 供「本地图库」这类资产已经在内存里的场景直接使用：
/// 拿到 filter 后本地过滤即可，不需要服务端参与。
Future<AdvancedMediaFilter?> showAvesFilterSheet(
  BuildContext context, {
  AdvancedMediaFilter initial = AdvancedMediaFilter.empty,
}) {
  return showModalBottomSheet<AdvancedMediaFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _AlbumFilterSheet(initial: initial),
  );
}

Future<void> showAlbumFilterSheet(BuildContext context, WidgetRef ref, {required String albumId}) async {
  final filter = ref.read(albumMediaFilterProvider(albumId));
  final applied = await showAvesFilterSheet(context, initial: filter);
  if (applied != null) {
    ref.read(albumMediaFilterProvider(albumId).notifier).state = applied;
  }
}

class _AlbumFilterSheet extends StatefulWidget {
  final AdvancedMediaFilter initial;

  const _AlbumFilterSheet({required this.initial});

  @override
  State<_AlbumFilterSheet> createState() => _AlbumFilterSheetState();
}

class _AlbumFilterSheetState extends State<_AlbumFilterSheet> {
  late DateTime? _takenAfter;
  late DateTime? _takenBefore;
  late AssetType? _mediaType;
  late Set<String> _formats;
  late TriStateFilter _favorite;
  late TextEditingController _queryController;

  static const _formatOptions = <String, String>{
    'jpg': 'JPG',
    'png': 'PNG',
    'heic': 'HEIC',
    'raw': 'RAW',
    'gif': 'GIF',
    'webp': 'WebP',
    'mp4': 'MP4',
    'mov': 'MOV',
  };

  @override
  void initState() {
    super.initState();
    _takenAfter = widget.initial.takenAfter;
    _takenBefore = widget.initial.takenBefore;
    _mediaType = widget.initial.mediaType;
    _formats = {...widget.initial.fileFormats};
    _favorite = widget.initial.favoriteFilter;
    _queryController = TextEditingController(text: widget.initial.textQuery ?? '');
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  AdvancedMediaFilter _build() {
    return AdvancedMediaFilter(
      takenAfter: _takenAfter,
      takenBefore: _takenBefore,
      mediaType: _mediaType,
      fileFormats: _formats,
      favoriteFilter: _favorite,
      textQuery: _queryController.text.trim().isEmpty ? null : _queryController.text.trim(),
    );
  }

  void _applyPreset(_DatePreset preset) {
    final now = DateTime.now();
    setState(() {
      switch (preset) {
        case _DatePreset.any:
          _takenAfter = null;
          _takenBefore = null;
        case _DatePreset.thisWeek:
          _takenAfter = now.subtract(const Duration(days: 7));
          _takenBefore = null;
        case _DatePreset.thisMonth:
          _takenAfter = DateTime(now.year, now.month, 1);
          _takenBefore = null;
        case _DatePreset.thisYear:
          _takenAfter = DateTime(now.year, 1, 1);
          _takenBefore = null;
      }
    });
  }

  _DatePreset get _currentPreset {
    if (_takenAfter == null && _takenBefore == null) {
      return _DatePreset.any;
    }
    final now = DateTime.now();
    final after = _takenAfter;
    if (after == null) {
      return _DatePreset.any;
    }
    if (after.difference(now.subtract(const Duration(days: 7))).inMinutes.abs() <= 1) {
      return _DatePreset.thisWeek;
    }
    if (after.year == now.year && after.month == now.month && after.day == 1) {
      return _DatePreset.thisMonth;
    }
    if (after.year == now.year && after.month == 1 && after.day == 1) {
      return _DatePreset.thisYear;
    }
    return _DatePreset.any;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '在相册内筛选',
                      style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _takenAfter = null;
                      _takenBefore = null;
                      _mediaType = null;
                      _formats = {};
                      _favorite = TriStateFilter.any;
                      _queryController.clear();
                    }),
                    child: const Text('重置'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _sectionTitle(context, '媒体类型'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in <AssetType?, String>{
                        null: '全部',
                        AssetType.image: '图片',
                        AssetType.video: '视频',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _mediaType == entry.key,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _mediaType = entry.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _sectionTitle(context, '格式'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final entry in _formatOptions.entries)
                        FilterChip(
                          label: Text(entry.value),
                          selected: _formats.contains(entry.key),
                          visualDensity: VisualDensity.compact,
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _formats.add(entry.key);
                            } else {
                              _formats.remove(entry.key);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _sectionTitle(context, '拍摄时间'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final preset in _DatePreset.values)
                        ChoiceChip(
                          label: Text(preset.label),
                          selected: _currentPreset == preset,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => _applyPreset(preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _sectionTitle(context, '收藏'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in <TriStateFilter, String>{
                        TriStateFilter.any: '不限',
                        TriStateFilter.yes: '仅收藏',
                        TriStateFilter.no: '未收藏',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _favorite == entry.key,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _favorite = entry.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _sectionTitle(context, '文件名 / 关键词'),
                  TextField(
                    controller: _queryController,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '例如 IMG_2026、screenshot',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(AdvancedMediaFilter.empty),
                      child: const Text('清除筛选'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_build()),
                      child: const Text('应用'),
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

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

enum _DatePreset {
  any('不限'),
  thisWeek('最近 7 天'),
  thisMonth('本月'),
  thisYear('今年');

  final String label;
  const _DatePreset(this.label);
}
