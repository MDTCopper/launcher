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

  /// 菜单非按钮区域是否拦截事件。
  ///
  /// 为 false（默认）时，菜单露出区域内点击 / 滚动会透传到下层组件；
  /// 为 true 时菜单区域拦截所有事件（按钮仍可点击）。
  final bool blockMenuEvents;

  const ActionSlideLayer({
    super.key,
    required this.child,
    required this.actions,
    this.openRatio = 0.5,
    this.animationDuration = const Duration(milliseconds: 250),
    this.curve = Curves.fastOutSlowIn,
    this.blockMenuEvents = false,
  });

  @override
  State<StatefulWidget> createState() => _ActionSlideLayerState();
}

class _ActionSlideLayerState extends State<ActionSlideLayer>
    with SingleTickerProviderStateMixin {
  /// 展开度控制器（无边界）：正常值 [0,1] 表示展开度；
  /// 拖动过冲时可超出边界（负 = 超过菜单宽，正 = 超过 0），
  /// 松手回弹时由 [animateTo] 平滑滑回边界。
  late final AnimationController _controller;

  final GlobalKey _menuKey = GlobalKey();

  double _menuWidth = 0;

  /// 手势累计偏移（px，负值表示左移）。过冲时可超出
  /// [-_menuWidth, 0]，超出部分带阻尼（橡皮筋手感）。
  double _dragDistance = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(
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
    // 从当前视觉偏移开始累计（含未回弹完的过冲）
    _dragDistance = -_menuWidth * _controller.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final raw = _dragDistance + details.delta.dx;
    final min = -_menuWidth;
    final max = 0.0;
    if (raw < min) {
      // 左过冲：超出部分阻尼 80%，越拖越难
      _dragDistance = min + (raw - min) * 0.9;
    } else if (raw > max) {
      // 右过冲：超出部分阻尼40%
      _dragDistance = raw * 0.4;
    } else {
      _dragDistance = raw;
    }
    if (_menuWidth > 0) {
      // 无边界控制器直接存偏移比例（可超界）
      _controller.value = -_dragDistance / _menuWidth;
    }
    setState(() {});
  }

  void _onDragEnd(DragEndDetails details) {
    final shouldOpen = _controller.value > widget.openRatio;
    // 过冲值由 animateTo 从超界位置平滑滑回边界
    _animateTo(shouldOpen ? 1 : 0);
  }

  void _onDragCancel() {
    _onDragEnd(DragEndDetails());
  }

  /// child 平移偏移（px，负值左移）。过冲时超出边界，由 Stack 裁剪。
  double get _translateOffset => -_menuWidth * _controller.value;

  @override
  Widget build(BuildContext context) {
    final isOpen = _controller.value > 0.5;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // ── child 层：手势 + 平移露出菜单（垫底）──
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
                offset: Offset(_translateOffset, 0),
                child: child,
              );
            },
            child: widget.child,
          ),
        ),
        // ── 菜单层：置顶，保证按钮能收到点击 ──
        // ClipPath 差集把「child 平移后占据的区域」从菜单层裁掉（PS 蒙版思路），
        // child 移开多少，菜单就从右往左露出多少。
        // 非按钮区域默认透传（ClipPath 外不命中，点击/滚动穿到下层）；
        // blockMenuEvents 为 true 时菜单露出区域拦截所有事件。
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // 菜单露出宽度：展开度 clamp 到 [0,1]（过冲不改变菜单宽度）
              final reveal = _menuWidth * _controller.value.clamp(0.0, 1.0);
              return ClipPath(
                clipper: _MenuRevealClipper(reveal),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 背景拦截层：仅当 blockMenuEvents 时拦截露出区域的事件
                    //（在 ClipPath 内，只作用于菜单露出部分，不影响 child 层）
                    if (widget.blockMenuEvents)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _noop,
                        ),
                      ),
                    Align(
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
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

void _noop() {}

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
