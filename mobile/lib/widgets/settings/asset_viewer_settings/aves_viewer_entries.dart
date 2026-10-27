import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/pages/aves_overlay_settings.page.dart';
import 'package:immich_mobile/presentation/pages/aves_slideshow_settings.page.dart';
import 'package:immich_mobile/presentation/pages/aves_statistics.page.dart';
import 'package:immich_mobile/presentation/widgets/settings/aves_customization_sheet.widget.dart';
import 'package:immich_mobile/providers/aves_overlay.provider.dart';
import 'package:immich_ui/immich_ui.dart';

/// 「设置 → 查看器」里 Aves 那三个二级入口。
///
/// Aves 的查看器分组是：快速操作 › / 叠加层 › / 幻灯片 ›，然后才是各种开关。
/// 这里保持同样的顺序和形态（右侧 chevron + 二级页面），不塞进我们自己的
/// 自定义中心 tab，免得用户在原生的设置层级里找不到。
class AvesQuickActionsEntry extends StatelessWidget {
  const AvesQuickActionsEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingListTile(
      title: '快速操作',
      subtitle: '查看器里显示哪些按钮，以及它们的顺序',
      leading: const Icon(Icons.bolt_outlined),
      trailing: const Icon(Icons.chevron_right_rounded),
      // 复用自定义中心第 0 个 tab（查看器按钮编辑器），避免维护两份 UI。
      onTap: () => unawaited(openAvesCustomizationScreen(context, initialTab: 0)),
    );
  }
}

class AvesOverlayEntry extends StatelessWidget {
  const AvesOverlayEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingListTile(
      title: '叠加层',
      subtitle: '照片上的信息层：标题、拍摄参数、小地图、直方图、缩略图',
      leading: const Icon(Icons.layers_outlined),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AvesOverlaySettingsPage()),
        ),
      ),
    );
  }
}

class AvesSlideshowEntry extends StatelessWidget {
  const AvesSlideshowEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingListTile(
      title: '幻灯片',
      subtitle: '过渡动画、时间间隔、随机播放与视频处理',
      leading: const Icon(Icons.slideshow_rounded),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AvesSlideshowSettingsPage()),
        ),
      ),
    );
  }
}

/// 图像背景选择弹窗：一排圆形色块，Aves 的做法。
Future<void> showAvesImageBackgroundPicker(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(avesOverlayProvider);
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Center(child: Text('图像背景', style: TextStyle(fontWeight: FontWeight.w700))),
        contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1),
            for (var i = 0; i < AvesImageBackgroundSetting._labels.length; i++)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Icon(
                  settings.imageBackground == i
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: settings.imageBackground == i ? theme.colorScheme.primary : theme.colorScheme.outline,
                ),
                title: Text(AvesImageBackgroundSetting._labels[i]),
                trailing: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: settings.copyWith(imageBackground: i).imageBackgroundColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                  ),
                ),
                onTap: () {
                  ref.read(avesOverlayProvider.notifier).setImageBackground(i);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消'))],
      );
    },
  );
}

/// 「使用刘海/挖孔区域」开关。
class AvesDisplayCutoutSetting extends ConsumerWidget {
  const AvesDisplayCutoutSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(avesOverlayProvider.select((s) => s.useDisplayCutout));
    return SettingsSwitchListTile(
      valueNotifier: ValueNotifier(enabled),
      title: '使用刘海/挖孔区域',
      subtitle: '关闭后查看器顶部会让出挖孔高度，避免信息被裁掉',
      onChanged: (_) => ref.read(avesOverlayProvider.notifier).toggleDisplayCutout(),
    );
  }
}

/// 「自动播放动态照片」开关。
class AvesMotionPhotoSetting extends ConsumerWidget {
  const AvesMotionPhotoSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(avesOverlayProvider.select((s) => s.autoPlayMotionPhoto));
    return SettingsSwitchListTile(
      valueNotifier: ValueNotifier(enabled),
      title: '自动播放动态照片',
      subtitle: '打开查看器时，动态照片立即播放而不是停在首帧',
      onChanged: (_) => ref.read(avesOverlayProvider.notifier).toggleAutoPlayMotionPhoto(),
    );
  }
}

/// 「图像背景」色块 + 选择弹窗。
class AvesImageBackgroundSetting extends ConsumerWidget {
  const AvesImageBackgroundSetting({super.key});

  static const _labels = ['黑色', '深灰', '中灰', '深灰白', '深海蓝'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(avesOverlayProvider);
    final current = settings.imageBackground.clamp(0, 4);

    return SettingListTile(
      title: '图像背景',
      subtitle: _labels[current],
      leading: const Icon(Icons.contrast_rounded),
      trailing: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: settings.imageBackgroundColor,
          shape: BoxShape.circle,
          border: Border.all(color: context.colorScheme.outline.withValues(alpha: 0.6)),
        ),
      ),
      onTap: () => unawaited(showAvesImageBackgroundPicker(context, ref)),
    );
  }
}

/// 打开查看器时「相册/媒体集」之外还能直达的入口——Aves 的底部导航里也有，
/// 这里放在设置页给个显性入口，避免功能被埋。
class AvesStatisticsEntry extends StatelessWidget {
  const AvesStatisticsEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingListTile(
      title: '全景统计',
      subtitle: '格式分布、年份分布、地点与相机排行榜',
      leading: const Icon(Icons.pie_chart_outline_rounded),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => unawaited(openAvesStatisticsScreen(context)),
    );
  }
}
