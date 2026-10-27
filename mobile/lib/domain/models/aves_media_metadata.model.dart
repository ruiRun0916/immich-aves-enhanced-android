import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:path/path.dart' as p;

/// Identifies the origin of a media item in Immich-Aves Enhanced.
enum UnifiedMediaSource {
  /// Stored only on the Android device (MediaStore).
  local,

  /// Stored only on the Immich server.
  immich,

  /// Linked between local MediaStore and Immich server (verified via checksum/ID, never filename).
  merged,
}

/// Permission state for accessing local device media on Android 13/14+.
enum MediaPermissionStatus {
  grantedFull,
  grantedPartial,
  denied,
  restricted,
  notApplicable,
}

/// Operations supported on a given [UnifiedMediaItem].
enum MediaCapability {
  viewDetails,
  copyMetadata,
  shareSystem,
  shareServerLink,
  manageServerTags,
  favoriteServer,
  archiveServer,
  trashServer,
  openOnMap,
  editNonDestructive,
}

/// Special media format badges inspired by Aves Gallery.
enum SpecialMediaFormat {
  raw('RAW'),
  heif('HEIF/HEIC'),
  avif('AVIF'),
  webp('WebP'),
  tiff('TIFF'),
  geotiff('GeoTIFF'),
  svg('SVG'),
  gif('GIF'),
  jxl('JPEG XL'),
  motionPhoto('实况/动态照片'),
  animated('动图'),
  panorama360('360° 全景');

  final String label;
  const SpecialMediaFormat(this.label);
}

/// Comprehensive media metadata model for P0-1 (Enhanced Photo Details) & P0-2 (Advanced Filtering).
class AvesMediaMetadata {
  final String fileName;
  final String? mimeType;
  final int? fileSize;
  final int? width;
  final int? height;
  final DateTime? capturedAt;
  final String? timeZone;
  final DateTime? modifiedAt;
  final String? make;
  final String? model;
  final String? lensModel;
  final String? exposureTime;
  final String? fNumber;
  final int? iso;
  final String? focalLength;
  final double? latitude;
  final double? longitude;
  final String? city;
  final String? state;
  final String? country;
  final Duration? duration;
  final String? videoCodec;
  final double? fps;
  final int? bitRate;
  final String? colorSpace;
  final String? projectionType;
  final String? filePath;
  final String? contentUri;
  final List<String> albumNames;
  final UnifiedMediaSource source;
  final String? checksum;
  final String? remoteId;
  final String? localId;

  /// 资产描述（Aves 叠加层「显示描述」用）。
  final String? description;

  /// 星级评分（Aves 叠加层「显示评分和标签」用）。
  final int? rating;

  const AvesMediaMetadata({
    required this.fileName,
    this.mimeType,
    this.fileSize,
    this.width,
    this.height,
    this.capturedAt,
    this.timeZone,
    this.modifiedAt,
    this.make,
    this.model,
    this.lensModel,
    this.exposureTime,
    this.fNumber,
    this.iso,
    this.focalLength,
    this.latitude,
    this.longitude,
    this.city,
    this.state,
    this.country,
    this.duration,
    this.videoCodec,
    this.fps,
    this.bitRate,
    this.colorSpace,
    this.projectionType,
    this.filePath,
    this.contentUri,
    this.albumNames = const [],
    required this.source,
    this.checksum,
    this.remoteId,
    this.localId,
    this.description,
    this.rating,
  });

  bool get hasValidGps =>
      latitude != null &&
      longitude != null &&
      latitude != 0 &&
      longitude != 0 &&
      !latitude!.isNaN &&
      !longitude!.isNaN;

  String? get formattedGps =>
      hasValidGps ? '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}' : null;

  String? get formattedLocationName {
    final parts = [city, state, country].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  String? get formattedResolution {
    if (width == null || height == null || width! <= 0 || height! <= 0) {
      return null;
    }
    final mp = (width! * height!) / 1000000.0;
    final mpStr = mp >= 0.1 ? ' (${mp.toStringAsFixed(1)} MP)' : '';
    final ratio = _aspectRatioLabel(width!, height!);
    return '$width × $height$mpStr${ratio != null ? ' • $ratio' : ''}';
  }

  String? get formattedDuration {
    if (duration == null || duration == Duration.zero) {
      return null;
    }
    final d = duration!;
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String? get formattedVideoEncoding {
    final parts = <String>[];
    if (videoCodec != null && videoCodec!.trim().isNotEmpty) {
      parts.add(videoCodec!.trim());
    }
    if (fps != null && fps! > 0) {
      parts.add('${fps!.toStringAsFixed(fps! % 1 == 0 ? 0 : 2)} fps');
    }
    if (bitRate != null && bitRate! > 0) {
      final mbps = bitRate! / 1000000.0;
      if (mbps >= 1.0) {
        parts.add('${mbps.toStringAsFixed(1)} Mbps');
      } else {
        parts.add('${(bitRate! / 1000.0).round()} kbps');
      }
    }
    if (colorSpace != null && colorSpace!.trim().isNotEmpty) {
      parts.add(colorSpace!.trim());
    }
    return parts.isEmpty ? null : parts.join(' • ');
  }

  String get fileExtension {
    final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    return ext;
  }

  /// Infers MIME type from explicit value or filename extension.
  String get effectiveMimeType {
    if (mimeType != null && mimeType!.trim().isNotEmpty) {
      return mimeType!.trim();
    }
    return inferMimeTypeFromFilename(fileName);
  }

  /// Detects special formats (RAW, GeoTIFF, TIFF, SVG, HEIC, AVIF, WebP, Motion Photo, 360).
  List<SpecialMediaFormat> detectSpecialFormats({bool isMotionPhoto = false, bool isAnimated = false}) {
    final formats = <SpecialMediaFormat>[];
    final ext = fileExtension;
    final mime = effectiveMimeType.toLowerCase();

    const rawExtensions = {'dng', 'cr2', 'cr3', 'nef', 'nrw', 'arw', 'srf', 'sr2', 'orf', 'rw2', 'raf', 'pef', 'raw'};
    if (rawExtensions.contains(ext) ||
        mime.contains('x-adobe-dng') ||
        mime.contains('x-canon-') ||
        mime.contains('x-nikon-') ||
        mime.contains('x-sony-') ||
        mime.contains('x-panasonic-') ||
        mime.contains('x-fuji-') ||
        mime.contains('x-olympus-')) {
      formats.add(SpecialMediaFormat.raw);
    }

    if (ext == 'tif' || ext == 'tiff' || mime == 'image/tiff') {
      if (hasValidGps || (projectionType != null && projectionType!.isNotEmpty)) {
        formats.add(SpecialMediaFormat.geotiff);
      } else {
        formats.add(SpecialMediaFormat.tiff);
      }
    }

    if (ext == 'svg' || mime == 'image/svg+xml') {
      formats.add(SpecialMediaFormat.svg);
    }
    if (ext == 'heic' || ext == 'heif' || mime == 'image/heic' || mime == 'image/heif') {
      formats.add(SpecialMediaFormat.heif);
    }
    if (ext == 'avif' || mime == 'image/avif') {
      formats.add(SpecialMediaFormat.avif);
    }
    if (ext == 'webp' || mime == 'image/webp') {
      formats.add(SpecialMediaFormat.webp);
    }
    if (ext == 'gif' || mime == 'image/gif') {
      formats.add(SpecialMediaFormat.gif);
    }
    if (ext == 'jxl' || mime == 'image/jxl') {
      formats.add(SpecialMediaFormat.jxl);
    }
    if (isMotionPhoto) {
      formats.add(SpecialMediaFormat.motionPhoto);
    }
    if (isAnimated) {
      formats.add(SpecialMediaFormat.animated);
    }
    if (projectionType != null && projectionType!.toUpperCase().contains('EQUIRECTANGULAR')) {
      formats.add(SpecialMediaFormat.panorama360);
    }
    return formats;
  }

  static String inferMimeTypeFromFilename(String filename) {
    final ext = p.extension(filename).replaceFirst('.', '').toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      'avif' => 'image/avif',
      'gif' => 'image/gif',
      'svg' => 'image/svg+xml',
      'tif' || 'tiff' => 'image/tiff',
      'dng' => 'image/x-adobe-dng',
      'cr2' => 'image/x-canon-cr2',
      'cr3' => 'image/x-canon-cr3',
      'nef' => 'image/x-nikon-nef',
      'arw' => 'image/x-sony-arw',
      'orf' => 'image/x-olympus-orf',
      'rw2' => 'image/x-panasonic-rw2',
      'raf' => 'image/x-fuji-raf',
      'jxl' => 'image/jxl',
      'bmp' => 'image/bmp',
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'mkv' => 'video/x-matroska',
      'webm' => 'video/webm',
      'avi' => 'video/x-msvideo',
      '3gp' => 'video/3gpp',
      _ => '未知',
    };
  }

  static String? _aspectRatioLabel(int w, int h) {
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final g = gcd(w, h);
    final rw = w ~/ g;
    final rh = h ~/ g;
    if (rw <= 32 && rh <= 32) {
      return '$rw:$rh';
    }
    final ratio = w / h;
    if ((ratio - 16 / 9).abs() < 0.03) {
      return '16:9';
    }
    if ((ratio - 9 / 16).abs() < 0.03) {
      return '9:16';
    }
    if ((ratio - 4 / 3).abs() < 0.03) {
      return '4:3';
    }
    if ((ratio - 3 / 4).abs() < 0.03) {
      return '3:4';
    }
    if ((ratio - 3 / 2).abs() < 0.03) {
      return '3:2';
    }
    if ((ratio - 2 / 3).abs() < 0.03) {
      return '2:3';
    }
    if ((ratio - 1.0).abs() < 0.02) {
      return '1:1';
    }
    return null;
  }

  factory AvesMediaMetadata.fromAssetAndExif(
    BaseAsset asset,
    ExifInfo? exif, {
    String? mimeType,
    DateTime? modifiedAt,
    String? videoCodec,
    double? fps,
    int? bitRate,
    String? colorSpace,
    String? projectionType,
    String? filePath,
    String? contentUri,
    List<String> albumNames = const [],
  }) {
    final source = switch (asset.storage) {
      AssetState.local => UnifiedMediaSource.local,
      AssetState.remote => UnifiedMediaSource.immich,
      AssetState.merged => UnifiedMediaSource.merged,
    };

    double? lat = exif?.latitude;
    double? lng = exif?.longitude;
    if ((lat == null || lng == null) && asset is LocalAsset) {
      lat = asset.latitude;
      lng = asset.longitude;
    }

    final width = exif?.width ?? asset.width;
    final height = exif?.height ?? asset.height;

    return AvesMediaMetadata(
      fileName: asset.name,
      mimeType: mimeType,
      fileSize: exif?.fileSize,
      width: width,
      height: height,
      capturedAt: exif?.dateTimeOriginal ?? asset.createdAt,
      timeZone: exif?.timeZone,
      modifiedAt: modifiedAt ?? asset.updatedAt,
      make: exif?.make,
      model: exif?.model,
      lensModel: exif?.lens,
      exposureTime: (exif != null && exif.exposureTime.isNotEmpty) ? exif.exposureTime : null,
      fNumber: (exif != null && exif.fNumber.isNotEmpty) ? 'ƒ/${exif.fNumber}' : null,
      iso: exif?.iso,
      focalLength: (exif != null && exif.focalLength.isNotEmpty) ? '${exif.focalLength} mm' : null,
      latitude: lat,
      longitude: lng,
      city: exif?.city,
      state: exif?.state,
      country: exif?.country,
      duration: asset.isVideo ? asset.duration : null,
      videoCodec: videoCodec,
      fps: fps,
      bitRate: bitRate,
      colorSpace: colorSpace,
      projectionType: projectionType,
      filePath: filePath,
      contentUri: contentUri,
      albumNames: albumNames,
      source: source,
      checksum: asset.checksum,
      remoteId: asset.remoteId,
      localId: asset.localId,
      description: exif?.description,
      rating: exif?.rating,
    );
  }
}

/// Unified media abstraction (P1-2 & Section 七.2) that wraps [BaseAsset]
/// while strictly preserving data source identity and separating local/server IDs.
class UnifiedMediaItem {
  final UnifiedMediaSource source;
  final String stableId;
  final BaseAsset asset;
  final String thumbnailSource;
  final String originalSource;
  final AvesMediaMetadata metadata;
  final Set<MediaCapability> capabilities;
  final MediaPermissionStatus permissionStatus;

  const UnifiedMediaItem({
    required this.source,
    required this.stableId,
    required this.asset,
    required this.thumbnailSource,
    required this.originalSource,
    required this.metadata,
    required this.capabilities,
    required this.permissionStatus,
  });

  bool get isLocal => source == UnifiedMediaSource.local;
  bool get isServer => source == UnifiedMediaSource.immich;
  bool get isMerged => source == UnifiedMediaSource.merged;

  /// Two items represent the same media ONLY if they share a non-null remoteId,
  /// a non-null localId, or an identical cryptographic checksum.
  /// Never compares by filename alone, and never compares localId against remoteId.
  bool refersToSameMedia(UnifiedMediaItem other) {
    if (stableId == other.stableId) {
      return true;
    }
    return asset.refersToSameAsset(other.asset);
  }

  factory UnifiedMediaItem.fromBaseAsset(
    BaseAsset asset, {
    ExifInfo? exif,
    AvesMediaMetadata? customMetadata,
    MediaPermissionStatus permissionStatus = MediaPermissionStatus.grantedFull,
  }) {
    final source = switch (asset.storage) {
      AssetState.local => UnifiedMediaSource.local,
      AssetState.remote => UnifiedMediaSource.immich,
      AssetState.merged => UnifiedMediaSource.merged,
    };

    // Stable ID uses explicit namespace prefix so local MediaStore ID is never confused with Immich UUID.
    final stableId = switch (source) {
      UnifiedMediaSource.local => 'local:${asset.localId ?? asset.id}',
      UnifiedMediaSource.immich => 'immich:${asset.remoteId ?? asset.id}',
      UnifiedMediaSource.merged => 'merged:immich:${asset.remoteId}_local:${asset.localId}',
    };

    final thumbnailSource = asset.hasRemote
        ? 'immich://assets/${asset.remoteId}/thumbnail'
        : 'content://media/external/images/media/${asset.localId}/thumbnail';

    final originalSource = asset.hasLocal
        ? 'content://media/external/file/${asset.localId}'
        : 'immich://assets/${asset.remoteId}/original';

    final meta = customMetadata ?? AvesMediaMetadata.fromAssetAndExif(asset, exif);

    final capabilities = <MediaCapability>{
      MediaCapability.viewDetails,
      MediaCapability.copyMetadata,
      MediaCapability.shareSystem,
      if (meta.hasValidGps) MediaCapability.openOnMap,
      if (asset.hasRemote) ...[
        MediaCapability.shareServerLink,
        MediaCapability.manageServerTags,
        MediaCapability.favoriteServer,
        MediaCapability.archiveServer,
        MediaCapability.trashServer,
      ],
      if (asset.isEditable) MediaCapability.editNonDestructive,
    };

    return UnifiedMediaItem(
      source: source,
      stableId: stableId,
      asset: asset,
      thumbnailSource: thumbnailSource,
      originalSource: originalSource,
      metadata: meta,
      capabilities: capabilities,
      permissionStatus: asset.hasLocal ? permissionStatus : MediaPermissionStatus.notApplicable,
    );
  }
}
