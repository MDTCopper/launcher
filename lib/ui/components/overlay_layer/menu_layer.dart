import 'dart:math' as math;

import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

import 'popup_overlay.dart';

/// 菜单弹窗 Field：包住目标组件，右键 / 长按在鼠标位置弹出菜单
///
/// 基于 [PopupOverlay] 实现，默认使用"缩放 + 淡入淡出"动画
/// 缩放锚点贴近鼠标 / 锚点位置（根据浮层实际方位自动适配）
class MenuLayer extends StatefulWidget {
  /// 锚点目标组件：在其上右键 / 长按触发菜单
  final Widget child;

  /// 菜单内容构建器，[controller] 用于菜单项点击后关闭菜单
  final List<Widget> Function(
    BuildContext context,
    PopupOverlayController controller,
  )
  menuBuilder;

  /// 外部控制器；为空时内部自动创建并传入 [menuBuilder]
  final PopupOverlayController? controller;

  /// 是否右键触发（桌面）
  final bool rightClickTrigger;

  /// 是否长按触发（移动端）
  final bool longPressTrigger;

  /// 菜单动画。默认为自适应锚点的缩放 + 淡入淡出
  final PopupOverlayAnimationBuilder? animation;

  /// 位置策略。默认为 [AnchorFlipPositionDelegate]
  final PopupOverlayPositionDelegate? positionDelegate;

  /// 是否点击菜单外部关闭。
  final bool dismissOnTapOutside;

  /// 是否按 Esc 关闭。
  final bool dismissOnEsc;

  /// 菜单距屏幕边缘的最小安全距离。
  final EdgeInsets screenPadding;

  /// 入场 / 退场动画时长。
  final Duration animationDuration;

  const MenuLayer({
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
  State<MenuLayer> createState() => _MenuLayerState();
}

class _MenuLayerState extends State<MenuLayer> {
  late final PopupOverlayController _controller =
      widget.controller ?? PopupOverlayController();

  @override
  Widget build(BuildContext context) {
    return PopupOverlay(
      controller: _controller,
      animation: widget.animation ?? _menuScaleFadeAnimation,
      positionDelegate:
          widget.positionDelegate ?? const _MenuPositionDelegate(),
      animationDuration: widget.animationDuration,
      screenPadding: widget.screenPadding,
      dismissOnTapOutside: widget.dismissOnTapOutside,
      dismissOnEsc: widget.dismissOnEsc,
      // 右键菜单：吞掉外部“点击”（左键，不透传、避免关闭误触下层），右键 / 滚动透传
      consumeTapOutside: true,
      overlayChildBuilder: (context, anchorRect) =>
          _MenuPanel(items: widget.menuBuilder(context, _controller)),
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
/// 菜单因翻转 / 贴边偏移多远，缩放都从鼠标位置生长
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
      child: Column(mainAxisSize: MainAxisSize.min, children: items),
    );
  }
}

/// 默认菜单项按钮：图标 + 文本，供 [MenuLayer.menuBuilder] 使用
///
/// [danger] 为 true 时用 error 色
class MenuButton extends StatelessWidget {
  final Icon icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const MenuButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = danger ? colors.error : colors.itemSecondary;
    return SizedBox(
      width: 100,
      child: ReboundButton(
        hoverElevation: 0.0,
        pressedScale: 0.9,
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconTheme.of(context).copyWith(size: 16, color: color),
              child: icon,
            ),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

/// 菜单位置策略：按锚点优先级从鼠标位置生长
///
/// 1. 左上（向右下生长，菜单在鼠标右下）
/// 2. 右上（向左下生长，菜单在鼠标左下）
/// 3. 左下（向右上生长，菜单在鼠标右上）
/// 4. 右下（向左上生长，菜单在鼠标左上）
/// 5/6. 菜单太大（宽或高超屏幕，单侧都放不下）：
///      垂直中点对齐鼠标，水平优先左中（向右），放不下则右中（向左）
class _MenuPositionDelegate extends PopupOverlayPositionDelegate {
  const _MenuPositionDelegate();

  @override
  Offset getPosition({
    required Rect anchorRect,
    required Offset? position,
    required Size overlaySize,
    required Size childSize,
    required EdgeInsets padding,
  }) {
    final anchorOrigin = anchorRect.topLeft;
    // 鼠标在 overlay 中的位置（锚点内偏移，否则锚点右下）
    final mouse = Offset(
      (position?.dx ?? anchorRect.width) + anchorOrigin.dx,
      (position?.dy ?? anchorRect.height) + anchorOrigin.dy,
    );
    final w = childSize.width;
    final h = childSize.height;
    final right = overlaySize.width - padding.right;
    final bottom = overlaySize.height - padding.bottom;

    // 1. 左上：向右下生长（显示在鼠标右下）
    if (mouse.dx + w <= right && mouse.dy + h <= bottom) {
      return Offset(mouse.dx, mouse.dy);
    }
    // 2. 右上：向左下生长（显示在鼠标左下）
    if (mouse.dx - w >= padding.left && mouse.dy + h <= bottom) {
      return Offset(mouse.dx - w, mouse.dy);
    }
    // 3. 左下：向右上生长（显示在鼠标右上）
    if (mouse.dx + w <= right && mouse.dy - h >= padding.top) {
      return Offset(mouse.dx, mouse.dy - h);
    }
    // 4. 右下：向左上生长（显示在鼠标左上）
    if (mouse.dx - w >= padding.left && mouse.dy - h >= padding.top) {
      return Offset(mouse.dx - w, mouse.dy - h);
    }
    // 5/6. 菜单太大（宽或高超屏幕，单侧都放不下）：沉底显示，
    //      水平优先左中（菜单左边缘 = 鼠标，向右展开），
    //      右侧放不下则右中（菜单右边缘 = 鼠标，向左展开）
    var left = mouse.dx;
    if (left + w > right && mouse.dx - w >= padding.left) {
      left = mouse.dx - w;
    }
    final top = bottom - h; // 沉底：菜单底边对齐屏幕底
    left = left
        .clamp(padding.left, math.max(padding.left, right - w))
        .toDouble();
    final clampedTop = top
        .clamp(padding.top, math.max(padding.top, bottom - h))
        .toDouble();

    return Offset(left, clampedTop);
  }

  @override
  bool shouldReposition(PopupOverlayPositionDelegate oldDelegate) =>
      oldDelegate is! _MenuPositionDelegate;
}
