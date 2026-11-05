import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';

/// 菜单项：右键菜单与下拉共用
class TemplateMenuItem {
  const TemplateMenuItem({
    required this.label,
    this.icon,
    this.onTap,
    this.danger = false,
    this.checked,
    this.shortcut,
    this.enabled = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  /// 危险项：文字与图标变红（与按钮的 `danger` 标识同一套口径）
  final bool danger;

  /// 复选菜单：true 勾选 / false 未选 / null 不占位
  final bool? checked;

  /// 右侧快捷键提示
  final String? shortcut;
  final bool enabled;
}

/// 弹出右键 / 长按菜单（位置用指针的全局坐标）
///
/// 覆盖度审计 P0-5：现有 App 有 7 处右键菜单，设计层原先没有。
/// 这里用 `showMenu` 拿定位与外部点击关闭，样式全部换成皮肤
Future<void> showTemplateMenu(
  BuildContext context, {
  required TemplateSkin skin,
  required Offset globalPosition,
  required List<TemplateMenuItem> items,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;
  final position = RelativeRect.fromRect(
    Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
    Offset.zero & overlay.size,
  );
  await showMenu<void>(
    context: context,
    position: position,
    color: skin.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(TemplateRadius.card),
      side: BorderSide(color: skin.border),
    ),
    constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
    items: _menuEntries(skin, items),
  );
}

/// 下拉选项
class TemplateDropdownItem<T> {
  const TemplateDropdownItem({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

/// 真下拉：点一下在指针处弹菜单（单选）
///
/// 覆盖度审计 P0-5：`TemplateSelectRow` 原先只是死框，这是能用的那支
class TemplateDropdown<T> extends StatelessWidget {
  const TemplateDropdown({
    super.key,
    required this.skin,
    required this.value,
    required this.items,
    required this.onSelected,
    this.enabled = true,
    this.width,
    this.hint = '请选择',
  });

  final TemplateSkin skin;
  final T? value;
  final List<TemplateDropdownItem<T>> items;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final double? width;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final current = items.where((item) => item.value == value).firstOrNull;
    return SizedBox(
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled
            ? (details) => _open(context, details.globalPosition)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: TemplateSpace.md,
            vertical: TemplateSpace.sm,
          ),
          decoration: BoxDecoration(
            color: enabled ? skin.sunken : skin.standardDisabledSurface,
            borderRadius: BorderRadius.circular(TemplateRadius.control),
            border: Border.all(
              color: enabled ? skin.border : skin.controlBorderDisabled,
            ),
          ),
          child: Row(
            mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
            spacing: TemplateSpace.sm,
            children: [
              if (current?.icon != null)
                Icon(
                  current!.icon,
                  size: 16,
                  color: enabled ? skin.textSecondary : skin.textDisabled,
                ),
              Expanded(
                child: Text(
                  current?.label ?? hint,
                  style: TemplateType.item.copyWith(
                    color: enabled
                        ? (current == null
                              ? skin.textTertiary
                              : skin.textPrimary)
                        : skin.textDisabled,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: enabled ? skin.textTertiary : skin.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, Offset position) async {
    final menuItems = [
      for (final item in items)
        TemplateMenuItem(
          label: item.label,
          icon: item.icon,
          checked: item.value == value,
          onTap: () => onSelected(item.value),
        ),
    ];
    await showTemplateMenu(
      context,
      skin: skin,
      globalPosition: position + const Offset(0, 28),
      items: menuItems,
    );
  }
}

List<PopupMenuEntry<void>> _menuEntries(
  TemplateSkin skin,
  List<TemplateMenuItem> items,
) {
  return [
    for (final item in items)
      PopupMenuItem<void>(
        height: 36,
        padding: EdgeInsets.zero,
        enabled: item.enabled,
        onTap: item.onTap,
        child: _TemplateMenuItemRow(skin: skin, item: item),
      ),
  ];
}

/// 静态菜单面板：样式与 [showTemplateMenu] 弹出的一致，给样张 / 内嵌菜单用
class TemplateMenuPanel extends StatelessWidget {
  const TemplateMenuPanel({
    super.key,
    required this.skin,
    required this.items,
    this.minWidth = 200,
  });

  final TemplateSkin skin;
  final List<TemplateMenuItem> items;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    // 静态面板要有确定宽度：行里的 Expanded 需要有限约束（弹出菜单那条由 showMenu 给）
    return SizedBox(
      width: minWidth,
      child: Container(
        padding: const EdgeInsets.all(TemplateSpace.xs),
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(TemplateRadius.card),
          border: Border.all(color: skin.border),
          boxShadow: [
            BoxShadow(
              color: skin.shadow,
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              ReboundContainer(
                onTap: item.enabled ? item.onTap : null,
                pressedScale: 0.99,
                borderRadius: BorderRadius.circular(TemplateRadius.control),
                hoverColor: skin.hoverOn(skin.surface),
                highlightColor: skin.pressed,
                padding: const EdgeInsets.symmetric(
                  horizontal: TemplateSpace.sm,
                  vertical: TemplateSpace.sm,
                ),
                child: _TemplateMenuItemRow(skin: skin, item: item),
              ),
          ],
        ),
      ),
    );
  }
}

class _TemplateMenuItemRow extends StatelessWidget {
  const _TemplateMenuItemRow({required this.skin, required this.item});

  final TemplateSkin skin;
  final TemplateMenuItem item;

  @override
  Widget build(BuildContext context) {
    final color = !item.enabled
        ? skin.textDisabled
        : item.danger
        ? skin.dangerText
        : skin.textPrimary;
    final iconColor = !item.enabled
        ? skin.textDisabled
        : item.danger
        ? skin.dangerText
        : skin.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TemplateSpace.sm),
      child: Row(
        spacing: TemplateSpace.sm,
        children: [
          SizedBox(
            width: 18,
            child: item.icon == null
                ? null
                : Icon(item.icon, size: 16, color: iconColor),
          ),
          Expanded(
            child: Text(
              item.label,
              style: TemplateType.item.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (item.shortcut != null)
            Text(
              item.shortcut!,
              style: TemplateType.micro.copyWith(color: skin.textTertiary),
            ),
          if (item.checked != null)
            SizedBox(
              width: 16,
              child: item.checked!
                  ? Icon(Icons.check, size: 14, color: skin.accentText)
                  : null,
            ),
        ],
      ),
    );
  }
}
