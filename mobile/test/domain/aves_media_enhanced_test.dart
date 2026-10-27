import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/aves_media_metadata.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/infrastructure/repositories/local_media_aves.repository.dart';
import 'package:immich_mobile/presentation/widgets/timeline/fixed/segment_builder.dart';
import 'package:flutter/widgets.dart';
import 'package:immich_mobile/providers/album_media_filter.provider.dart';
import 'package:immich_mobile/providers/aves_scroll_chrome.provider.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';

void main() {
  group('P0-1: AvesMediaMetadata & Special Format Detection', () {
    test('calculates resolution MP/aspect ratio, infers MIME type, and detects RAW/GeoTIFF/SVG formats', () {
      final rawMeta = AvesMediaMetadata(
        fileName: 'DSC00123.ARW',
        mimeType: AvesMediaMetadata.inferMimeTypeFromFilename('DSC00123.ARW'),
        fileSize: 25 * 1024 * 1024,
        width: 6000,
        height: 4000,
        capturedAt: DateTime(2026, 5, 1, 12, 30),
        make: 'SONY',
        model: 'ILCE-7RM4',
        lensModel: 'FE 24-70mm F2.8 GM',
        exposureTime: '1/250 s',
        fNumber: 'ƒ/2.8',
        iso: 100,
        focalLength: '35 mm',
        latitude: 31.2304,
        longitude: 121.4737,
        source: UnifiedMediaSource.immich,
      );

      expect(rawMeta.effectiveMimeType, 'image/x-sony-arw');
      expect(rawMeta.formattedResolution, contains('6000 × 4000'));
      expect(rawMeta.formattedResolution, contains('24.0 MP'));
      expect(rawMeta.formattedResolution, contains('3:2'));
      expect(rawMeta.hasValidGps, isTrue);
      expect(rawMeta.detectSpecialFormats(), contains(SpecialMediaFormat.raw));

      const geoTiffMeta = AvesMediaMetadata(
        fileName: 'terrain_map.tif',
        mimeType: 'image/tiff',
        latitude: 39.9042,
        longitude: 116.4074,
        source: UnifiedMediaSource.local,
      );
      expect(geoTiffMeta.detectSpecialFormats(), contains(SpecialMediaFormat.geotiff));

      const svgMeta = AvesMediaMetadata(
        fileName: 'vector_diagram.svg',
        mimeType: 'image/svg+xml',
        source: UnifiedMediaSource.local,
      );
      expect(svgMeta.detectSpecialFormats(), contains(SpecialMediaFormat.svg));
    });
  });

  group('P1-1 & P1-2: UnifiedMediaItem Source & ID Namespace Isolation', () {
    test('separates local MediaStore ID and Immich server asset ID and never matches by filename alone', () {
      final now = DateTime(2026, 10, 20, 10, 0);
      final localOnlyAsset = LocalAsset(
        id: '10042',
        name: 'IMG_20261020.JPG',
        checksum: 'local_hash_aaa',
        type: AssetType.image,
        createdAt: now,
        updatedAt: now,
        width: 4000,
        height: 3000,
        isFavorite: false,
        isEdited: false,
        playbackStyle: AssetPlaybackStyle.image,
      );

      final serverOnlyAsset = RemoteAsset(
        id: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        name: 'IMG_20261020.JPG', // Same filename, different photo!
        checksum: 'server_hash_bbb',
        type: AssetType.image,
        createdAt: now,
        updatedAt: now,
        width: 4000,
        height: 3000,
        isFavorite: true,
        isEdited: false,
        ownerId: 'user-1',
        visibility: AssetVisibility.timeline,
      );

      final localItem = UnifiedMediaItem.fromBaseAsset(localOnlyAsset);
      final serverItem = UnifiedMediaItem.fromBaseAsset(serverOnlyAsset);

      expect(localItem.source, UnifiedMediaSource.local);
      expect(localItem.stableId, 'local:10042');
      expect(localItem.metadata.localId, '10042');
      expect(localItem.metadata.remoteId, isNull);

      expect(serverItem.source, UnifiedMediaSource.immich);
      expect(serverItem.stableId, 'immich:f47ac10b-58cc-4372-a567-0e02b2c3d479');
      expect(serverItem.metadata.remoteId, 'f47ac10b-58cc-4372-a567-0e02b2c3d479');
      expect(serverItem.metadata.localId, isNull);

      expect(localItem.stableId, isNot(equals(serverItem.stableId)));
      expect(localItem.refersToSameMedia(serverItem), isFalse);
    });

    test('categorizes local MediaStore folders into Camera, Screenshots, Downloads, Videos, and Other', () {
      LocalAlbum makeAlbum(String name) =>
          LocalAlbum(id: name, name: name, updatedAt: DateTime(2026), backupSelection: BackupSelection.none);

      expect(LocalMediaRepository.categorizeAlbum(makeAlbum('Camera')), LocalAlbumCategory.camera);
      expect(LocalMediaRepository.categorizeAlbum(makeAlbum('Screenshots')), LocalAlbumCategory.screenshots);
      expect(LocalMediaRepository.categorizeAlbum(makeAlbum('Download')), LocalAlbumCategory.downloads);
      expect(LocalMediaRepository.categorizeAlbum(makeAlbum('Movies')), LocalAlbumCategory.videos);
      expect(LocalMediaRepository.categorizeAlbum(makeAlbum('WeiXin')), LocalAlbumCategory.other);
    });
  });

  group('P0-2: AdvancedMediaFilter Composable Filtering', () {
    final captureDate = DateTime(2026, 8, 15, 14, 20);
    final sampleAsset = RemoteAsset(
      id: 'asset-uuid-1',
      name: 'IMG_0099.HEIC',
      checksum: 'chk-1',
      type: AssetType.image,
      createdAt: captureDate,
      updatedAt: captureDate,
      width: 4032,
      height: 3024,
      isFavorite: true,
      isEdited: false,
      ownerId: 'user-1',
      visibility: AssetVisibility.timeline,
    );

    final sampleExif = ExifInfo(
      fileSize: 8 * 1024 * 1024, // 8 MB
      width: 4032,
      height: 3024,
      dateTimeOriginal: captureDate,
      make: 'Xiaomi',
      model: 'M2102K1C',
      latitude: 39.9042,
      longitude: 116.4074,
    );

    test('matches when all combined filter conditions are satisfied', () {
      final filter = AdvancedMediaFilter(
        takenAfter: DateTime(2026, 8, 1),
        takenBefore: DateTime(2026, 8, 31),
        mediaType: AssetType.image,
        fileFormats: const {'heic', 'jpg'},
        minWidth: 3840,
        minHeight: 2160,
        minSizeBytes: 5 * 1024 * 1024,
        maxSizeBytes: 20 * 1024 * 1024,
        gpsFilter: TriStateFilter.yes,
        cameraMake: 'Xiaomi',
        cameraModel: 'M2102K1C',
        favoriteFilter: TriStateFilter.yes,
        sourceScope: MediaSourceScope.serverOnly,
      );

      expect(filter.isNotEmpty, isTrue);
      expect(filter.activeFilterCount, greaterThanOrEqualTo(9));
      expect(filter.matchesAsset(sampleAsset, exif: sampleExif), isTrue);
    });

    test('rejects when any single condition in the combination fails', () {
      const failByGps = AdvancedMediaFilter(gpsFilter: TriStateFilter.no);
      expect(failByGps.matchesAsset(sampleAsset, exif: sampleExif), isFalse);

      const failByFormat = AdvancedMediaFilter(fileFormats: {'png', 'svg'});
      expect(failByFormat.matchesAsset(sampleAsset, exif: sampleExif), isFalse);

      const failBySource = AdvancedMediaFilter(sourceScope: MediaSourceScope.localOnly);
      expect(failBySource.matchesAsset(sampleAsset, exif: sampleExif), isFalse);

      const failByCamera = AdvancedMediaFilter(cameraModel: 'Nikon Z9');
      expect(failByCamera.matchesAsset(sampleAsset, exif: sampleExif), isFalse);
    });

    test('clearAll resets filter to empty state', () {
      const filter = AdvancedMediaFilter(
        mediaType: AssetType.video,
        gpsFilter: TriStateFilter.yes,
        favoriteFilter: TriStateFilter.yes,
      );
      expect(filter.isEmpty, isFalse);
      final cleared = filter.clearAll();
      expect(cleared.isEmpty, isTrue);
      expect(cleared.activeFilterCount, 0);
    });
  });

  group('P2: Aves Layout, Sectioning, Pinch-Zoom (1-8 Columns), Sorting & Customization', () {
    test('clamps column count between 1 (full screen width) and 8, and serializes/deserializes settings', () {
      const base = AvesViewSettings();
      final oneCol = base.copyWith(
        tileLayout: AvesTileLayout.mosaic,
        sectionMode: AvesSectionMode.none,
        sortMode: AvesSortMode.bySize,
        isSortAscending: true,
        columnCount: 1,
        pinnedAlbumIds: {'album-1', 'album-2'},
      );
      expect(oneCol.columnCount, 1);

      final roundTrip = AvesViewSettings.fromJson(oneCol.toJson());
      expect(roundTrip.tileLayout, AvesTileLayout.mosaic);
      expect(roundTrip.sectionMode, AvesSectionMode.none);
      expect(roundTrip.sortMode, AvesSortMode.bySize);
      expect(roundTrip.isSortAscending, isTrue);
      expect(roundTrip.columnCount, 1);
      expect(roundTrip.pinnedAlbumIds, containsAll(['album-1', 'album-2']));

      final clampedHigh = base.copyWith(columnCount: 20);
      expect(clampedHigh.columnCount, 8);
      final clampedLow = base.copyWith(columnCount: 0);
      expect(clampedLow.columnCount, 1);
    });

    test('merges buckets seamlessly for GroupAssetsBy.none and GroupAssetsBy.month in FixedSegmentBuilder', () {
      final dailyBuckets = <Bucket>[
        TimeBucket(date: DateTime(2026, 10, 26), assetCount: 5),
        TimeBucket(date: DateTime(2026, 10, 25), assetCount: 7),
        TimeBucket(date: DateTime(2026, 9, 15), assetCount: 4),
      ];

      // 1. GroupAssetsBy.none ("不区分"): collapses all buckets into 1 continuous segment with 0 header
      final noneSegments = FixedSegmentBuilder(
        buckets: dailyBuckets,
        tileHeight: 100,
        columnCount: 4,
        groupBy: GroupAssetsBy.none,
      ).generate();
      expect(noneSegments.length, 1);
      expect(noneSegments.first.bucket.assetCount, 16);
      expect(noneSegments.first.headerExtent, 0.0);

      // 2. GroupAssetsBy.month ("按月份"): merges Oct 26 + Oct 25 into one October bucket (12 items) + Sept (4 items)
      final monthSegments = FixedSegmentBuilder(
        buckets: dailyBuckets,
        tileHeight: 100,
        columnCount: 4,
        groupBy: GroupAssetsBy.month,
      ).generate();
      expect(monthSegments.length, 2);
      expect(monthSegments[0].bucket.assetCount, 12);
      expect(monthSegments[1].bucket.assetCount, 4);
    });

    test('sorts assets by title, size (resolution), favorite rating, and duration', () {
      final a1 = LocalAsset(
        id: '1',
        name: 'B_Photo.jpg',
        checksum: 'c1',
        type: AssetType.image,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
        width: 1920,
        height: 1080,
        isFavorite: false,
        durationMs: 0,
        isEdited: false,
        playbackStyle: AssetPlaybackStyle.image,
      );
      final a2 = LocalAsset(
        id: '2',
        name: 'A_Video.mp4',
        checksum: 'c2',
        type: AssetType.video,
        createdAt: DateTime(2026, 10, 2),
        updatedAt: DateTime(2026, 10, 2),
        width: 3840,
        height: 2160,
        isFavorite: true,
        durationMs: 45000,
        isEdited: false,
        playbackStyle: AssetPlaybackStyle.video,
      );

      const byTitleAsc = AvesViewSettings(sortMode: AvesSortMode.byTitle, isSortAscending: true);
      expect(byTitleAsc.sortAssets([a1, a2]).first.id, '2');

      const bySizeDesc = AvesViewSettings(sortMode: AvesSortMode.bySize, isSortAscending: false);
      expect(bySizeDesc.sortAssets([a1, a2]).first.id, '2');

      const byFavDesc = AvesViewSettings(sortMode: AvesSortMode.byRating, isSortAscending: false);
      expect(byFavDesc.sortAssets([a1, a2]).first.id, '2');
    });
  });

  group('相册内就地筛选（AvesHeaderScope.album）', () {
    RemoteAsset makeAsset(String id, String name, {bool favorite = false, AssetType type = AssetType.image}) {
      final t = DateTime(2026, 10, 1);
      return RemoteAsset(
        id: id,
        name: name,
        checksum: 'chk-$id',
        type: type,
        createdAt: t,
        updatedAt: t,
        width: 4000,
        height: 3000,
        isFavorite: favorite,
        isEdited: false,
        ownerId: 'user-1',
        visibility: AssetVisibility.timeline,
      );
    }

    test('按媒体类型与格式过滤相册资产', () {
      final assets = <BaseAsset>[
        makeAsset('1', 'IMG_0001.JPG'),
        makeAsset('2', 'IMG_0002.HEIC'),
        makeAsset('3', 'VID_0003.MP4', type: AssetType.video),
      ];

      expect(filterAlbumAssets(assets, AdvancedMediaFilter.empty).length, 3);

      final videoOnly = filterAlbumAssets(assets, const AdvancedMediaFilter(mediaType: AssetType.video));
      expect(videoOnly.map((a) => a.id).toList(), ['3']);

      final jpgOnly = filterAlbumAssets(assets, const AdvancedMediaFilter(fileFormats: {'jpg'}));
      expect(jpgOnly.map((a) => a.id).toList(), ['1']);
    });

    test('按收藏与关键词过滤相册资产', () {
      final assets = <BaseAsset>[makeAsset('1', 'IMG_0001.JPG', favorite: true), makeAsset('2', 'screenshot_0002.png')];

      final favorites = filterAlbumAssets(assets, const AdvancedMediaFilter(favoriteFilter: TriStateFilter.yes));
      expect(favorites.map((a) => a.id).toList(), ['1']);

      final keyword = filterAlbumAssets(assets, const AdvancedMediaFilter(textQuery: 'screenshot'));
      expect(keyword.map((a) => a.id).toList(), ['2']);
    });
  });

  group('Aves 式滚动外壳：上滑全屏 / 下滑出底栏', () {
    const dockHeight = 64.0;
    ScrollMetrics metricsAt(double pixels, {double max = 8000}) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: max,
      pixels: pixels,
      viewportDimension: 800,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 3,
    );

    test('上滑 64dp 后底栏完全滑出，下滑 64dp 后完全滑回', () {
      final notifier = ValueNotifier<double>(0);
      final tracker = AvesChromeScrollTracker(notifier);
      addTearDown(notifier.dispose);

      var pixels = 1000.0;
      tracker.onScroll(metricsAt(pixels), childHeight: dockHeight); // 建立基线
      expect(notifier.value, 0, reason: '第一帧只记基线，不应移动');

      // 手指上滑（内容上移，pixels 增大）→ 底栏逐步滑出
      for (var i = 0; i < 4; i++) {
        pixels += 16;
        tracker.onScroll(metricsAt(pixels), childHeight: dockHeight);
      }
      expect(notifier.value, closeTo(1, 0.001), reason: '累计上滑一个底栏高度后应完全隐藏');

      // 手指下滑（pixels 减小）→ 底栏原路滑回
      for (var i = 0; i < 4; i++) {
        pixels -= 16;
        tracker.onScroll(metricsAt(pixels), childHeight: dockHeight);
      }
      expect(notifier.value, closeTo(0, 0.001), reason: '下滑同样距离后应完全露出');
    });

    test('接近列表底部时最多收起 extentAfter/高度，最后一排不被遮挡', () {
      final notifier = ValueNotifier<double>(0);
      final tracker = AvesChromeScrollTracker(notifier);
      addTearDown(notifier.dispose);

      // 先在列表中部把底栏收满
      tracker.onScroll(metricsAt(400, max: 2000), childHeight: dockHeight);
      tracker.onScroll(metricsAt(500, max: 2000), childHeight: dockHeight);
      expect(notifier.value, 1);

      // 再接近底部：after 只剩 60 < 64，此时上滑应被压到 60/64，最后一行仍能完整露出
      tracker.reset();
      tracker.onScroll(metricsAt(1900, max: 2000), childHeight: dockHeight);
      tracker.onScroll(metricsAt(1940, max: 2000), childHeight: dockHeight);
      expect(notifier.value, closeTo(60 / 64, 0.001));
    });

    test('进度条往上拖会收满底栏，往回拖不会让底栏闪回', () {
      final notifier = ValueNotifier<double>(0);
      final tracker = AvesChromeScrollTracker(notifier);
      addTearDown(notifier.dispose);

      // 往回跳（内容下移）：底栏保持隐藏，避免拖动滚动条时底栏乱闪
      tracker.onScroll(metricsAt(4000, max: 8000), childHeight: dockHeight);
      tracker.onScroll(metricsAt(500, max: 8000), childHeight: dockHeight);
      expect(notifier.value, 0);

      // 往上跳（内容上移）：按两倍高度限幅计入，一帧收满
      tracker.onScroll(metricsAt(6000, max: 8000), childHeight: dockHeight);
      expect(notifier.value, 1);
    });

    test('reveal 立即恢复底栏', () {
      final notifier = ValueNotifier<double>(0.8);
      final tracker = AvesChromeScrollTracker(notifier);
      addTearDown(notifier.dispose);

      tracker.reveal();
      expect(notifier.value, 0);
    });
  });
}
