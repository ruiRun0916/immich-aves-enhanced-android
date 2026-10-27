import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/aves_media_metadata.model.dart';
import 'package:immich_mobile/infrastructure/repositories/immich_asset_aves.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/local_media_aves.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/unified_media_aves.repository.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';

class AdvancedMediaFilterNotifier extends StateNotifier<AdvancedMediaFilter> {
  AdvancedMediaFilterNotifier() : super(AdvancedMediaFilter.empty);

  void update(AdvancedMediaFilter filter) {
    state = filter;
  }

  void clearAll() {
    state = AdvancedMediaFilter.empty;
  }
}

/// Session-persistent provider for P0-2 Advanced Photo Filtering.
final advancedMediaFilterProvider = StateNotifierProvider<AdvancedMediaFilterNotifier, AdvancedMediaFilter>(
  (ref) => AdvancedMediaFilterNotifier(),
);

class AdvancedFilteredAssetsState {
  final List<BaseAsset> assets;
  final List<UnifiedMediaItem> unifiedItems;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;

  const AdvancedFilteredAssetsState({
    this.assets = const [],
    this.unifiedItems = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.currentPage = 0,
    this.error,
  });

  AdvancedFilteredAssetsState copyWith({
    List<BaseAsset>? assets,
    List<UnifiedMediaItem>? unifiedItems,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
  }) {
    return AdvancedFilteredAssetsState(
      assets: assets ?? this.assets,
      unifiedItems: unifiedItems ?? this.unifiedItems,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
    );
  }
}

class AdvancedFilteredAssetsNotifier extends StateNotifier<AdvancedFilteredAssetsState> {
  final Ref _ref;
  static const int _pageSize = 200;

  AdvancedFilteredAssetsNotifier(this._ref) : super(const AdvancedFilteredAssetsState());

  Future<void> applyFilter(AdvancedMediaFilter filter) async {
    _ref.read(advancedMediaFilterProvider.notifier).update(filter);
    if (filter.isEmpty) {
      state = const AdvancedFilteredAssetsState();
      return;
    }

    state = state.copyWith(isLoading: true, currentPage: 1, error: null);
    try {
      final unifiedRepo = _ref.read(unifiedMediaAvesRepositoryProvider);
      final result = await unifiedRepo.filterUnifiedAssets(
        filter,
        page: 1,
        pageSize: _pageSize,
      );
      final items = result.assets.map(UnifiedMediaItem.fromBaseAsset).toList(growable: false);
      state = AdvancedFilteredAssetsState(
        assets: result.assets,
        unifiedItems: items,
        isLoading: false,
        hasMore: result.nextPage != null,
        currentPage: 1,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadNextPage() async {
    final filter = _ref.read(advancedMediaFilterProvider);
    if (filter.isEmpty || state.isLoading || !state.hasMore) {
      return;
    }

    final nextPage = state.currentPage + 1;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final unifiedRepo = _ref.read(unifiedMediaAvesRepositoryProvider);
      final result = await unifiedRepo.filterUnifiedAssets(
        filter,
        page: nextPage,
        pageSize: _pageSize,
      );

      final nextItems = result.assets.map(UnifiedMediaItem.fromBaseAsset).toList();
      if (nextItems.isEmpty) {
        state = state.copyWith(isLoading: false, hasMore: false);
        return;
      }

      final existingKeys = state.unifiedItems.map((e) => e.stableId).toSet();
      final dedupedNext = nextItems.where((e) => existingKeys.add(e.stableId)).toList();

      final combinedItems = [...state.unifiedItems, ...dedupedNext];
      final combinedAssets = combinedItems.map((e) => e.asset).toList(growable: false);

      state = state.copyWith(
        assets: combinedAssets,
        unifiedItems: combinedItems,
        isLoading: false,
        hasMore: result.nextPage != null && dedupedNext.isNotEmpty,
        currentPage: nextPage,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clear() {
    _ref.read(advancedMediaFilterProvider.notifier).clearAll();
    state = const AdvancedFilteredAssetsState();
  }
}

final advancedFilteredAssetsProvider =
    StateNotifierProvider<AdvancedFilteredAssetsNotifier, AdvancedFilteredAssetsState>(
      (ref) => AdvancedFilteredAssetsNotifier(ref),
    );

final knownCameraModelsProvider = FutureProvider.autoDispose<List<({String? make, String model})>>((ref) async {
  final repo = ref.watch(immichAssetAvesRepositoryProvider);
  return repo.getKnownCameraModels();
});

final filterableAlbumsProvider = FutureProvider.autoDispose<({List<RemoteAlbum> remote, List<LocalAlbum> local})>((
  ref,
) async {
  final remoteState = ref.watch(remoteAlbumProvider);
  final local = await ref.watch(localAlbumProvider.future).catchError((_) => <LocalAlbum>[]);
  return (remote: remoteState.albums, local: local);
});

final localMediaPermissionStatusProvider = FutureProvider.autoDispose<MediaPermissionStatus>((ref) async {
  final localRepo = ref.watch(localMediaAvesRepositoryProvider);
  return localRepo.checkPermissionStatus();
});
