import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/data/store.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/search/advanced_filter.provider.dart';
import 'package:intl/intl.dart';

Future<void> showAdvancedFilterSheet(
  BuildContext context, {
  ValueChanged<AdvancedMediaFilter>? onApplied,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (_, scrollController) => AdvancedFilterBottomSheet(
        scrollController: scrollController,
        onApplied: onApplied,
      ),
    ),
  );
}

Future<void> openAdvancedFilterBrowser(BuildContext context, {bool openSheetImmediately = false}) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AdvancedFilterBrowserScreen(openSheetImmediately: openSheetImmediately),
    ),
  );
}

class AdvancedFilterBottomSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final ValueChanged<AdvancedMediaFilter>? onApplied;

  const AdvancedFilterBottomSheet({
    super.key,
    required this.scrollController,
    this.onApplied,
  });

  @override
  ConsumerState<AdvancedFilterBottomSheet> createState() => _AdvancedFilterBottomSheetState();
}

class _AdvancedFilterBottomSheetState extends ConsumerState<AdvancedFilterBottomSheet> {
  late AdvancedMediaFilter _draft;
  late TextEditingController _minWidthController;
  late TextEditingController _maxWidthController;
  late TextEditingController _minHeightController;
  late TextEditingController _maxHeightController;
  late TextEditingController _minSizeMbController;
  late TextEditingController _maxSizeMbController;
  late TextEditingController _cameraMakeController;
  late TextEditingController _cameraModelController;
  late TextEditingController _filenameQueryController;

  static const List<String> _commonFormats = [
    'jpg',
    'png',
    'heic',
    'webp',
    'avif',
    'dng',
    'cr2',
    'nef',
    'arw',
    'tiff',
    'svg',
    'gif',
    'mp4',
    'mov',
    'mkv',
  ];

  @override
  void initState() {
    super.initState();
    _draft = ref.read(advancedMediaFilterProvider);
    _initControllersFromDraft();
  }

  void _initControllersFromDraft() {
    _minWidthController = TextEditingController(text: _draft.minWidth?.toString() ?? '');
    _maxWidthController = TextEditingController(text: _draft.maxWidth?.toString() ?? '');
    _minHeightController = TextEditingController(text: _draft.minHeight?.toString() ?? '');
    _maxHeightController = TextEditingController(text: _draft.maxHeight?.toString() ?? '');
    _minSizeMbController = TextEditingController(
      text: _draft.minSizeBytes != null
          ? (_draft.minSizeBytes! / (1024 * 1024)).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')
          : '',
    );
    _maxSizeMbController = TextEditingController(
      text: _draft.maxSizeBytes != null
          ? (_draft.maxSizeBytes! / (1024 * 1024)).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')
          : '',
    );
    _cameraMakeController = TextEditingController(text: _draft.cameraMake ?? '');
    _cameraModelController = TextEditingController(text: _draft.cameraModel ?? '');
    _filenameQueryController = TextEditingController(text: _draft.textQuery ?? '');
  }

  @override
  void dispose() {
    _minWidthController.dispose();
    _maxWidthController.dispose();
    _minHeightController.dispose();
    _maxHeightController.dispose();
    _minSizeMbController.dispose();
    _maxSizeMbController.dispose();
    _cameraMakeController.dispose();
    _cameraModelController.dispose();
    _filenameQueryController.dispose();
    super.dispose();
  }

  AdvancedMediaFilter _collectFilter() {
    final minW = int.tryParse(_minWidthController.text.trim());
    final maxW = int.tryParse(_maxWidthController.text.trim());
    final minH = int.tryParse(_minHeightController.text.trim());
    final maxH = int.tryParse(_maxHeightController.text.trim());
    final minMb = double.tryParse(_minSizeMbController.text.trim());
    final maxMb = double.tryParse(_maxSizeMbController.text.trim());

    return _draft.copyWith(
      minWidth: minW,
      clearMinWidth: minW == null,
      maxWidth: maxW,
      clearMaxWidth: maxW == null,
      minHeight: minH,
      clearMinHeight: minH == null,
      maxHeight: maxH,
      clearMaxHeight: maxH == null,
      minSizeBytes: minMb != null ? (minMb * 1024 * 1024).round() : null,
      clearMinSizeBytes: minMb == null,
      maxSizeBytes: maxMb != null ? (maxMb * 1024 * 1024).round() : null,
      clearMaxSizeBytes: maxMb == null,
      cameraMake: _cameraMakeController.text.trim().isEmpty ? null : _cameraMakeController.text.trim(),
      clearCameraMake: _cameraMakeController.text.trim().isEmpty,
      cameraModel: _cameraModelController.text.trim().isEmpty ? null : _cameraModelController.text.trim(),
      clearCameraModel: _cameraModelController.text.trim().isEmpty,
      textQuery: _filenameQueryController.text.trim().isEmpty ? null : _filenameQueryController.text.trim(),
      clearTextQuery: _filenameQueryController.text.trim().isEmpty,
    );
  }

  void _resetAll() {
    setState(() {
      _draft = AdvancedMediaFilter.empty;
      _minWidthController.clear();
      _maxWidthController.clear();
      _minHeightController.clear();
      _maxHeightController.clear();
      _minSizeMbController.clear();
      _maxSizeMbController.clear();
      _cameraMakeController.clear();
      _cameraModelController.clear();
      _filenameQueryController.clear();
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final after = _draft.takenAfter;
    final before = _draft.takenBefore;
    final initialRange = (after != null && before != null)
        ? DateTimeRange(
            start: after,
            end: before.isAfter(now) ? now : before,
          )
        : DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: now,
      initialDateRange: initialRange,
    );
    if (picked != null && mounted) {
      setState(() {
        _draft = _draft.copyWith(
          takenAfter: picked.start,
          takenBefore: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final knownCamerasAsync = ref.watch(knownCameraModelsProvider);
    final albumsAsync = ref.watch(filterableAlbumsProvider);
    final tagsAsync = ref.watch(Store.tags.all());
    final dateFmt = DateFormat('yyyy-MM-dd');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, color: context.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '高级照片筛选 (Aves 增强)',
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: _resetAll,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('一键清除'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const _SectionTitle(icon: Icons.storage_rounded, title: '1. 媒体来源 (本地 / 服务器)'),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _ChoiceChipItem(
                    label: '全部 (本地+服务器)',
                    selected: _draft.sourceScope == MediaSourceScope.all,
                    onSelected: () => setState(() => _draft = _draft.copyWith(sourceScope: MediaSourceScope.all)),
                  ),
                  _ChoiceChipItem(
                    label: '仅服务器媒体',
                    selected: _draft.sourceScope == MediaSourceScope.serverOnly,
                    onSelected: () =>
                        setState(() => _draft = _draft.copyWith(sourceScope: MediaSourceScope.serverOnly)),
                  ),
                  _ChoiceChipItem(
                    label: '仅本地媒体',
                    selected: _draft.sourceScope == MediaSourceScope.localOnly,
                    onSelected: () => setState(() => _draft = _draft.copyWith(sourceScope: MediaSourceScope.localOnly)),
                  ),
                  _ChoiceChipItem(
                    label: '已备份合并媒体',
                    selected: _draft.sourceScope == MediaSourceScope.mergedOnly,
                    onSelected: () =>
                        setState(() => _draft = _draft.copyWith(sourceScope: MediaSourceScope.mergedOnly)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const _SectionTitle(icon: Icons.perm_media_outlined, title: '2. 媒体类型 (图片 / 视频)'),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _ChoiceChipItem(
                    label: '全部类型',
                    selected: _draft.mediaType == null,
                    onSelected: () => setState(() => _draft = _draft.copyWith(clearMediaType: true)),
                  ),
                  _ChoiceChipItem(
                    label: '仅图片 (Image)',
                    selected: _draft.mediaType == AssetType.image,
                    onSelected: () => setState(() => _draft = _draft.copyWith(mediaType: AssetType.image)),
                  ),
                  _ChoiceChipItem(
                    label: '仅视频 (Video)',
                    selected: _draft.mediaType == AssetType.video,
                    onSelected: () => setState(() => _draft = _draft.copyWith(mediaType: AssetType.video)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const _SectionTitle(icon: Icons.calendar_month_outlined, title: '3. 拍摄日期范围'),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.date_range_rounded, size: 16),
                    label: Text(
                      (_draft.takenAfter != null || _draft.takenBefore != null)
                          ? '${_draft.takenAfter != null ? dateFmt.format(_draft.takenAfter!) : '不限'} ~ ${_draft.takenBefore != null ? dateFmt.format(_draft.takenBefore!) : '今天'}'
                          : '选择日期范围',
                    ),
                    onPressed: _pickDateRange,
                  ),
                  ActionChip(
                    label: const Text('近 7 天'),
                    onPressed: () {
                      final now = DateTime.now();
                      setState(() {
                        _draft = _draft.copyWith(
                          takenAfter: now.subtract(const Duration(days: 7)),
                          takenBefore: now,
                        );
                      });
                    },
                  ),
                  ActionChip(
                    label: const Text('近 30 天'),
                    onPressed: () {
                      final now = DateTime.now();
                      setState(() {
                        _draft = _draft.copyWith(
                          takenAfter: now.subtract(const Duration(days: 30)),
                          takenBefore: now,
                        );
                      });
                    },
                  ),
                  ActionChip(
                    label: const Text('今年'),
                    onPressed: () {
                      final now = DateTime.now();
                      setState(() {
                        _draft = _draft.copyWith(
                          takenAfter: DateTime(now.year, 1, 1),
                          takenBefore: now,
                        );
                      });
                    },
                  ),
                  if (_draft.takenAfter != null || _draft.takenBefore != null)
                    ActionChip(
                      avatar: const Icon(Icons.clear_rounded, size: 16),
                      label: const Text('清除日期'),
                      onPressed: () => setState(
                        () => _draft = _draft.copyWith(clearTakenAfter: true, clearTakenBefore: true),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              const _SectionTitle(icon: Icons.insert_drive_file_outlined, title: '4. 文件格式 / 扩展名 (可多选)'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _commonFormats.map((fmt) {
                  final selected = _draft.fileFormats.contains(fmt);
                  return FilterChip(
                    label: Text(fmt.toUpperCase()),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (val) {
                      setState(() {
                        final next = Set<String>.from(_draft.fileFormats);
                        if (val) {
                          next.add(fmt);
                        } else {
                          next.remove(fmt);
                        }
                        _draft = _draft.copyWith(fileFormats: next);
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              const _SectionTitle(icon: Icons.aspect_ratio_rounded, title: '5. 图片宽度与高度 (像素 px)'),
              Row(
                children: [
                  Expanded(
                    child: _CompactNumberField(
                      controller: _minWidthController,
                      label: '最小宽度 (px)',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CompactNumberField(
                      controller: _maxWidthController,
                      label: '最大宽度 (px)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _CompactNumberField(
                      controller: _minHeightController,
                      label: '最小高度 (px)',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CompactNumberField(
                      controller: _maxHeightController,
                      label: '最大高度 (px)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: const Text('≥ 1080p'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _minWidthController.text = '1920';
                      _minHeightController.text = '1080';
                    }),
                  ),
                  ActionChip(
                    label: const Text('≥ 4K (3840×2160)'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _minWidthController.text = '3840';
                      _minHeightController.text = '2160';
                    }),
                  ),
                  ActionChip(
                    label: const Text('清空尺寸'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _minWidthController.clear();
                      _maxWidthController.clear();
                      _minHeightController.clear();
                      _maxHeightController.clear();
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const _SectionTitle(icon: Icons.data_usage_rounded, title: '6. 文件大小范围 (MB)'),
              Row(
                children: [
                  Expanded(
                    child: _CompactNumberField(
                      controller: _minSizeMbController,
                      label: '最小大小 (MB)',
                      allowDecimal: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CompactNumberField(
                      controller: _maxSizeMbController,
                      label: '最大大小 (MB)',
                      allowDecimal: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: const Text('> 5 MB'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _minSizeMbController.text = '5'),
                  ),
                  ActionChip(
                    label: const Text('> 20 MB'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _minSizeMbController.text = '20'),
                  ),
                  ActionChip(
                    label: const Text('> 100 MB (大视频/RAW)'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _minSizeMbController.text = '100'),
                  ),
                  ActionChip(
                    label: const Text('清空大小'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _minSizeMbController.clear();
                      _maxSizeMbController.clear();
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const _SectionTitle(icon: Icons.location_on_outlined, title: '7. 是否包含 GPS 坐标'),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _ChoiceChipItem(
                    label: '不限',
                    selected: _draft.gpsFilter == TriStateFilter.any,
                    onSelected: () => setState(() => _draft = _draft.copyWith(gpsFilter: TriStateFilter.any)),
                  ),
                  _ChoiceChipItem(
                    label: '包含 GPS 位置',
                    selected: _draft.gpsFilter == TriStateFilter.yes,
                    onSelected: () => setState(() => _draft = _draft.copyWith(gpsFilter: TriStateFilter.yes)),
                  ),
                  _ChoiceChipItem(
                    label: '无 GPS 坐标',
                    selected: _draft.gpsFilter == TriStateFilter.no,
                    onSelected: () => setState(() => _draft = _draft.copyWith(gpsFilter: TriStateFilter.no)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const _SectionTitle(icon: Icons.camera_alt_outlined, title: '8. 相机制造商与型号'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cameraMakeController,
                      decoration: const InputDecoration(
                        labelText: '制造商 (如 Xiaomi, Sony)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _cameraModelController,
                      decoration: const InputDecoration(
                        labelText: '型号 (如 M2102K1C, iPhone)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              knownCamerasAsync.maybeWhen(
                data: (models) {
                  if (models.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: models.take(12).map((cam) {
                        final label = [cam.make, cam.model]
                            .where((s) => s != null && s.trim().isNotEmpty)
                            .join(' ');
                        final isSelected = _cameraModelController.text == cam.model;
                        return ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(
                            isSelected ? Icons.check_circle : Icons.camera_outlined,
                            size: 15,
                          ),
                          label: Text(label, style: const TextStyle(fontSize: 12)),
                          onPressed: () {
                            setState(() {
                              _cameraMakeController.text = cam.make ?? '';
                              _cameraModelController.text = cam.model;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),

              const _SectionTitle(icon: Icons.favorite_border_rounded, title: '9. 收藏状态'),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _ChoiceChipItem(
                    label: '不限',
                    selected: _draft.favoriteFilter == TriStateFilter.any,
                    onSelected: () => setState(() => _draft = _draft.copyWith(favoriteFilter: TriStateFilter.any)),
                  ),
                  _ChoiceChipItem(
                    label: '仅已收藏',
                    selected: _draft.favoriteFilter == TriStateFilter.yes,
                    onSelected: () => setState(() => _draft = _draft.copyWith(favoriteFilter: TriStateFilter.yes)),
                  ),
                  _ChoiceChipItem(
                    label: '未收藏',
                    selected: _draft.favoriteFilter == TriStateFilter.no,
                    onSelected: () => setState(() => _draft = _draft.copyWith(favoriteFilter: TriStateFilter.no)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const _SectionTitle(icon: Icons.photo_album_outlined, title: '10. 相册归属'),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _ChoiceChipItem(
                    label: '不限相册',
                    selected: _draft.albumId == null && !_draft.notInAnyAlbum,
                    onSelected: () => setState(
                      () => _draft = _draft.copyWith(
                        clearAlbum: true,
                        notInAnyAlbum: false,
                      ),
                    ),
                  ),
                  _ChoiceChipItem(
                    label: '未加入任何相册',
                    selected: _draft.notInAnyAlbum,
                    onSelected: () => setState(
                      () => _draft = _draft.copyWith(
                        clearAlbum: true,
                        notInAnyAlbum: true,
                      ),
                    ),
                  ),
                ],
              ),
              albumsAsync.maybeWhen(
                data: (albums) {
                  final combined = <({String id, String name, bool isLocal})>[
                    ...albums.remote.map((a) => (id: a.id, name: '☁️ ${a.name}', isLocal: false)),
                    ...albums.local.map((a) => (id: a.id, name: '📱 ${a.name}', isLocal: true)),
                  ];
                  if (combined.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: combined.take(20).map((album) {
                        final selected = _draft.albumId == album.id;
                        return ChoiceChip(
                          label: Text(album.name, style: const TextStyle(fontSize: 12)),
                          selected: selected,
                          visualDensity: VisualDensity.compact,
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                _draft = _draft.copyWith(
                                  albumId: album.id,
                                  albumName: album.name,
                                  isLocalAlbum: album.isLocal,
                                  notInAnyAlbum: false,
                                );
                              } else {
                                _draft = _draft.copyWith(clearAlbum: true);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),

              const _SectionTitle(icon: Icons.label_outline_rounded, title: '11. 服务器标签筛选'),
              tagsAsync.maybeWhen(
                data: (List<Tag> tags) {
                  if (tags.isEmpty) {
                    return Text(
                      '暂无服务器标签，可在详情页或标签管理中创建',
                      style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurfaceVariant),
                    );
                  }
                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: tags.map((tag) {
                      final selected = _draft.tags.any((t) => t.id == tag.id);
                      return FilterChip(
                        label: Text(tag.value.replaceAll('/', ' › ')),
                        selected: selected,
                        visualDensity: VisualDensity.compact,
                        onSelected: (val) {
                          setState(() {
                            final nextTags = Set<Tag>.from(_draft.tags);
                            if (val) {
                              nextTags.add(tag);
                            } else {
                              nextTags.removeWhere((t) => t.id == tag.id);
                            }
                            _draft = _draft.copyWith(tags: nextTags);
                          });
                        },
                      );
                    }).toList(),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),

              const _SectionTitle(icon: Icons.abc_rounded, title: '12. 文件名关键词'),
              TextField(
                controller: _filenameQueryController,
                decoration: const InputDecoration(
                  hintText: '输入文件名包含的字符 (例如 IMG_2026, DJI, PXL)...',
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () {
                    final finalFilter = _collectFilter();
                    unawaited(ref.read(advancedFilteredAssetsProvider.notifier).applyFilter(finalFilter));
                    widget.onApplied?.call(finalFilter);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.filter_alt_rounded),
                  label: const Text('应用组合筛选'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: context.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ChoiceChipItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _ChoiceChipItem({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => onSelected(),
    );
  }
}

class _CompactNumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool allowDecimal;

  const _CompactNumberField({
    required this.controller,
    required this.label,
    this.allowDecimal = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Full-screen browser page for viewing and paginating P0-2 Advanced Photo Filter results.
class AdvancedFilterBrowserScreen extends ConsumerStatefulWidget {
  final bool openSheetImmediately;

  const AdvancedFilterBrowserScreen({super.key, this.openSheetImmediately = false});

  @override
  ConsumerState<AdvancedFilterBrowserScreen> createState() => _AdvancedFilterBrowserScreenState();
}

class _AdvancedFilterBrowserScreenState extends ConsumerState<AdvancedFilterBrowserScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final activeFilter = ref.read(advancedMediaFilterProvider);
      final state = ref.read(advancedFilteredAssetsProvider);
      if (activeFilter.isNotEmpty && state.assets.isEmpty && !state.isLoading) {
        unawaited(ref.read(advancedFilteredAssetsProvider.notifier).applyFilter(activeFilter));
      }
      if (widget.openSheetImmediately || activeFilter.isEmpty) {
        unawaited(showAdvancedFilterSheet(context));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(advancedMediaFilterProvider);
    final resultsState = ref.watch(advancedFilteredAssetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          filter.isEmpty
              ? '高级照片筛选'
              : '高级筛选 (${resultsState.assets.length}${resultsState.hasMore ? '+' : ''})',
        ),
        actions: [
          if (filter.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.filter_alt_off_outlined),
              tooltip: '清除所有筛选',
              onPressed: () => ref.read(advancedFilteredAssetsProvider.notifier).clear(),
            ),
          IconButton(
            icon: Badge(
              isLabelVisible: filter.isNotEmpty,
              label: Text('${filter.activeFilterCount}'),
              child: const Icon(Icons.tune_rounded),
            ),
            tooltip: '编辑筛选条件',
            onPressed: () => showAdvancedFilterSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (filter.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: context.colorScheme.surfaceContainerLow,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ..._buildSummaryChips(context, filter),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Icon(Icons.clear_all_rounded, size: 16),
                      label: const Text('清除全部'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => ref.read(advancedFilteredAssetsProvider.notifier).clear(),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _buildBody(context, filter, resultsState),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSummaryChips(BuildContext context, AdvancedMediaFilter filter) {
    final chips = <Widget>[];
    void addChip(String label) {
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Chip(
            label: Text(label, style: const TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
          ),
        ),
      );
    }

    if (filter.sourceScope != MediaSourceScope.all) {
      addChip(filter.sourceScope.label);
    }
    if (filter.mediaType != null) {
      addChip(filter.mediaType == AssetType.image ? '图片' : '视频');
    }
    if (filter.takenAfter != null || filter.takenBefore != null) {
      final fmt = DateFormat('yyyy-MM-dd');
      addChip(
        '日期: ${filter.takenAfter != null ? fmt.format(filter.takenAfter!) : ''}~${filter.takenBefore != null ? fmt.format(filter.takenBefore!) : ''}',
      );
    }
    if (filter.fileFormats.isNotEmpty) {
      addChip('格式: ${filter.fileFormats.map((e) => e.toUpperCase()).join('/')}');
    }
    if (filter.minWidth != null || filter.maxWidth != null || filter.minHeight != null || filter.maxHeight != null) {
      addChip('分辨率筛选');
    }
    if (filter.minSizeBytes != null || filter.maxSizeBytes != null) {
      addChip('文件大小筛选');
    }
    if (filter.gpsFilter != TriStateFilter.any) {
      addChip(filter.gpsFilter == TriStateFilter.yes ? '含 GPS' : '无 GPS');
    }
    if (filter.cameraMake != null || filter.cameraModel != null) {
      addChip('相机: ${[filter.cameraMake, filter.cameraModel].whereType<String>().join(' ')}');
    }
    if (filter.favoriteFilter != TriStateFilter.any) {
      addChip(filter.favoriteFilter == TriStateFilter.yes ? '已收藏' : '未收藏');
    }
    if (filter.notInAnyAlbum) {
      addChip('未入相册');
    } else if (filter.albumName != null) {
      addChip('相册: ${filter.albumName}');
    }
    if (filter.tags.isNotEmpty) {
      addChip('标签: ${filter.tags.map((t) => t.value).join(', ')}');
    }
    if (filter.textQuery != null) {
      addChip('文件名: ${filter.textQuery}');
    }
    return chips;
  }

  Widget _buildBody(
    BuildContext context,
    AdvancedMediaFilter filter,
    AdvancedFilteredAssetsState state,
  ) {
    if (filter.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_alt_outlined, size: 56, color: context.colorScheme.primary),
              const SizedBox(height: 12),
              Text('尚未设置筛选条件', style: context.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '支持组合拍摄日期、图片/视频、格式、分辨率、文件大小、GPS、相机型号、收藏、相册、标签及本地/服务器来源进行筛选。',
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => showAdvancedFilterSheet(context),
                icon: const Icon(Icons.tune_rounded),
                label: const Text('配置筛选条件'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.isLoading && state.assets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.assets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('筛选出错: ${state.error}', style: TextStyle(color: context.colorScheme.error)),
        ),
      );
    }

    if (state.assets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 56, color: context.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('未找到符合所有筛选条件的媒体', style: context.textTheme.titleMedium),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => showAdvancedFilterSheet(context),
                icon: const Icon(Icons.tune_rounded),
                label: const Text('调整筛选条件'),
              ),
            ],
          ),
        ),
      );
    }

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical) {
          final remaining = notification.metrics.maxScrollExtent - notification.metrics.pixels;
          if (remaining < 400 && state.hasMore && !state.isLoading) {
            unawaited(ref.read(advancedFilteredAssetsProvider.notifier).loadNextPage());
          }
        }
        return false;
      },
      child: ProviderScope(
        key: ValueKey('adv_filter_${state.assets.length}_${state.currentPage}'),
        overrides: [
          timelineServiceProvider.overrideWith((ref) {
            final service = ref
                .watch(timelineFactoryProvider)
                .fromAssetsWithBuckets(state.assets, TimelineOrigin.search);
            ref.onDispose(service.dispose);
            return service;
          }),
        ],
        child: const Timeline(
          appBar: null,
          showStorageIndicator: true,
        ),
      ),
    );
  }
}
