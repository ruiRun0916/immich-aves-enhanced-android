import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:path/path.dart' as p;

/// 相册内筛选条件。
///
/// 与主界面 `advancedMediaFilterProvider` 完全隔离：
/// - 主界面的高级筛选会跳到独立的「筛选结果页」
/// - 这里的筛选是**就地过滤当前相册**，改完立刻重建相册时间线
/// - 用 `family` 按相册 ID 分开存，互不干扰；`autoDispose` 保证退出相册后自动清空
final albumMediaFilterProvider = StateProvider.autoDispose
    .family<AdvancedMediaFilter, String>((ref, albumId) => AdvancedMediaFilter.empty);

/// 相册全部资产（用于相册内就地筛选）。
///
/// 只在用户真正启用筛选时才会被拉取一次，之后在内存里反复过滤，
/// 不会为了筛选去逐个下载原图或 EXIF。
final albumAssetsProvider = FutureProvider.autoDispose.family<List<BaseAsset>, String>((ref, albumId) async {
  final assets = await ref.read(remoteAlbumProvider.notifier).getAssets(albumId);
  return assets;
});

/// 按相册内筛选条件过滤资产。
///
/// 只用到 `BaseAsset` 一定能提供的字段（类型 / 文件名格式 / 拍摄或创建时间 / 收藏 / 名称），
/// 因此不需要额外拉 EXIF，也不会为了筛选去下载原图。
List<BaseAsset> filterAlbumAssets(List<BaseAsset> assets, AdvancedMediaFilter filter) {
  if (filter.isEmpty) {
    return assets;
  }
  return assets.where((asset) => filter.matchesAsset(asset)).toList(growable: false);
}

/// 给筛选面板展示用的「该相册里实际存在的格式」统计，避免列出一堆没结果的选项。
Set<String> collectAlbumFormats(List<BaseAsset> assets) {
  return assets
      .map((asset) => p.extension(asset.name).replaceFirst('.', '').toLowerCase())
      .where((ext) => ext.isNotEmpty)
      .toSet();
}
