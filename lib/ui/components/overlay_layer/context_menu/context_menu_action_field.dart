import 'package:copper_launcher/ui/components/overlay_layer/action_slide_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

/// 组合菜单：右键 / 长按出铜菜单（[ContextMenuField]）+ 左滑动作（[ActionSlideLayer]）
///
/// 原 `ActionMenu` 的替代：菜单那半换成新的条目模型
class ContextMenuActionField extends StatelessWidget {
  const ContextMenuActionField({
    super.key,
    required this.child,
    required this.menuBuilder,
    this.actions = const [],
    this.enableSwipe,
    this.rightClickTrigger = true,
    this.longPressTrigger = true,
    this.relocateOnReopen,
    this.positionDelegate,
    this.style = const ContextMenuStyle(),
  });

  final Widget child;

  /// 菜单内容；每次弹出前调用一次
  final List<ContextMenuEntry> Function(BuildContext context) menuBuilder;

  /// 左滑露出的动作
  final List<Widget> actions;

  /// 是否开启左滑；null（默认）按平台自动（移动端常开，桌面端仅 debug 下可测）
  final bool? enableSwipe;
  final bool rightClickTrigger;
  final bool longPressTrigger;

  /// 同级菜单再次出现时，是否让同一个面板移动过去换内容；为空时按宿主设置
  final bool? relocateOnReopen;
  final ContextMenuPositionDelegate? positionDelegate;
  final ContextMenuStyle style;

  @override
  Widget build(BuildContext context) {
    return ActionSlideLayer(
      actions: actions,
      enabled: enableSwipe ?? (isMobile || kDebugMode),
      child: ContextMenuField(
        menuBuilder: menuBuilder,
        rightClickTrigger: rightClickTrigger,
        longPressTrigger: longPressTrigger,
        relocateOnReopen: relocateOnReopen,
        positionDelegate: positionDelegate,
        style: style,
        child: child,
      ),
    );
  }
}
