import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/pages/aves_slideshow_settings.page.dart' show showAvesRadioDialog;
import 'package:immich_mobile/providers/aves_overlay.provider.dart';

/// Aves「叠加层」设置页。
///
/// 视觉照抄 Aves：分组之间只用 1px 分隔线，不加卡片；
/// 每行右侧是「小图标 + 开关」——那个小图标是 Aves 的辨识特征，别省。
class AvesOverlaySettingsPage extends ConsumerWidget {
  const AvesOverlaySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(avesOverlayProvider);
    final notifier = ref.read(avesOverlayProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('叠加层'),
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
          _OverlaySwitchRow(
            title: '打开时显示',
            subtitle: '进入查看器时自动展开叠加层；关闭后点按画面可临时唤出',
            value: settings.showOnOpen,
            onChanged: (_) => notifier.toggleShowOnOpen(),
          ),
          const Divider(height: 1),

          _OverlaySwitchRow(
            title: '显示信息',
            subtitle: '显示标题、日期、位置等',
            value: settings.showInfo,
            onChanged: (_) => notifier.toggleInfo(),
          ),
          // 这三项是「显示信息」的子项：父项关掉时整行置灰不可点，与 Aves 一致。
          _OverlaySwitchRow(
            title: '显示拍摄详情',
            trailingIcon: Icons.camera_rounded,
            value: settings.showShootingDetails,
            enabled: settings.showInfo,
            onChanged: (_) => notifier.toggleShootingDetails(),
          ),
          _OverlaySwitchRow(
            title: '显示评分和标签',
            trailingIcon: Icons.sell_outlined,
            value: settings.showRatingAndTags,
            enabled: settings.showInfo,
            onChanged: (_) => notifier.toggleRatingAndTags(),
          ),
          _OverlaySwitchRow(
            title: '显示描述',
            trailingIcon: Icons.notes_rounded,
            value: settings.showDescription,
            enabled: settings.showInfo,
            onChanged: (_) => notifier.toggleDescription(),
          ),
          const Divider(height: 1),

          _OverlaySwitchRow(
            title: '显示缩放级别',
            trailingIcon: Icons.zoom_in_rounded,
            value: settings.showZoomLevel,
            onChanged: (_) => notifier.toggleZoomLevel(),
          ),
          _OverlaySwitchRow(
            title: '显示小地图',
            trailingIcon: Icons.map_outlined,
            value: settings.showMiniMap,
            onChanged: (_) => notifier.toggleMiniMap(),
          ),
          _OverlayValueRow(
            title: '显示直方图',
            value: settings.histogram.label,
            enabled: true,
            onTap: () => unawaited(_pickHistogram(context, ref)),
          ),
          const Divider(height: 1),

          _OverlaySwitchRow(
            title: '显示缩略图',
            trailingIcon: Icons.view_carousel_outlined,
            value: settings.showFilmstrip,
            onChanged: (_) => notifier.toggleFilmstrip(),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text(
              '叠加层会以半透明卡片浮在照片之上，不改变照片本身的缩放与构图。'
              '查看器里点按画面可以临时收起或唤出。',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlaySwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? trailingIcon;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _OverlaySwitchRow({
    required this.title,
    this.subtitle,
    this.trailingIcon,
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleColor = enabled ? null : theme.colorScheme.onSurface.withValues(alpha: 0.38);
    final subColor = enabled
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface.withValues(alpha: 0.30);

    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyLarge?.copyWith(color: titleColor)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: subColor)),
                    ),
                ],
              ),
            ),
            if (trailingIcon != null) ...[
              Icon(
                trailingIcon,
                size: 20,
                color: enabled
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface.withValues(alpha: 0.26),
              ),
              const SizedBox(width: 10),
            ],
            Switch(value: value, onChanged: enabled ? onChanged : null),
          ],
        ),
      ),
    );
  }
}

/// 「标签 + 右侧当前值」，Aves 里「显示直方图 · 无」就是这种行。
class _OverlayValueRow extends StatelessWidget {
  final String title;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  const _OverlayValueRow({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.outline;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
            Icon(Icons.bar_chart_rounded, size: 20, color: color),
            const SizedBox(width: 10),
            Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: color)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

Future<void> _pickHistogram(BuildContext context, WidgetRef ref) async {
  final current = ref.read(avesOverlayProvider).histogram;
  final picked = await showAvesRadioDialog<AvesHistogramMode>(
    context: context,
    title: '显示直方图',
    current: current,
    options: [
      for (final mode in AvesHistogramMode.values) (value: mode, label: mode.label),
    ],
  );
  if (picked != null) {
    ref.read(avesOverlayProvider.notifier).setHistogram(picked);
  }
}
