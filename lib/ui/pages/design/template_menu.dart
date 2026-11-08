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
    elevation: 8,
    shadowColor: Colors.black,
    surfaceTintColor: Colors.transparent,
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

/// 真下拉：点一下弹出选项面板（单选）
///
/// 2026-11-08：**下拉风格统一**——单选 / 多选 / 右键菜单面板共用一套
/// （面板 `_PopupPanel`：12 圆角 + 1px 边 + 黑 30 投影；行 `_PopupRow`：32 高、圆角 8、
/// 图标 16、行尾 16 宽勾选槽；触发器 `_DropdownTrigger`：凹槽底 + 控件圆角）
class TemplateDropdown<T> extends StatefulWidget {
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
  State<TemplateDropdown<T>> createState() => _TemplateDropdownState<T>();
}

class _TemplateDropdownState<T> extends State<TemplateDropdown<T>> {
  final _link = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _toggle() {
    if (_entry != null) {
      _removeOverlay();
      return;
    }
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_entry!);
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  Widget _buildOverlay(BuildContext context) {
    final skin = widget.skin;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _removeOverlay,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: const Offset(0, 34),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: widget.width,
              child: _PopupPanel(
                skin: skin,
                minWidth: widget.width ?? 180,
                children: [
                  for (final item in widget.items)
                    _PopupRow(
                      skin: skin,
                      icon: item.icon,
                      label: item.label,
                      checked: item.value == widget.value,
                      onTap: () {
                        _removeOverlay();
                        widget.onSelected(item.value);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final current = widget.items
        .where((item) => item.value == widget.value)
        .firstOrNull;
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => _toggle() : null,
        child: _DropdownTrigger(
          skin: skin,
          width: widget.width,
          enabled: widget.enabled,
          icon: current?.icon,
          label: current?.label ?? widget.hint,
          muted: current == null,
        ),
      ),
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
        void toggle(T value) {
          final next = Set<T>.of(widget.values);
          if (!next.remove(value)) next.add(value);
          widget.onChanged(next);
          setPanelState(() {});
        }

        void selectAllOrClear() {
          widget.onChanged(
            widget.values.length == widget.items.length
                ? <T>{}
                : widget.items.map((e) => e.value).toSet(),
          );
          setPanelState(() {});
        }

        return SizedBox(
          width: widget.width,
          child: _PopupPanel(
            skin: skin,
            minWidth: widget.width,
            children: [
              // 头部：已选数量 + 全选/清除（与行同内衬，像一个操作条）
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
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: selectAllOrClear,
                      child: Text(
                        widget.values.length == widget.items.length
                            ? '清除'
                            : '全选',
                        style: TemplateType.micro.copyWith(
                          color: skin.accentText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: skin.border),
              for (final item in widget.items)
                _PopupRow(
                  skin: skin,
                  icon: item.icon,
                  label: item.label,
                  checked: widget.values.contains(item.value),
                  onTap: () => toggle(item.value),
                ),
            ],
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
        child: _DropdownTrigger(
          skin: skin,
          width: widget.width,
          enabled: widget.enabled,
          label: hasValue ? '已选 ${widget.values.length} 项' : widget.hint,
          muted: !hasValue,
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
        child: _PopupRow(
          skin: skin,
          icon: item.icon,
          label: item.label,
          checked: item.checked,
          danger: item.danger,
          enabled: item.enabled,
          onTap: item.onTap,
        ),
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
    // 与下拉面板同一套（_PopupPanel / _PopupRow），保证「菜单 / 下拉」风格一致
    return SizedBox(
      width: minWidth,
      child: _PopupPanel(
        skin: skin,
        minWidth: minWidth,
        children: [
          for (final item in items) ...[
            if (item.dividerBefore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: TemplateSpace.xs),
                child: Container(height: 1, color: skin.border),
              ),
            _PopupRow(
              skin: skin,
              icon: item.icon,
              label: item.label,
              shortcut: item.shortcut,
              checked: item.checked,
              danger: item.danger,
              enabled: item.enabled,
              onTap: item.onTap,
            ),
          ],
        ],
      ),
    );
  }
}

/// 统一的弹出面板：右键菜单 / 单选下拉 / 多选下拉共用
///
/// 12 圆角 + 1px 边 + 黑 30 投影，内衬 4（与 App 的 `ContextMenuPanel` 一致）
class _PopupPanel extends StatelessWidget {
  const _PopupPanel({
    required this.skin,
    required this.children,
    required this.minWidth,
  });

  final TemplateSkin skin;
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    // Overlay 里的面板不在任何 Material 下面，DefaultTextStyle 没带主题字体
    // （测试里就会掉回 Roboto → 中文变方块）；这里用 Material 把主题文字样式补上
    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: BoxConstraints(minWidth: minWidth, maxWidth: 320),
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
          children: children,
        ),
      ),
    );
  }
}

/// 统一的面板行：32 高、圆角 8、图标 16、行尾 16 宽槽（勾选 / 快捷键）
class _PopupRow extends StatelessWidget {
  const _PopupRow({
    required this.skin,
    required this.label,
    required this.onTap,
    this.icon,
    this.checked,
    this.shortcut,
    this.danger = false,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool? checked;
  final String? shortcut;
  final bool danger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? skin.textDisabled
        : danger
        ? skin.dangerText
        : skin.textSecondary;
    return SizedBox(
      height: 32,
      child: ReboundContainer(
        onTap: enabled ? onTap : null,
        pressedScale: 0.98,
        borderRadius: BorderRadius.circular(8),
        backgroundColor: Colors.transparent,
        hoverColor: skin.hoverOn(skin.surface),
        highlightColor: skin.pressed,
        padding: const EdgeInsets.symmetric(horizontal: TemplateSpace.sm),
        child: Row(
          spacing: TemplateSpace.sm,
          children: [
            SizedBox(
              width: 16,
              child: icon == null ? null : Icon(icon, size: 16, color: color),
            ),
            Expanded(
              child: Text(
                label,
                style: TemplateType.item.copyWith(color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (shortcut != null)
              Text(
                shortcut!,
                style: TemplateType.micro.copyWith(color: skin.textTertiary),
              ),
            // 行尾槽固定 16 宽：勾 / 箭头都钉在同一列
            SizedBox(
              width: 16,
              child: checked == true
                  ? Icon(Icons.check, size: 16, color: skin.accentText)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 统一的触发器（下拉按钮壳）：凹槽底 + 控件圆角 + 1px 边 + 右侧小箭头
class _DropdownTrigger extends StatelessWidget {
  const _DropdownTrigger({
    required this.skin,
    required this.label,
    required this.enabled,
    this.muted = false,
    this.icon,
    this.width,
  });

  final TemplateSkin skin;
  final String label;
  final bool enabled;

  /// 占位文案（未选值）时字色降一档
  final bool muted;
  final IconData? icon;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
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
          if (icon != null)
            Icon(
              icon,
              size: 16,
              color: enabled ? skin.textSecondary : skin.textDisabled,
            ),
          Expanded(
            child: Text(
              label,
              style: TemplateType.item.copyWith(
                color: !enabled
                    ? skin.textDisabled
                    : muted
                    ? skin.textTertiary
                    : skin.textPrimary,
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
    );
  }
}
