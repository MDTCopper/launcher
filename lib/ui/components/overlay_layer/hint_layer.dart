import 'dart:async';

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/material.dart';

import 'popup_overlay.dart';

// ---------------------------------------------------------------------------
// HintPosition
// ---------------------------------------------------------------------------

enum HintPosition { top, bottom, left, right, auto }

// ---------------------------------------------------------------------------
// HintAnimation
// ---------------------------------------------------------------------------

/// 入场 / 退场动画定义。
///
/// 内置预设：[HintAnimation.fade]、[HintAnimation.scale]、[HintAnimation.slide]。
/// [scale] 和 [slide] 会根据提示框的[实际方位][HintPosition]自适应锚点和方向。
class HintAnimation {
  final Widget Function(
    BuildContext context,
    Animation<double> animation,
    Widget child,
    HintPosition position,
  )
  builder;

  const HintAnimation(this.builder);

  // ---- 预设 ----

  static const fade = HintAnimation(_fadeBuilder);
  static const scale = HintAnimation(_scaleBuilder);
  static const slide = HintAnimation(_slideBuilder);

  static Widget _fadeBuilder(
    BuildContext c,
    Animation<double> a,
    Widget w,
    HintPosition p,
  ) {
    return FadeTransition(opacity: a, child: w);
  }

  static Widget _scaleBuilder(
    BuildContext c,
    Animation<double> a,
    Widget w,
    HintPosition p,
  ) {
    return ScaleTransition(
      scale: a,
      alignment: _scaleAlignment(p),
      child: FadeTransition(opacity: a, child: w),
    );
  }

  static Widget _slideBuilder(
    BuildContext c,
    Animation<double> a,
    Widget w,
    HintPosition p,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: _slideOffset(p),
        end: Offset.zero,
      ).animate(a),
      child: FadeTransition(opacity: a, child: w),
    );
  }

  static Alignment _scaleAlignment(HintPosition pos) {
    switch (pos) {
      case HintPosition.top:
        return Alignment.bottomCenter;
      case HintPosition.bottom:
        return Alignment.topCenter;
      case HintPosition.left:
        return Alignment.centerRight;
      case HintPosition.right:
        return Alignment.centerLeft;
      case HintPosition.auto:
        return Alignment.center;
    }
  }

  static Offset _slideOffset(HintPosition pos) {
    switch (pos) {
      case HintPosition.top:
        return const Offset(0, 0.3);
      case HintPosition.bottom:
        return const Offset(0, -0.3);
      case HintPosition.left:
        return const Offset(0.3, 0);
      case HintPosition.right:
        return const Offset(-0.3, 0);
      case HintPosition.auto:
        return Offset.zero;
    }
  }
}

// ---------------------------------------------------------------------------
// HintLayer
// ---------------------------------------------------------------------------

class HintLayer extends StatefulWidget {
  final Widget child;

  /// 纯文本提示内容，与 [hintWidget] 二选一
  final String? hint;

  /// 自定义组件提示，与 [hint] 二选一，同时提供时优先使用。
  final Widget? hintWidget;

  /// 优先显示方位。[HintPosition.auto] 时桌面端依次尝试上→下→左→右，
  /// 移动端根据组件相对屏幕中心的位置智能排序。
  final HintPosition preferPosition;

  /// 长按触发后自动消失的时长。hover 模式忽略，移出即消失。
  final Duration showDuration;

  /// 悬停 / 长按后，提示框出现前的等待时长。
  final Duration waitDuration;

  /// 共享 waitDuration 的分组 id：同 id 的 hint 共享"跳过等待"计时，
  /// **不同 id 互不共享**（例如页面 hint 与菜单栏 hint 用不同 id，互不干扰）。
  /// `null` 时归入默认组。
  final String? id;

  /// 提示框消失后，等待重置间隔。在此间隔内悬停另一个组件可跳过 [waitDuration]。
  /// `null` 时默认等于 [animationDuration]。
  final Duration? waitResetDuration;

  /// 入场 / 退场动画的播放时长。
  final Duration animationDuration;

  /// 入场动画。内置 [HintAnimation.fade]、[HintAnimation.scale]、[HintAnimation.slide]。
  final HintAnimation showAnimation;

  /// 退场动画。`null` 时默认与 [showAnimation] 相同。
  final HintAnimation? hideAnimation;

  /// 提示框与子组件的间距（像素）。
  final double gap;

  /// 提示框距屏幕四边的最小安全距离，防止贴边。
  final EdgeInsets screenPadding;

  /// 提示框最大宽度。`null` 时默认为屏幕宽度的 1/3，文本超出自动换行。
  final double? maxWidth;

  // ---- 纯文本模式专用样式 ----

  /// 纯文本提示的内边距。
  final EdgeInsets padding;

  /// 纯文本提示的容器装饰。`null` 时使用默认样式。
  final BoxDecoration? decoration;

  /// 纯文本提示的文字样式。`null` 时使用主题的 [TextTheme.labelMedium]。
  final TextStyle? textStyle;

  // ---- 静态协调（按分组 id 隔离"跳过等待"计时，避免页面 / 菜单栏互串）----
  static HintLayerState? _activeHint;
  static final Map<String, DateTime> _lastShowTime = {};
  static final Map<String, DateTime> _lastDismissTime = {};

  /// 默认分组：未指定 id 的 hint 归入此组（彼此共享，同旧全局行为）。
  static const String defaultGroup = 'default';

  const HintLayer({
    super.key,
    required this.child,
    this.hint,
    this.hintWidget,
    this.preferPosition = HintPosition.auto,
    this.showDuration = const Duration(seconds: 2),
    this.waitDuration = const Duration(milliseconds: 800),
    this.waitResetDuration,
    this.id,
    this.animationDuration = const Duration(milliseconds: 200),
    this.showAnimation = HintAnimation.scale,
    this.hideAnimation,
    this.gap = 4.0,
    this.screenPadding = const EdgeInsets.all(8.0),
    this.maxWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
    this.decoration,
    this.textStyle,
  });

  @override
  State<HintLayer> createState() => HintLayerState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class HintLayerState extends State<HintLayer> {
  final PopupOverlayController _popupController = PopupOverlayController();

  /// 实际显示方位，由环绕定位在布局阶段确定，供动画接口使用。
  final ValueNotifier<HintPosition?> _actualPosition = ValueNotifier(null);

  Timer? _waitTimer;
  Timer? _dismissTimer;

  bool _disposed = false;
  bool _isLongPressing = false;
  bool _isShowing = false;

  @override
  void didUpdateWidget(HintLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hint != oldWidget.hint) {
      // 文本变化时无需预测量（尺寸由布局管道提供），仅触发重建
    }
  }

  double _effectiveMaxWidth() {
    if (widget.maxWidth != null) return widget.maxWidth!;
    return MediaQuery.of(context).size.width / 3;
  }

  @override
  void dispose() {
    _disposed = true;
    _dismiss(immediate: true);
    _waitTimer?.cancel();
    _dismissTimer?.cancel();
    _actualPosition.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child;

    if (isDesktop) {
      child = MouseRegion(
        onEnter: _onMouseEnter,
        onExit: _onMouseExit,
        child: child,
      );
    } else {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: _onLongPressStart,
        onLongPressEnd: _onLongPressEnd,
        onLongPressCancel: _onLongPressCancel,
        child: child,
      );
    }

    return PopupOverlay(
      controller: _popupController,
      animation: _buildHintAnimation,
      positionDelegate: _HintPositionDelegate(
        preferPosition: widget.preferPosition,
        gap: widget.gap,
        onPositioned: (pos) => _actualPosition.value = pos,
      ),
      // 提示框不拦截点击、不响应 Esc（与原行为一致）
      dismissOnTapOutside: false,
      dismissOnEsc: false,
      // 锚点移动自动关闭等外部关闭时同步自身状态（防止 _isShowing 卡死）
      onClose: _onPopupClosed,
      screenPadding: widget.screenPadding,
      animationDuration: widget.animationDuration,
      overlayChildBuilder: _buildHintOverlayChild, // (context, anchorRect)
      child: child,
    );
  }

  Widget _buildHintOverlayChild(BuildContext context, Rect anchorRect) {
    final Widget content = widget.hintWidget ?? _buildTextHint();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _effectiveMaxWidth()),
      child: content,
    );
  }

  Widget _buildTextHint() {
    final color = AppColors.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: widget.padding,
      decoration:
          widget.decoration ??
          BoxDecoration(
            color: color.cardBackground.withAlpha(185),
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            border: Border.all(color: color.border),
          ),
      child: Text(
        widget.hint!,
        style: widget.textStyle ?? theme.textTheme.labelMedium,
      ),
    );
  }

  /// 动画适配：把 PopupOverlay 的动画流转接给 [HintAnimation]，
  /// 实际方位由环绕定位在布局阶段确定后传入。
  Widget _buildHintAnimation(
    BuildContext context,
    Animation<double> animation,
    Widget child,
    PopupOverlayPlacement? placement,
  ) {
    final pos = _actualPosition.value ?? HintPosition.auto;
    final anim = _isShowing
        ? widget.showAnimation
        : (widget.hideAnimation ?? widget.showAnimation);
    return anim.builder(context, animation, child, pos);
  }

  // ------------------------------------------------------------------
  // Triggers
  // ------------------------------------------------------------------

  void _onMouseEnter(PointerEvent event) => _requestShow();
  void _onMouseExit(PointerEvent event) => _dismiss();

  void _onLongPressStart(LongPressStartDetails d) {
    _isLongPressing = true;
    _requestShow();
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    _isLongPressing = false;
    _dismiss();
  }

  void _onLongPressCancel() {
    _isLongPressing = false;
    _dismiss();
  }

  // ------------------------------------------------------------------
  // Show / Dismiss
  // ------------------------------------------------------------------

  void _requestShow() {
    if (widget.hint == null && widget.hintWidget == null) return;
    if (HintLayer._activeHint != null && HintLayer._activeHint != this) {
      HintLayer._activeHint!._dismiss(immediate: true);
    }

    if (_isShowing) return;

    HintLayer._activeHint = this;

    final Duration resetWindow =
        widget.waitResetDuration ?? widget.animationDuration;
    // 只读取本分组的最近事件，避免与其它 id 的 hint 互串"跳过等待"
    final String group = widget.id ?? HintLayer.defaultGroup;
    final DateTime? lastEvent = HintLayer._lastDismissTime[group] ??
        HintLayer._lastShowTime[group];
    final bool skipWait =
        lastEvent != null && DateTime.now().difference(lastEvent) < resetWindow;

    _waitTimer?.cancel();
    if (skipWait) {
      _show();
    } else {
      _waitTimer = Timer(widget.waitDuration, _show);
    }
  }

  void _show() {
    if (!mounted || _isShowing) return;

    _isShowing = true;
    HintLayer._lastShowTime[widget.id ?? HintLayer.defaultGroup] =
        DateTime.now();
    if (mounted) setState(() {});
    _popupController.open();

    if (_isLongPressing) {
      _dismissTimer?.cancel();
      _dismissTimer = Timer(widget.showDuration, _dismiss);
    }
  }

  void _dismiss({bool immediate = false}) {
    _waitTimer?.cancel();
    _dismissTimer?.cancel();
    final bool wasVisible = _isShowing;
    _isShowing = false;
    if (mounted && !_disposed) setState(() {});

    if (wasVisible) {
      HintLayer._lastDismissTime[widget.id ?? HintLayer.defaultGroup] =
          DateTime.now();
    }

    if (HintLayer._activeHint == this) {
      HintLayer._activeHint = null;
    }

    _popupController.dismiss(immediate: immediate);
  }

  /// 浮层被外部机制关闭（锚点移动自动关闭 / 点击外部等）时同步自身状态，
  /// 避免 `_isShowing` 卡在 true 导致后续无法重新显示。
  void _onPopupClosed() {
    if (_disposed) return;
    _waitTimer?.cancel();
    _dismissTimer?.cancel();
    final bool wasVisible = _isShowing;
    _isShowing = false;
    if (wasVisible) {
      HintLayer._lastDismissTime[widget.id ?? HintLayer.defaultGroup] =
          DateTime.now();
    }
    if (HintLayer._activeHint == this) {
      HintLayer._activeHint = null;
    }
  }
}

// ---------------------------------------------------------------------------
// 环绕定位策略：围绕锚点四边选择最合适的方位
// ---------------------------------------------------------------------------

class _HintPositionDelegate extends PopupOverlayPositionDelegate {
  final HintPosition preferPosition;
  final double gap;
  final ValueChanged<HintPosition> onPositioned;

  const _HintPositionDelegate({
    required this.preferPosition,
    required this.gap,
    required this.onPositioned,
  });

  @override
  Offset getPosition({
    required Rect anchorRect,
    required Offset? position,
    required Size overlaySize,
    required Size childSize,
    required EdgeInsets padding,
  }) {
    final screenW = overlaySize.width;
    final screenH = overlaySize.height;
    final childTop = anchorRect.top;
    final childBottom = anchorRect.bottom;
    final childLeft = anchorRect.left;
    final childRight = anchorRect.right;
    final childCenterX = anchorRect.center.dx;
    final childCenterY = anchorRect.center.dy;

    final candidates = _positionCandidates(
      preferPosition,
      childCenterX,
      childCenterY,
      screenW,
      screenH,
      padding,
    );

    for (final pos in candidates) {
      final offset = _positionFor(
        pos,
        childTop,
        childBottom,
        childLeft,
        childRight,
        childCenterX,
        childCenterY,
        childSize,
      );
      if (_fitsAt(offset, childSize, screenW, screenH, padding)) {
        onPositioned(pos);
        return offset;
      }
    }

    // 兜底：取第一个候选方位，靠 clamp 保证不越界
    final fallback = candidates.first;
    onPositioned(fallback);
    return _clamp(
      _positionFor(
        fallback,
        childTop,
        childBottom,
        childLeft,
        childRight,
        childCenterX,
        childCenterY,
        childSize,
      ),
      childSize,
      screenW,
      screenH,
      padding,
    );
  }

  /// 按 preferPosition 和组件位置生成尝试顺序。
  List<HintPosition> _positionCandidates(
    HintPosition prefer,
    double childCenterX,
    double childCenterY,
    double screenW,
    double screenH,
    EdgeInsets padding,
  ) {
    const all = [
      HintPosition.top,
      HintPosition.bottom,
      HintPosition.left,
      HintPosition.right,
    ];
    if (prefer != HintPosition.auto) {
      return [prefer, ...all.where((p) => p != prefer)];
    }

    // 桌面端 auto 保持简单顺序。
    if (isDesktop) return all;

    // --- 移动端 auto：根据组件相对屏幕中心的偏移决定优先级 ---
    final cx = screenW / 2;
    final cy = screenH / 2;
    final rx = (childCenterX - cx) / cx; // -1..1
    final ry = (childCenterY - cy) / cy;

    final absRx = rx.abs();
    final absRy = ry.abs();

    final topSpace = childCenterY - padding.top;
    final bottomSpace = screenH - childCenterY - padding.bottom;
    final leftSpace = childCenterX - padding.left;
    final rightSpace = screenW - childCenterX - padding.right;

    if (absRy > absRx) {
      final v = topSpace >= bottomSpace
          ? [HintPosition.top, HintPosition.bottom]
          : [HintPosition.bottom, HintPosition.top];
      final h = leftSpace >= rightSpace
          ? [HintPosition.left, HintPosition.right]
          : [HintPosition.right, HintPosition.left];
      return [...v, ...h];
    } else if (absRx > absRy) {
      final h = leftSpace >= rightSpace
          ? [HintPosition.left, HintPosition.right]
          : [HintPosition.right, HintPosition.left];
      final v = topSpace >= bottomSpace
          ? [HintPosition.top, HintPosition.bottom]
          : [HintPosition.bottom, HintPosition.top];
      return [...h, ...v];
    } else {
      return [
        HintPosition.top,
        HintPosition.left,
        HintPosition.bottom,
        HintPosition.right,
      ];
    }
  }

  Offset _positionFor(
    HintPosition pos,
    double childTop,
    double childBottom,
    double childLeft,
    double childRight,
    double childCenterX,
    double childCenterY,
    Size hintSize,
  ) {
    final hintW = hintSize.width;
    final hintH = hintSize.height;

    switch (pos) {
      case HintPosition.top:
        return Offset(childCenterX - hintW / 2, childTop - hintH - gap);
      case HintPosition.bottom:
        return Offset(childCenterX - hintW / 2, childBottom + gap);
      case HintPosition.left:
        return Offset(childLeft - hintW - gap, childCenterY - hintH / 2);
      case HintPosition.right:
        return Offset(childRight + gap, childCenterY - hintH / 2);
      case HintPosition.auto:
        return Offset.zero;
    }
  }

  bool _fitsAt(
    Offset offset,
    Size hintSize,
    double screenW,
    double screenH,
    EdgeInsets padding,
  ) {
    return offset.dx >= padding.left &&
        offset.dy >= padding.top &&
        offset.dx + hintSize.width <= screenW - padding.right &&
        offset.dy + hintSize.height <= screenH - padding.bottom;
  }

  Offset _clamp(
    Offset offset,
    Size hintSize,
    double screenW,
    double screenH,
    EdgeInsets padding,
  ) {
    final maxLeft = (screenW - padding.right - hintSize.width)
        .clamp(padding.left, double.infinity);
    final maxTop = (screenH - padding.bottom - hintSize.height)
        .clamp(padding.top, double.infinity);
    return Offset(
      offset.dx.clamp(padding.left, maxLeft),
      offset.dy.clamp(padding.top, maxTop),
    );
  }

  @override
  bool shouldReposition(PopupOverlayPositionDelegate oldDelegate) =>
      oldDelegate is! _HintPositionDelegate ||
      oldDelegate.preferPosition != preferPosition ||
      oldDelegate.gap != gap;
}
