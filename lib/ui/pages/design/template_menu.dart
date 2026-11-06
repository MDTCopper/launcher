import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';

/// 菜单项：右键菜单与下拉共用
///
/// 样式对齐当前 App 的 `ContextMenuPanel`：面板 12 圆角 + 1px 边 + 投影，
/// 条目高 32、图标槽 16、左右内衬 8、条目圆角 8
class TemplateMenuItem {
  const TemplateMenuItem({
    required this.label,
    this.icon,
    this.onTap,
    this.danger = false,
    this.checked,
    this.shortcut,
    this.enabled = true,
    this.dividerBefore = false,
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

  /// 在这一项前面画一条分隔线
  final bool dividerBefore;
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
      borderRadius: BorderRadius.circular(12),
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

/// 多选下拉：点开面板可以连续勾选，带「全选 / 清除」；点外部关闭
///
/// 单选走 [TemplateDropdown]（`showMenu` 一次性弹）；多选要留在面板里反复点，
/// 所以这里自己开一层 Overlay，勾选状态由面板自己维护
class TemplateMultiDropdown<T> extends StatefulWidget {
  const TemplateMultiDropdown({
    super.key,
    required this.skin,
    required this.values,
    required this.items,
    required this.onChanged,
    this.width = 240,
    this.hint = '请选择',
    this.enabled = true,
  });

  final TemplateSkin skin;
  final Set<T> values;
  final List<TemplateDropdownItem<T>> items;
  final ValueChanged<Set<T>> onChanged;
  final double width;
  final String hint;
  final bool enabled;

  @override
  State<TemplateMultiDropdown<T>> createState() =>
      _TemplateMultiDropdownState<T>();
}

class _TemplateMultiDropdownState<T> extends State<TemplateMultiDropdown<T>> {
  final _link = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _toggle() {
    if (_entry != null) {
      _close();
      return;
    }
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  Widget _buildOverlay(BuildContext context) {
    final skin = widget.skin;
    return Stack(
      children: [
        // 点外部关闭
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: Offset(0, 30),
          child: Align(alignment: Alignment.topLeft, child: _buildPanel(skin)),
        ),
      ],
    );
  }

  Widget _buildPanel(TemplateSkin skin) {
    // 面板内部自己 setState：外层 Select 的选中集合通过 onChanged 回写
    return StatefulBuilder(
      builder: (context, setPanelState) {
        Widget row({
          required String label,
          IconData? icon,
          bool? checked,
          required VoidCallback onTap,
        }) {
          return ReboundContainer(
            onTap: onTap,
            pressedScale: 0.99,
            borderRadius: BorderRadius.circular(TemplateRadius.control),
            backgroundColor: Colors.transparent,
            hoverColor: skin.hoverOn(skin.surface),
            highlightColor: skin.pressed,
            padding: const EdgeInsets.symmetric(
              horizontal: TemplateSpace.sm,
              vertical: TemplateSpace.sm,
            ),
            child: Row(
              spacing: TemplateSpace.sm,
              children: [
                SizedBox(
                  width: 18,
                  child: icon == null
                      ? null
                      : Icon(icon, size: 16, color: skin.textSecondary),
                ),
                Expanded(
                  child: Text(
                    label,
                    style: TemplateType.item.copyWith(color: skin.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (checked != null)
                  SizedBox(
                    width: 16,
                    child: checked
                        ? Icon(Icons.check, size: 14, color: skin.accentText)
                        : null,
                  ),
              ],
            ),
          );
        }

        return SizedBox(
          width: widget.width,
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TemplateSpace.sm,
                    vertical: TemplateSpace.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已选 ${widget.values.length} 项',
                          style: TemplateType.micro.copyWith(
                            color: skin.textTertiary,
                          ),
                        ),
                      ),
                      Text(
                        '全选',
                        style: TemplateType.micro.copyWith(
                          color: skin.accentText,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final item in widget.items)
                  row(
                    label: item.label,
                    icon: item.icon,
                    checked: widget.values.contains(item.value),
                    onTap: () {
                      final next = Set<T>.of(widget.values);
                      if (!next.remove(item.value)) next.add(item.value);
                      widget.onChanged(next);
                      setPanelState(() {});
                    },
                  ),
                Container(height: 1, color: skin.border),
                row(
                  label: '全选 / 清除',
                  icon: Icons.checklist,
                  onTap: () {
                    widget.onChanged(
                      widget.values.length == widget.items.length
                          ? <T>{}
                          : widget.items.map((e) => e.value).toSet(),
                    );
                    setPanelState(() {});
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final hasValue = widget.values.isNotEmpty;
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => _toggle() : null,
        child: Container(
          width: widget.width,
          padding: const EdgeInsets.symmetric(
            horizontal: TemplateSpace.md,
            vertical: TemplateSpace.sm,
          ),
          decoration: BoxDecoration(
            color: widget.enabled ? skin.sunken : skin.standardDisabledSurface,
            borderRadius: BorderRadius.circular(TemplateRadius.control),
            border: Border.all(
              color: widget.enabled ? skin.border : skin.controlBorderDisabled,
            ),
          ),
          child: Row(
            spacing: TemplateSpace.sm,
            children: [
              Expanded(
                child: Text(
                  hasValue ? '已选 ${widget.values.length} 项' : widget.hint,
                  style: TemplateType.item.copyWith(
                    color: !widget.enabled
                        ? skin.textDisabled
                        : (hasValue ? skin.textPrimary : skin.textTertiary),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: widget.enabled ? skin.textTertiary : skin.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<PopupMenuEntry<void>> _menuEntries(
  TemplateSkin skin,
  List<TemplateMenuItem> items,
) {
  return [
    for (final item in items) ...[
      if (item.dividerBefore)
        PopupMenuItem<void>(
          height: 9,
          padding: EdgeInsets.zero,
          enabled: false,
          child: Center(child: Container(height: 1, color: skin.border)),
        ),
      PopupMenuItem<void>(
        height: 32,
        padding: EdgeInsets.zero,
        enabled: item.enabled,
        onTap: item.onTap,
        child: _TemplateMenuItemRow(skin: skin, item: item),
      ),
    ],
  ];
}

/// 静态菜单面板：样式与 [showTemplateMenu] 弹出的一致，给样张 / 内嵌菜单用
///
/// 照当前 App 的 `ContextMenuPanel` 取：卡面 + 12 圆角 + 1px 边 + 黑 30 投影，
/// 内衬 4，条目 32 高、圆角 8
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: skin.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items) ...[
              if (item.dividerBefore)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: TemplateSpace.xs,
                  ),
                  child: Container(height: 1, color: skin.border),
                ),
              SizedBox(
                height: 32,
                child: ReboundContainer(
                  onTap: item.enabled ? item.onTap : null,
                  pressedScale: 0.98,
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: Colors.transparent,
                  hoverColor: skin.hoverOn(skin.surface),
                  highlightColor: skin.pressed,
                  padding: const EdgeInsets.symmetric(
                    horizontal: TemplateSpace.sm,
                  ),
                  child: _TemplateMenuItemRow(skin: skin, item: item),
                ),
              ),
            ],
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
        : skin.textSecondary;
    return Row(
      spacing: TemplateSpace.sm,
      children: [
        SizedBox(
          width: 16,
          child: item.icon == null
              ? null
              : Icon(item.icon, size: 16, color: color),
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
        // 行尾槽固定 16 宽：勾 / 箭头都钉在同一列
        SizedBox(
          width: 16,
          child: item.checked == true
              ? Icon(Icons.check, size: 16, color: skin.accentText)
              : null,
        ),
      ],
    );
  }
}
