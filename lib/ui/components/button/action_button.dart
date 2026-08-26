import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 带选中态的图标 + 文本按钮
///
/// - 点击切换选中态
/// - 带 [hint] 悬停提示
/// - 有禁用态：[enable] 为 false 时不可点击、无浮出、前景置灰
/// - 双模式背景：暗色玻璃 / 浅色云母片浮动（elevation 阴影不透传）
class ActionButton extends StatefulWidget {
  final IconData icon;
  final String content;
  final String? hint;
  final VoidCallback? onTap;
  final bool selected;
  final bool enable;
  final double hoverElevation;
  final double? pressedScale;
  final Color? backgroundColor; // 按钮所在容器背景，用于混合选中背景色
  final HintPosition hintPosition;

  const ActionButton({
    super.key,
    required this.icon,
    required this.content,
    this.hint,
    this.onTap,

    this.selected = false,
    this.enable = true,
    this.hoverElevation = 2,
    this.pressedScale,
    this.backgroundColor,
    this.hintPosition = HintPosition.auto,
  });

  @override
  State<StatefulWidget> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton>
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
  void didUpdateWidget(covariant ActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    _animateSelected();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateSelected() {
    if (widget.selected) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = widget.backgroundColor ?? colors.cardBackground;
    final enabled = widget.enable;

    final beginBackground = isDark
        ? colors.interactive.withAlpha(0)
        : backgroundColor;
    final endBackground = isDark
        ? colors.interactive.withAlpha(45)
        : Color.alphaBlend(colors.interactive.withAlpha(45), backgroundColor);

    final backgroundT = ColorTween(
      begin: beginBackground,
      // 禁用时背景停在基色，不随选中态变化
      end: enabled ? endBackground : beginBackground,
    ).animate(_controller);
    final foregroundT = ColorTween(
      // 禁用时前景置灰
      begin: enabled ? colors.itemPrimary : colors.itemHint,
      end: enabled ? colors.interactive : colors.itemHint,
    ).animate(_controller);

    Widget child = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final itemColor = foregroundT.value;
        return ReboundContainer(
          pressedScale: widget.pressedScale,
          elevation: 0,
          hoverElevation: enabled ? widget.hoverElevation : 0,
          borderRadius: BorderRadius.circular(4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          backgroundColor: backgroundT.value,
          onTap: enabled ? widget.onTap : null,
          child: IconTheme(
            data: IconTheme.of(context).copyWith(color: itemColor),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon),
                const SizedBox(width: 8),
                Text(
                  widget.content,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: itemColor,
                    fontWeight: widget.selected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (widget.hint != null) {
      child = HintLayer(
        hint: widget.hint,
        preferPosition: widget.hintPosition,
        child: child,
      );
    }
    return child;
  }
}
