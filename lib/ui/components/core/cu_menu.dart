import 'package:copper_launcher/ui/components/core/cu_pressable.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
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

/// 图标菜单按钮：点开项目已有的全局右键菜单（[ContextMenu]）
///
/// 行尾「⋯」、目录操作这类轻量菜单用它；菜单本体、定位、动画、外点关闭
/// 全走项目现成的 `CopperContextMenuController`，不再另起一套。
class CuMenuButton extends StatelessWidget {
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

  void _open(BuildContext context) {
    if (!enabled || items.isEmpty) return;
    ContextMenu.showBelow(
      context: context,
      entries: [
        for (final item in items)
          ContextMenuAction(
            label: item.label,
            icon: item.icon,
            danger: item.danger,
            onSelected: item.onSelected,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    Widget button = Builder(
      builder: (context) => CuPressable(
        enabled: enabled,
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: AppIconSize.inline,
            color: colors.itemSecondary,
          ),
        ),
      ),
    );

    final hintText = hint;
    if (hintText != null) {
      button = HintLayer(hint: hintText, child: button);
    }
    return button;
  }
}
