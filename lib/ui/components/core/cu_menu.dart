import 'package:copper_launcher/ui/components/core/cu_pressable.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 菜单项
class CuMenuItem {
  const CuMenuItem({
    required this.label,
    required this.onSelected,
    this.icon,
    this.danger = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onSelected;
  final bool danger;
}

/// 图标菜单按钮：点开 [MenuAnchor] 菜单，键盘 / 关闭交给框架
///
/// 行尾「⋯」、目录操作这类轻量菜单用它，不再用一排按钮 + 下拉框。
class CuMenuButton extends StatefulWidget {
  const CuMenuButton({
    super.key,
    required this.items,
    this.icon = Icons.more_horiz,
    this.hint,
    this.enabled = true,
    this.size = AppControlHeight.iconButton,
  });

  final List<CuMenuItem> items;
  final IconData icon;
  final String? hint;
  final bool enabled;
  final double size;

  @override
  State<CuMenuButton> createState() => _CuMenuButtonState();
}

class _CuMenuButtonState extends State<CuMenuButton> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return MenuAnchor(
      controller: _controller,
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
        for (final item in widget.items)
          MenuItemButton(
            onPressed: item.onSelected,
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
                return Colors.transparent;
              }),
              foregroundColor: WidgetStatePropertyAll(
                item.danger ? colors.error : colors.itemPrimary,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.related,
              children: [
                if (item.icon != null)
                  Icon(
                    item.icon,
                    size: AppIconSize.inline,
                    color: item.danger ? colors.error : colors.itemSecondary,
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: item.danger ? colors.error : colors.itemPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      builder: (context, controller, child) => CuPressable(
        enabled: widget.enabled,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Icon(
            widget.icon,
            size: AppIconSize.inline,
            color: colors.itemSecondary,
          ),
        ),
      ),
    );
  }
}
