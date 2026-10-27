import 'package:flutter/material.dart';
import 'package:immich_mobile/widgets/settings/asset_viewer_settings/aves_viewer_entries.dart';
import 'package:immich_mobile/widgets/settings/asset_viewer_settings/image_viewer_quality_setting.dart';
import 'package:immich_mobile/widgets/settings/asset_viewer_settings/image_viewer_tap_to_navigate_setting.dart';
import 'package:immich_mobile/widgets/settings/asset_viewer_settings/video_viewer_settings.dart';
import 'package:immich_ui/immich_ui.dart';

/// 「设置 → 查看器」。
///
/// 顺序对齐 Aves 的同名分组：先三个二级入口（快速操作 / 叠加层 / 幻灯片），
/// 再是行为开关（轻触边缘翻页 / 挖孔区域 / 动态照片 / 图像背景），
/// 最后才是画质与视频这类原生项。
///
/// 原来内联的 `SlideshowSettings` 被移除了：幻灯片现在走
/// [AvesSlideshowEntry] 的二级页面，那边多了过渡动画等 Aves 才有的设置，
/// 两套并存只会让人不知道该改哪一个。
class AssetViewerSettings extends StatelessWidget {
  const AssetViewerSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final assetViewerSetting = [
      const SettingGroupTitle(title: '查看器增强'),
      const AvesQuickActionsEntry(),
      const AvesOverlayEntry(),
      const AvesSlideshowEntry(),
      const ImageViewerTapToNavigateSetting(),
      const AvesDisplayCutoutSetting(),
      const AvesMotionPhotoSetting(),
      const AvesImageBackgroundSetting(),
      const SettingGroupTitle(title: '画质与播放'),
      const ImageViewerQualitySetting(),
      const VideoViewerSettings(),
    ];

    return SettingsSubPageScaffold(settings: assetViewerSetting, showDivider: true);
  }
}
