import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Color;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Aves「叠加层 → 显示直方图」的三种模式。
enum AvesHistogramMode {
  none(label: '无'),
  luminance(label: '亮度'),
  rgb(label: 'RGB');

  final String label;
  const AvesHistogramMode({required this.label});
}

/// Aves「叠加层」设置。
///
/// 对应 Aves 那页从下到上的分组：
/// 「打开时显示」/「显示信息…显示直方图」/「显示缩略图」。
///
/// 这里的每一项都决定查看器里叠在照片上那一层要不要渲染对应元素，
/// 全部关掉 + 打开时不显示 = 回到纯净的沉浸看图。
class AvesOverlaySettings {
  /// Aves「打开时显示」：进入查看器时叠加层是否自动展开。
  /// 关闭后叠加层仍然在，双击/点按可以临时唤出。
  final bool showOnOpen;

  /// 标题、日期、位置等基础信息。
  final bool showInfo;

  /// 光圈 / 快门 / 焦段 / ISO 等拍摄参数。
  final bool showShootingDetails;

  /// 评分与标签。
  final bool showRatingAndTags;

  /// 描述文案。
  final bool showDescription;

  /// 当前缩放倍率。
  final bool showZoomLevel;

  /// 缩略图位置（小地图）。
  final bool showMiniMap;

  final AvesHistogramMode histogram;

  /// Aves「显示缩略图」：底部胶片条。
  final bool showFilmstrip;

  /// Aves「使用刘海/挖孔区域」：查看器内容是否延伸到挖孔区域。
  final bool useDisplayCutout;

  /// Aves「自动播放动态照片」：进入查看器时动态照片是否立刻播放。
  final bool autoPlayMotionPhoto;

  /// Aves「图像背景」：查看器底色索引，见 [imageBackgroundColor]。
  final int imageBackground;

  const AvesOverlaySettings({
    this.showOnOpen = true,
    this.showInfo = true,
    this.showShootingDetails = true,
    this.showRatingAndTags = true,
    this.showDescription = true,
    this.showZoomLevel = true,
    this.showMiniMap = true,
    this.histogram = AvesHistogramMode.none,
    this.showFilmstrip = true,
    this.useDisplayCutout = true,
    this.autoPlayMotionPhoto = true,
    this.imageBackground = 0,
  });

  /// 「显示信息」是「拍摄详情 / 评分标签 / 描述」的父开关。
  ///
  /// Aves 里父项一关，那三项整行变灰且不生效；渲染层也必须走这三个 getter，
  /// 否则会出现「设置页灰着但画面还在显示」的错位。
  bool get effectiveShootingDetails => showInfo && showShootingDetails;
  bool get effectiveRatingAndTags => showInfo && showRatingAndTags;
  bool get effectiveDescription => showInfo && showDescription;

  /// 查看器底色。0 黑 / 1 深灰 / 2 浅灰 / 3 白 / 4 深蓝黑。
  Color get imageBackgroundColor => switch (imageBackground) {
    0 => const Color(0xFF000000),
    1 => const Color(0xFF1C1C1E),
    2 => const Color(0xFF2C2C2E),
    3 => const Color(0xFF3A3A3C),
    _ => const Color(0xFF0A1420),
  };

  AvesOverlaySettings copyWith({
    bool? showOnOpen,
    bool? showInfo,
    bool? showShootingDetails,
    bool? showRatingAndTags,
    bool? showDescription,
    bool? showZoomLevel,
    bool? showMiniMap,
    AvesHistogramMode? histogram,
    bool? showFilmstrip,
    bool? useDisplayCutout,
    bool? autoPlayMotionPhoto,
    int? imageBackground,
  }) {
    return AvesOverlaySettings(
      showOnOpen: showOnOpen ?? this.showOnOpen,
      showInfo: showInfo ?? this.showInfo,
      showShootingDetails: showShootingDetails ?? this.showShootingDetails,
      showRatingAndTags: showRatingAndTags ?? this.showRatingAndTags,
      showDescription: showDescription ?? this.showDescription,
      showZoomLevel: showZoomLevel ?? this.showZoomLevel,
      showMiniMap: showMiniMap ?? this.showMiniMap,
      histogram: histogram ?? this.histogram,
      showFilmstrip: showFilmstrip ?? this.showFilmstrip,
      useDisplayCutout: useDisplayCutout ?? this.useDisplayCutout,
      autoPlayMotionPhoto: autoPlayMotionPhoto ?? this.autoPlayMotionPhoto,
      imageBackground: (imageBackground ?? this.imageBackground).clamp(0, 4),
    );
  }

  Map<String, dynamic> toJson() => {
    'showOnOpen': showOnOpen,
    'showInfo': showInfo,
    'showShootingDetails': showShootingDetails,
    'showRatingAndTags': showRatingAndTags,
    'showDescription': showDescription,
    'showZoomLevel': showZoomLevel,
    'showMiniMap': showMiniMap,
    'histogram': histogram.name,
    'showFilmstrip': showFilmstrip,
    'useDisplayCutout': useDisplayCutout,
    'autoPlayMotionPhoto': autoPlayMotionPhoto,
    'imageBackground': imageBackground,
  };

  factory AvesOverlaySettings.fromJson(Map<String, dynamic> json) {
    return AvesOverlaySettings(
      showOnOpen: json['showOnOpen'] as bool? ?? true,
      showInfo: json['showInfo'] as bool? ?? true,
      showShootingDetails: json['showShootingDetails'] as bool? ?? true,
      showRatingAndTags: json['showRatingAndTags'] as bool? ?? true,
      showDescription: json['showDescription'] as bool? ?? true,
      showZoomLevel: json['showZoomLevel'] as bool? ?? true,
      showMiniMap: json['showMiniMap'] as bool? ?? true,
      histogram: AvesHistogramMode.values.firstWhere(
        (e) => e.name == json['histogram'],
        orElse: () => AvesHistogramMode.none,
      ),
      showFilmstrip: json['showFilmstrip'] as bool? ?? true,
      useDisplayCutout: json['useDisplayCutout'] as bool? ?? true,
      autoPlayMotionPhoto: json['autoPlayMotionPhoto'] as bool? ?? true,
      imageBackground: ((json['imageBackground'] as num?)?.toInt() ?? 0).clamp(0, 4),
    );
  }
}

class AvesOverlayNotifier extends StateNotifier<AvesOverlaySettings> {
  AvesOverlayNotifier() : super(const AvesOverlaySettings()) {
    unawaited(_loadFromDisk());
  }

  static const _fileName = 'aves_overlay_settings_v1.json';

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
          state = AvesOverlaySettings.fromJson(decoded);
        }
      }
    } catch (_) {
      // 读失败保留默认值。
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

  void _update(AvesOverlaySettings next) {
    state = next;
    unawaited(_saveToDisk());
  }

  void toggleShowOnOpen() => _update(state.copyWith(showOnOpen: !state.showOnOpen));
  void toggleInfo() => _update(state.copyWith(showInfo: !state.showInfo));
  void toggleShootingDetails() => _update(state.copyWith(showShootingDetails: !state.showShootingDetails));
  void toggleRatingAndTags() => _update(state.copyWith(showRatingAndTags: !state.showRatingAndTags));
  void toggleDescription() => _update(state.copyWith(showDescription: !state.showDescription));
  void toggleZoomLevel() => _update(state.copyWith(showZoomLevel: !state.showZoomLevel));
  void toggleMiniMap() => _update(state.copyWith(showMiniMap: !state.showMiniMap));
  void toggleFilmstrip() => _update(state.copyWith(showFilmstrip: !state.showFilmstrip));
  void toggleDisplayCutout() => _update(state.copyWith(useDisplayCutout: !state.useDisplayCutout));
  void toggleAutoPlayMotionPhoto() => _update(state.copyWith(autoPlayMotionPhoto: !state.autoPlayMotionPhoto));

  void setImageBackground(int index) => _update(state.copyWith(imageBackground: index));

  void setHistogram(AvesHistogramMode mode) => _update(state.copyWith(histogram: mode));

  void resetToDefaults() => _update(const AvesOverlaySettings());
}

final avesOverlayProvider = StateNotifierProvider<AvesOverlayNotifier, AvesOverlaySettings>(
  (ref) => AvesOverlayNotifier(),
);
