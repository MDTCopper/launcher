import 'package:copper_launcher/ui/components/core/app_pressable.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 分段控件：凹槽底 + 选中格，单选
///
/// 与设计层 `TemplateSegment` 同一形制，但只吃 `AppColors` + 几何令牌；
/// 按压只变色，不做整格缩放。单段可禁用。
class AppSegment extends StatelessWidget {
  const AppSegment({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.icons,
    this.disabled = const {},
    this.enabled = true,
  });

  final List<String> options;
  final int value;
  final ValueChanged<int> onChanged;

  /// 与 [options] 等长的段内图标（可空）
  final List<IconData>? icons;

  /// 禁用的段下标
  final Set<int> disabled;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.inline),
      decoration: BoxDecoration(
        color: colors.inputBackground,
        borderRadius: BorderRadius.circular(
          AppRadius.control + AppSpacing.inline,
        ),
        border: Border.all(
          color: enabled ? colors.border : colors.lowBackgroundOnCard,
        ),
      ),
      child: Row(
        spacing: AppSpacing.inline,
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: _SegmentCell(
                label: options[i],
                icon: icons == null ? null : icons![i],
                selected: value == i,
                enabled: enabled && !disabled.contains(i),
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentCell extends StatelessWidget {
  const _SegmentCell({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    final foreground = !enabled
        ? colors.itemHint
        : selected
        ? colors.itemPrimary
        : colors.itemSecondary;

    return AppPressable(
      enabled: enabled,
      selected: selected,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      backgroundColor: selected
          ? colors.elevatedBackground
          : Colors.transparent,
      selectedColor: colors.elevatedBackground,
      decoration: selected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: colors.border),
            )
          : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.related,
        vertical: AppSpacing.tight + 2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: AppSpacing.tight,
        children: [
          if (icon != null)
            Icon(icon, size: AppIconSize.inline - 2, color: foreground),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: foreground,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
