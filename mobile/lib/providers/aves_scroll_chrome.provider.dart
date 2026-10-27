import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Aves 式「滚动驱动的界面外壳显隐」。
///
/// Aves 的 `FloatingNavBar`（`lib/widgets/navigation/nav_bar/floating.dart`）做法是：
/// 监听主 `ScrollController`，按 `delta / childHeight` **跟手驱动** `SlideTransition`，
/// 而不是用阈值判断。上滑（内容上移，delta > 0）时底栏逐渐滑出屏幕，
/// 下滑（delta < 0）时逐渐滑回。
///
/// 这里把这个状态抽成全局 notifier，方便时间线以外的悬浮元素（底栏、FAB）共用同一进度。
///
/// 值域：`0.0` = 完全展开（可见），`1.0` = 完全收起（全屏沉浸）。
final avesChromeHideProvider = Provider<ValueNotifier<double>>((ref) {
  final notifier = ValueNotifier<double>(0);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// 把滚动偏移量换算成底部悬浮栏的收起进度。
///
/// 逻辑逐行对齐 Aves `_FloatingNavBarState._onScrollChanged`：
/// 1. `delta > 0` 表示手指上滑（内容向上走），底栏向下滑出；
/// 2. 接近列表底部且仍在上滑时，最多只收起 `extentAfter / childHeight`，
///    保证最后一排照片不会被底栏永久遮住；
/// 3. 其它情况线性累加，clamp 到 `[0, 1]`。
class AvesChromeScrollTracker {
  AvesChromeScrollTracker(this.notifier);

  final ValueNotifier<double> notifier;

  /// 单帧超过「两倍底栏高度」的位移视为非连续滚动（进度条拖动、滚动锚点恢复、
  /// 切列数重排等），见 [onScroll] 的处理策略。
  static const double _jumpFactor = 2;

  double? _lastPixels;

  /// 重置基线（切 tab、切布局、回到前台时调用，避免跨视图算出差值）。
  void reset() {
    _lastPixels = null;
  }

  /// 主滚动视图每帧调用。
  void onScroll(ScrollMetrics metrics, {required double childHeight}) {
    final pixels = metrics.pixels;
    final last = _lastPixels;
    _lastPixels = pixels;

    if (last == null || childHeight <= 0) {
      return;
    }

    final rawDelta = pixels - last;
    if (rawDelta == 0) {
      return;
    }

    // 大幅跳转不能直接丢弃：快速 fling 时单帧位移也可能很大，
    // 真丢掉会让底栏在惯性滚动中卡住不动。这里改成「限幅 + 单向」：
    // - 正向跳转（内容上移）按两倍高度计入 → 一帧收满；
    // - 反向跳转（拖动滚动条往回 / 锚点恢复）直接忽略，避免底栏突然闪回。
    // 这与 Aves `FloatingNavBar` 里 `_isDragging` 时只允许隐藏的规则等价。
    final jumpLimit = childHeight * _jumpFactor;
    final isJump = rawDelta.abs() > jumpLimit;
    if (isJump && rawDelta < 0) {
      return;
    }
    final delta = isJump ? jumpLimit : rawDelta;

    final after = metrics.extentAfter;
    double next;
    if (after < childHeight && delta > 0) {
      final capped = after / childHeight;
      next = notifier.value < capped ? notifier.value : capped;
    } else {
      next = notifier.value + delta / childHeight;
    }

    final clamped = next.clamp(0.0, 1.0);
    if (clamped != notifier.value) {
      notifier.value = clamped;
    }
  }

  /// 强制展示（回到顶部、切换筛选、退出多选等场景）。
  void reveal() {
    notifier.value = 0;
  }
}
