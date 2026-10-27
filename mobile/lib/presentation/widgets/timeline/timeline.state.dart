import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/presentation/widgets/timeline/constants.dart';
import 'package:immich_mobile/presentation/widgets/timeline/fixed/segment_builder.dart';
import 'package:immich_mobile/presentation/widgets/timeline/segment.model.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';

part 'timeline.state.freezed.dart';

@freezed
abstract class TimelineArgs with _$TimelineArgs {
  const factory TimelineArgs({
    required double maxWidth,
    required double maxHeight,
    @Default(kTimelineSpacing) double spacing,
    @Default(kTimelineColumnCount) int columnCount,
    @Default(false) bool showStorageIndicator,
    @Default(false) bool withStack,
    GroupAssetsBy? groupBy,
  }) = _TimelineArgs;
}

class TimelineState {
  final bool isScrolling;

  /// Indicates whether the timeline is scrolling beyond some configured "high" speed,
  /// such as when programmatically scrolling to the top or a really fast user fling
  final bool recommendDeferredLoading;

  const TimelineState({this.isScrolling = false, this.recommendDeferredLoading = false});

  bool get isInteracting => isScrolling || recommendDeferredLoading;

  @override
  bool operator ==(covariant TimelineState other) {
    return isScrolling == other.isScrolling && recommendDeferredLoading == other.recommendDeferredLoading;
  }

  @override
  int get hashCode => isScrolling.hashCode ^ recommendDeferredLoading.hashCode;

  TimelineState copyWith({bool? isScrolling, bool? recommendDeferredLoading}) {
    return TimelineState(
      isScrolling: isScrolling ?? this.isScrolling,
      recommendDeferredLoading: recommendDeferredLoading ?? this.recommendDeferredLoading,
    );
  }
}

class TimelineStateNotifier extends Notifier<TimelineState> {
  void setScrolling(bool isScrolling) {
    state = state.copyWith(isScrolling: isScrolling);
  }

  void setRecommendDeferredLoading(bool recommendDeferredLoading) {
    state = state.copyWith(recommendDeferredLoading: recommendDeferredLoading);
  }

  @override
  TimelineState build() => const TimelineState(isScrolling: false, recommendDeferredLoading: false);
}

// This provider watches the buckets from the timeline service & args and serves the segments.
// It should be used only after the timeline service and timeline args provider is overridden
final timelineSegmentProvider = StreamProvider.autoDispose<List<Segment>>((ref) async* {
  // maxHeight is left out on purpose, a height-only change must not restart the bucket stream
  final (maxWidth, argsColumnCount, spacing, groupByArg) = ref.watch(
    timelineArgsProvider.select((args) => (args.maxWidth, args.columnCount, args.spacing, args.groupBy)),
  );
  final (tileLayout, sectionMode, listRowExtent, avesColumns) = ref.watch(
    avesSettingsProvider.select((s) => (s.tileLayout, s.sectionMode, s.listRowExtent, s.columnCount)),
  );

  final effectiveColumnCount = tileLayout == AvesTileLayout.list
      ? 1
      : (avesColumns > 0 ? avesColumns : argsColumnCount).clamp(1, 8);

  final availableTileWidth = maxWidth - (spacing * (effectiveColumnCount - 1));
  final baseTileExtent = math.max(40.0, availableTileWidth) / effectiveColumnCount;

  final double tileExtent;
  if (tileLayout == AvesTileLayout.list) {
    tileExtent = listRowExtent;
  } else if (tileLayout == AvesTileLayout.mosaic && effectiveColumnCount == 1) {
    // Full screen width single-photo feed (4:3 natural aspect height)
    tileExtent = baseTileExtent * 0.72;
  } else {
    tileExtent = baseTileExtent;
  }

  final groupBy = tileLayout == AvesTileLayout.calendar
      ? GroupAssetsBy.day
      : (groupByArg ?? sectionMode.toTimelineGroupBy);

  final timelineService = ref.watch(timelineServiceProvider);
  yield* timelineService.watchBuckets().map((buckets) {
    return FixedSegmentBuilder(
      buckets: buckets,
      tileHeight: tileExtent,
      columnCount: effectiveColumnCount,
      tileLayout: tileLayout,
      maxWidth: maxWidth,
      spacing: spacing,
      groupBy: groupBy,
    ).generate();
  });
}, dependencies: [timelineServiceProvider, timelineArgsProvider]);

final timelineStateProvider = NotifierProvider<TimelineStateNotifier, TimelineState>(TimelineStateNotifier.new);
