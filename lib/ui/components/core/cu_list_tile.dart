import 'package:copper_launcher/ui/components/core/cu_pressable.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 内核列表行：leading / 标题 / 副标题 / trailing，可选中、可禁用
///
/// 按压只变色（[CuPressable]），行内不加任何几何动画，因此
/// 行间分隔线可以安全地用 [decoration]（`Border(bottom: ...)`）透传。
class CuListTile extends StatelessWidget {
  const CuListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.group,
      vertical: AppSpacing.related + 2,
    ),
    this.margin,
    this.borderRadius,
    this.decoration,
    this.backgroundColor,
    this.hint,
    this.itemSpacing = AppSpacing.related,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final bool selected;
  final bool enabled;

  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;

  /// 透传容器装饰（行底分隔线 / 描边等）
  final BoxDecoration? decoration;

  final Color? backgroundColor;

  /// 悬停提示
  final String? hint;

  final double itemSpacing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    final foreground = selected
        ? colors.interactive
        : enabled
        ? colors.itemPrimary
        : colors.itemHint;
    final subForeground = selected
        ? colors.interactiveLow
        : enabled
        ? colors.itemSecondary
        : colors.itemHint;

    Widget tile = CuPressable(
      enabled: enabled,
      selected: selected,
      onTap: onTap,
      onLongTap: onLongPress,
      borderRadius: borderRadius ?? BorderRadius.circular(AppRadius.control),
      padding: padding,
      margin: margin,
      decoration: decoration,
      backgroundColor: backgroundColor ?? Colors.transparent,
      child: IconTheme(
        data: IconTheme.of(context).copyWith(color: foreground),
        child: Row(
          spacing: itemSpacing,
          children: [
            if (leading != null) leading!,
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  if (title != null)
                    DefaultTextStyle(
                      style: textTheme.bodyMedium!.copyWith(color: foreground),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: title!,
                    ),
                  if (subtitle != null)
                    DefaultTextStyle(
                      style: textTheme.bodySmall!.copyWith(
                        color: subForeground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: subtitle!,
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );

    final hintText = hint;
    if (hintText != null) {
      tile = HintLayer(hint: hintText, child: tile);
    }
    return tile;
  }
}
