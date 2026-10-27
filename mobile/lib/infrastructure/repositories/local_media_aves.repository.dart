import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/data/db/main/database.dart';
import 'package:immich_mobile/data/db/main/table/local/asset.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/aves_media_metadata.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:logging/logging.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart' hide LatLng;

final localMediaAvesRepositoryProvider = Provider<LocalMediaRepository>((ref) {
  final db = ref.watch(driftProvider);
  return LocalMediaRepository(db);
});

/// Categorized local album groups for P1-1 (Local Gallery Mode).
enum LocalAlbumCategory {
  all('全部文件夹'),
  camera('相机 (Camera)'),
  screenshots('截图 (Screenshots)'),
  downloads('下载 (Download)'),
  videos('视频 (Videos)'),
  other('其他相册');

  final String label;
  const LocalAlbumCategory(this.label);
}

/// Marker model for a local photo with GPS coordinates (P1-3).
class LocalMapMarker {
  final LocalAsset asset;
  final LatLng location;

  const LocalMapMarker({required this.asset, required this.location});
}

/// Dedicated repository for Android MediaStore & local Drift media queries (read-only by default).
class LocalMediaRepository {
  static final _log = Logger('LocalMediaRepository');

  final Drift _db;

  /// Cache of local MediaStore metadata keyed by local asset ID.
  final Map<String, AvesMediaMetadata> _localMetaCache = {};

  LocalMediaRepository(this._db);

  /// Checks current Android media permission state without triggering destructive actions.
  Future<MediaPermissionStatus> checkPermissionStatus({bool requestIfNeeded = false}) async {
    try {
      final state = requestIfNeeded
          ? await PhotoManager.requestPermissionExtend(
              requestOption: const PermissionRequestOption(
                androidPermission: AndroidPermission(
                  type: RequestType.common,
                  mediaLocation: true,
                ),
              ),
            )
          : await PhotoManager.getPermissionState(
              requestOption: const PermissionRequestOption(
                androidPermission: AndroidPermission(
                  type: RequestType.common,
                  mediaLocation: true,
                ),
              ),
            );

      return switch (state) {
        PermissionState.authorized => MediaPermissionStatus.grantedFull,
        PermissionState.limited => MediaPermissionStatus.grantedPartial,
        PermissionState.restricted => MediaPermissionStatus.restricted,
        PermissionState.denied || PermissionState.notDetermined => MediaPermissionStatus.denied,
      };
    } catch (e) {
      _log.warning('Failed to query PhotoManager permission state: $e');
      return MediaPermissionStatus.denied;
    }
  }

  /// Opens the Android 14+ system picker to re-select allowed photos when in limited permission mode.
  Future<void> presentLimitedPhotoPicker() async {
    try {
      await PhotoManager.presentLimited();
    } catch (e) {
      _log.warning('Failed to present limited photo picker: $e');
    }
  }

  /// Reads rich metadata for a local asset from Android MediaStore (`AssetEntity`) + local DB.
  /// Never loads full image bitmap into memory; only reads MediaStore columns and `File.length()`.
  Future<AvesMediaMetadata> getRichMetadata(LocalAsset asset, {ExifInfo? pairedRemoteExif}) async {
    final cached = _localMetaCache[asset.id];
    if (cached != null && pairedRemoteExif == null) {
      return cached;
    }

    String fileName = asset.name;
    String? mimeType;
    int? fileSize = pairedRemoteExif?.fileSize;
    int? width = asset.width ?? pairedRemoteExif?.width;
    int? height = asset.height ?? pairedRemoteExif?.height;
    DateTime? capturedAt = pairedRemoteExif?.dateTimeOriginal ?? asset.createdAt;
    DateTime? modifiedAt = asset.updatedAt;
    double? lat = asset.latitude ?? pairedRemoteExif?.latitude;
    double? lng = asset.longitude ?? pairedRemoteExif?.longitude;
    String? filePath;
    String? contentUri;

    final albumNames = await _getLocalAlbumNames(asset.id);

    try {
      final entity = await AssetEntity.fromId(asset.id);
      if (entity != null) {
        final title = await entity.titleAsync;
        if (title.isNotEmpty) {
          fileName = title;
        }
        mimeType = await entity.mimeTypeAsync;
        width ??= entity.width > 0 ? entity.width : null;
        height ??= entity.height > 0 ? entity.height : null;
        capturedAt = entity.createDateTime;
        modifiedAt = entity.modifiedDateTime;

        final mediaUrl = await entity.getMediaUrl();
        contentUri = mediaUrl ?? 'content://media/external/file/${entity.id}';

        final relativePath = entity.relativePath;
        if (relativePath != null && relativePath.isNotEmpty) {
          filePath = p.join('/storage/emulated/0', relativePath, fileName);
        }

        if (lat == null || lng == null || (lat == 0 && lng == 0)) {
          final latLng = await entity.latlngAsync();
          if (latLng != null && (latLng.latitude != 0 || latLng.longitude != 0)) {
            lat = latLng.latitude;
            lng = latLng.longitude;
          }
        }

        if (fileSize == null) {
          final file = await entity.file;
          if (file != null) {
            filePath ??= file.path;
            try {
              fileSize = file.lengthSync();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      _log.fine('MediaStore metadata lookup fallback for local asset ${asset.id}: $e');
    }

    mimeType ??= AvesMediaMetadata.inferMimeTypeFromFilename(fileName);
    contentUri ??= 'content://media/external/file/${asset.id}';

    final meta = AvesMediaMetadata(
      fileName: fileName,
      mimeType: mimeType,
      fileSize: fileSize,
      width: width,
      height: height,
      capturedAt: capturedAt,
      timeZone: pairedRemoteExif?.timeZone,
      modifiedAt: modifiedAt,
      make: pairedRemoteExif?.make,
      model: pairedRemoteExif?.model,
      lensModel: pairedRemoteExif?.lens,
      exposureTime: (pairedRemoteExif != null && pairedRemoteExif.exposureTime.isNotEmpty)
          ? pairedRemoteExif.exposureTime
          : null,
      fNumber: (pairedRemoteExif != null && pairedRemoteExif.fNumber.isNotEmpty)
          ? 'ƒ/${pairedRemoteExif.fNumber}'
          : null,
      iso: pairedRemoteExif?.iso,
      focalLength: (pairedRemoteExif != null && pairedRemoteExif.focalLength.isNotEmpty)
          ? '${pairedRemoteExif.focalLength} mm'
          : null,
      latitude: lat,
      longitude: lng,
      city: pairedRemoteExif?.city,
      state: pairedRemoteExif?.state,
      country: pairedRemoteExif?.country,
      duration: asset.isVideo ? asset.duration : null,
      filePath: filePath,
      contentUri: contentUri,
      albumNames: albumNames,
      source: asset.hasRemote ? UnifiedMediaSource.merged : UnifiedMediaSource.local,
      checksum: asset.checksum,
      remoteId: asset.remoteId,
      localId: asset.id,
    );

    if (_localMetaCache.length > 300) {
      _localMetaCache.remove(_localMetaCache.keys.first);
    }
    _localMetaCache[asset.id] = meta;
    return meta;
  }

  Future<List<String>> _getLocalAlbumNames(String localAssetId) async {
    try {
      final query = _db.localAlbumEntity.selectOnly().join([
        innerJoin(
          _db.localAlbumAssetEntity,
          _db.localAlbumAssetEntity.albumId.equalsExp(_db.localAlbumEntity.id),
          useColumns: false,
        ),
      ])
        ..addColumns([_db.localAlbumEntity.name])
        ..where(_db.localAlbumAssetEntity.assetId.equals(localAssetId));
      final rows = await query.get();
      return rows.map((r) => r.read(_db.localAlbumEntity.name)).whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Categorizes a [LocalAlbum] into Aves-style folder categories (Camera, Screenshots, Downloads, etc.).
  static LocalAlbumCategory categorizeAlbum(LocalAlbum album) {
    final lower = album.name.toLowerCase();
    if (lower == 'camera' || lower == 'dcim' || lower.contains('相机')) {
      return LocalAlbumCategory.camera;
    }
    if (lower.contains('screenshot') || lower.contains('截屏') || lower.contains('截图')) {
      return LocalAlbumCategory.screenshots;
    }
    if (lower.contains('download') || lower.contains('下载')) {
      return LocalAlbumCategory.downloads;
    }
    if (lower.contains('video') || lower.contains('movies') || lower.contains('视频')) {
      return LocalAlbumCategory.videos;
    }
    return LocalAlbumCategory.other;
  }

  /// Paginated query of all local assets (across all folders or filtered by category/criteria).
  Future<({List<LocalAsset> assets, int? nextPage})> filterLocalAssets(
    AdvancedMediaFilter filter, {
    required int page,
    int pageSize = 200,
  }) async {
    if (filter.sourceScope == MediaSourceScope.serverOnly) {
      return (assets: const <LocalAsset>[], nextPage: null);
    }
    // Local-only assets cannot match server-only tags unless merged
    if (filter.tags.isNotEmpty) {
      return (assets: const <LocalAsset>[], nextPage: null);
    }

    final offset = (page - 1) * pageSize;

    final remoteIdSubquery = subqueryExpression<String>(
      _db.remoteAssetEntity.selectOnly()
        ..addColumns([_db.remoteAssetEntity.id])
        ..where(_db.remoteAssetEntity.checksum.equalsExp(_db.localAssetEntity.checksum))
        ..limit(1),
    );

    final query = _db.localAssetEntity.select().addColumns([remoteIdSubquery]).join([
      if (filter.albumId != null && filter.isLocalAlbum)
        innerJoin(
          _db.localAlbumAssetEntity,
          _db.localAlbumAssetEntity.assetId.equalsExp(_db.localAssetEntity.id) &
              _db.localAlbumAssetEntity.albumId.equals(filter.albumId!),
          useColumns: false,
        ),
    ]);

    Expression<bool> predicate = const Constant(true);

    if (filter.mediaType != null) {
      predicate = predicate & _db.localAssetEntity.type.equalsValue(filter.mediaType);
    }
    if (filter.takenAfter != null) {
      predicate = predicate & _db.localAssetEntity.createdAt.isBiggerOrEqualValue(filter.takenAfter!);
    }
    if (filter.takenBefore != null) {
      predicate = predicate & _db.localAssetEntity.createdAt.isSmallerOrEqualValue(filter.takenBefore!);
    }
    if (filter.favoriteFilter == TriStateFilter.yes) {
      predicate = predicate & _db.localAssetEntity.isFavorite.equals(true);
    } else if (filter.favoriteFilter == TriStateFilter.no) {
      predicate = predicate & _db.localAssetEntity.isFavorite.equals(false);
    }
    if (filter.minWidth != null) {
      predicate = predicate & _db.localAssetEntity.width.isBiggerOrEqualValue(filter.minWidth!);
    }
    if (filter.maxWidth != null) {
      predicate = predicate & _db.localAssetEntity.width.isSmallerOrEqualValue(filter.maxWidth!);
    }
    if (filter.minHeight != null) {
      predicate = predicate & _db.localAssetEntity.height.isBiggerOrEqualValue(filter.minHeight!);
    }
    if (filter.maxHeight != null) {
      predicate = predicate & _db.localAssetEntity.height.isSmallerOrEqualValue(filter.maxHeight!);
    }
    if (filter.gpsFilter == TriStateFilter.yes) {
      predicate =
          predicate &
          _db.localAssetEntity.latitude.isNotNull() &
          _db.localAssetEntity.longitude.isNotNull() &
          _db.localAssetEntity.latitude.equals(0.0).not() &
          _db.localAssetEntity.longitude.equals(0.0).not();
    } else if (filter.gpsFilter == TriStateFilter.no) {
      predicate =
          predicate &
          (_db.localAssetEntity.latitude.isNull() |
              _db.localAssetEntity.longitude.isNull() |
              _db.localAssetEntity.latitude.equals(0.0));
    }
    if (filter.textQuery != null && filter.textQuery!.trim().isNotEmpty) {
      predicate = predicate & _db.localAssetEntity.name.like('%${filter.textQuery!.trim()}%');
    }

    query
      ..where(predicate)
      ..orderBy([OrderingTerm.desc(_db.localAssetEntity.createdAt)])
      ..limit(pageSize, offset: offset);

    final rows = await query.get();
    final results = <LocalAsset>[];
    for (final row in rows) {
      final asset = row.readTable(_db.localAssetEntity).toDto(remoteId: row.read(remoteIdSubquery));
      // If cameraMake/cameraModel/fileSize filter is active, only merged local assets with remoteExif can match
      if ((filter.cameraMake != null && filter.cameraMake!.trim().isNotEmpty) ||
          (filter.cameraModel != null && filter.cameraModel!.trim().isNotEmpty) ||
          filter.minSizeBytes != null ||
          filter.maxSizeBytes != null) {
        continue;
      }
      if (filter.matchesAsset(asset)) {
        results.add(asset);
      }
    }

    final hasMore = rows.length >= pageSize;
    return (assets: results, nextPage: hasMore ? page + 1 : null);
  }

  /// Queries local assets that have valid GPS coordinates for P1-3 (Map & Location Browsing).
  Future<List<LocalMapMarker>> getLocalMapMarkers({LatLngBounds? bounds, int limit = 500}) async {
    try {
      final remoteIdSubquery = subqueryExpression<String>(
        _db.remoteAssetEntity.selectOnly()
          ..addColumns([_db.remoteAssetEntity.id])
          ..where(_db.remoteAssetEntity.checksum.equalsExp(_db.localAssetEntity.checksum))
          ..limit(1),
      );

      final query = _db.localAssetEntity.select().addColumns([remoteIdSubquery]);
      Expression<bool> predicate =
          _db.localAssetEntity.latitude.isNotNull() &
          _db.localAssetEntity.longitude.isNotNull() &
          _db.localAssetEntity.latitude.equals(0.0).not() &
          _db.localAssetEntity.longitude.equals(0.0).not();

      if (bounds != null) {
        final minLat = bounds.southwest.latitude;
        final maxLat = bounds.northeast.latitude;
        final minLng = bounds.southwest.longitude;
        final maxLng = bounds.northeast.longitude;
        if (minLat != maxLat && minLng != maxLng) {
          predicate =
              predicate &
              _db.localAssetEntity.latitude.isBetweenValues(minLat, maxLat) &
              _db.localAssetEntity.longitude.isBetweenValues(minLng, maxLng);
        }
      }

      query
        ..where(predicate)
        ..orderBy([OrderingTerm.desc(_db.localAssetEntity.createdAt)])
        ..limit(limit);

      final rows = await query.get();
      return rows.map((row) {
        final asset = row.readTable(_db.localAssetEntity).toDto(remoteId: row.read(remoteIdSubquery));
        return LocalMapMarker(
          asset: asset,
          location: LatLng(asset.latitude!, asset.longitude!),
        );
      }).toList();
    } catch (e) {
      _log.warning('Failed to query local map markers: $e');
      return const [];
    }
  }
}
