import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Aves `SlideshowTransition` —— 幻灯片切图时的六种过渡方式。
///
/// 与 Aves「幻灯片 → 过渡动画」弹窗一一对应：
/// 滑动 / 视差滚动 / 淡入淡出 / 放大 / 无 / 随机。
enum AvesSlideshowTransition {
  slide(label: '滑动', icon: Icons.swipe_rounded),
  parallax(label: '视差滚动', icon: Icons.filter_drama_rounded),
  fade(label: '淡入淡出', icon: Icons.gradient_rounded),
  zoom(label: '放大', icon: Icons.zoom_in_rounded),
  none(label: '无', icon: Icons.block_rounded),
  random(label: '随机', icon: Icons.shuffle_rounded);

  final String label;
  final IconData icon;
  const AvesSlideshowTransition({required this.label, required this.icon});

  /// 「随机」不能自己再随机自己，抽签池里只放五种具体过渡。
  static const List<AvesSlideshowTransition> pool = [slide, parallax, fade, zoom, none];

  /// 落到具体某一张时该用哪个过渡。
  AvesSlideshowTransition resolve(math.Random random) {
    if (this != AvesSlideshowTransition.random) {
      return this;
    }
    return pool[random.nextInt(pool.length)];
  }
}

/// Aves「幻灯片 → 视频播放」的三种策略。
enum AvesVideoPlaybackMode {
  muted(label: '静音播放', icon: Icons.volume_off_rounded),
  sound(label: '带声音播放', icon: Icons.volume_up_rounded),
  skip(label: '跳过视频', icon: Icons.skip_next_rounded);

  final String label;
  final IconData icon;
  const AvesVideoPlaybackMode({required this.label, required this.icon});
}

class AvesSlideshowSettings {
  /// 播到最后一张后是否回到第一张。
  final bool repeat;

  /// 是否打乱播放顺序。
  final bool shuffle;

  /// true = 裁切填满屏幕（cover），false = 完整显示（contain）。
  final bool fillScreen;

  /// Aves「动画缩放效果」：单张停留时的 Ken Burns 缓慢推近。
  final bool animateZoom;

  final AvesSlideshowTransition transition;

  /// 单张停留秒数（Aves 默认 5 秒）。
  final int intervalSeconds;

  final AvesVideoPlaybackMode videoPlayback;

  /// 播放时是否显示叠加信息（与 Aves「叠加层 → 打开时显示」同一个开关语义）。
  final bool showOverlay;

  const AvesSlideshowSettings({
    this.repeat = true,
    this.shuffle = false,
    this.fillScreen = false,
    this.animateZoom = true,
    this.transition = AvesSlideshowTransition.parallax,
    this.intervalSeconds = 5,
    this.videoPlayback = AvesVideoPlaybackMode.muted,
    this.showOverlay = true,
  });

  Duration get interval => Duration(seconds: intervalSeconds.clamp(1, 60));

  AvesSlideshowSettings copyWith({
    bool? repeat,
    bool? shuffle,
    bool? fillScreen,
    bool? animateZoom,
    AvesSlideshowTransition? transition,
    int? intervalSeconds,
    AvesVideoPlaybackMode? videoPlayback,
    bool? showOverlay,
  }) {
    return AvesSlideshowSettings(
      repeat: repeat ?? this.repeat,
      shuffle: shuffle ?? this.shuffle,
      fillScreen: fillScreen ?? this.fillScreen,
      animateZoom: animateZoom ?? this.animateZoom,
      transition: transition ?? this.transition,
      intervalSeconds: (intervalSeconds ?? this.intervalSeconds).clamp(1, 60),
      videoPlayback: videoPlayback ?? this.videoPlayback,
      showOverlay: showOverlay ?? this.showOverlay,
    );
  }

  Map<String, dynamic> toJson() => {
    'repeat': repeat,
    'shuffle': shuffle,
    'fillScreen': fillScreen,
    'animateZoom': animateZoom,
    'transition': transition.name,
    'intervalSeconds': intervalSeconds,
    'videoPlayback': videoPlayback.name,
    'showOverlay': showOverlay,
  };

  factory AvesSlideshowSettings.fromJson(Map<String, dynamic> json) {
    return AvesSlideshowSettings(
      repeat: json['repeat'] as bool? ?? true,
      shuffle: json['shuffle'] as bool? ?? false,
      fillScreen: json['fillScreen'] as bool? ?? false,
      animateZoom: json['animateZoom'] as bool? ?? true,
      transition: AvesSlideshowTransition.values.firstWhere(
        (e) => e.name == json['transition'],
        orElse: () => AvesSlideshowTransition.parallax,
      ),
      intervalSeconds: ((json['intervalSeconds'] as num?)?.toInt() ?? 5).clamp(1, 60),
      videoPlayback: AvesVideoPlaybackMode.values.firstWhere(
        (e) => e.name == json['videoPlayback'],
        orElse: () => AvesVideoPlaybackMode.muted,
      ),
      showOverlay: json['showOverlay'] as bool? ?? true,
    );
  }
}

class AvesSlideshowNotifier extends StateNotifier<AvesSlideshowSettings> {
  AvesSlideshowNotifier() : super(const AvesSlideshowSettings()) {
    unawaited(_loadFromDisk());
  }

  static const _fileName = 'aves_slideshow_settings_v1.json';

  Future<File?> _getSettingsFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final file = await _getSettingsFile();
      if (file != null && file.existsSync()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          state = AvesSlideshowSettings.fromJson(decoded);
        }
      }
    } catch (_) {
      // 读不出来就保持默认值，不影响启动。
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _getSettingsFile();
      if (file != null) {
        await file.writeAsString(jsonEncode(state.toJson()));
      }
    } catch (_) {}
  }

  void _update(AvesSlideshowSettings next) {
    state = next;
    unawaited(_saveToDisk());
  }

  void toggleRepeat() => _update(state.copyWith(repeat: !state.repeat));
  void toggleShuffle() => _update(state.copyWith(shuffle: !state.shuffle));
  void toggleFillScreen() => _update(state.copyWith(fillScreen: !state.fillScreen));
  void toggleAnimateZoom() => _update(state.copyWith(animateZoom: !state.animateZoom));
  void toggleShowOverlay() => _update(state.copyWith(showOverlay: !state.showOverlay));

  void setTransition(AvesSlideshowTransition transition) => _update(state.copyWith(transition: transition));

  void setIntervalSeconds(int seconds) => _update(state.copyWith(intervalSeconds: seconds));

  void setVideoPlayback(AvesVideoPlaybackMode mode) => _update(state.copyWith(videoPlayback: mode));

  void resetToDefaults() => _update(const AvesSlideshowSettings());
}

final avesSlideshowProvider = StateNotifierProvider<AvesSlideshowNotifier, AvesSlideshowSettings>(
  (ref) => AvesSlideshowNotifier(),
);
