import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_controller.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_entry.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_panel.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_position.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';

export 'context_menu_action_field.dart';
export 'context_menu_controller.dart';
export 'context_menu_entry.dart';
export 'context_menu_host.dart';
export 'context_menu_panel.dart';
export 'context_menu_position.dart';

/// 右键菜单门面：全局单控制器 + 包裹式触发组件
///
/// 一个应用只该有一个 [GlobalContextMenuController.instance]，所有菜单都从它出去；
/// 页面里包一层 [ContextMenuField] 就能接上右键 / 长按
abstract final class ContextMenu {
  /// 全局单控制器；要手动开菜单 / 判断状态时用它
  static GlobalContextMenuController get controller =>
      GlobalContextMenuController.instance;

  static bool get isShowing => controller.isShowing;

  static int get depth => controller.depth;

  /// 在 [position]（全局坐标，如 `details.globalPosition`）弹出菜单
  static Future<void> show({
    required BuildContext context,
    required Offset position,
    required List<ContextMenuEntry> entries,
    ContextMenuPositionDelegate? positionDelegate,
    bool relocateOnReopen = false,
    ContextMenuStyle style = const ContextMenuStyle(),
  }) {
    return controller.show(
      context: context,
      position: position,
      entries: entries,
      positionDelegate: positionDelegate,
      relocateOnReopen: relocateOnReopen,
      style: style,
    );
  }

  static void dismiss({bool immediate = false}) =>
      controller.dismiss(immediate: immediate);

  /// 在 [context] 所属组件的正下方弹菜单（锚点 = 该组件的左下角）
  ///
  /// 给「点按钮弹菜单」那类用：这种场景拿不到指针位置，只能按组件自己的位置来
  static Future<void> showBelow({
    required BuildContext context,
    required List<ContextMenuEntry> entries,
    ContextMenuPositionDelegate? positionDelegate,
    bool relocateOnReopen = false,
    ContextMenuStyle style = const ContextMenuStyle(),
  }) {
    final box = context.findRenderObject();
    final anchor = box is RenderBox
        ? box.localToGlobal(box.size.bottomLeft(Offset.zero))
        : Offset.zero;
    return show(
      context: context,
      position: anchor,
      entries: entries,
      positionDelegate: positionDelegate,
      relocateOnReopen: relocateOnReopen,
      style: style,
    );
  }
}

/// 菜单触发区：包住目标组件，右键（桌面）或长按（触屏）在这里弹出菜单
///
/// 只管接手势，菜单本身归全局控制器
class ContextMenuField extends StatelessWidget {
  const ContextMenuField({
    super.key,
    required this.child,
    required this.menuBuilder,
    this.rightClickTrigger = true,
    this.longPressTrigger = true,
    this.relocateOnReopen = false,
    this.positionDelegate,
    this.style = const ContextMenuStyle(),
  });

  final Widget child;

  /// 菜单内容；每次弹出前调用一次，条目可以跟着当时的页面状态算
  final List<ContextMenuEntry> Function(BuildContext context) menuBuilder;

  /// 是否右键触发（桌面）
  final bool rightClickTrigger;

  /// 是否长按触发（触屏）
  final bool longPressTrigger;

  /// 同级菜单再次出现时，是否让同一个面板移动过去换内容
  final bool relocateOnReopen;

  /// 位置策略；为空时按平台取
  final ContextMenuPositionDelegate? positionDelegate;

  final ContextMenuStyle style;

  @override
  Widget build(BuildContext context) {
    // 右键用原生 Listener 在 pointer down 当场弹，不用 onSecondaryTapDown：
    // 后者要等抬起或 100ms 超时，那时关闭层早把旧菜单收了，同级菜单接不上
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: rightClickTrigger
          ? (event) {
              if ((event.buttons & kSecondaryButton) == 0) return;
              _open(context, event.position);
            }
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: longPressTrigger
            ? (details) => _open(context, details.globalPosition)
            : null,
        child: child,
      ),
    );
  }

  void _open(BuildContext context, Offset globalPosition) {
    ContextMenu.show(
      context: context,
      position: globalPosition,
      entries: menuBuilder(context),
      positionDelegate: positionDelegate,
      relocateOnReopen: relocateOnReopen,
      style: style,
    );
  }
}
