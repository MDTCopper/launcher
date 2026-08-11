import 'package:flutter/material.dart';

/// 滑动菜单 Field：child 背面垫一层动作菜单，向左滑动露出（类似手机通知管理）。
///
/// - 向左拖动 child 平移露出右侧 [actions] 菜单，松手后：
///   超过 [openRatio] 保持展开，否则回弹收回
/// - 展开状态下点击 child 收回
/// - 移动端多用（与 [MenuLayer] 的桌面端点开区分）
class ActionSlideLayer extends StatefulWidget {
  final Widget child;
  final List<Widget> actions; // 菜单动作按钮
  final double openRatio; // 保持展开的阈值（0~1，相对菜单宽）
  final Duration animationDuration;
  final Curve curve;

  const ActionSlideLayer({
    super.key,
    required this.child,
    required this.actions,
    this.openRatio = 0.5,
    this.animationDuration = const Duration(milliseconds: 250),
    this.curve = Curves.fastOutSlowIn,
  });

  @override
  State<StatefulWidget> createState() => _ActionSlideLayerState();
}

class _ActionSlideLayerState extends State<ActionSlideLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final GlobalKey _menuKey = GlobalKey();

  double _menuWidth = 0;

  /// 手势累计偏移（负值表示左滑），范围 [-_menuWidth, 0]
  double _dragDistance = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _measureMenu();
  }

  @override
  void didUpdateWidget(covariant ActionSlideLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actions != widget.actions) {
      _measureMenu();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measureMenu() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = _menuKey.currentContext?.size;
      final width = size?.width ?? 0;
      if (width != _menuWidth) {
        setState(() => _menuWidth = width);
      }
    });
  }

  void _close() {
    _animateTo(0);
  }

  void _animateTo(double target) {
    _controller.animateTo(
      target,
      duration: widget.animationDuration,
      curve: widget.curve,
    );
  }

  void _onDragStart(DragStartDetails details) {
    _controller.stop();
    // 从当前展开度开始累计
    _dragDistance = -_menuWidth * _controller.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragDistance = (_dragDistance + details.delta.dx).clamp(-_menuWidth, 0);
    if (_menuWidth > 0) {
      _controller.value = -_dragDistance / _menuWidth;
    }
    setState(() {});
  }

  void _onDragEnd(DragEndDetails details) {
    final shouldOpen = _controller.value > widget.openRatio;
    _animateTo(shouldOpen ? 1 : 0);
  }

  void _onDragCancel() {
    _onDragEnd(DragEndDetails());
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = _controller.value > 0.5;

    return Stack(
      children: [
        // 菜单层：静态垫底，右对齐
        // 用 ClipPath 差集裁剪：child 平移后的区域从菜单层"裁掉"，
        // child 背景透明也不会透出菜单（PS 遮罩思路：child 区域即蒙版）
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final reveal = _menuWidth * _controller.value;
              return ClipPath(
                clipper: _MenuRevealClipper(reveal),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    key: _menuKey,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final action in widget.actions)
                        SizedBox(height: double.infinity, child: action),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // child 层：手势 + 平移露出菜单
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          onTap: isOpen ? _close : null,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-_menuWidth * _controller.value, 0),
                child: child,
              );
            },
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// 菜单层遮罩：把「child 平移后占据的区域」从菜单层裁剪掉（PS 蒙版思路）。
///
/// [reveal] = child 左移距离；差集路径 = 整个区域挖掉 child 区域，
/// child 移开多少，菜单就从右往左露出多少。
class _MenuRevealClipper extends CustomClipper<Path> {
  final double reveal;

  const _MenuRevealClipper(this.reveal);

  @override
  Path getClip(Size size) {
    final stackRect = Offset.zero & size;
    // child 左移 reveal，占据 [−reveal, width−reveal] 区域
    final childRect = Rect.fromLTWH(-reveal, 0, size.width, size.height);
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(stackRect),
      Path()..addRect(childRect),
    );
  }

  @override
  bool shouldReclip(covariant _MenuRevealClipper oldClipper) =>
      oldClipper.reveal != reveal;
}
