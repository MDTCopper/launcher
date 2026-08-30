import 'package:copper_launcher/ui/components/overlay_layer/action_slide_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/menu_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/popup_overlay.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

/// 组合菜单：把右键 / 长按菜单（[MenuLayer]）与左滑动作菜单（[ActionSlideLayer]）
/// 组合为一个组件，包住 [child]（通常是列表 tile）。
///
/// - 右键（桌面端专属）/ 长按（多端）：弹出 [menuBuilder] 的内容
/// - 左滑：露出 [actions]。是否开启由 [enableSwipe] 决定：
///   null（默认）= 按平台自动（移动端常开，桌面端仅 debug 下可测试）；
///   true / false = 强制开 / 关
class ActionMenu extends StatelessWidget {
  final Widget child;
  final List<Widget> Function(
    BuildContext context,
    PopupOverlayController controller,
  )
  menuBuilder;
  final List<Widget> actions;

  /// 是否开启左滑菜单；null（默认）按平台自动，true / false 强制。
  final bool? enableSwipe;
  final bool rightClickTrigger;
  final bool longPressTrigger;

  const ActionMenu({
    super.key,
    required this.child,
    required this.menuBuilder,
    this.actions = const [],
    this.enableSwipe,
    this.rightClickTrigger = true,
    this.longPressTrigger = true,
  });

  @override
  Widget build(BuildContext context) {
    // 右键 / 长按菜单在内层
    Widget child = MenuLayer(
      rightClickTrigger: rightClickTrigger,
      longPressTrigger: longPressTrigger,
      menuBuilder: menuBuilder,
      child: this.child,
    );

    // 左滑菜单在外层
    final swipe = enableSwipe ?? (isMobile || kDebugMode);
    if (swipe) {
      child = ActionSlideLayer(actions: actions, child: child);
    }

    return child;
  }
}
