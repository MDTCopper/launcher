import 'package:copper_launcher/ui/components/core/cu_pressable.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 下拉选项
class CuSelectOption<T> {
  const CuSelectOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// 内核下拉选择：锚点按钮 + 弹出菜单（用 Flutter [MenuAnchor] 管键盘 / 关闭）
///
/// 视觉吃 `AppColors`：锚点 = 输入面 + 描边，菜单 = 卡片底 + 1px 描边，
/// 选项 hover 只换底色（不做隐式颜色插值）。
class CuSelect<T> extends StatefulWidget {
  const CuSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hint = '请选择',
    this.enabled = true,
    this.expanded = false,
    this.leading,
  });

  final List<CuSelectOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String hint;
  final bool enabled;

  /// 撑满可用宽度
  final bool expanded;

  /// 锚点左侧图标
  final Widget? leading;

  @override
  State<CuSelect<T>> createState() => _CuSelectState<T>();
}

class _CuSelectState<T> extends State<CuSelect<T>> {
  final _controller = MenuController();

  CuSelectOption<T>? get _selected {
    for (final option in widget.options) {
      if (option.value == widget.value) return option;
    }
    return null;
  }

  Widget _label(
    AppColors colors,
    TextTheme textTheme,
    CuSelectOption<T>? selected,
  ) {
    return Text(
      selected?.label ?? widget.hint,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.bodyMedium?.copyWith(
        color: selected == null
            ? colors.itemHint
            : widget.enabled
            ? colors.itemPrimary
            : colors.itemHint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final selected = _selected;

    final anchor = CuPressable(
      enabled: widget.enabled,
      onTap: () =>
          _controller.isOpen ? _controller.close() : _controller.open(),
      borderRadius: BorderRadius.circular(AppRadius.control),
      decoration: BoxDecoration(
        color: widget.enabled
            ? colors.inputBackground
            : colors.lowBackgroundOnCard,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: widget.enabled
              ? colors.contentBorder
              : colors.lowBackgroundOnCard,
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.related,
        vertical: AppSpacing.related - 2,
      ),
      child: Row(
        mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
        spacing: AppSpacing.related,
        children: [
          if (widget.leading != null) widget.leading!,
          if (selected?.icon != null)
            Icon(
              selected!.icon,
              size: AppIconSize.inline,
              color: colors.itemSecondary,
            ),
          if (widget.expanded)
            Expanded(child: _label(colors, textTheme, selected))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: _label(colors, textTheme, selected),
            ),
          Icon(
            Icons.keyboard_arrow_down,
            size: AppIconSize.inline,
            color: colors.itemHint,
          ),
        ],
      ),
    );

    final content = Row(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [widget.expanded ? Expanded(child: anchor) : anchor],
    );

    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.cardBackground),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(4),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: AppSpacing.tight),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.item),
            side: BorderSide(color: colors.border),
          ),
        ),
      ),
      menuChildren: [
        for (final option in widget.options)
          MenuItemButton(
            onPressed: () => widget.onChanged(option.value),
            style: ButtonStyle(
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(
                  horizontal: AppSpacing.group,
                  vertical: AppSpacing.related,
                ),
              ),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return colors.highBackgroundOnCard;
                }
                if (option.value == widget.value) {
                  return colors.indicatorBackground;
                }
                return Colors.transparent;
              }),
              foregroundColor: WidgetStatePropertyAll(colors.itemPrimary),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.related,
              children: [
                if (option.icon != null)
                  Icon(
                    option.icon,
                    size: AppIconSize.inline,
                    color: colors.itemSecondary,
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.itemPrimary,
                    ),
                  ),
                ),
                if (option.value == widget.value)
                  Icon(
                    Icons.check,
                    size: AppIconSize.inline,
                    color: colors.interactive,
                  ),
              ],
            ),
          ),
      ],
      builder: (context, controller, child) => content,
    );
  }
}
