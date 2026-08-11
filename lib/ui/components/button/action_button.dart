import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 带选中态的图标 + 文本按钮。
///
/// - 点击切换选中态（自持状态，按压回弹本身就是视觉反馈）
/// - 尺寸按内容收缩，不撑大父容器
/// - 带 [hint] 悬停提示
/// - 有禁用态：[enable] 为 false 时不可点击、无浮出、前景置灰
/// - 双模式背景：暗色玻璃 / 浅色云母片浮动（elevation 阴影不透传）
class ActionButton extends StatefulWidget {
  final IconData icon;
  final String content;
  final String? hint;
  final VoidCallback? onTap;
  final void Function(bool selected)? onChanged;
  final bool initialSelected;
  final bool enable;
  final double hoverElevation;
  final double? pressedScale;
  final Color? baseColor; // 按钮所在容器背景，用于混合选中背景色
  final HintPosition hintPosition;

  const ActionButton({
    super.key,
    required this.icon,
    required this.content,
    this.hint,
    this.onTap,
    this.onChanged,
    this.initialSelected = false,
    this.enable = true,
    this.hoverElevation = 2,
    this.pressedScale,
    this.baseColor,
    this.hintPosition = HintPosition.auto,
  });

  @override
  State<StatefulWidget> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton>
    with SingleTickerProviderStateMixin {
  late bool _selected;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelected;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (_selected) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant ActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSelected != widget.initialSelected &&
        _selected != widget.initialSelected) {
      _selected = widget.initialSelected;
      _animateSelected();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateSelected() {
    if (_selected) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _toggle() {
    setState(() => _selected = !_selected);
    _animateSelected();
    widget.onTap?.call();
    widget.onChanged?.call(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = widget.baseColor ?? colors.cardBackground;
    final enabled = widget.enable;

    // 双模式设计：
    // - 暗色：玻璃感——真透明背景（能看到底下的背景色），elevation 已由
    //   ReboundContainer 在暗色强制为 0，无阴影透传问题
    // - 浅色：Windows 云母片浮动感——不透明背景（模拟半透明主题色），
    //   hover 浮出 elevation 时阴影不会从背景透传
    final beginBackground = isDark ? Colors.transparent : baseColor;
    final endBackground = isDark
        ? colors.interactive.withAlpha(100)
        : Color.alphaBlend(colors.interactive.withAlpha(100), baseColor);

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
          borderRadius: BorderRadius.circular(8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          backgroundColor: backgroundT.value,
          onTap: enabled ? _toggle : null,
          child: IconTheme(
            data: IconTheme.of(context).copyWith(color: itemColor),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 18),
                const SizedBox(width: 8),
                Text(
                  widget.content,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: itemColor,
                    fontWeight: _selected ? FontWeight.bold : FontWeight.normal,
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
