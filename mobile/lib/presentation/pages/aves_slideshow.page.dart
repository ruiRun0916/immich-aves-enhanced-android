import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/presentation/pages/aves_slideshow_settings.page.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/video_viewer.widget.dart';
import 'package:immich_mobile/presentation/widgets/images/full_image.widget.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/providers/aves_slideshow.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:intl/intl.dart';

/// 从当前时间线取一批素材直接开播。
///
/// 上限 500 张：幻灯片是「随手放一遍」，把几万张全拉进内存只会在低端机上直接 OOM。
/// 想从某一张开始播的话，调用方自己传 `startIndex`。
Future<void> openAvesSlideshowFromTimeline(
  BuildContext context,
  WidgetRef ref, {
  String title = '幻灯片',
  int startIndex = 0,
}) async {
  final service = ref.read(timelineServiceProvider);
  final total = service.totalAssets;
  if (total <= 0) {
    return;
  }

  const maxCount = 500;
  final count = math.min(total, maxCount);
  final assets = await service.loadAssets(0, count);
  if (!context.mounted || assets.isEmpty) {
    return;
  }

  await openAvesSlideshow(
    context,
    assets: assets,
    initialIndex: startIndex.clamp(0, assets.length - 1),
    title: title,
  );
}

/// 打开 Aves 式幻灯片。
///
/// 传进来的 `assets` 就是这次播放的全部素材（调用方负责从时间线/相册取列表），
/// 幻灯片本身不查库，避免在各处重复写分页逻辑。
Future<void> openAvesSlideshow(
  BuildContext context, {
  required List<BaseAsset> assets,
  int initialIndex = 0,
  String title = '幻灯片',
}) async {
  if (assets.isEmpty) {
    return;
  }
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => AvesSlideshowPage(assets: assets, initialIndex: initialIndex, title: title),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Aves `SlideshowScreen` 的等价物：全屏黑底、按间隔自动切图、六种过渡、Ken Burns 推镜。
class AvesSlideshowPage extends ConsumerStatefulWidget {
  final List<BaseAsset> assets;
  final int initialIndex;
  final String title;

  const AvesSlideshowPage({
    super.key,
    required this.assets,
    this.initialIndex = 0,
    this.title = '幻灯片',
  });

  @override
  ConsumerState<AvesSlideshowPage> createState() => _AvesSlideshowPageState();
}

class _AvesSlideshowPageState extends ConsumerState<AvesSlideshowPage> {
  /// 播放顺序（存的是 [widget.assets] 的下标）。开启随机播放时这里会被打乱。
  late List<int> _order;
  late int _cursor;

  Timer? _timer;
  bool _paused = false;
  bool _chromeVisible = true;
  int _direction = 1;
  final math.Random _random = math.Random();

  /// 当前这张要用的过渡方式（「随机」模式每张重新抽签）。
  late AvesSlideshowTransition _resolvedTransition;

  BaseAsset get _current => widget.assets[_order[_cursor]];

  @override
  void initState() {
    super.initState();

    // 竖屏沉浸：幻灯片是「看照片」，不是「操作 App」，把系统栏收掉。
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));

    _buildOrder();

    final settings = ref.read(avesSlideshowProvider);
    _resolvedTransition = settings.transition.resolve(_random);
    _scheduleNext();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _buildOrder() {
    final count = widget.assets.length;
    final start = widget.initialIndex.clamp(0, math.max(0, count - 1)).toInt();
    final rest = List<int>.generate(count, (i) => i)..remove(start);

    if (ref.read(avesSlideshowProvider).shuffle) {
      rest.shuffle(_random);
    } else {
      // 不随机时按原顺序循环：从起点往后接，再接起点之前的。
      rest.sort((a, b) => a.compareTo(b));
      final tail = rest.where((i) => i > start).toList();
      final head = rest.where((i) => i < start).toList();
      rest
        ..clear()
        ..addAll(tail)
        ..addAll(head);
    }

    _order = [start, ...rest];
    _cursor = 0;
  }

  /// Aves 的节奏是「一张停留 N 秒 → 自动下一张」，每次切图都重排一次计时器，
  /// 这样手动翻页也不会被上一张的残留计时打断。
  void _scheduleNext() {
    _timer?.cancel();
    if (_paused) {
      return;
    }
    _timer = Timer(ref.read(avesSlideshowProvider).interval, _advance);
  }

  void _advance() {
    if (!mounted) {
      return;
    }
    final settings = ref.read(avesSlideshowProvider);
    if (_cursor >= _order.length - 1) {
      if (!settings.repeat) {
        setState(() => _paused = true);
        return;
      }
      _goTo(0, direction: 1);
      return;
    }
    _goTo(_cursor + 1, direction: 1);
  }

  void _goTo(int cursor, {required int direction}) {
    setState(() {
      _cursor = cursor;
      _direction = direction;
      _resolvedTransition = ref.read(avesSlideshowProvider).transition.resolve(_random);
    });
    _scheduleNext();
  }

  void _manualStep(int delta) {
    final target = _cursor + delta;
    if (target < 0) {
      if (!ref.read(avesSlideshowProvider).repeat) {
        return;
      }
      _goTo(_order.length - 1, direction: -1);
      return;
    }
    if (target >= _order.length) {
      if (!ref.read(avesSlideshowProvider).repeat) {
        return;
      }
      _goTo(0, direction: 1);
      return;
    }
    _goTo(target, direction: delta.sign);
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    _scheduleNext();
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  Duration get _switchDuration => switch (_resolvedTransition) {
    AvesSlideshowTransition.none => Duration.zero,
    AvesSlideshowTransition.slide => const Duration(milliseconds: 360),
    AvesSlideshowTransition.parallax => const Duration(milliseconds: 420),
    AvesSlideshowTransition.fade => const Duration(milliseconds: 520),
    AvesSlideshowTransition.zoom => const Duration(milliseconds: 480),
    AvesSlideshowTransition.random => const Duration(milliseconds: 400),
  };

  Widget _buildTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final dx = _direction.toDouble();

    return switch (_resolvedTransition) {
      AvesSlideshowTransition.none => child,

      AvesSlideshowTransition.slide => SlideTransition(
        position: Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero).animate(curved),
        child: child,
      ),

      // 视差滚动：新图位移比旧图小、同时轻微放大，于是背景像是被「留在后面」。
      AvesSlideshowTransition.parallax => SlideTransition(
        position: Tween<Offset>(begin: Offset(0.32 * dx, 0), end: Offset.zero).animate(curved),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        ),
      ),

      AvesSlideshowTransition.fade => FadeTransition(opacity: curved, child: child),

      AvesSlideshowTransition.zoom => ScaleTransition(
        scale: Tween<double>(begin: 0.78, end: 1).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      ),

      AvesSlideshowTransition.random => FadeTransition(opacity: curved, child: child),
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(avesSlideshowProvider);
    final asset = _current;
    final size = MediaQuery.sizeOf(context);

    // 「跳过视频」时直接把视频过滤掉，不应该出现一屏黑着等 5 秒。
    final isVideo = asset.isVideo;
    final shouldSkipVideo = isVideo && settings.videoPlayback == AvesVideoPlaybackMode.skip;
    if (shouldSkipVideo && _order.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _manualStep(1);
        }
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleChrome,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -120) {
            _manualStep(1);
          } else if (velocity > 120) {
            _manualStep(-1);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: _switchDuration,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: _buildTransition,
              child: KeyedSubtree(
                key: ValueKey('slide_$_cursor'),
                child: _AvesSlideStage(
                  asset: asset,
                  size: size,
                  fillScreen: settings.fillScreen,
                  animateZoom: settings.animateZoom,
                  interval: settings.interval,
                  volume: switch (settings.videoPlayback) {
                    AvesVideoPlaybackMode.muted => 0.0,
                    AvesVideoPlaybackMode.sound => 1.0,
                    AvesVideoPlaybackMode.skip => 0.0,
                  },
                  isPaused: _paused,
                ),
              ),
            ),
            _AvesSlideshowTopBar(
              visible: _chromeVisible,
              order: _order,
              cursor: _cursor,
              interval: settings.interval,
              paused: _paused,
              title: widget.title,
              onClose: () => Navigator.of(context).maybePop(),
              onTogglePause: _togglePause,
              onOpenSettings: () => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AvesSlideshowSettingsPage()),
                ),
              ),
            ),
            if (settings.showOverlay) _AvesSlideshowCaption(asset: asset, visible: _chromeVisible),
            if (_chromeVisible)
              Align(
                alignment: Alignment.centerLeft,
                child: _AvesEdgeArrow(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => _manualStep(-1),
                ),
              ),
            if (_chromeVisible)
              Align(
                alignment: Alignment.centerRight,
                child: _AvesEdgeArrow(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => _manualStep(1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 单张照片/视频的渲染层。
///
/// 抽成独立 StatefulWidget 是因为 Ken Burns 需要**每张自己的** AnimationController，
/// 放外层会让切图时缩放值继承上一张，看起来像抖了一下。
class _AvesSlideStage extends StatefulWidget {
  final BaseAsset asset;
  final Size size;
  final bool fillScreen;
  final bool animateZoom;
  final Duration interval;
  final double volume;
  final bool isPaused;

  const _AvesSlideStage({
    required this.asset,
    required this.size,
    required this.fillScreen,
    required this.animateZoom,
    required this.interval,
    required this.volume,
    required this.isPaused,
  });

  @override
  State<_AvesSlideStage> createState() => _AvesSlideStageState();
}

class _AvesSlideStageState extends State<_AvesSlideStage> with SingleTickerProviderStateMixin {
  late final AnimationController _kenBurns;

  @override
  void initState() {
    super.initState();
    _kenBurns = AnimationController(vsync: this, duration: widget.interval);
    if (widget.animateZoom) {
      unawaited(_kenBurns.forward(from: 0));
    }
  }

  @override
  void didUpdateWidget(covariant _AvesSlideStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused != oldWidget.isPaused) {
      if (widget.isPaused) {
        _kenBurns.stop();
      } else if (widget.animateZoom) {
        unawaited(_kenBurns.forward());
      }
    }
  }

  @override
  void dispose() {
    _kenBurns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fit = widget.fillScreen ? BoxFit.cover : BoxFit.contain;
    final asset = widget.asset;

    Widget media;
    if (asset.isVideo) {
      media = NativeVideoViewer(
        asset: asset,
        image: Thumbnail.fromAsset(asset: asset, fit: fit),
        isCurrent: true,
        volumeOverride: widget.volume,
        loopOverride: true,
      );
    } else {
      media = FullImage(asset, size: widget.size, fit: fit);
    }

    if (!widget.animateZoom) {
      return Center(child: media);
    }

    return AnimatedBuilder(
      animation: _kenBurns,
      builder: (context, child) {
        // 1.0 → 1.08 的极缓推近，Aves「动画缩放效果」就是这个手感。
        final scale = 1.0 + 0.08 * Curves.easeOut.transform(_kenBurns.value);
        return Transform.scale(scale: scale, child: child);
      },
      child: Center(child: media),
    );
  }
}

/// 顶部：分段进度条 + 标题 + 暂停/设置/关闭。
class _AvesSlideshowTopBar extends StatelessWidget {
  final bool visible;
  final List<int> order;
  final int cursor;
  final Duration interval;
  final bool paused;
  final String title;
  final VoidCallback onClose;
  final VoidCallback onTogglePause;
  final VoidCallback onOpenSettings;

  const _AvesSlideshowTopBar({
    required this.visible,
    required this.order,
    required this.cursor,
    required this.interval,
    required this.paused,
    required this.title,
    required this.onClose,
    required this.onTogglePause,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !visible,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 12,
              right: 12,
              bottom: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AvesSegmentedProgress(total: order.length, current: cursor, interval: interval, paused: paused),
                const SizedBox(height: 10),
                Row(
                  children: [
                    IconButton(
                      tooltip: '关闭',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: paused ? '继续' : '暂停',
                      onPressed: onTogglePause,
                      icon: Icon(
                        paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      tooltip: '幻灯片设置',
                      onPressed: onOpenSettings,
                      icon: const Icon(Icons.tune_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Aves 式分段进度条：素材不多时每张一段，太多时退化成一条连续进度。
class _AvesSegmentedProgress extends StatelessWidget {
  final int total;
  final int current;
  final Duration interval;
  final bool paused;

  const _AvesSegmentedProgress({
    required this.total,
    required this.current,
    required this.interval,
    required this.paused,
  });

  @override
  Widget build(BuildContext context) {
    if (total <= 0) {
      return const SizedBox.shrink();
    }

    if (total > 60) {
      final ratio = (current + 1) / total;
      return ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 3,
          backgroundColor: Colors.white24,
          valueColor: const AlwaysStoppedAnimation(Colors.white),
        ),
      );
    }

    return SizedBox(
      height: 3,
      child: Row(
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == total - 1 ? 0 : 3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: _AvesProgressSegment(
                    filled: i < current ? 1 : (i == current ? null : 0),
                    interval: interval,
                    paused: paused || i != current,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvesProgressSegment extends StatefulWidget {
  /// 1 = 已过，0 = 未到，null = 正在播放（按 interval 自己走）。
  final double? filled;
  final Duration interval;
  final bool paused;

  const _AvesProgressSegment({required this.filled, required this.interval, required this.paused});

  @override
  State<_AvesProgressSegment> createState() => _AvesProgressSegmentState();
}

class _AvesProgressSegmentState extends State<_AvesProgressSegment> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.interval);
    if (widget.filled == null) {
      unawaited(_controller.forward(from: 0));
    }
  }

  @override
  void didUpdateWidget(covariant _AvesProgressSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filled == null && oldWidget.filled != null) {
      unawaited(_controller.forward(from: 0));
    }
    if (widget.paused && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fixed = widget.filled;
    if (fixed != null) {
      return LinearProgressIndicator(
        value: fixed,
        minHeight: 3,
        backgroundColor: Colors.white30,
        valueColor: const AlwaysStoppedAnimation(Colors.white),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => LinearProgressIndicator(
        value: _controller.value,
        minHeight: 3,
        backgroundColor: Colors.white30,
        valueColor: const AlwaysStoppedAnimation(Colors.white),
      ),
    );
  }
}

/// 底部说明条（Aves「叠加层 → 显示信息」在幻灯片里的对应物）。
class _AvesSlideshowCaption extends StatelessWidget {
  final BaseAsset asset;
  final bool visible;

  const _AvesSlideshowCaption({required this.asset, required this.visible});

  @override
  Widget build(BuildContext context) {
    final date = asset.createdAt.toLocal();
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              28,
              20,
              MediaQuery.paddingOf(context).bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('yyyy年M月d日 HH:mm').format(date)}'
                  '${asset.width != null && asset.height != null ? ' · ${asset.width}×${asset.height}' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvesEdgeArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AvesEdgeArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: Colors.black26,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, color: Colors.white70, size: 26),
          ),
        ),
      ),
    );
  }
}
