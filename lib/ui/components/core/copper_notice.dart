import 'package:copper_launcher/ui/components/core/copper_pressable.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 提示条语气
enum CopperNoticeTone { info, success, warning, danger, note }

/// 内核提示条：左侧一道语义色 + 淡底，可带标题 / 图标 / 行内动作 / 关闭
///
/// 替代 `buildWarningBar` 的视觉表现（「按 key 记住关闭」的行为仍由调用方负责）。
class CopperNotice extends StatelessWidget {
  const CopperNotice({
    super.key,
    required this.text,
    this.title,
    this.tone = CopperNoticeTone.info,
    this.icon,
    this.action,
    this.onClose,
  });

  final String text;
  final String? title;
  final CopperNoticeTone tone;
  final IconData? icon;

  /// 行内动作（右对齐）
  final Widget? action;

  final VoidCallback? onClose;

  Color _toneColor(AppColors colors) => switch (tone) {
    CopperNoticeTone.info => colors.interactive,
    CopperNoticeTone.success => colors.success,
    CopperNoticeTone.warning => colors.warning,
    CopperNoticeTone.danger => colors.error,
    CopperNoticeTone.note => colors.itemSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final toneColor = _toneColor(colors);

    return Container(
      decoration: BoxDecoration(
        color: toneColor.withAlpha(24),
        borderRadius: BorderRadius.circular(AppRadius.item),
        border: Border(
          left: BorderSide(color: toneColor, width: AppBorderWidth.emphasis),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.group,
        vertical: AppSpacing.related,
      ),
      child: Row(
        spacing: AppSpacing.related,
        children: [
          if (icon != null)
            Icon(icon, size: AppIconSize.inline, color: toneColor),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.inline,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.itemPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  text,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.itemSecondary,
                    height: 18 / 12,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) action!,
          if (onClose != null)
            CopperPressable(
              onTap: onClose,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Icon(
                Icons.close,
                size: AppIconSize.inline,
                color: colors.itemHint,
              ),
            ),
        ],
      ),
    );
  }
}
