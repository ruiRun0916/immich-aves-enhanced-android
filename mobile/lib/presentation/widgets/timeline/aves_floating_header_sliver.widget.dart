import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

/// 把一条顶栏（`AvesTimelineHeaderBottom` 之类）包成**浮动** sliver。
///
/// 抄自 Aves 的做法：`SliverPersistentHeader(floating: true)` + 固定 extent，
/// 再叠加 `snapConfiguration` 让「反向滑动 → 松手 → 整条一次性弹出」。
///
/// 注意：`snapConfiguration` 生效的前提是 delegate 能提供 `vsync`
/// （`RenderSliverFloatingPersistentHeader._updateAnimation` 里断言 `vsync != null`，
/// release 下 `vsync!` 会直接抛异常），所以这里必须是 StatefulWidget + TickerProvider。
///
/// 相册页的大标题 `SliverAppBar` 是 `pinned: true` 的，本 sliver 放在它**后面**：
/// 展开时紧贴大标题下方，收起后被钉住的 toolbar 顶住、向下悬浮露出 ——
/// 不需要额外处理状态栏高度。
class AvesFloatingHeaderSliver extends StatefulWidget {
  final Widget child;
  final Color? backgroundColor;
  final bool showBottomDivider;

  const AvesFloatingHeaderSliver({
    super.key,
    required this.child,
    this.backgroundColor,
    this.showBottomDivider = true,
  });

  @override
  State<AvesFloatingHeaderSliver> createState() => _AvesFloatingHeaderSliverState();
}

class _AvesFloatingHeaderSliverState extends State<AvesFloatingHeaderSliver>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final preferredHeight = child is PreferredSizeWidget ? child.preferredSize.height : 96.0;

    return SliverPersistentHeader(
      floating: true,
      pinned: false,
      delegate: _AvesFloatingHeaderDelegate(
        tickerProvider: this,
        height: preferredHeight,
        backgroundColor: widget.backgroundColor ?? context.colorScheme.surface,
        showBottomDivider: widget.showBottomDivider,
        child: child,
      ),
    );
  }
}

class _AvesFloatingHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TickerProvider tickerProvider;
  final double height;
  final Color backgroundColor;
  final bool showBottomDivider;
  final Widget child;

  _AvesFloatingHeaderDelegate({
    required this.tickerProvider,
    required this.height,
    required this.backgroundColor,
    required this.showBottomDivider,
    required this.child,
  });

  @override
  TickerProvider? get vsync => tickerProvider;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  FloatingHeaderSnapConfiguration get snapConfiguration =>
      FloatingHeaderSnapConfiguration(curve: Curves.easeOut, duration: const Duration(milliseconds: 200));

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: showBottomDivider
            ? Border(bottom: BorderSide(color: context.colorScheme.outlineVariant.withValues(alpha: 0.4)))
            : null,
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _AvesFloatingHeaderDelegate oldDelegate) {
    return oldDelegate.height != height ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.showBottomDivider != showBottomDivider ||
        oldDelegate.child != child;
  }
}
