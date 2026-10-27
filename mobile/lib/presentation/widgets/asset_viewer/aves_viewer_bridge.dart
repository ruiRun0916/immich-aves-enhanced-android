import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';

/// 当前查看器的实时缩放倍率（1.0 = 刚好铺满屏幕）。
///
/// Aves 的「显示缩放级别」要的是**真实倍率**，而 Immich 原来只暴露一个
/// `isZoomed` 布尔量，所以这里由 `AssetPage` 把 `PhotoViewController` 的
/// 连续 scale 值推上来，叠加层直接监听。
final avesViewerZoomProvider = Provider<ValueNotifier<double>>((ref) {
  final notifier = ValueNotifier<double>(1);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// 叠加层胶片条 → 查看器翻页的桥。
///
/// 胶片条在 `Stack` 的顶层，翻页控制器在 `_AssetViewerState` 里，两者没有
/// 父子关系；用一个静态回调比在 provider 里塞一个 PageController 更不容易泄漏。
class AvesViewerJumpBus {
  AvesViewerJumpBus._();

  static void Function(int index)? _handler;

  static void register(void Function(int index)? handler) => _handler = handler;

  static bool get available => _handler != null;

  static void jumpTo(int index) => _handler?.call(index);
}

/// 叠加层底部胶片条的数据：以当前页为中心取一小段。
///
/// 不取全量是故意的——胶片条只需要前后十几张的上下文，
/// 拉全部素材在几万张的库里会直接把内存吃穿。
final avesFilmstripProvider = FutureProvider.autoDispose.family<({int start, List<BaseAsset> assets}), int>((
  ref,
  index,
) async {
  final service = ref.watch(timelineServiceProvider);
  final total = service.totalAssets;
  if (total <= 0) {
    return (start: 0, assets: const <BaseAsset>[]);
  }

  const window = 25;
  const half = window ~/ 2;
  final start = (index - half).clamp(0, math.max(0, total - window)).toInt();
  final count = math.min(window, total - start);
  if (count <= 0) {
    return (start: 0, assets: const <BaseAsset>[]);
  }

  final assets = await service.loadAssets(start, count);
  return (start: start, assets: assets);
});
