import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';

/// 抄自 Aves `lib/widgets/common/fx/blurred.dart` 的 `BlurredRRect`。
///
/// Aves 全应用只用一档模糊：`ImageFilter.blur(sigmaX: 4, sigmaY: 4)` —— 非常克制，
/// 目的是「让背后的照片透上来一点点」，而不是做成一块毛玻璃板。
///
/// 两个细节保持一致：
/// 1. 关闭磨砂时**不改变组件树**，只把滤镜换成恒等矩阵
///    （源码注释：`do not modify tree when disabling filter`，否则子树会被重建，
///    滚动位置和动画状态都会丢）；
/// 2. 磨砂由设置项 [AvesViewSettings.enableBlurEffect] 总控（Aves 也有同名开关），
///    低端机上关掉即退回纯色玻璃，不影响布局。
class AvesBlurredRRect extends ConsumerWidget {
  /// Aves 的固定模糊半径
  static const double sigma = 4;

  static final ui.ImageFilter _identity = ui.ImageFilter.matrix(Matrix4.identity().storage);

  final bool enabled;
  final BorderRadius borderRadius;
  final Widget child;

  const AvesBlurredRRect({super.key, this.enabled = true, required this.borderRadius, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blurAllowed = ref.watch(avesSettingsProvider.select((s) => s.enableBlurEffect));
    final blurring = enabled && blurAllowed;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: blurring ? ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma) : _identity,
        child: child,
      ),
    );
  }
}
