import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/data/store.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/actions/tag.action.dart';
import 'package:immich_mobile/presentation/pages/search/paginated_search.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';

const _collapsedTagsMaxHeight = 140.0;

class TagDetails extends ConsumerStatefulWidget {
  final BaseAsset asset;

  const TagDetails({super.key, required this.asset});

  @override
  ConsumerState createState() => _TagDetailsState();
}

class _TagDetailsState extends ConsumerState<TagDetails> {
  bool _isExpanded = false;
  bool _hasOverflow = false;

  void _openTag(Tag tag) {
    ref.invalidate(assetViewerProvider);
    ref.invalidate(paginatedSearchProvider);
    ref.read(searchPreFilterProvider.notifier)
      ..clear()
      ..setFilter(
        .new(
          tags: {tag},
          people: {},
          location: const .new(),
          camera: const .new(),
          date: const .new(),
          display: const .new(isNotInAlbum: false, isArchive: false, isFavorite: false),
          rating: const .new(),
          mediaType: .other,
        ),
      );

    unawaited(context.navigateTo(const SearchRoute()));
  }

  bool _onTagsMetrics(ScrollMetricsNotification notification) {
    final hasOverflow =
        notification.metrics.maxScrollExtent + notification.metrics.viewportDimension > _collapsedTagsMaxHeight;
    if (hasOverflow != _hasOverflow) {
      setState(() => _hasOverflow = hasOverflow);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final remoteId = asset.remoteId;
    final user = ref.watch(currentUserProvider);
    final isOwned = asset is RemoteAsset ? asset.ownerId == user?.id : remoteId != null;
    if (remoteId == null) {
      return const SizedBox.shrink();
    }

    final tags = ref.watch(Store.tags.forAsset(remoteId)).valueOrNull ?? const <Tag>[];
    if (!isOwned && tags.isEmpty) {
      return const SizedBox.shrink();
    }
    final tagAction = isOwned ? const TagAction(source: .viewer).create(context, ref) : null;
    final tagBackground = context.primaryColor.withAlpha(25);
    final tagBorder = context.colorScheme.outlineVariant;
    final tagText = context.colorScheme.onSurface;
    final brandColor = context.primaryColor;
    final chipTheme = context.themeData.copyWith(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: brandColor.withValues(alpha: 0.15),
    );
    final isCollapsed = !_isExpanded;

    final tagWrap = Theme(
      data: chipTheme,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in tags)
            InputChip(
              onPressed: () => _openTag(tag),
              tooltip: tag.value,
              avatar: tag.value.contains('/')
                  ? Icon(Icons.account_tree_outlined, size: 15, color: context.primaryColor)
                  : Icon(Icons.sell_outlined, size: 15, color: context.primaryColor),
              label: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: context.width * 0.65),
                child: Text(
                  tag.value.replaceAll('/', ' › '),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              labelStyle: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w400),
              backgroundColor: tagBackground,
              shape: const StadiumBorder(),
              side: BorderSide(color: tagBorder),
              deleteIcon: Icon(Icons.close, size: 16, color: tagText),
              onDeleted: isOwned
                  ? switch (UntagAction(source: .viewer, tagId: tag.id).create(context, ref)) {
                      final action? => () async => await action.onAction(),
                      null => null,
                    }
                  : null,
              deleteButtonTooltipMessage: context.t.remove_tag,
            ),
        ],
      ),
    );

    Widget tagArea = NotificationListener<ScrollMetricsNotification>(
      onNotification: _onTagsMetrics,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: isCollapsed ? _collapsedTagsMaxHeight : double.infinity),
        child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: tagWrap),
      ),
    );

    if (isCollapsed && _hasOverflow) {
      tagArea = ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.75, 1.0],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: tagArea,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            context.t.tags,
            style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.onSurfaceSecondary),
          ),
          tagArea,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_hasOverflow)
                ActionChip(
                  label: Text(
                    _isExpanded ? context.t.show_less : context.t.view_more,
                    style: context.textTheme.labelLarge?.copyWith(color: context.primaryColor),
                  ),
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                  backgroundColor: Colors.transparent,
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                ),
              if (tagAction != null)
                ActionChip(
                  avatar: Icon(Icons.new_label_outlined, size: 18, color: context.primaryColor),
                  label: Text(context.t.add_tag),
                  color: WidgetStateProperty.resolveWith(
                    (states) =>
                        states.contains(WidgetState.hovered) ? brandColor.withValues(alpha: 0.15) : Colors.transparent,
                  ),
                  onPressed: tagAction.onAction,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
