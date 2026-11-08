import 'package:copper_launcher/ui/components/core/app_pressable.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 列表项（类似 ListTile）
///
/// - 按压反馈用 [AppPressable]：只变色、不缩放，行间可以安全地加分隔线
/// - 有选中态：[selected] 驱动背景 / 前景的过渡动画（双模式背景同 [ActionButton]）
/// - 有禁用态：[enable] 为 false 时不可点击、前景置灰
/// - 结构：leading / title / subtitle / trailing
class ReboundListTile extends StatefulWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final bool selected;
  final bool enable;

  /// 行底 1px 分隔线；画在行内、不参与任何缩放
  final bool showDivider;

  final Color? baseColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final double itemSpacing;

  /// 保留参数以兼容旧调用点；按压反馈已改为变色，不再缩放
  final double elevation;
  final double hoverElevation;
  final double pressedScale;

  const ReboundListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongTap,
    this.selected = false,
    this.enable = true,
    this.showDivider = false,
    this.baseColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.margin,
    this.borderRadius,
    this.itemSpacing = 8,
    this.elevation = 0,
    this.hoverElevation = 4,
    this.pressedScale = 0.95,
  });

  @override
  State<StatefulWidget> createState() => _ReboundListTileState();
}

class _ReboundListTileState extends State<ReboundListTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (widget.selected) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant ReboundListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      if (widget.selected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = widget.baseColor ?? colors.cardBackground;
    final enabled = widget.enable;

    final endBackground = isDark
        ? colors.interactive.withAlpha(100)
        : Color.alphaBlend(colors.interactive.withAlpha(100), baseColor);
    final backgroundT = ColorTween(
      begin: baseColor,
      end: endBackground,
    ).animate(_controller);

    // 前景：禁用置灰；未选中 itemPrimary → 选中 interactive
    final foregroundT = ColorTween(
      begin: enabled ? colors.itemPrimary : colors.itemHint,
      end: enabled ? colors.interactive : colors.itemHint,
    ).animate(_controller);

    final subForegroundT = ColorTween(
      begin: enabled ? colors.itemSecondary : colors.itemHint,
      end: enabled ? colors.interactiveLow : colors.itemHint,
    ).animate(_controller);

    final tile = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final foreground = foregroundT.value;
        final subForeground = subForegroundT.value;
        return AppPressable(
          enabled: enabled,
          onTap: widget.onTap,
          onLongTap: widget.onLongTap,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
          padding: widget.padding,
          margin: widget.margin,
          backgroundColor: backgroundT.value,
          child: IconTheme(
            data: IconTheme.of(context).copyWith(color: foreground),
            child: Row(
              children: [
                if (widget.leading != null) ...[
                  widget.leading!,
                  SizedBox(width: widget.itemSpacing),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle(
                        style: theme.textTheme.headlineMedium!.copyWith(
                          color: foreground,
                        ),
                        child: widget.title ?? const SizedBox.shrink(),
                      ),
                      if (widget.subtitle != null)
                        DefaultTextStyle(
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: colors.itemSecondary,
                          ),
                          child: IconTheme(
                            data: IconTheme.of(
                              context,
                            ).copyWith(color: subForeground, size: 17),
                            child: widget.subtitle!,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        );
      },
    );

    if (!widget.showDivider) return tile;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        Divider(height: 1, thickness: 1, color: colors.border),
      ],
    );
  }
}
