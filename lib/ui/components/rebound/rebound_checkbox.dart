import 'package:copper_launcher/ui/components/core/copper_checkbox.dart';
import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:flutter/material.dart';

/// copper 风格复选：兼容外壳，内部是 [CopperCheckbox]（方框 + 勾）
///
/// 参数与旧版一致：`label` / `icon` / `hint` / `enable` / `itemColor` 映射到新组件。
class ReboundCheckbox extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChange;
  final EdgeInsets? padding;
  final String? hint;
  final bool enable;
  final double? pressedScale;

  /// 图标着色（未选中时）
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
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return CopperCheckbox(
      value: value,
      label: label,
      icon: icon,
      onChanged: onChange,
      enabled: enable,
      hint: hint,
      iconColor: itemColor,
    );
  }
}

/// 勾选图标切换版复选：未选显示 [icon]（默认 ✕）、选中切换为 [activeIcon]（默认 ✓）
///
/// 与 [ReboundCheckbox] 的区别在内容表现：图标本身随选中态切换（淡入过渡），
/// 适合 trailing 等紧凑场景
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
