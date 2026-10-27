import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/data/store.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/immich_asset_aves.repository.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

Future<void> openTagExplorerScreen(BuildContext context, {Tag? initialTag}) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TagExplorerScreen(initialTag: initialTag),
    ),
  );
}

class _TagTreeNode {
  final String segmentName;
  final String fullPath;
  Tag? exactTag;
  final Map<String, _TagTreeNode> children = {};

  _TagTreeNode({
    required this.segmentName,
    required this.fullPath,
  });

  List<Tag> collectAllDescendantTags() {
    final result = <Tag>[];
    if (exactTag != null) {
      result.add(exactTag!);
    }
    for (final child in children.values) {
      result.addAll(child.collectAllDescendantTags());
    }
    return result;
  }
}

class TagExplorerScreen extends ConsumerStatefulWidget {
  final Tag? initialTag;

  const TagExplorerScreen({super.key, this.initialTag});

  @override
  ConsumerState<TagExplorerScreen> createState() => _TagExplorerScreenState();
}

class _TagExplorerScreenState extends ConsumerState<TagExplorerScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _treeMode = true;
  Set<String> _selectedTagIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialTag != null) {
      _selectedTagIds = {widget.initialTag!.id};
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, _TagTreeNode> _buildHierarchy(List<Tag> tags) {
    final roots = <String, _TagTreeNode>{};
    for (final tag in tags) {
      final segments = tag.value
          .split('/')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (segments.isEmpty) {
        continue;
      }

      var currentMap = roots;
      var currentPath = '';
      _TagTreeNode? currentNode;

      for (var i = 0; i < segments.length; i++) {
        final seg = segments[i];
        currentPath = currentPath.isEmpty ? seg : '$currentPath/$seg';
        currentNode = currentMap.putIfAbsent(
          seg,
          () => _TagTreeNode(segmentName: seg, fullPath: currentPath),
        );
        if (i == segments.length - 1) {
          currentNode.exactTag = tag;
        }
        currentMap = currentNode.children;
      }
    }
    return roots;
  }

  Future<void> _showCreateTagDialog({String? parentPrefix}) async {
    final controller = TextEditingController(
      text: parentPrefix != null && parentPrefix.isNotEmpty ? '$parentPrefix/' : '',
    );
    final createdValue = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建服务器标签'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '支持使用 "/" 创建层级标签 (例如: 旅行/日本/东京 或 家庭/聚会)',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '标签名称或层级路径',
                hintText: '例如: 旅行/2026',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (createdValue == null || createdValue.isEmpty || !mounted) {
      return;
    }

    try {
      await ref.read(Store.tags).upsert([createdValue]);
      ref.invalidate(Store.tags.all());
      if (mounted) {
        ImmichToast.show(
          context: context,
          msg: '已创建标签 "$createdValue"',
          toastType: ToastType.success,
          gravity: ToastGravity.BOTTOM,
        );
      }
    } catch (error) {
      if (mounted) {
        ImmichToast.show(
          context: context,
          msg: '创建标签失败 (请检查服务器连接或版本支持): $error',
          toastType: ToastType.error,
          gravity: ToastGravity.BOTTOM,
        );
      }
    }
  }

  Future<void> _confirmDeleteTag(Tag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器标签'),
        content: Text('确定要从 Immich 服务器删除标签 "${tag.value}" 吗？照片本身不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除标签'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await ref.read(Store.tags).deleteTag(tag.id);
      setState(() {
        _selectedTagIds.remove(tag.id);
      });
      ref.invalidate(Store.tags.all());
      if (mounted) {
        ImmichToast.show(
          context: context,
          msg: '已删除标签 "${tag.value}"',
          toastType: ToastType.info,
          gravity: ToastGravity.BOTTOM,
        );
      }
    } catch (error) {
      if (mounted) {
        ImmichToast.show(
          context: context,
          msg: '删除标签失败: $error',
          toastType: ToastType.error,
          gravity: ToastGravity.BOTTOM,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(Store.tags.all());

    return Scaffold(
      appBar: AppBar(
        title: const Text('标签管理与层级浏览'),
        actions: [
          IconButton(
            icon: Icon(_treeMode ? Icons.account_tree_rounded : Icons.view_list_rounded),
            tooltip: _treeMode ? '切换为平铺列表' : '切换为层级树视图',
            onPressed: () => setState(() => _treeMode = !_treeMode),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新服务器标签',
            onPressed: () => ref.invalidate(Store.tags.all()),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '新建标签',
            onPressed: _showCreateTagDialog,
          ),
        ],
      ),
      body: tagsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: context.colorScheme.error),
                const SizedBox(height: 12),
                Text('加载服务器标签失败: $err', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(Store.tags.all()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (allTags) {
          final filteredTags = _searchQuery.isEmpty
              ? allTags
              : allTags
                    .where((t) => t.value.toLowerCase().contains(_searchQuery.toLowerCase()))
                    .toList();
          final selectedTags = allTags.where((t) => _selectedTagIds.contains(t.id)).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v.trim()),
                        decoration: InputDecoration(
                          hintText: '搜索标签或层级路径...',
                          isDense: true,
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _showCreateTagDialog,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('新建'),
                    ),
                  ],
                ),
              ),
              if (allTags.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.label_off_outlined, size: 56, color: context.colorScheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text('服务器上暂无标签', style: context.textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(
                            '点击右上角 "+" 创建标签，或在任意照片详情页中为照片添加标签。',
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodyMedium?.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else ...[
                SizedBox(
                  height: _selectedTagIds.isEmpty ? 280 : 185,
                  child: _treeMode
                      ? _buildTreeList(filteredTags)
                      : _buildFlatList(filteredTags),
                ),
                const Divider(height: 1),
                Expanded(
                  child: selectedTags.isEmpty
                      ? Center(
                          child: Text(
                            '请在上方点选一个或多个标签（或层级节点）查看对应照片',
                            style: context.textTheme.bodyMedium?.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : _TaggedPhotosTimelineView(
                          selectedTags: selectedTags,
                          onClearSelection: () => setState(() => _selectedTagIds.clear()),
                        ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildFlatList(List<Tag> tags) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: tags.length,
      itemBuilder: (context, index) {
        final tag = tags[index];
        final isSelected = _selectedTagIds.contains(tag.id);
        return ListTile(
          dense: true,
          selected: isSelected,
          leading: Icon(
            isSelected ? Icons.label_rounded : Icons.label_outline_rounded,
            color: isSelected ? context.colorScheme.primary : null,
          ),
          title: Text(
            tag.value.replaceAll('/', ' › '),
            style: TextStyle(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
          ),
          subtitle: tag.value.contains('/') ? Text('原始路径: ${tag.value}', style: const TextStyle(fontSize: 11)) : null,
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedTagIds.remove(tag.id);
              } else {
                _selectedTagIds.add(tag.id);
              }
            });
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                tooltip: '添加子标签',
                onPressed: () => _showCreateTagDialog(parentPrefix: tag.value),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: context.colorScheme.error),
                tooltip: '删除此标签',
                onPressed: () => _confirmDeleteTag(tag),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTreeList(List<Tag> tags) {
    final roots = _buildHierarchy(tags);
    final sortedNodes = roots.values.toList()..sort((a, b) => a.segmentName.compareTo(b.segmentName));
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: sortedNodes.map((node) => _buildTreeNodeTile(node, 0)).toList(),
    );
  }

  Widget _buildTreeNodeTile(_TagTreeNode node, int depth) {
    final descendantTags = node.collectAllDescendantTags();
    final descendantIds = descendantTags.map((e) => e.id).toSet();
    final isSelected = descendantIds.isNotEmpty && descendantIds.every(_selectedTagIds.contains);
    final isPartiallySelected =
        !isSelected && descendantIds.any(_selectedTagIds.contains);

    if (node.children.isEmpty) {
      final tag = node.exactTag;
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(left: 16.0 + depth * 18.0, right: 8.0),
        selected: isSelected,
        leading: Icon(
          isSelected ? Icons.label_rounded : Icons.label_outline_rounded,
          size: 20,
          color: isSelected ? context.colorScheme.primary : null,
        ),
        title: Text(
          node.segmentName,
          style: TextStyle(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
        ),
        onTap: tag == null
            ? null
            : () {
                setState(() {
                  if (_selectedTagIds.contains(tag.id)) {
                    _selectedTagIds.remove(tag.id);
                  } else {
                    _selectedTagIds.add(tag.id);
                  }
                });
              },
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add_rounded, size: 18),
              tooltip: '在此层级下新建子标签',
              onPressed: () => _showCreateTagDialog(parentPrefix: node.fullPath),
            ),
            if (tag != null)
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: context.colorScheme.error),
                tooltip: '删除标签',
                onPressed: () => _confirmDeleteTag(tag),
              ),
          ],
        ),
      );
    }

    final sortedChildren = node.children.values.toList()
      ..sort((a, b) => a.segmentName.compareTo(b.segmentName));

    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding: EdgeInsets.only(left: 16.0 + depth * 18.0, right: 8.0),
      leading: Icon(
        Icons.folder_special_outlined,
        size: 20,
        color: (isSelected || isPartiallySelected) ? context.colorScheme.primary : null,
      ),
      title: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedTagIds.removeAll(descendantIds);
            } else {
              _selectedTagIds.addAll(descendantIds);
            }
          });
        },
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${node.segmentName} (${descendantTags.length})',
                style: TextStyle(
                  fontWeight: (isSelected || isPartiallySelected) ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_rounded, size: 18),
              tooltip: '新建子标签',
              onPressed: () => _showCreateTagDialog(parentPrefix: node.fullPath),
            ),
            if (node.exactTag != null)
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: context.colorScheme.error),
                tooltip: '删除标签',
                onPressed: () => _confirmDeleteTag(node.exactTag!),
              ),
          ],
        ),
      ),
      children: sortedChildren.map((c) => _buildTreeNodeTile(c, depth + 1)).toList(),
    );
  }
}

class _TaggedPhotosTimelineView extends ConsumerStatefulWidget {
  final List<Tag> selectedTags;
  final VoidCallback onClearSelection;

  const _TaggedPhotosTimelineView({
    required this.selectedTags,
    required this.onClearSelection,
  });

  @override
  ConsumerState<_TaggedPhotosTimelineView> createState() => _TaggedPhotosTimelineViewState();
}

class _TaggedPhotosTimelineViewState extends ConsumerState<_TaggedPhotosTimelineView> {
  List<BaseAsset> _assets = const [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTaggedAssets());
  }

  @override
  void didUpdateWidget(covariant _TaggedPhotosTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.selectedTags.map((e) => e.id).join(',');
    final newIds = widget.selectedTags.map((e) => e.id).join(',');
    if (oldIds != newIds) {
      unawaited(_loadTaggedAssets());
    }
  }

  Future<void> _loadTaggedAssets() async {
    if (widget.selectedTags.isEmpty) {
      setState(() {
        _assets = const [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ref.read(immichAssetAvesRepositoryProvider);
      final filter = AdvancedMediaFilter(
        tags: widget.selectedTags.toSet(),
        sourceScope: MediaSourceScope.serverOnly,
      );
      final results = await repo.filterServerAssets(
        filter,
        page: 1,
        pageSize: 250,
      );
      if (mounted) {
        setState(() {
          _assets = results.assets;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: context.colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Icon(Icons.filter_list_rounded, size: 16, color: context.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '已选标签 (${widget.selectedTags.length}): ${widget.selectedTags.map((e) => e.value.replaceAll('/', ' › ')).join(', ')} — 共 ${_assets.length} 项',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: '刷新标签下照片',
                onPressed: _loadTaggedAssets,
              ),
              TextButton(
                onPressed: widget.onClearSelection,
                child: const Text('清除选择'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('读取标签照片出错: $_error'))
                  : _assets.isEmpty
                      ? Center(
                          child: Text(
                            '所选标签下暂无照片。可在浏览照片时点击详情或右上角菜单添加标签。',
                            style: context.textTheme.bodyMedium?.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ProviderScope(
                          key: ValueKey(
                            'tag_timeline_${widget.selectedTags.map((e) => e.id).join('_')}_${_assets.length}',
                          ),
                          overrides: [
                            timelineServiceProvider.overrideWith((ref) {
                              final service = ref
                                  .watch(timelineFactoryProvider)
                                  .fromAssetsWithBuckets(_assets, TimelineOrigin.search);
                              ref.onDispose(service.dispose);
                              return service;
                            }),
                          ],
                          child: const Timeline(
                            appBar: null,
                            showStorageIndicator: true,
                          ),
                        ),
        ),
      ],
    );
  }
}
