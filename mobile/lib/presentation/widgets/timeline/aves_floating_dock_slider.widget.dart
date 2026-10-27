import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/aves_scroll_chrome.provider.dart';

/// 让底部悬浮栏跟随滚动方向滑出 / 滑回。
///
/// 直接对标 Aves `lib/widgets/navigation/nav_bar/floating.dart` 里的
/// `FloatingNavBar`：`SlideTransition` + 由滚动增量驱动的进度值，
/// 上滑（内容上移）底栏滑出屏幕 → 全屏浏览；下滑底栏原路滑回。
///
/// 与 Aves 的差别只有一处：Aves 的进度存在组件内部的 `AnimationController`，
/// 这里存在 [avesChromeHideProvider] 里，方便同屏的其它悬浮元素（FAB、多选按钮）共用。
class AvesFloatingDockSlider extends ConsumerWidget {
  /// 完整滑出屏幕所需的位移量（底栏内容高度 + 外边距 + 底部安全区）。
  final double height;

  final Widget child;

  const AvesFloatingDockSlider({super.key, required this.height, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideNotifier = ref.watch(avesChromeHideProvider);

    return ValueListenableBuilder<double>(
      valueListenable: hideNotifier,
      child: child,
      builder: (context, hide, child) {
        if (hide <= 0.001) {
          return child!;
        }

        return IgnorePointer(
          // 滑出大半后不再接收点击，避免误触屏幕外的按钮
          ignoring: hide > 0.6,
          child: Transform.translate(offset: Offset(0, height * hide), child: child),
        );
      },
    );
  }
}
