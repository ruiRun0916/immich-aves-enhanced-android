import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/aves_media_metadata.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/infrastructure/repositories/immich_asset_aves.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/local_media_aves.repository.dart';

final unifiedMediaAvesRepositoryProvider = Provider<UnifiedMediaRepository>((ref) {
  final immichRepo = ref.watch(immichAssetAvesRepositoryProvider);
  final localRepo = ref.watch(localMediaAvesRepositoryProvider);
  return UnifiedMediaRepository(
    immichRepository: immichRepo,
    localRepository: localRepo,
  );
});

/// Provider for fetching rich [AvesMediaMetadata] for any [BaseAsset] in the viewer or detail sheet.
final avesAssetMetadataProvider = FutureProvider.autoDispose.family<AvesMediaMetadata, BaseAsset>((ref, asset) {
  return ref.watch(unifiedMediaAvesRepositoryProvider).getUnifiedMetadata(asset);
});

/// Coordinates [ImmichAssetRepository] and [LocalMediaRepository] while keeping
/// their storage models, IDs, and business rules strictly separated (P1-2 & Section 七.2).
class UnifiedMediaRepository {
  final ImmichAssetRepository immichRepository;
  final LocalMediaRepository localRepository;

  const UnifiedMediaRepository({
    required this.immichRepository,
    required this.localRepository,
  });

  /// Resolves comprehensive metadata for any [BaseAsset] (`LocalAsset` or `RemoteAsset`),
  /// prioritizing Immich API metadata for server assets and Android MediaStore for local assets.
  Future<AvesMediaMetadata> getUnifiedMetadata(BaseAsset asset, {ExifInfo? exif}) async {
    if (asset is RemoteAsset) {
      final serverMeta = await immichRepository.getRichMetadata(asset, cachedExif: exif);
      if (asset.localId != null) {
        final localDummy = LocalAsset(
          id: asset.localId!,
          remoteId: asset.id,
          name: asset.name,
          checksum: asset.checksum,
          type: asset.type,
          createdAt: asset.createdAt,
          updatedAt: asset.updatedAt,
          width: asset.width,
          height: asset.height,
          durationMs: asset.durationMs,
          isFavorite: asset.isFavorite,
          playbackStyle: asset.playbackStyle,
          isEdited: asset.isEdited,
        );
        final localMeta = await localRepository.getRichMetadata(localDummy);
        final mergedAlbums = {...serverMeta.albumNames, ...localMeta.albumNames}.toList();
        return AvesMediaMetadata(
          fileName: serverMeta.fileName,
          mimeType: serverMeta.mimeType ?? localMeta.mimeType,
          fileSize: serverMeta.fileSize ?? localMeta.fileSize,
          width: serverMeta.width ?? localMeta.width,
          height: serverMeta.height ?? localMeta.height,
          capturedAt: serverMeta.capturedAt ?? localMeta.capturedAt,
          timeZone: serverMeta.timeZone,
          modifiedAt: serverMeta.modifiedAt ?? localMeta.modifiedAt,
          make: serverMeta.make,
          model: serverMeta.model,
          lensModel: serverMeta.lensModel,
          exposureTime: serverMeta.exposureTime,
          fNumber: serverMeta.fNumber,
          iso: serverMeta.iso,
          focalLength: serverMeta.focalLength,
          latitude: serverMeta.latitude ?? localMeta.latitude,
          longitude: serverMeta.longitude ?? localMeta.longitude,
          city: serverMeta.city,
          state: serverMeta.state,
          country: serverMeta.country,
          duration: serverMeta.duration ?? localMeta.duration,
          videoCodec: serverMeta.videoCodec,
          fps: serverMeta.fps,
          bitRate: serverMeta.bitRate,
          colorSpace: serverMeta.colorSpace,
          projectionType: serverMeta.projectionType,
          filePath: localMeta.filePath ?? serverMeta.filePath,
          contentUri: localMeta.contentUri ?? serverMeta.contentUri,
          albumNames: mergedAlbums,
          source: UnifiedMediaSource.merged,
          checksum: asset.checksum,
          remoteId: asset.id,
          localId: asset.localId,
        );
      }
      return serverMeta;
    }

    if (asset is LocalAsset) {
      final ExifInfo? remoteExif = exif;
      AvesMediaMetadata? remoteMeta;
      if (asset.remoteId != null) {
        remoteMeta = await immichRepository.getRichMetadata(asset, cachedExif: remoteExif);
      }
      final localMeta = await localRepository.getRichMetadata(asset, pairedRemoteExif: remoteExif);
      if (remoteMeta != null) {
        final mergedAlbums = {...localMeta.albumNames, ...remoteMeta.albumNames}.toList();
        return AvesMediaMetadata(
          fileName: localMeta.fileName,
          mimeType: localMeta.mimeType ?? remoteMeta.mimeType,
          fileSize: localMeta.fileSize ?? remoteMeta.fileSize,
          width: localMeta.width ?? remoteMeta.width,
          height: localMeta.height ?? remoteMeta.height,
          capturedAt: remoteMeta.capturedAt ?? localMeta.capturedAt,
          timeZone: remoteMeta.timeZone,
          modifiedAt: localMeta.modifiedAt ?? remoteMeta.modifiedAt,
          make: remoteMeta.make ?? localMeta.make,
          model: remoteMeta.model ?? localMeta.model,
          lensModel: remoteMeta.lensModel ?? localMeta.lensModel,
          exposureTime: remoteMeta.exposureTime ?? localMeta.exposureTime,
          fNumber: remoteMeta.fNumber ?? localMeta.fNumber,
          iso: remoteMeta.iso ?? localMeta.iso,
          focalLength: remoteMeta.focalLength ?? localMeta.focalLength,
          latitude: localMeta.latitude ?? remoteMeta.latitude,
          longitude: localMeta.longitude ?? remoteMeta.longitude,
          city: remoteMeta.city ?? localMeta.city,
          state: remoteMeta.state ?? localMeta.state,
          country: remoteMeta.country ?? localMeta.country,
          duration: localMeta.duration ?? remoteMeta.duration,
          videoCodec: remoteMeta.videoCodec,
          fps: remoteMeta.fps,
          bitRate: remoteMeta.bitRate,
          colorSpace: remoteMeta.colorSpace,
          projectionType: remoteMeta.projectionType,
          filePath: localMeta.filePath ?? remoteMeta.filePath,
          contentUri: localMeta.contentUri,
          albumNames: mergedAlbums,
          source: UnifiedMediaSource.merged,
          checksum: asset.checksum,
          remoteId: asset.remoteId,
          localId: asset.id,
        );
      }
      return localMeta;
    }

    return AvesMediaMetadata.fromAssetAndExif(asset, exif);
  }

  /// Paginated unified media query supporting Server-only, Local-only, Merged-only, or Unified (All) browsing.
  /// Never merges two assets based on filename; only deduplicates when explicit `remoteId` or `checksum` matches.
  Future<({List<BaseAsset> assets, int? nextPage})> filterUnifiedAssets(
    AdvancedMediaFilter filter, {
    required int page,
    int pageSize = 200,
  }) async {
    switch (filter.sourceScope) {
      case MediaSourceScope.serverOnly:
        return immichRepository.filterServerAssets(filter, page: page, pageSize: pageSize);
      case MediaSourceScope.localOnly:
        final res = await localRepository.filterLocalAssets(filter, page: page, pageSize: pageSize);
        return (assets: res.assets.cast<BaseAsset>(), nextPage: res.nextPage);
      case MediaSourceScope.mergedOnly:
        final serverRes = await immichRepository.filterServerAssets(filter, page: page, pageSize: pageSize);
        final merged = serverRes.assets.where((a) => a.isMerged).cast<BaseAsset>().toList();
        return (assets: merged, nextPage: serverRes.nextPage);
      case MediaSourceScope.all:
        final serverFuture = immichRepository.filterServerAssets(filter, page: page, pageSize: pageSize);
        final localFuture = localRepository.filterLocalAssets(filter, page: page, pageSize: pageSize);
        final results = await Future.wait([serverFuture, localFuture]);
        final serverRes = results[0] as ({List<RemoteAsset> assets, int? nextPage});
        final localRes = results[1] as ({List<LocalAsset> assets, int? nextPage});

        final combined = <BaseAsset>[...serverRes.assets];
        final seenRemoteIds = <String>{
          for (final a in serverRes.assets) a.id,
        };
        final seenLocalIds = <String>{
          for (final a in serverRes.assets)
            if (a.localId != null) a.localId!,
        };
        final seenChecksums = <String>{
          for (final a in serverRes.assets)
            if (a.checksum != null && a.checksum!.isNotEmpty) a.checksum!,
        };

        for (final local in localRes.assets) {
          if (seenLocalIds.contains(local.id)) {
            continue;
          }
          if (local.remoteId != null && seenRemoteIds.contains(local.remoteId)) {
            continue;
          }
          if (local.checksum != null && local.checksum!.isNotEmpty && seenChecksums.contains(local.checksum)) {
            continue;
          }
          combined.add(local);
        }

        combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final hasNext = serverRes.nextPage != null || localRes.nextPage != null;
        return (assets: combined, nextPage: hasNext ? page + 1 : null);
    }
  }
}
