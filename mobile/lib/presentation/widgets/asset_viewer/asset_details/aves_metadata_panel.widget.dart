import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/aves_media_metadata.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/unified_media_aves.repository.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/repositories/asset_media.repository.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/bytes_units.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:openapi/api.dart';

/// Complete Aves-inspired media metadata panel (P0-1, P1-3, P1-4).
/// Displays all 16+ required metadata fields, source badge, format chips,
/// copy-to-clipboard actions (GPS, filename, path, URI, server/shared link), and map jump.
class AvesMetadataPanel extends ConsumerStatefulWidget {
  final BaseAsset asset;
  final ExifInfo? exifInfo;

  const AvesMetadataPanel({
    super.key,
    required this.asset,
    this.exifInfo,
  });

  @override
  ConsumerState<AvesMetadataPanel> createState() => _AvesMetadataPanelState();
}

class _AvesMetadataPanelState extends ConsumerState<AvesMetadataPanel> {
  bool _isExpanded = true;
  bool _showUnknownFields = false;
  bool _isCreatingShareLink = false;

  void _copyToClipboard(BuildContext context, String label, String value) {
    unawaited(Clipboard.setData(ClipboardData(text: value)));
    unawaited(Future.value(ref.read(toastServiceProvider).success('已复制$label: $value')));
  }

  Future<void> _copyOrCreateServerLink(BuildContext context, String remoteId) async {
    final serverEndpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (serverEndpoint == null || serverEndpoint.isEmpty) {
      _copyToClipboard(context, '资产 ID', remoteId);
      return;
    }

    // Strip `/api` suffix from serverEndpoint to build web photo link
    final baseWebUrl = serverEndpoint.replaceAll(RegExp(r'/api/?$'), '');
    final directWebLink = '$baseWebUrl/photos/$remoteId';

    if (_isCreatingShareLink) {
      return;
    }
    setState(() => _isCreatingShareLink = true);
    try {
      final sharedLinksApi = ref.read(apiServiceProvider).sharedLinksApi;
      final dto = await sharedLinksApi.createSharedLink(
        SharedLinkCreateDto(
          type: SharedLinkType.INDIVIDUAL,
          assetIds: Optional.present([remoteId]),
          allowDownload: const Optional.present(true),
          allowUpload: const Optional.present(false),
          showMetadata: const Optional.present(true),
        ),
      );
      if (dto != null && dto.key.isNotEmpty) {
        final shareUrl = '$baseWebUrl/share/${dto.key}';
        if (context.mounted) {
          _copyToClipboard(context, '公开分享链接', shareUrl);
        }
        return;
      }
    } catch (_) {
      // Fallback to direct web asset URL if sharedLinks API is restricted or offline
    } finally {
      if (mounted) {
        setState(() => _isCreatingShareLink = false);
      }
    }

    if (context.mounted) {
      _copyToClipboard(context, '服务器资产链接', directWebLink);
    }
  }

  Future<void> _shareSystem(BuildContext context) async {
    await ref.read(assetMediaRepositoryProvider).shareAssets([widget.asset], context);
  }

  @override
  Widget build(BuildContext context) {
    final asyncMeta = ref.watch(avesAssetMetadataProvider(widget.asset));
    final fallbackMeta = AvesMediaMetadata.fromAssetAndExif(widget.asset, widget.exifInfo);
    final meta = asyncMeta.valueOrNull ?? fallbackMeta;

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final capturedText = meta.capturedAt != null
        ? '${dateFormat.format(meta.capturedAt!.toLocal())}${meta.timeZone != null ? ' (${meta.timeZone})' : ''}'
        : null;
    final modifiedText = meta.modifiedAt != null ? dateFormat.format(meta.modifiedAt!.toLocal()) : null;
    final fileSizeText = meta.fileSize != null && meta.fileSize! > 0
        ? '${formatBytes(meta.fileSize!)} (${NumberFormat.decimalPattern().format(meta.fileSize)} B)'
        : null;
    final widthText = meta.width != null && meta.width! > 0 ? '${meta.width} px' : null;
    final heightText = meta.height != null && meta.height! > 0 ? '${meta.height} px' : null;
    final resolutionText = meta.formattedResolution;
    final isoText = meta.iso != null && meta.iso! > 0 ? 'ISO ${meta.iso}' : null;

    final specialFormats = meta.detectSpecialFormats(
      isMotionPhoto: widget.asset.isMotionPhoto,
      isAnimated: widget.asset.isAnimatedImage,
    );

    final rows = <_MetadataRowItem>[
      _MetadataRowItem(
        label: '文件名',
        value: meta.fileName,
        icon: Icons.insert_drive_file_outlined,
        copyable: true,
        alwaysShow: true,
      ),
      _MetadataRowItem(
        label: 'MIME 类型',
        value: meta.effectiveMimeType,
        icon: Icons.code_rounded,
        copyable: true,
        alwaysShow: true,
      ),
      _MetadataRowItem(
        label: '文件大小',
        value: fileSizeText,
        icon: Icons.sd_storage_outlined,
        alwaysShow: true,
      ),
      _MetadataRowItem(
        label: '分辨率 (宽 × 高)',
        value: resolutionText ?? (widthText != null && heightText != null ? '$widthText × $heightText' : null),
        icon: Icons.aspect_ratio_rounded,
        copyable: resolutionText != null,
        alwaysShow: true,
      ),
      _MetadataRowItem(
        label: '拍摄时间',
        value: capturedText,
        icon: Icons.calendar_today_outlined,
        copyable: capturedText != null,
        alwaysShow: true,
      ),
      _MetadataRowItem(
        label: '修改时间',
        value: modifiedText,
        icon: Icons.update_rounded,
      ),
      _MetadataRowItem(
        label: '相机制造商',
        value: meta.make,
        icon: Icons.business_outlined,
      ),
      _MetadataRowItem(
        label: '相机型号',
        value: meta.model,
        icon: Icons.camera_alt_outlined,
        copyable: meta.model != null,
      ),
      _MetadataRowItem(
        label: '镜头型号',
        value: meta.lensModel,
        icon: Icons.camera_outlined,
        copyable: meta.lensModel != null,
      ),
      _MetadataRowItem(
        label: '曝光时间',
        value: meta.exposureTime,
        icon: Icons.shutter_speed_rounded,
      ),
      _MetadataRowItem(
        label: '光圈',
        value: meta.fNumber,
        icon: Icons.lens_blur_outlined,
      ),
      _MetadataRowItem(
        label: 'ISO 感光度',
        value: isoText,
        icon: Icons.iso_rounded,
      ),
      _MetadataRowItem(
        label: '焦距',
        value: meta.focalLength,
        icon: Icons.straighten_rounded,
      ),
      _MetadataRowItem(
        label: 'GPS 坐标',
        value: meta.formattedGps,
        subtitle: meta.formattedLocationName,
        icon: Icons.my_location_rounded,
        copyable: meta.hasValidGps,
        alwaysShow: true,
        trailingAction: meta.hasValidGps
            ? IconButton(
                icon: Icon(Icons.map_outlined, size: 18, color: context.primaryColor),
                tooltip: '在地图中查看',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  unawaited(
                    context.pushRoute(
                      MapRoute(
                        initialLocation: LatLng(meta.latitude!, meta.longitude!),
                      ),
                    ),
                  );
                },
              )
            : null,
      ),
      if (widget.asset.isVideo || meta.duration != null)
        _MetadataRowItem(
          label: '视频时长',
          value: meta.formattedDuration,
          icon: Icons.timer_outlined,
          alwaysShow: widget.asset.isVideo,
        ),
      if (widget.asset.isVideo || meta.formattedVideoEncoding != null)
        _MetadataRowItem(
          label: '视频编码信息',
          value: meta.formattedVideoEncoding,
          icon: Icons.movie_filter_outlined,
          alwaysShow: widget.asset.isVideo,
        ),
      if (meta.filePath != null && meta.filePath!.isNotEmpty)
        _MetadataRowItem(
          label: '文件路径',
          value: meta.filePath,
          icon: Icons.folder_open_outlined,
          copyable: true,
        ),
      if (meta.contentUri != null && meta.contentUri!.isNotEmpty)
        _MetadataRowItem(
          label: '媒体 URI',
          value: meta.contentUri,
          icon: Icons.link_rounded,
          copyable: true,
        ),
      if (meta.albumNames.isNotEmpty)
        _MetadataRowItem(
          label: '所属相册/文件夹',
          value: meta.albumNames.join(' • '),
          icon: Icons.photo_album_outlined,
          copyable: true,
        ),
    ];

    final visibleRows = rows.where((r) {
      if (_showUnknownFields) {
        return true;
      }
      if (r.alwaysShow) {
        return true;
      }
      return r.value != null && r.value!.trim().isNotEmpty && r.value != '未知';
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: context.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header bar with source badge, format badges, and collapse toggle
            InkWell(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: context.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '完整媒体信息 (Aves 增强)',
                            style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          _SourceBadge(source: meta.source),
                          for (final fmt in specialFormats) _FormatBadge(label: fmt.label),
                        ],
                      ),
                    ),
                    if (asyncMeta.isLoading)
                      const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Icon(
                      _isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: context.colorScheme.onSurfaceSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (_isExpanded) ...[
              Divider(height: 1, color: context.colorScheme.outlineVariant.withAlpha(60)),
              // Quick action bar (Copy filename / Copy GPS / Copy Link / System Share / Toggle Unknowns)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    _QuickActionChip(
                      icon: Icons.share_outlined,
                      label: '系统分享',
                      onTap: () => _shareSystem(context),
                    ),
                    const SizedBox(width: 8),
                    _QuickActionChip(
                      icon: Icons.copy_rounded,
                      label: '复制文件名',
                      onTap: () => _copyToClipboard(context, '文件名', meta.fileName),
                    ),
                    if (meta.hasValidGps) ...[
                      const SizedBox(width: 8),
                      _QuickActionChip(
                        icon: Icons.pin_drop_outlined,
                        label: '复制 GPS',
                        onTap: () => _copyToClipboard(context, 'GPS 坐标', meta.formattedGps!),
                      ),
                      const SizedBox(width: 8),
                      _QuickActionChip(
                        icon: Icons.map_outlined,
                        label: '地图定位',
                        onTap: () => context.pushRoute(
                          MapRoute(initialLocation: LatLng(meta.latitude!, meta.longitude!)),
                        ),
                      ),
                    ],
                    if (meta.remoteId != null) ...[
                      const SizedBox(width: 8),
                      _QuickActionChip(
                        icon: _isCreatingShareLink ? Icons.hourglass_top_rounded : Icons.add_link_rounded,
                        label: '复制分享链接',
                        onTap: () => _copyOrCreateServerLink(context, meta.remoteId!),
                      ),
                    ],
                    if (meta.contentUri != null) ...[
                      const SizedBox(width: 8),
                      _QuickActionChip(
                        icon: Icons.link_rounded,
                        label: '复制 URI',
                        onTap: () => _copyToClipboard(context, '媒体 URI', meta.contentUri!),
                      ),
                    ],
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(
                        _showUnknownFields ? '隐藏未知项' : '显示全部字段',
                        style: context.textTheme.labelSmall,
                      ),
                      selected: _showUnknownFields,
                      onSelected: (v) => setState(() => _showUnknownFields = v),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.colorScheme.outlineVariant.withAlpha(60)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final item in visibleRows)
                      _buildRow(context, item),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, _MetadataRowItem item) {
    final hasValue = item.value != null && item.value!.trim().isNotEmpty && item.value != '未知';
    final displayValue = hasValue ? item.value!.trim() : '未知';

    return InkWell(
      onTap: hasValue && item.copyable ? () => _copyToClipboard(context, item.label, displayValue) : null,
      onLongPress: hasValue ? () => _copyToClipboard(context, item.label, displayValue) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              item.icon,
              size: 18,
              color: hasValue ? context.colorScheme.primary : context.colorScheme.outline,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 108,
              child: Text(
                item.label,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayValue,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: hasValue ? context.colorScheme.onSurface : context.colorScheme.outline,
                      fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                  if (item.subtitle != null && item.subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.subtitle!,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (item.trailingAction != null) item.trailingAction!,
            if (hasValue && item.copyable)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.copy_all_outlined,
                  size: 15,
                  color: context.colorScheme.onSurfaceSecondary.withAlpha(150),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetadataRowItem {
  final String label;
  final String? value;
  final String? subtitle;
  final IconData icon;
  final bool copyable;
  final bool alwaysShow;
  final Widget? trailingAction;

  const _MetadataRowItem({
    required this.label,
    required this.value,
    this.subtitle,
    required this.icon,
    this.copyable = false,
    this.alwaysShow = false,
    this.trailingAction,
  });
}

class _SourceBadge extends StatelessWidget {
  final UnifiedMediaSource source;

  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (source) {
      UnifiedMediaSource.local => ('本地媒体', Icons.phone_android_rounded, Colors.teal),
      UnifiedMediaSource.immich => ('Immich 服务器', Icons.cloud_done_outlined, Colors.indigo),
      UnifiedMediaSource.merged => ('已同步 (本地+云端)', Icons.cloud_sync_outlined, Colors.deepPurple),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatBadge extends StatelessWidget {
  final String label;

  const _FormatBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.colorScheme.tertiaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: context.colorScheme.onTertiaryContainer,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 15, color: context.primaryColor),
      label: Text(label, style: context.textTheme.labelSmall),
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}
