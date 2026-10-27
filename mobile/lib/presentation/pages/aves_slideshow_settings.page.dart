import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/aves_slideshow.provider.dart';

/// Aves「幻灯片」设置页。
///
/// 布局照抄 Aves：白底、无卡片、一行一个设置项，标题在左、控件在右，
/// 需要选择的那几项（过渡动画 / 时间间隔 / 视频播放）点开一个居中圆角单选弹窗。
class AvesSlideshowSettingsPage extends ConsumerWidget {
  const AvesSlideshowSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(avesSlideshowProvider);
    final notifier = ref.read(avesSlideshowProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('幻灯片'),
        actions: [
          TextButton(
            onPressed: notifier.resetToDefaults,
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _AvesSwitchRow(
            title: '重复',
            subtitle: '播到最后一张后重新开始',
            value: settings.repeat,
            onChanged: (_) => notifier.toggleRepeat(),
          ),
          _AvesSwitchRow(
            title: '随机播放',
            subtitle: '打乱播放顺序，每次进入重新抽签',
            value: settings.shuffle,
            onChanged: (_) => notifier.toggleShuffle(),
          ),
          _AvesSwitchRow(
            title: '填充屏幕',
            subtitle: '裁切画面铺满整屏（关闭则完整显示，留黑边）',
            value: settings.fillScreen,
            onChanged: (_) => notifier.toggleFillScreen(),
          ),
          _AvesSwitchRow(
            title: '动画缩放效果',
            subtitle: '每张停留时缓慢推近（Ken Burns）',
            value: settings.animateZoom,
            onChanged: (_) => notifier.toggleAnimateZoom(),
          ),
          _AvesValueRow(
            title: '过渡动画',
            value: settings.transition.label,
            onTap: () => unawaited(_pickTransition(context, ref)),
          ),
          _AvesValueRow(
            title: '时间间隔',
            value: '${settings.intervalSeconds} 秒',
            onTap: () => unawaited(_pickInterval(context, ref)),
          ),
          _AvesValueRow(
            title: '视频播放',
            value: settings.videoPlayback.label,
            onTap: () => unawaited(_pickVideoMode(context, ref)),
          ),
          const Divider(height: 28),
          _AvesSwitchRow(
            title: '播放时显示信息',
            subtitle: '在画面下方显示文件名、拍摄时间与分辨率',
            value: settings.showOverlay,
            onChanged: (_) => notifier.toggleShowOverlay(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              '播放中左右滑动可手动翻页，点一下画面可收起/显示控制栏。',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aves 那种「标题 +（说明）+ 右侧开关」的行。
class _AvesSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AvesSwitchRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyLarge),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// 「标题 +（说明）+ 右侧当前值」的行，点开选择弹窗。
class _AvesValueRow extends StatelessWidget {
  final String title;
  final String value;
  final VoidCallback onTap;

  const _AvesValueRow({required this.title, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 20, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

/// Aves 的居中单选弹窗：白色圆角卡片、一排圆圈选项、底部「取消」。
Future<T?> showAvesRadioDialog<T>({
  required BuildContext context,
  required String title,
  required List<({T value, String label})> options,
  required T current,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final option in options)
                    InkWell(
                      onTap: () => Navigator.of(ctx).pop(option.value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                        child: Row(
                          children: [
                            Icon(
                              option.value == current
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              size: 22,
                              color: option.value == current
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Text(option.label, style: theme.textTheme.bodyMedium)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      );
    },
  );
}

Future<void> _pickTransition(BuildContext context, WidgetRef ref) async {
  final current = ref.read(avesSlideshowProvider).transition;
  final picked = await showAvesRadioDialog<AvesSlideshowTransition>(
    context: context,
    title: '过渡动画',
    current: current,
    options: [
      for (final t in AvesSlideshowTransition.values) (value: t, label: t.label),
    ],
  );
  if (picked != null) {
    ref.read(avesSlideshowProvider.notifier).setTransition(picked);
  }
}

const _intervalPresets = [1, 2, 3, 5, 8, 10, 15, 20, 30];

Future<void> _pickInterval(BuildContext context, WidgetRef ref) async {
  final current = ref.read(avesSlideshowProvider).intervalSeconds;
  final picked = await showAvesRadioDialog<int>(
    context: context,
    title: '时间间隔',
    current: current,
    options: [
      for (final s in _intervalPresets) (value: s, label: '$s 秒'),
    ],
  );
  if (picked != null) {
    ref.read(avesSlideshowProvider.notifier).setIntervalSeconds(picked);
  }
}

Future<void> _pickVideoMode(BuildContext context, WidgetRef ref) async {
  final current = ref.read(avesSlideshowProvider).videoPlayback;
  final picked = await showAvesRadioDialog<AvesVideoPlaybackMode>(
    context: context,
    title: '视频播放',
    current: current,
    options: [
      for (final m in AvesVideoPlaybackMode.values) (value: m, label: m.label),
    ],
  );
  if (picked != null) {
    ref.read(avesSlideshowProvider.notifier).setVideoPlayback(picked);
  }
}
