import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/data/db/main/database.dart';
import 'package:immich_mobile/data/db/main/table/remote/asset.dart';
import 'package:immich_mobile/data/db/main/table/remote/exif.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart' hide AssetVisibility;
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart' as domain show AssetVisibility;
import 'package:immich_mobile/domain/models/aves_media_metadata.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/extensions/asset_extensions.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

final immichAssetAvesRepositoryProvider = Provider<ImmichAssetRepository>((ref) {
  final db = ref.watch(driftProvider);
  final apiService = ref.watch(apiServiceProvider);
  return ImmichAssetRepository(
    db: db,
    assetsApi: apiService.assetsApi,
    searchApi: apiService.searchApi,
  );
});

/// Dedicated repository for Immich Server media operations, metadata enrichment, and paginated filtering.
class ImmichAssetRepository {
  static final _log = Logger('ImmichAssetRepository');

  final Drift _db;
  final AssetsApi _assetsApi;
  final SearchApi _searchApi;

  /// Lightweight LRU-like in-memory cache of remote asset API details to avoid redundant network requests.
  final Map<String, AssetResponseDto> _dtoCache = {};

  ImmichAssetRepository({
    required this._db,
    required this._assetsApi,
    required this._searchApi,
  });

  /// Reads complete metadata for a remote (or merged) asset.
  /// Prioritizes Immich REST API (`getAssetInfo`) + local Drift DB `ExifInfo`, and gracefully falls back offline.
  Future<AvesMediaMetadata> getRichMetadata(BaseAsset asset, {ExifInfo? cachedExif}) async {
    final remoteId = asset.remoteId;
    if (remoteId == null) {
      return AvesMediaMetadata.fromAssetAndExif(asset, cachedExif);
    }

    ExifInfo? exif = cachedExif;
    if (exif == null) {
      final row = await (_db.remoteExifEntity.select()..where((tbl) => tbl.assetId.equals(remoteId))).getSingleOrNull();
      exif = row?.toDto();
    }

    // Query albums this remote asset belongs to from local synced DB
    final albumNames = await _getRemoteAlbumNames(remoteId);

    AssetResponseDto? dto = _dtoCache[remoteId];
    if (dto == null) {
      try {
        dto = await _assetsApi.getAssetInfo(remoteId);
        if (dto != null) {
          if (_dtoCache.length > 200) {
            _dtoCache.remove(_dtoCache.keys.first);
          }
          _dtoCache[remoteId] = dto;
        }
      } catch (e) {
        _log.fine('Offline or failed to fetch remote AssetResponseDto for $remoteId: $e');
      }
    }

    final dtoExif = dto?.exifInfo.orElse(null);
    final mimeType = dto?.originalMimeType.orElse(null) ?? AvesMediaMetadata.inferMimeTypeFromFilename(asset.name);
    final modifiedAt = dto?.fileModifiedAt ?? dtoExif?.modifyDate.orElse(null) ?? asset.updatedAt;
    final projectionType = dtoExif?.projectionType.orElse(null);

    final effectiveExif = exif ??
        (dtoExif != null
            ? ExifInfo(
                fileSize: dtoExif.fileSizeInByte.orElse(null),
                description: dtoExif.description.orElse(null),
                orientation: dtoExif.orientation.orElse(null),
                timeZone: dtoExif.timeZone.orElse(null),
                dateTimeOriginal: dtoExif.dateTimeOriginal.orElse(null),
                rating: dtoExif.rating.orElse(null),
                width: dtoExif.exifImageWidth.orElse(null) ?? dto?.width,
                height: dtoExif.exifImageHeight.orElse(null) ?? dto?.height,
                latitude: dtoExif.latitude.orElse(null),
                longitude: dtoExif.longitude.orElse(null),
                city: dtoExif.city.orElse(null),
                state: dtoExif.state.orElse(null),
                country: dtoExif.country.orElse(null),
                make: dtoExif.make.orElse(null),
                model: dtoExif.model.orElse(null),
                lens: dtoExif.lensModel.orElse(null),
                f: dtoExif.fNumber.orElse(null),
                mm: dtoExif.focalLength.orElse(null),
                iso: dtoExif.iso.orElse(null),
                exposureSeconds: _parseExposureTime(dtoExif.exposureTime.orElse(null)),
              )
            : null);

    final baseMeta = AvesMediaMetadata.fromAssetAndExif(
      asset,
      effectiveExif,
      mimeType: mimeType,
      modifiedAt: modifiedAt,
      projectionType: projectionType,
      filePath: dto?.originalPath,
      contentUri: 'immich://assets/$remoteId',
      albumNames: albumNames,
    );

    // If exposureTime was a raw string from DTO and not parsed into seconds, preserve the raw string
    final rawExposure = dtoExif?.exposureTime.orElse(null);
    if ((baseMeta.exposureTime == null || baseMeta.exposureTime!.isEmpty) &&
        rawExposure != null &&
        rawExposure.isNotEmpty) {
      return AvesMediaMetadata(
        fileName: dto?.originalFileName.isNotEmpty == true ? dto!.originalFileName : baseMeta.fileName,
        mimeType: baseMeta.mimeType,
        fileSize: baseMeta.fileSize,
        width: baseMeta.width,
        height: baseMeta.height,
        capturedAt: baseMeta.capturedAt,
        timeZone: baseMeta.timeZone,
        modifiedAt: baseMeta.modifiedAt,
        make: baseMeta.make,
        model: baseMeta.model,
        lensModel: baseMeta.lensModel,
        exposureTime: rawExposure.endsWith('s') ? rawExposure : '$rawExposure s',
        fNumber: baseMeta.fNumber,
        iso: baseMeta.iso,
        focalLength: baseMeta.focalLength,
        latitude: baseMeta.latitude,
        longitude: baseMeta.longitude,
        city: baseMeta.city,
        state: baseMeta.state,
        country: baseMeta.country,
        duration: baseMeta.duration,
        videoCodec: baseMeta.videoCodec,
        fps: baseMeta.fps,
        bitRate: baseMeta.bitRate,
        colorSpace: baseMeta.colorSpace,
        projectionType: baseMeta.projectionType,
        filePath: baseMeta.filePath,
        contentUri: baseMeta.contentUri,
        albumNames: baseMeta.albumNames,
        source: baseMeta.source,
        checksum: baseMeta.checksum,
        remoteId: baseMeta.remoteId,
        localId: baseMeta.localId,
      );
    }

    return baseMeta;
  }

  Future<List<String>> _getRemoteAlbumNames(String remoteAssetId) async {
    try {
      final query = _db.remoteAlbumEntity.selectOnly().join([
        innerJoin(
          _db.remoteAlbumAssetEntity,
          _db.remoteAlbumAssetEntity.albumId.equalsExp(_db.remoteAlbumEntity.id),
          useColumns: false,
        ),
      ])
        ..addColumns([_db.remoteAlbumEntity.name])
        ..where(_db.remoteAlbumAssetEntity.assetId.equals(remoteAssetId));
      final rows = await query.get();
      return rows.map((r) => r.read(_db.remoteAlbumEntity.name)).whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  static double? _parseExposureTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final cleaned = raw.replaceAll('s', '').trim();
    if (cleaned.contains('/')) {
      final parts = cleaned.split('/');
      if (parts.length == 2) {
        final num = double.tryParse(parts[0]);
        final den = double.tryParse(parts[1]);
        if (num != null && den != null && den != 0) {
          return num / den;
        }
      }
    }
    return double.tryParse(cleaned);
  }

  /// Paginated server asset filtering (P0-2).
  /// 1. When tags are specified or online search is needed, calls Immich REST API `searchAssets` (`MetadataSearchDto`)
  ///    and applies client-side refinement on returned `AssetResponseDto` + `ExifResponseDto`.
  /// 2. Also supports fast SQLite query over synced `RemoteAssetEntity` + `RemoteExifEntity` for instant filtering.
  Future<({List<RemoteAsset> assets, int? nextPage})> filterServerAssets(
    AdvancedMediaFilter filter, {
    required int page,
    int pageSize = 200,
  }) async {
    if (filter.sourceScope == MediaSourceScope.localOnly) {
      return (assets: const <RemoteAsset>[], nextPage: null);
    }

    // If tags are selected, we MUST use the Immich Server Search API because server tags are not duplicated in a local table (P0-3 requirement).
    if (filter.tags.isNotEmpty) {
      return _filterViaRestApi(filter, page: page, pageSize: pageSize);
    }

    // Try local synced database first for rich SQL filtering (width, height, fileSize, GPS, album, make/model),
    // and fall back to REST API if local synced DB is empty.
    final localSyncedCount = await _db.remoteAssetEntity.count().getSingle();
    if (localSyncedCount > 0) {
      return _filterViaSyncedDb(filter, page: page, pageSize: pageSize);
    }

    return _filterViaRestApi(filter, page: page, pageSize: pageSize);
  }

  Future<({List<RemoteAsset> assets, int? nextPage})> _filterViaRestApi(
    AdvancedMediaFilter filter, {
    required int page,
    required int pageSize,
  }) async {
    try {
      AssetTypeEnum? apiType;
      if (filter.mediaType == AssetType.image) {
        apiType = AssetTypeEnum.IMAGE;
      } else if (filter.mediaType == AssetType.video) {
        apiType = AssetTypeEnum.VIDEO;
      }

      final dto = MetadataSearchDto(
        originalFileName: filter.textQuery != null && filter.textQuery!.trim().isNotEmpty
            ? Optional.present(filter.textQuery!.trim())
            : const Optional.absent(),
        make: filter.cameraMake != null && filter.cameraMake!.trim().isNotEmpty
            ? Optional.present(filter.cameraMake!.trim())
            : const Optional.absent(),
        model: filter.cameraModel != null && filter.cameraModel!.trim().isNotEmpty
            ? Optional.present(filter.cameraModel!.trim())
            : const Optional.absent(),
        takenAfter: filter.takenAfter != null ? Optional.present(filter.takenAfter) : const Optional.absent(),
        takenBefore: filter.takenBefore != null ? Optional.present(filter.takenBefore) : const Optional.absent(),
        isFavorite: switch (filter.favoriteFilter) {
          TriStateFilter.yes => const Optional.present(true),
          TriStateFilter.no => const Optional.present(false),
          TriStateFilter.any => const Optional.absent(),
        },
        isNotInAlbum: filter.notInAnyAlbum ? const Optional.present(true) : const Optional.absent(),
        tagIds: filter.tags.isNotEmpty
            ? Optional.present(filter.tags.map((t) => t.id).toList())
            : const Optional.absent(),
        type: apiType != null ? Optional.present(apiType) : const Optional.absent(),
        visibility: const Optional.present(AssetVisibility.timeline),
        withExif: const Optional.present(true),
        page: Optional.present(page),
        size: Optional.present(pageSize),
      );

      final response = await _searchApi.searchAssets(dto);
      if (response == null) {
        return (assets: const <RemoteAsset>[], nextPage: null);
      }

      final filtered = <RemoteAsset>[];
      for (final item in response.assets.items) {
        final remoteAsset = item.toDto();
        final dtoExif = item.exifInfo.orElse(null);
        final exif = dtoExif != null
            ? ExifInfo(
                fileSize: dtoExif.fileSizeInByte.orElse(null),
                width: dtoExif.exifImageWidth.orElse(null) ?? item.width,
                height: dtoExif.exifImageHeight.orElse(null) ?? item.height,
                latitude: dtoExif.latitude.orElse(null),
                longitude: dtoExif.longitude.orElse(null),
                make: dtoExif.make.orElse(null),
                model: dtoExif.model.orElse(null),
                city: dtoExif.city.orElse(null),
                description: dtoExif.description.orElse(null),
                dateTimeOriginal: dtoExif.dateTimeOriginal.orElse(null),
              )
            : null;
        if (filter.matchesAsset(remoteAsset, exif: exif)) {
          filtered.add(remoteAsset);
        }
      }

      final nextPageStr = response.assets.nextPage;
      final nextPage = nextPageStr != null ? int.tryParse(nextPageStr) : null;
      return (assets: filtered, nextPage: nextPage);
    } catch (e, s) {
      _log.warning('Failed to filter server assets via REST API', e, s);
      return (assets: const <RemoteAsset>[], nextPage: null);
    }
  }

  Future<({List<RemoteAsset> assets, int? nextPage})> _filterViaSyncedDb(
    AdvancedMediaFilter filter, {
    required int page,
    required int pageSize,
  }) async {
    final offset = (page - 1) * pageSize;

    final localIdSubquery = subqueryExpression<String>(
      _db.localAssetEntity.selectOnly()
        ..addColumns([_db.localAssetEntity.id])
        ..where(_db.localAssetEntity.checksum.equalsExp(_db.remoteAssetEntity.checksum))
        ..limit(1),
    );

    final query = _db.remoteAssetEntity.select().addColumns([localIdSubquery]).join([
      leftOuterJoin(
        _db.remoteExifEntity,
        _db.remoteExifEntity.assetId.equalsExp(_db.remoteAssetEntity.id),
      ),
      if (filter.albumId != null && !filter.isLocalAlbum)
        innerJoin(
          _db.remoteAlbumAssetEntity,
          _db.remoteAlbumAssetEntity.assetId.equalsExp(_db.remoteAssetEntity.id) &
              _db.remoteAlbumAssetEntity.albumId.equals(filter.albumId!),
          useColumns: false,
        ),
    ]);

    Expression<bool> predicate =
        _db.remoteAssetEntity.deletedAt.isNull() &
        _db.remoteAssetEntity.visibility.equalsValue(domain.AssetVisibility.timeline);

    if (filter.mediaType != null) {
      predicate = predicate & _db.remoteAssetEntity.type.equalsValue(filter.mediaType);
    }
    if (filter.takenAfter != null) {
      predicate = predicate & _db.remoteAssetEntity.createdAt.isBiggerOrEqualValue(filter.takenAfter!);
    }
    if (filter.takenBefore != null) {
      predicate = predicate & _db.remoteAssetEntity.createdAt.isSmallerOrEqualValue(filter.takenBefore!);
    }
    if (filter.favoriteFilter == TriStateFilter.yes) {
      predicate = predicate & _db.remoteAssetEntity.isFavorite.equals(true);
    } else if (filter.favoriteFilter == TriStateFilter.no) {
      predicate = predicate & _db.remoteAssetEntity.isFavorite.equals(false);
    }
    if (filter.minWidth != null) {
      predicate = predicate & _db.remoteAssetEntity.width.isBiggerOrEqualValue(filter.minWidth!);
    }
    if (filter.maxWidth != null) {
      predicate = predicate & _db.remoteAssetEntity.width.isSmallerOrEqualValue(filter.maxWidth!);
    }
    if (filter.minHeight != null) {
      predicate = predicate & _db.remoteAssetEntity.height.isBiggerOrEqualValue(filter.minHeight!);
    }
    if (filter.maxHeight != null) {
      predicate = predicate & _db.remoteAssetEntity.height.isSmallerOrEqualValue(filter.maxHeight!);
    }
    if (filter.minSizeBytes != null) {
      predicate = predicate & _db.remoteExifEntity.fileSize.isBiggerOrEqualValue(filter.minSizeBytes!);
    }
    if (filter.maxSizeBytes != null) {
      predicate = predicate & _db.remoteExifEntity.fileSize.isSmallerOrEqualValue(filter.maxSizeBytes!);
    }
    if (filter.gpsFilter == TriStateFilter.yes) {
      predicate =
          predicate &
          _db.remoteExifEntity.latitude.isNotNull() &
          _db.remoteExifEntity.longitude.isNotNull() &
          _db.remoteExifEntity.latitude.equals(0.0).not() &
          _db.remoteExifEntity.longitude.equals(0.0).not();
    } else if (filter.gpsFilter == TriStateFilter.no) {
      predicate =
          predicate &
          (_db.remoteExifEntity.latitude.isNull() |
              _db.remoteExifEntity.longitude.isNull() |
              _db.remoteExifEntity.latitude.equals(0.0));
    }
    if (filter.cameraMake != null && filter.cameraMake!.trim().isNotEmpty) {
      predicate = predicate & _db.remoteExifEntity.make.like('%${filter.cameraMake!.trim()}%');
    }
    if (filter.cameraModel != null && filter.cameraModel!.trim().isNotEmpty) {
      predicate = predicate & _db.remoteExifEntity.model.like('%${filter.cameraModel!.trim()}%');
    }
    if (filter.notInAnyAlbum) {
      final inAnyAlbum = _db.remoteAlbumAssetEntity.selectOnly()
        ..addColumns([_db.remoteAlbumAssetEntity.assetId])
        ..where(_db.remoteAlbumAssetEntity.assetId.equalsExp(_db.remoteAssetEntity.id));
      predicate = predicate & notExistsQuery(inAnyAlbum);
    }
    if (filter.textQuery != null && filter.textQuery!.trim().isNotEmpty) {
      final q = '%${filter.textQuery!.trim()}%';
      predicate =
          predicate &
          (_db.remoteAssetEntity.name.like(q) |
              _db.remoteExifEntity.description.like(q) |
              _db.remoteExifEntity.city.like(q) |
              _db.remoteExifEntity.model.like(q));
    }

    query
      ..where(predicate)
      ..orderBy([OrderingTerm.desc(_db.remoteAssetEntity.createdAt)])
      ..limit(pageSize, offset: offset);

    final rows = await query.get();
    final results = <RemoteAsset>[];
    for (final row in rows) {
      final asset = row.readTable(_db.remoteAssetEntity).toDto(localId: row.read(localIdSubquery));
      final exif = row.readTableOrNull(_db.remoteExifEntity)?.toDto();
      if (filter.matchesAsset(asset, exif: exif)) {
        results.add(asset);
      }
    }

    final hasMore = rows.length >= pageSize;
    return (assets: results, nextPage: hasMore ? page + 1 : null);
  }

  /// Queries distinct camera models known in the synced server EXIF table for filter suggestions.
  Future<List<({String? make, String model})>> getKnownCameraModels() async {
    try {
      final query = _db.remoteExifEntity.selectOnly(distinct: true)
        ..addColumns([_db.remoteExifEntity.make, _db.remoteExifEntity.model])
        ..where(_db.remoteExifEntity.model.isNotNull() & _db.remoteExifEntity.model.equals('').not())
        ..orderBy([OrderingTerm.asc(_db.remoteExifEntity.make), OrderingTerm.asc(_db.remoteExifEntity.model)]);
      final rows = await query.get();
      return rows
          .map(
            (r) => (
              make: r.read(_db.remoteExifEntity.make),
              model: r.read(_db.remoteExifEntity.model)!,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
