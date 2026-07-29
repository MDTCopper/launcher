import 'dart:async';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/material.dart';

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
// HintField
// ---------------------------------------------------------------------------

class HintField extends StatefulWidget {
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

  // ---- 静态协调 ----
  static HintFieldState? _activeHint;
  static DateTime? _lastShowTime;
  static DateTime? _lastDismissTime;

  const HintField({
    super.key,
    required this.child,
    this.hint,
    this.hintWidget,
    this.preferPosition = HintPosition.auto,
    this.showDuration = const Duration(seconds: 2),
    this.waitDuration = const Duration(milliseconds: 800),
    this.waitResetDuration,
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
  State<HintField> createState() => HintFieldState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class HintFieldState extends State<HintField> with TickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();

  OverlayEntry? _overlayEntry;
  AnimationController? _animationController;
  Timer? _waitTimer;
  Timer? _dismissTimer;

  bool _isLongPressing = false;
  bool _isShowing = false;

  // 缓存的文本尺寸，避免重复用 TextPainter 测量。
  Size? _cachedTextSize;

  @override
  void didUpdateWidget(HintField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hint != oldWidget.hint ||
        widget.textStyle != oldWidget.textStyle ||
        widget.maxWidth != oldWidget.maxWidth ||
        widget.padding != oldWidget.padding) {
      _cachedTextSize = null;
    }
  }

  double _effectiveMaxWidth() {
    if (widget.maxWidth != null) return widget.maxWidth!;
    return MediaQuery.of(context).size.width / 3;
  }

  @override
  void dispose() {
    _dismiss(immediate: true);
    _waitTimer?.cancel();
    _dismissTimer?.cancel();
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

    return CompositedTransformTarget(link: _layerLink, child: child);
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
    if (HintField._activeHint != null && HintField._activeHint != this) {
      HintField._activeHint!._dismiss(immediate: true);
    }

    if (_isShowing) return;

    HintField._activeHint = this;

    final Duration resetWindow =
        widget.waitResetDuration ?? widget.animationDuration;
    final DateTime? lastEvent =
        HintField._lastDismissTime ?? HintField._lastShowTime;
    final bool skipWait =
        lastEvent != null && DateTime.now().difference(lastEvent) < resetWindow;

    _waitTimer?.cancel();
    if (skipWait) {
      _prepareAndShow();
    } else {
      _waitTimer = Timer(widget.waitDuration, _prepareAndShow);
    }
  }

  /// 测量 hint 尺寸，选最佳方位，然后显示。
  Future<void> _prepareAndShow() async {
    if (!mounted || _isShowing) return;

    final Size hintSize;
    if (widget.hintWidget != null) {
      hintSize = await _measureOffstage();
      if (!mounted || _isShowing) return;
    } else {
      hintSize = _measureText();
    }

    _showAt(hintSize);
  }

  void _showAt(Size hintSize) {
    if (!mounted || _isShowing) return;

    _removeOverlay();
    _isShowing = true;
    HintField._lastShowTime = DateTime.now();

    _animationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _buildOverlay(ctx, hintSize),
    );
    Overlay.of(context).insert(_overlayEntry!);
    _animationController!.forward();

    if (_isLongPressing) {
      _dismissTimer?.cancel();
      _dismissTimer = Timer(widget.showDuration, _dismiss);
    }
  }

  void _dismiss({bool immediate = false}) {
    _waitTimer?.cancel();
    _dismissTimer?.cancel();
    final bool wasVisible = _overlayEntry != null;
    _isShowing = false;

    if (wasVisible) {
      HintField._lastDismissTime = DateTime.now();
    }

    if (HintField._activeHint == this) {
      HintField._activeHint = null;
    }

    if (_overlayEntry == null) {
      _animationController?.dispose();
      _animationController = null;
      return;
    }

    if (immediate || _animationController == null) {
      _removeOverlay();
      return;
    }

    _animationController!.stop();
    _animationController!.reverse().then(
      (_) => _removeOverlay(),
      onError: (_) => _removeOverlay(),
    );
  }

  void _removeOverlay() {
    _isShowing = false;
    _animationController?.stop();
    _animationController?.dispose();
    _animationController = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ------------------------------------------------------------------
  // Measurement
  // ------------------------------------------------------------------

  /// 用 TextPainter 测纯文本 hint 的实际尺寸（含 padding）。
  Size _measureText() {
    if (_cachedTextSize != null) return _cachedTextSize!;

    final style =
        widget.textStyle ??
        Theme.of(context).textTheme.labelMedium ??
        const TextStyle(fontSize: 13);

    final textPainter = TextPainter(
      text: TextSpan(text: widget.hint, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
    textPainter.layout(maxWidth: _effectiveMaxWidth());

    final size = Size(
      textPainter.width + widget.padding.horizontal,
      textPainter.height + widget.padding.vertical,
    );
    _cachedTextSize = size;
    return size;
  }

  /// 用 Offstage Overlay 测量自定义 Widget 的实际尺寸。
  Future<Size> _measureOffstage() async {
    final GlobalKey key = GlobalKey();
    final OverlayEntry measureEntry = OverlayEntry(
      builder: (_) => Offstage(
        child: UnconstrainedBox(
          child: Container(
            key: key,
            constraints: BoxConstraints(maxWidth: _effectiveMaxWidth()),
            child: widget.hintWidget,
          ),
        ),
      ),
    );

    Overlay.of(context).insert(measureEntry);
    await WidgetsBinding.instance.endOfFrame;
    final Size size = key.currentContext?.size ?? const Size(48, 24);
    measureEntry.remove();
    return size;
  }

  // ------------------------------------------------------------------
  // Position helpers
  // ------------------------------------------------------------------

  /// 按 preferPosition 和组件位置生成尝试顺序。
  /// 移动端 auto 模式会根据组件在屏幕中的位置智能排列优先方向。
  List<HintPosition> _positionCandidates(
    HintPosition prefer,
    double childCenterX,
    double childCenterY,
    double screenW,
    double screenH,
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

    // 各方向可用空间。
    final topSpace = childCenterY - widget.screenPadding.top;
    final bottomSpace = screenH - childCenterY - widget.screenPadding.bottom;
    final leftSpace = childCenterX - widget.screenPadding.left;
    final rightSpace = screenW - childCenterX - widget.screenPadding.right;

    if (absRy > absRx) {
      // 垂直偏移更大 → 先垂直方向（上/下），再水平（左/右）。
      final v = topSpace >= bottomSpace
          ? [HintPosition.top, HintPosition.bottom]
          : [HintPosition.bottom, HintPosition.top];
      final h = leftSpace >= rightSpace
          ? [HintPosition.left, HintPosition.right]
          : [HintPosition.right, HintPosition.left];
      return [...v, ...h];
    } else if (absRx > absRy) {
      // 水平偏移更大 → 先水平方向，再垂直。
      final h = leftSpace >= rightSpace
          ? [HintPosition.left, HintPosition.right]
          : [HintPosition.right, HintPosition.left];
      final v = topSpace >= bottomSpace
          ? [HintPosition.top, HintPosition.bottom]
          : [HintPosition.bottom, HintPosition.top];
      return [...h, ...v];
    } else {
      // 偏移相等 → 默认：上 → 左 → 下 → 右。
      return [
        HintPosition.top,
        HintPosition.left,
        HintPosition.bottom,
        HintPosition.right,
      ];
    }
  }

  /// 检查 hint 在指定方位是否放得下（同时检查水平和垂直）。
  bool _fitsAt(
    HintPosition pos,
    double childTop,
    double childBottom,
    double childLeft,
    double childRight,
    double childCenterX,
    double childCenterY,
    Size hintSize,
    double screenW,
    double screenH,
  ) {
    final hintW = hintSize.width;
    final hintH = hintSize.height;
    final padL = widget.screenPadding.left;
    final padT = widget.screenPadding.top;
    final padR = widget.screenPadding.right;
    final padB = widget.screenPadding.bottom;

    double left, top;

    switch (pos) {
      case HintPosition.top:
        top = childTop - hintH - widget.gap;
        left = childCenterX - hintW / 2;
      case HintPosition.bottom:
        top = childBottom + widget.gap;
        left = childCenterX - hintW / 2;
      case HintPosition.left:
        top = childCenterY - hintH / 2;
        left = childLeft - hintW - widget.gap;
      case HintPosition.right:
        top = childCenterY - hintH / 2;
        left = childRight + widget.gap;
      default:
        return false;
    }

    return left >= padL &&
        top >= padT &&
        left + hintW <= screenW - padR &&
        top + hintH <= screenH - padB;
  }

  // ------------------------------------------------------------------
  // Overlay
  // ------------------------------------------------------------------

  Widget _buildOverlay(BuildContext context, Size hintSize) {
    final Widget content = widget.hintWidget ?? _buildTextHint();

    // 获取子组件屏幕位置。
    final RenderBox? childBox = this.context.findRenderObject() as RenderBox?;
    final double screenW = MediaQuery.of(context).size.width;
    final double screenH = MediaQuery.of(context).size.height;
    double childTop = 0, childBottom = 0, childLeft = 0, childRight = 0;
    if (childBox != null && childBox.attached) {
      final Offset pos = childBox.localToGlobal(Offset.zero);
      childTop = pos.dy;
      childBottom = pos.dy + childBox.size.height;
      childLeft = pos.dx;
      childRight = pos.dx + childBox.size.width;
    }
    final double childCenterX = childLeft + (childRight - childLeft) / 2;
    final double childCenterY = childTop + (childBottom - childTop) / 2;

    // 按真实尺寸选最佳方位。
    final candidates = _positionCandidates(
      widget.preferPosition,
      childCenterX,
      childCenterY,
      screenW,
      screenH,
    );
    HintPosition actualPos = candidates.first;
    for (final pos in candidates) {
      if (_fitsAt(
        pos,
        childTop,
        childBottom,
        childLeft,
        childRight,
        childCenterX,
        childCenterY,
        hintSize,
        screenW,
        screenH,
      )) {
        actualPos = pos;
        break;
      }
    }

    final Alignment targetAnchor;
    final Alignment followerAnchor;
    final Offset offset;

    switch (actualPos) {
      case HintPosition.top:
        targetAnchor = Alignment.topCenter;
        followerAnchor = Alignment.bottomCenter;
        offset = Offset(0, -widget.gap);
      case HintPosition.bottom:
        targetAnchor = Alignment.bottomCenter;
        followerAnchor = Alignment.topCenter;
        offset = Offset(0, widget.gap);
      case HintPosition.left:
        targetAnchor = Alignment.centerLeft;
        followerAnchor = Alignment.centerRight;
        offset = Offset(-widget.gap, 0);
      case HintPosition.right:
        targetAnchor = Alignment.centerRight;
        followerAnchor = Alignment.centerLeft;
        offset = Offset(widget.gap, 0);
      case HintPosition.auto:
        targetAnchor = Alignment.topCenter;
        followerAnchor = Alignment.bottomCenter;
        offset = Offset(0, -widget.gap);
    }

    final Animation<double> showCurve = CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Stack(
      children: [
        CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: targetAnchor,
          followerAnchor: followerAnchor,
          offset: offset,
          child: AnimatedBuilder(
            animation: showCurve,
            builder: (context, child) {
              final HintAnimation anim = _isShowing
                  ? widget.showAnimation
                  : (widget.hideAnimation ?? widget.showAnimation);
              return anim.builder(context, showCurve, child!, actualPos);
            },
            child: content,
          ),
        ),
      ],
    );
  }

  Widget _buildTextHint() {
    final color = AppColors.of(context);
    final theme = Theme.of(context);

    Widget hint = Container(
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

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _effectiveMaxWidth()),
      child: hint,
    );
  }
}
