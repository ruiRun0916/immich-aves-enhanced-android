import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/presentation/widgets/images/image_provider.dart';
import 'package:immich_mobile/providers/aves_overlay.provider.dart';

/// Aves「显示直方图」的渲染层。
///
/// 采样对象是**缩略图**而不是原图：直方图只关心亮度/颜色分布，缩略图足够，
/// 而且不会为了一张叠加曲线去解码一张 50MP 的照片。
class AvesHistogram extends StatefulWidget {
  final BaseAsset asset;
  final AvesHistogramMode mode;
  final double width;
  final double height;

  const AvesHistogram({
    super.key,
    required this.asset,
    required this.mode,
    this.width = 96,
    this.height = 54,
  });

  @override
  State<AvesHistogram> createState() => _AvesHistogramState();
}

class _AvesHistogramState extends State<AvesHistogram> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Uint32List? _luma;
  Uint32List? _red;
  Uint32List? _green;
  Uint32List? _blue;

  static const int _bins = 64;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant AvesHistogram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _stop();
      _start();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    final listener = _listener;
    if (listener != null) {
      _stream?.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  void _start() {
    final provider = getThumbnailImageProvider(widget.asset, size: const Size(96, 96));
    if (provider == null) {
      return;
    }
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        unawaited(_compute(info.image, listener));
      },
      onError: (_, _) {},
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  Future<void> _compute(ui.Image image, ImageStreamListener listener) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null || !mounted || _listener != listener) {
        return;
      }
      final bytes = data.buffer.asUint8List();
      final luma = Uint32List(_bins);
      final red = Uint32List(_bins);
      final green = Uint32List(_bins);
      final blue = Uint32List(_bins);

      // 每隔若干像素采一个点即可，96×96 全采也就 9216 次，没必要跳。
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        final a = bytes[i + 3];
        if (a < 16) {
          continue;
        }
        final y = (0.2126 * r + 0.7152 * g + 0.0722 * b).round().clamp(0, 255);
        luma[(y * _bins) ~/ 256]++;
        red[(r * _bins) ~/ 256]++;
        green[(g * _bins) ~/ 256]++;
        blue[(b * _bins) ~/ 256]++;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _luma = luma;
        _red = red;
        _green = green;
        _blue = blue;
      });
    } catch (_) {
      // 采样失败就保持空白，不影响看图。
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_luma == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: CustomPaint(
        painter: _HistogramPainter(
          luma: _luma!,
          red: _red!,
          green: _green!,
          blue: _blue!,
          mode: widget.mode,
        ),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final Uint32List luma;
  final Uint32List red;
  final Uint32List green;
  final Uint32List blue;
  final AvesHistogramMode mode;

  const _HistogramPainter({
    required this.luma,
    required this.red,
    required this.green,
    required this.blue,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    if (mode == AvesHistogramMode.rgb) {
      _paintChannel(canvas, size, red, const Color(0xCCFF5252));
      _paintChannel(canvas, size, green, const Color(0xCC69F0AE));
      _paintChannel(canvas, size, blue, const Color(0xCC40C4FF));
    } else {
      _paintChannel(canvas, size, luma, const Color(0xDDFFFFFF));
    }
  }

  void _paintChannel(Canvas canvas, Size size, Uint32List data, Color color) {
    var max = 0;
    for (final v in data) {
      if (v > max) {
        max = v;
      }
    }
    if (max == 0) {
      return;
    }

    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i < data.length; i++) {
      // 用 sqrt 压一下动态范围，否则只有一两个尖峰，曲线其余部分全贴地。
      final normalized = (data[i] / max).clamp(0.0, 1.0);
      final h = size.height * (1 - normalized * 0.92 - 0.04);
      final x = size.width * i / (data.length - 1);
      path.lineTo(x, h);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.05)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) =>
      oldDelegate.mode != mode || oldDelegate.luma != luma || oldDelegate.red != red;
}
