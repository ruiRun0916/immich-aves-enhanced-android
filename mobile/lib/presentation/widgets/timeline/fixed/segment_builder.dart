import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/presentation/widgets/timeline/fixed/segment.model.dart';
import 'package:immich_mobile/presentation/widgets/timeline/segment.model.dart';
import 'package:immich_mobile/presentation/widgets/timeline/segment_builder.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';

class FixedSegmentBuilder extends SegmentBuilder {
  final double tileHeight;
  final int columnCount;
  final AvesTileLayout tileLayout;
  final double maxWidth;

  const FixedSegmentBuilder({
    required super.buckets,
    required this.tileHeight,
    required this.columnCount,
    this.tileLayout = AvesTileLayout.mosaic,
    this.maxWidth = 0,
    super.spacing,
    super.groupBy,
  });

  List<Bucket> _normalizeBuckets() {
    if (buckets.isEmpty) {
      return const [];
    }

    // Continuous stream without any section breaks ("不区分")
    if (groupBy == GroupAssetsBy.none) {
      final totalAssets = buckets.fold<int>(0, (sum, b) => sum + b.assetCount);
      if (totalAssets <= 0) {
        return const [];
      }
      return [Bucket(assetCount: totalAssets)];
    }

    // Merge consecutive daily buckets of the same month into a single monthly bucket ("按月份")
    if (groupBy == GroupAssetsBy.month) {
      final merged = <Bucket>[];
      DateTime? currentMonth;
      int currentCount = 0;

      for (final b in buckets) {
        if (b is TimeBucket) {
          final monthDate = DateTime(b.date.year, b.date.month);
          if (currentMonth == null) {
            currentMonth = monthDate;
            currentCount = b.assetCount;
          } else if (currentMonth.year == monthDate.year && currentMonth.month == monthDate.month) {
            currentCount += b.assetCount;
          } else {
            merged.add(TimeBucket(date: currentMonth, assetCount: currentCount));
            currentMonth = monthDate;
            currentCount = b.assetCount;
          }
        } else {
          if (currentMonth != null && currentCount > 0) {
            merged.add(TimeBucket(date: currentMonth, assetCount: currentCount));
            currentMonth = null;
            currentCount = 0;
          }
          merged.add(b);
        }
      }
      if (currentMonth != null && currentCount > 0) {
        merged.add(TimeBucket(date: currentMonth, assetCount: currentCount));
      }
      return merged;
    }

    return buckets;
  }

  List<Segment> generate() {
    final effectiveBuckets = _normalizeBuckets();
    final segments = <Segment>[];
    int firstIndex = 0;
    double startOffset = 0;
    int assetIndex = 0;
    DateTime? previousDate;

    final effectiveColumns = tileLayout == AvesTileLayout.list ? 1 : columnCount;

    for (int i = 0; i < effectiveBuckets.length; i++) {
      final bucket = effectiveBuckets[i];

      final assetCount = bucket.assetCount;
      if (assetCount <= 0) {
        continue;
      }

      final numberOfRows = (assetCount / effectiveColumns).ceil();
      final segmentCount = numberOfRows + 1;

      final segmentFirstIndex = firstIndex;
      firstIndex += segmentCount;
      final segmentLastIndex = firstIndex - 1;

      final timelineHeader = switch (groupBy) {
        GroupAssetsBy.month => bucket is TimeBucket ? HeaderType.month : HeaderType.none,
        GroupAssetsBy.day || GroupAssetsBy.auto =>
          bucket is TimeBucket
              ? (bucket.date.month != previousDate?.month || bucket.date.year != previousDate?.year
                    ? HeaderType.monthAndDay
                    : HeaderType.day)
              : HeaderType.none,
        GroupAssetsBy.none => HeaderType.none,
      };
      final headerExtent = SegmentBuilder.headerExtent(timelineHeader);

      final segmentStartOffset = startOffset;
      startOffset += headerExtent + (tileHeight * numberOfRows) + spacing * (numberOfRows - 1);
      final segmentEndOffset = startOffset;

      segments.add(
        FixedSegment(
          firstIndex: segmentFirstIndex,
          lastIndex: segmentLastIndex,
          startOffset: segmentStartOffset,
          endOffset: segmentEndOffset,
          firstAssetIndex: assetIndex,
          bucket: bucket,
          tileHeight: tileHeight,
          columnCount: effectiveColumns,
          tileLayout: tileLayout,
          maxWidth: maxWidth,
          headerExtent: headerExtent,
          spacing: spacing,
          header: timelineHeader,
        ),
      );

      assetIndex += assetCount;
      if (bucket is TimeBucket) {
        previousDate = bucket.date;
      }
    }
    return segments;
  }
}
