import 'dart:async';

import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu.dart';
import 'package:flutter/material.dart';

/// 输入框的右键 / 长按菜单：替掉框架那份 Material 灰条，走铜的 [ContextMenu]
///
/// 用法：交给 `TextField.contextMenuBuilder`（`OutlinedTextField` 已默认接上）。
/// 只返回一个空的桥接组件 —— 框架会把它塞进自己的 overlay entry，外面还套一层
/// 淡入与跟随选区的 LayerLink，面板交给全局 [ContextMenu] 画，免得两层淡入叠加
///
/// 剪贴板一律交给框架给的 `onPressed`，它已经处理了 `obscureText` 与剪贴板状态
Widget copperTextContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  // iOS 16+ 有真正的系统菜单，框架默认也走它，换掉会丢能力，所以原样交回去
  if (SystemContextMenu.isSupportedByField(editableTextState)) {
    return SystemContextMenu.editableText(editableTextState: editableTextState);
  }
  return _CopperTextContextMenuBridge(state: editableTextState);
}

/// 只负责「框架弹出 / 收起菜单」与铜面板之间的两条连接，自己不画东西
class _CopperTextContextMenuBridge extends StatefulWidget {
  const _CopperTextContextMenuBridge({required this.state});

  final EditableTextState state;

  @override
  State<_CopperTextContextMenuBridge> createState() =>
      _CopperTextContextMenuBridgeState();
}

class _CopperTextContextMenuBridgeState
    extends State<_CopperTextContextMenuBridge> {
  /// 这一份菜单是第几次 show，用来在自己被销毁时认回「收的是我那份」
  int? _generation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open();
    });
  }

  @override
  void dispose() {
    // 框架自己收了菜单（滚动 / 失焦 / 文本变化）⇒ 铜面板跟着收
    //
    // 不能在 dispose 里直接 dismiss：这时整棵树锁着，markNeedsBuild 会撞断言；
    // 而且期间可能已经切到别的输入框，得靠 generation 认回自己那一份
    final generation = _generation;
    if (generation != null) {
      ContextMenu.controller.dismissUnlessReplaced(generation);
    }
    super.dispose();
  }

  void _open() {
    final entries = _entriesOf(widget.state);
    if (entries.isEmpty) {
      widget.state.hideToolbar();
      return;
    }
    final closed = ContextMenu.show(
      context: context,
      position: widget.state.contextMenuAnchors.primaryAnchor,
      entries: entries,
      positionDelegate: _delegateFor(context),
    );
    _generation = ContextMenu.controller.showGeneration;
    unawaited(
      closed.whenComplete(() {
        // 铜面板收掉之后框架那份也得收：留着它 toolbarIsVisible 还是 true，
        // 下一次右键会被 toggleToolbar() 当成「关」，表现为第一次点了没反应
        if (mounted) widget.state.hideToolbar();
      }),
    );
  }

  /// 判据取 Theme 的 platform 而不是 `dart:io Platform`：输入框是长按出菜单
  /// 还是右键出菜单由框架按平台决定，两边要同一个口径
  ContextMenuPositionDelegate _delegateFor(BuildContext context) {
    final platform = Theme.of(context).platform;
    final isTouch =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    return isTouch
        ? const ContextMenuMobilePosition()
        : const ContextMenuDesktopPosition();
  }

  /// 条目直接照框架给的来：顺序不动、不可用的（`onPressed` 为空）不显示
  List<ContextMenuEntry> _entriesOf(EditableTextState state) {
    final entries = <ContextMenuEntry>[];
    var grouped = false;
    for (final item in state.contextMenuButtonItems) {
      if (item.onPressed == null) continue;
      final isEditAction = switch (item.type) {
        ContextMenuButtonType.cut ||
        ContextMenuButtonType.copy ||
        ContextMenuButtonType.paste => true,
        _ => false,
      };
      // 剪切 / 复制 / 粘贴 算一组，后面那些（全选等）用一条分隔线隔开
      if (!isEditAction && !grouped && entries.isNotEmpty) {
        entries.add(const ContextMenuDivider());
        grouped = true;
      }
      final label = _labelOf(item);
      if (label == null) continue;
      entries.add(
        ContextMenuAction(
          label: label,
          icon: _iconOf(item.type),
          onSelected: item.onPressed,
        ),
      );
    }
    return entries;
  }

  String? _labelOf(ContextMenuButtonItem item) => switch (item.type) {
    ContextMenuButtonType.cut => '剪切',
    ContextMenuButtonType.copy => '复制',
    ContextMenuButtonType.paste => '粘贴',
    ContextMenuButtonType.selectAll => '全选',
    ContextMenuButtonType.delete => '删除',
    ContextMenuButtonType.lookUp => '查询',
    ContextMenuButtonType.searchWeb => '搜索网页',
    ContextMenuButtonType.share => '分享',
    ContextMenuButtonType.liveTextInput => '实况文本',
    // 平台自定义项只有框架给的 label，没有就不显示
    ContextMenuButtonType.custom => item.label,
  };

  IconData? _iconOf(ContextMenuButtonType type) => switch (type) {
    ContextMenuButtonType.cut => Icons.content_cut,
    ContextMenuButtonType.copy => Icons.content_copy,
    ContextMenuButtonType.paste => Icons.content_paste,
    ContextMenuButtonType.selectAll => Icons.select_all,
    ContextMenuButtonType.delete => Icons.backspace_outlined,
    ContextMenuButtonType.lookUp => Icons.search,
    ContextMenuButtonType.searchWeb => Icons.travel_explore,
    ContextMenuButtonType.share => Icons.share_outlined,
    ContextMenuButtonType.liveTextInput => Icons.text_fields,
    ContextMenuButtonType.custom => null,
  };

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
