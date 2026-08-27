import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:flutter/material.dart';

/// copper 风格复选：基于 [ActionButton] 封装，风格与选中态/禁用态统一
///
/// - [value] 受控选中态(与 ActionButton.selected 同构)
/// - [onChange] 点击回调(传翻转后的值)
/// - [label]/[icon] 映射为 ActionButton 的 content/icon(Widget 形式)
/// - 可选 [hint] 悬停提示、[enable] 禁用态
class ReboundCheckbox extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChange;
  final String? hint;
  final bool enable;
  final double? pressedScale;

  /// 图标着色(未选中时)；ActionButton 选中前景走主题色体系
  final Color? itemColor;

  const ReboundCheckbox({
    super.key,
    required this.value,
    this.icon,
    this.label,
    this.onChange,
    this.hint,
    this.enable = true,
    this.pressedScale,
    this.itemColor,
  });

  @override
  Widget build(BuildContext context) {
    return ActionButton(
      icon: icon == null ? null : Icon(icon, size: 16, color: itemColor),
      content: label == null ? null : Text(label!),
      hint: hint,
      selected: value,
      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      enable: enable,
      onTap: onChange == null ? null : () => onChange!(!value),
      pressedScale: pressedScale,
    );
  }
}

/// 勾选图标切换版复选：未选显示 [icon](默认 ✕)、选中翻转动画切换为 [activeIcon](默认 ✓)。
///
/// 与 [ReboundCheckbox] 的区别在内容表现：这里是图标本身随选中态切换
/// (带旋转 + 淡入动画)，适合 trailing 等紧凑场景；按钮外壳同样走 ActionButton。
class ReboundCheckChangeBox extends StatefulWidget {
  final String? label;
  final bool value;
  final ValueChanged<bool>? onChange;
  final Icon? icon;
  final Icon? activeIcon;
  final String? hint;
  final bool enable;

  const ReboundCheckChangeBox({
    super.key,
    required this.value,
    this.icon,
    this.activeIcon,
    this.label,
    this.onChange,
    this.hint,
    this.enable = true,
  });

  @override
  State<StatefulWidget> createState() => _ReboundCheckChangeBoxState();
}

class _ReboundCheckChangeBoxState extends State<ReboundCheckChangeBox> {
  @override
  Widget build(BuildContext context) {
    final icon = widget.icon ?? const Icon(Icons.close, size: 16);
    final activeIcon = widget.activeIcon ?? const Icon(Icons.check, size: 16);

    // 图标随选中态切换：旋转 + 淡入动画(AnimatedSwitcher)
    final switcherIcon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(
        key: ValueKey(widget.value),
        child: widget.value ? activeIcon : icon,
      ),
    );

    return ActionButton(
      icon: switcherIcon,
      content: widget.label == null ? null : Text(widget.label!),
      padding: const EdgeInsets.all(8),
      hint: widget.hint,
      selected: widget.value,
      enable: widget.enable,
      onTap: widget.onChange == null
          ? null
          : () => widget.onChange!(!widget.value),
    );
  }
}
