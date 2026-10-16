import 'package:flutter/widgets.dart';

/// 菜单条目：用数据描述内容，而不是直接给 Widget
///
/// 面板要先量出完整尺寸才能定位；条目自带尺寸语义，尺寸可算、子菜单锚点也能取
sealed class ContextMenuEntry {
  const ContextMenuEntry();
}

/// 可点击的动作项
class ContextMenuAction extends ContextMenuEntry {
  const ContextMenuAction({
    required this.label,
    this.onSelected,
    this.icon,
    this.leading,
    this.color,
    this.danger = false,
    this.enabled = true,
    this.checked = false,
  });

  final String label;

  /// 点击后的回调；为空即禁用
  final VoidCallback? onSelected;
  final IconData? icon;

  /// 图标槽里的任意组件（品牌图 / 自定义图标…）；给了就优先用它。
  /// 尺寸由 [ContextMenuStyle.iconSize] 定，整条菜单统一，文字才对得齐
  final Widget? leading;

  /// 图标与文字的颜色；不给就按普通项 / [danger] 取
  final Color? color;

  /// 破坏性动作，用 error 色；与 [color] 同时给时以 [color] 为准
  final bool danger;

  /// 显式禁用；[onSelected] 为空时同样不可点
  final bool enabled;

  /// 行尾打勾，用于开关 / 多选类菜单
  final bool checked;

  bool get isEnabled => enabled && onSelected != null;
}

/// 展开下一级的条目
class ContextMenuSubmenu extends ContextMenuEntry {
  const ContextMenuSubmenu({
    required this.label,
    required this.entries,
    this.icon,
    this.leading,
    this.color,
    this.enabled = true,
  });

  final String label;
  final List<ContextMenuEntry> entries;
  final IconData? icon;

  /// 图标槽里的任意组件；给了就优先用它（同 [ContextMenuAction.leading]）
  final Widget? leading;

  /// 图标与文字的颜色；不给就按普通项取
  final Color? color;
  final bool enabled;
}

/// 分组分隔线
class ContextMenuDivider extends ContextMenuEntry {
  const ContextMenuDivider();
}

/// 分组标题，不可点击
class ContextMenuHeader extends ContextMenuEntry {
  const ContextMenuHeader(this.label);

  final String label;
}
