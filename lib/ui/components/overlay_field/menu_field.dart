import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

import 'popup_overlay.dart';

/// 菜单弹窗 Field：包住目标组件，右键 / 长按在鼠标位置弹出菜单。
///
/// 基于 [PopupOverlay] 实现，默认使用"缩放 + 淡入淡出"动画，
/// 缩放锚点贴近鼠标 / 锚点位置（根据浮层实际方位自动适配）。
class MenuField extends StatefulWidget {
  /// 锚点目标组件：在其上右键 / 长按触发菜单。
  final Widget child;

  /// 菜单内容构建器，[controller] 用于菜单项点击后关闭菜单。
  final List<Widget> Function(
    BuildContext context,
    PopupOverlayController controller,
  )
  menuBuilder;

  /// 外部控制器；为空时内部自动创建并传入 [menuBuilder]。
  final PopupOverlayController? controller;

  /// 是否右键触发（桌面）。
  final bool rightClickTrigger;

  /// 是否长按触发（移动端）。
  final bool longPressTrigger;

  /// 菜单动画。默认为自适应锚点的缩放 + 淡入淡出。
  final PopupOverlayAnimationBuilder? animation;

  /// 位置策略。默认为 [AnchorFlipPositionDelegate]。
  final PopupOverlayPositionDelegate? positionDelegate;

  /// 是否点击菜单外部关闭。
  final bool dismissOnTapOutside;

  /// 是否按 Esc 关闭。
  final bool dismissOnEsc;

  /// 菜单距屏幕边缘的最小安全距离。
  final EdgeInsets screenPadding;

  /// 入场 / 退场动画时长。
  final Duration animationDuration;

  const MenuField({
    super.key,
    required this.child,
    required this.menuBuilder,
    this.controller,
    this.rightClickTrigger = true,
    this.longPressTrigger = true,
    this.animation,
    this.positionDelegate,
    this.dismissOnTapOutside = true,
    this.dismissOnEsc = true,
    this.screenPadding = const EdgeInsets.all(8),
    this.animationDuration = const Duration(milliseconds: 150),
  });

  @override
  State<MenuField> createState() => _MenuFieldState();
}

class _MenuFieldState extends State<MenuField> {
  late final PopupOverlayController _controller =
      widget.controller ?? PopupOverlayController();

  @override
  Widget build(BuildContext context) {
    return PopupOverlay(
      controller: _controller,
      animation: widget.animation ?? _menuScaleFadeAnimation,
      positionDelegate: widget.positionDelegate,
      animationDuration: widget.animationDuration,
      screenPadding: widget.screenPadding,
      dismissOnTapOutside: widget.dismissOnTapOutside,
      dismissOnEsc: widget.dismissOnEsc,
      overlayChildBuilder: (context, anchorRect) => _MenuPanel(
        items: widget.menuBuilder(context, _controller),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: widget.rightClickTrigger
            ? (d) => _controller.open(position: d.localPosition)
            : null,
        onLongPressStart: widget.longPressTrigger
            ? (d) => _controller.open(position: d.localPosition)
            : null,
        child: widget.child,
      ),
    );
  }
}

/// 默认菜单动画：缩放 + 淡入淡出，缩放锚点 = 鼠标在菜单内的位置，
/// 菜单因翻转 / 贴边偏移多远，缩放都从鼠标位置生长。
Widget _menuScaleFadeAnimation(
  BuildContext context,
  Animation<double> animation,
  Widget child,
  PopupOverlayPlacement? placement,
) {
  return ScaleTransition(
    scale: animation,
    alignment: placement?.anchorAlignment ?? Alignment.topLeft,
    child: FadeTransition(opacity: animation, child: child),
  );
}

/// 菜单面板：自研容器（Copper 风格）。
class _MenuPanel extends StatelessWidget {
  final List<Widget> items;

  const _MenuPanel({required this.items});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
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
        children: items,
      ),
    );
  }
}
