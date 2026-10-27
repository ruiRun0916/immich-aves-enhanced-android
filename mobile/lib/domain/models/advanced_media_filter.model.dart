import 'package:flutter/foundation.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';
import 'package:path/path.dart' as p;

/// Filter option for tri-state boolean filters (e.g. GPS presence, Favorite).
enum TriStateFilter {
  any,
  yes,
  no,
}

/// Filter option for media data source (P0-2 & P1-1/P1-2).
enum MediaSourceScope {
  all('全部来源'),
  serverOnly('仅服务器 (Immich)'),
  localOnly('仅本地 (此设备)'),
  mergedOnly('已同步 (本地+服务器)');

  final String label;
  const MediaSourceScope(this.label);
}

/// Composable advanced media filter criteria (P0-2).
@immutable
class AdvancedMediaFilter {
  /// Date range filter
  final DateTime? takenAfter;
  final DateTime? takenBefore;

  /// Media type: null = all, AssetType.image, AssetType.video
  final AssetType? mediaType;

  /// File extensions / formats (normalized lowercase without dot, e.g. 'jpg', 'heic', 'dng', 'mp4')
  final Set<String> fileFormats;

  /// Resolution bounds (px)
  final int? minWidth;
  final int? maxWidth;
  final int? minHeight;
  final int? maxHeight;

  /// File size bounds (bytes)
  final int? minSizeBytes;
  final int? maxSizeBytes;

  /// GPS coordinate presence
  final TriStateFilter gpsFilter;

  /// Camera make & model
  final String? cameraMake;
  final String? cameraModel;

  /// Favorite filter
  final TriStateFilter favoriteFilter;

  /// Album filter (remote or local album ID & display name)
  final String? albumId;
  final String? albumName;
  final bool isLocalAlbum;
  final bool notInAnyAlbum;

  /// Data source scope (local vs server vs all)
  final MediaSourceScope sourceScope;

  /// Server tags filter (P0-3 integration)
  final Set<Tag> tags;

  /// Optional filename / text query
  final String? textQuery;

  const AdvancedMediaFilter({
    this.takenAfter,
    this.takenBefore,
    this.mediaType,
    this.fileFormats = const {},
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    this.minSizeBytes,
    this.maxSizeBytes,
    this.gpsFilter = TriStateFilter.any,
    this.cameraMake,
    this.cameraModel,
    this.favoriteFilter = TriStateFilter.any,
    this.albumId,
    this.albumName,
    this.isLocalAlbum = false,
    this.notInAnyAlbum = false,
    this.sourceScope = MediaSourceScope.all,
    this.tags = const {},
    this.textQuery,
  });

  bool get isEmpty =>
      takenAfter == null &&
      takenBefore == null &&
      mediaType == null &&
      fileFormats.isEmpty &&
      minWidth == null &&
      maxWidth == null &&
      minHeight == null &&
      maxHeight == null &&
      minSizeBytes == null &&
      maxSizeBytes == null &&
      gpsFilter == TriStateFilter.any &&
      (cameraMake == null || cameraMake!.trim().isEmpty) &&
      (cameraModel == null || cameraModel!.trim().isEmpty) &&
      favoriteFilter == TriStateFilter.any &&
      albumId == null &&
      !notInAnyAlbum &&
      sourceScope == MediaSourceScope.all &&
      tags.isEmpty &&
      (textQuery == null || textQuery!.trim().isEmpty);

  bool get isNotEmpty => !isEmpty;

  int get activeFilterCount {
    var count = 0;
    if (takenAfter != null || takenBefore != null) {
      count++;
    }
    if (mediaType != null) {
      count++;
    }
    if (fileFormats.isNotEmpty) {
      count++;
    }
    if (minWidth != null || maxWidth != null || minHeight != null || maxHeight != null) {
      count++;
    }
    if (minSizeBytes != null || maxSizeBytes != null) {
      count++;
    }
    if (gpsFilter != TriStateFilter.any) {
      count++;
    }
    if ((cameraMake != null && cameraMake!.trim().isNotEmpty) ||
        (cameraModel != null && cameraModel!.trim().isNotEmpty)) {
      count++;
    }
    if (favoriteFilter != TriStateFilter.any) {
      count++;
    }
    if (albumId != null || notInAnyAlbum) {
      count++;
    }
    if (sourceScope != MediaSourceScope.all) {
      count++;
    }
    if (tags.isNotEmpty) {
      count++;
    }
    if (textQuery != null && textQuery!.trim().isNotEmpty) {
      count++;
    }
    return count;
  }

  /// Checks whether a candidate [BaseAsset] + optional [ExifInfo] satisfies client-side conditions.
  bool matchesAsset(BaseAsset asset, {ExifInfo? exif}) {
    // 1. Source scope
    switch (sourceScope) {
      case MediaSourceScope.all:
        break;
      case MediaSourceScope.serverOnly:
        if (!asset.hasRemote) {
          return false;
        }
      case MediaSourceScope.localOnly:
        if (!asset.hasLocal) {
          return false;
        }
      case MediaSourceScope.mergedOnly:
        if (!asset.isMerged) {
          return false;
        }
    }

    // 2. Media type
    if (mediaType != null && asset.type != mediaType) {
      return false;
    }

    // 3. Date range
    final captureDate = exif?.dateTimeOriginal ?? asset.createdAt;
    if (takenAfter != null && captureDate.isBefore(takenAfter!)) {
      return false;
    }
    if (takenBefore != null && captureDate.isAfter(takenBefore!)) {
      return false;
    }

    // 4. File format / extension
    if (fileFormats.isNotEmpty) {
      final ext = p.extension(asset.name).replaceFirst('.', '').toLowerCase();
      final normalizedFormats = fileFormats.expand(_expandFormatGroup).toSet();
      if (!normalizedFormats.contains(ext)) {
        return false;
      }
    }

    // 5. Width & Height
    final w = exif?.width ?? asset.width;
    final h = exif?.height ?? asset.height;
    if (minWidth != null && (w == null || w < minWidth!)) {
      return false;
    }
    if (maxWidth != null && (w == null || w > maxWidth!)) {
      return false;
    }
    if (minHeight != null && (h == null || h < minHeight!)) {
      return false;
    }
    if (maxHeight != null && (h == null || h > maxHeight!)) {
      return false;
    }

    // 6. File size
    if (minSizeBytes != null || maxSizeBytes != null) {
      final size = exif?.fileSize;
      if (size == null) {
        return false;
      }
      if (minSizeBytes != null && size < minSizeBytes!) {
        return false;
      }
      if (maxSizeBytes != null && size > maxSizeBytes!) {
        return false;
      }
    }

    // 7. GPS presence
    if (gpsFilter != TriStateFilter.any) {
      final hasGps = (exif?.hasCoordinates ?? false) || (asset is LocalAsset && asset.hasCoordinates);
      if (gpsFilter == TriStateFilter.yes && !hasGps) {
        return false;
      }
      if (gpsFilter == TriStateFilter.no && hasGps) {
        return false;
      }
    }

    // 8. Camera make / model
    if (cameraMake != null && cameraMake!.trim().isNotEmpty) {
      final make = exif?.make?.toLowerCase() ?? '';
      if (!make.contains(cameraMake!.trim().toLowerCase())) {
        return false;
      }
    }
    if (cameraModel != null && cameraModel!.trim().isNotEmpty) {
      final model = exif?.model?.toLowerCase() ?? '';
      if (!model.contains(cameraModel!.trim().toLowerCase())) {
        return false;
      }
    }

    // 9. Favorite
    if (favoriteFilter == TriStateFilter.yes && !asset.isFavorite) {
      return false;
    }
    if (favoriteFilter == TriStateFilter.no && asset.isFavorite) {
      return false;
    }

    // 10. Text / filename query
    if (textQuery != null && textQuery!.trim().isNotEmpty) {
      final q = textQuery!.trim().toLowerCase();
      final nameMatch = asset.name.toLowerCase().contains(q);
      final descMatch = exif?.description?.toLowerCase().contains(q) ?? false;
      final cityMatch = exif?.city?.toLowerCase().contains(q) ?? false;
      final modelMatch = exif?.model?.toLowerCase().contains(q) ?? false;
      if (!nameMatch && !descMatch && !cityMatch && !modelMatch) {
        return false;
      }
    }

    return true;
  }

  static Iterable<String> _expandFormatGroup(String fmt) {
    final f = fmt.toLowerCase();
    return switch (f) {
      'jpg' || 'jpeg' => const ['jpg', 'jpeg'],
      'heic' || 'heif' => const ['heic', 'heif'],
      'tif' || 'tiff' => const ['tif', 'tiff'],
      'raw' => const ['dng', 'cr2', 'cr3', 'nef', 'arw', 'orf', 'rw2', 'raf', 'pef', 'raw'],
      _ => [f],
    };
  }

  AdvancedMediaFilter copyWith({
    DateTime? takenAfter,
    bool clearTakenAfter = false,
    DateTime? takenBefore,
    bool clearTakenBefore = false,
    AssetType? mediaType,
    bool clearMediaType = false,
    Set<String>? fileFormats,
    int? minWidth,
    bool clearMinWidth = false,
    int? maxWidth,
    bool clearMaxWidth = false,
    int? minHeight,
    bool clearMinHeight = false,
    int? maxHeight,
    bool clearMaxHeight = false,
    int? minSizeBytes,
    bool clearMinSizeBytes = false,
    int? maxSizeBytes,
    bool clearMaxSizeBytes = false,
    TriStateFilter? gpsFilter,
    String? cameraMake,
    bool clearCameraMake = false,
    String? cameraModel,
    bool clearCameraModel = false,
    TriStateFilter? favoriteFilter,
    String? albumId,
    String? albumName,
    bool? isLocalAlbum,
    bool clearAlbum = false,
    bool? notInAnyAlbum,
    MediaSourceScope? sourceScope,
    Set<Tag>? tags,
    String? textQuery,
    bool clearTextQuery = false,
  }) {
    return AdvancedMediaFilter(
      takenAfter: clearTakenAfter ? null : (takenAfter ?? this.takenAfter),
      takenBefore: clearTakenBefore ? null : (takenBefore ?? this.takenBefore),
      mediaType: clearMediaType ? null : (mediaType ?? this.mediaType),
      fileFormats: fileFormats ?? this.fileFormats,
      minWidth: clearMinWidth ? null : (minWidth ?? this.minWidth),
      maxWidth: clearMaxWidth ? null : (maxWidth ?? this.maxWidth),
      minHeight: clearMinHeight ? null : (minHeight ?? this.minHeight),
      maxHeight: clearMaxHeight ? null : (maxHeight ?? this.maxHeight),
      minSizeBytes: clearMinSizeBytes ? null : (minSizeBytes ?? this.minSizeBytes),
      maxSizeBytes: clearMaxSizeBytes ? null : (maxSizeBytes ?? this.maxSizeBytes),
      gpsFilter: gpsFilter ?? this.gpsFilter,
      cameraMake: clearCameraMake ? null : (cameraMake ?? this.cameraMake),
      cameraModel: clearCameraModel ? null : (cameraModel ?? this.cameraModel),
      favoriteFilter: favoriteFilter ?? this.favoriteFilter,
      albumId: clearAlbum ? null : (albumId ?? this.albumId),
      albumName: clearAlbum ? null : (albumName ?? this.albumName),
      isLocalAlbum: clearAlbum ? false : (isLocalAlbum ?? this.isLocalAlbum),
      notInAnyAlbum: notInAnyAlbum ?? this.notInAnyAlbum,
      sourceScope: sourceScope ?? this.sourceScope,
      tags: tags ?? this.tags,
      textQuery: clearTextQuery ? null : (textQuery ?? this.textQuery),
    );
  }

  /// Reset all filters at once (一键清除所有筛选).
  static const AdvancedMediaFilter empty = AdvancedMediaFilter();

  AdvancedMediaFilter clearAll() => empty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AdvancedMediaFilter &&
        other.takenAfter == takenAfter &&
        other.takenBefore == takenBefore &&
        other.mediaType == mediaType &&
        setEquals(other.fileFormats, fileFormats) &&
        other.minWidth == minWidth &&
        other.maxWidth == maxWidth &&
        other.minHeight == minHeight &&
        other.maxHeight == maxHeight &&
        other.minSizeBytes == minSizeBytes &&
        other.maxSizeBytes == maxSizeBytes &&
        other.gpsFilter == gpsFilter &&
        other.cameraMake == cameraMake &&
        other.cameraModel == cameraModel &&
        other.favoriteFilter == favoriteFilter &&
        other.albumId == albumId &&
        other.albumName == albumName &&
        other.isLocalAlbum == isLocalAlbum &&
        other.notInAnyAlbum == notInAnyAlbum &&
        other.sourceScope == sourceScope &&
        setEquals(other.tags, tags) &&
        other.textQuery == textQuery;
  }

  @override
  int get hashCode => Object.hashAll([
    takenAfter,
    takenBefore,
    mediaType,
    Object.hashAllUnordered(fileFormats),
    minWidth,
    maxWidth,
    minHeight,
    maxHeight,
    minSizeBytes,
    maxSizeBytes,
    gpsFilter,
    cameraMake,
    cameraModel,
    favoriteFilter,
    albumId,
    albumName,
    isLocalAlbum,
    notInAnyAlbum,
    sourceScope,
    Object.hashAllUnordered(tags),
    textQuery,
  ]);
}
