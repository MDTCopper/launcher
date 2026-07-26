import 'dart:async';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// HintPosition
// ---------------------------------------------------------------------------

/// 提示框相对于组件的方位。
enum HintPosition { top, bottom, left, right, auto }

// ---------------------------------------------------------------------------
// HintAnimation
// ---------------------------------------------------------------------------

/// 入场 / 退场动画定义。
///
/// 内置预设：[HintAnimation.fade]、[HintAnimation.scale]、[HintAnimation.slide]。
/// [scale] 和 [slide] 会根据提示框的[实际方位][HintPosition]自适应锚点和方向。
///
/// 自定义动画：
/// ```dart
/// HintAnimation(
///   (context, animation, child, position) {
///     return FadeTransition(opacity: animation, child: child);
///   },
/// )
/// ```
class HintAnimation {
  /// [animation] 已包好 easeOutCubic / easeInCubic 曲线。
  final Widget Function(
    BuildContext context,
    Animation<double> animation,
    Widget child,
    HintPosition position,
  )
  builder;

  const HintAnimation(this.builder);

  // ---- 预设 ----

  /// 纯淡入淡出。
  static const fade = HintAnimation(_fadeBuilder);

  /// 缩放 + 淡入淡出。锚点根据提示框方位自适应。
  static const scale = HintAnimation(_scaleBuilder);

  /// 滑动 + 淡入淡出。方向根据提示框方位自适应。
  static const slide = HintAnimation(_slideBuilder);

  static Widget _fadeBuilder(
    BuildContext context,
    Animation<double> animation,
    Widget child,
    HintPosition position,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }

  static Widget _scaleBuilder(
    BuildContext context,
    Animation<double> animation,
    Widget child,
    HintPosition position,
  ) {
    return ScaleTransition(
      scale: animation,
      alignment: _scaleAlignment(position),
      child: FadeTransition(opacity: animation, child: child),
    );
  }

  static Widget _slideBuilder(
    BuildContext context,
    Animation<double> animation,
    Widget child,
    HintPosition position,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: _slideOffset(position),
        end: Offset.zero,
      ).animate(animation),
      child: FadeTransition(opacity: animation, child: child),
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

/// 给任意组件附加悬浮提示框。
///
/// 支持纯文本 [hint] 和自定义组件 [hintWidget]。
///
/// 触发方式：桌面端鼠标悬停 / 移动端长按。
class HintField extends StatefulWidget {
  final Widget child;

  final String? hint;
  final Widget? hintWidget;

  /// 优先显示方位（[HintPosition.auto] 时依次尝试 top → bottom → left → right）。
  final HintPosition preferPosition;

  /// 长按触发后的自动消失时长。hover 模式忽略。
  final Duration showDuration;

  /// hover / 长按后到提示框出现前的等待时长。
  final Duration waitDuration;

  /// 提示框消失后，等待时间重置间隔。在此间隔内悬停另一个组件，跳过 [waitDuration]。
  /// `null` 时默认等于 [waitDuration]
  final Duration? waitResetDuration;

  /// 入场 / 退场动画时长
  final Duration animationDuration;

  /// 入场动画
  final HintAnimation showAnimation;

  /// 退场动画。`null` 时默认与 [showAnimation] 相同。
  final HintAnimation? hideAnimation;

  /// 提示框与子组件的间距
  final double gap;

  /// 提示框距屏幕边缘的最小安全距离
  final EdgeInsets screenPadding;

  //纯文本模式专用样式
  final EdgeInsets padding;
  final BoxDecoration? decoration;
  final TextStyle? textStyle;

  // 静态协调
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
    this.waitDuration = const Duration(milliseconds: 500),
    this.waitResetDuration,
    this.animationDuration = const Duration(milliseconds: 200),
    this.showAnimation = HintAnimation.slide,
    this.hideAnimation,
    this.gap = 4.0,
    this.screenPadding = const EdgeInsets.all(8.0),
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

  // ------------------------------------------------------------------
  // Dispose
  // ------------------------------------------------------------------

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
  // Mouse (desktop)
  // ------------------------------------------------------------------

  void _onMouseEnter(PointerEvent event) {
    _requestShow();
  }

  void _onMouseExit(PointerEvent event) {
    _dismiss();
  }

  // ------------------------------------------------------------------
  // Long press (mobile)
  // ------------------------------------------------------------------

  void _onLongPressStart(LongPressStartDetails details) {
    _isLongPressing = true;
    _requestShow();
  }

  void _onLongPressEnd(LongPressEndDetails details) {
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
    if (HintField._activeHint != null && HintField._activeHint != this) {
      HintField._activeHint!._dismiss(immediate: true);
    }

    if (_isShowing) return;

    HintField._activeHint = this;

    final Duration resetWindow =
        widget.waitResetDuration ?? widget.waitDuration;
    final DateTime? lastEvent =
        HintField._lastDismissTime ?? HintField._lastShowTime;
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

    _removeOverlay();

    _isShowing = true;
    HintField._lastShowTime = DateTime.now();

    _animationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    _overlayEntry = OverlayEntry(builder: _buildOverlay);
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
    _isShowing = false;

    HintField._lastDismissTime = DateTime.now();

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
  // Position helpers
  // ------------------------------------------------------------------

  static List<HintPosition> _positionCandidates(HintPosition prefer) {
    const all = [
      HintPosition.top,
      HintPosition.bottom,
      HintPosition.left,
      HintPosition.right,
    ];
    if (prefer == HintPosition.auto) return all;
    return [prefer, ...all.where((p) => p != prefer)];
  }

  bool _fitsAt(
    HintPosition pos,
    double childTop,
    double childBottom,
    double childLeft,
    double childRight,
    double hintEstimate,
    double screenW,
    double screenH,
  ) {
    switch (pos) {
      case HintPosition.top:
        return childTop >= hintEstimate + widget.gap + widget.screenPadding.top;
      case HintPosition.bottom:
        return childBottom + hintEstimate + widget.gap <=
            screenH - widget.screenPadding.bottom;
      case HintPosition.left:
        return childLeft >=
            hintEstimate + widget.gap + widget.screenPadding.left;
      case HintPosition.right:
        return childRight + hintEstimate + widget.gap <=
            screenW - widget.screenPadding.right;
      default:
        return false;
    }
  }

  // ------------------------------------------------------------------
  // Overlay content
  // ------------------------------------------------------------------

  Widget _buildOverlay(BuildContext context) {
    final Widget content = widget.hintWidget ?? _buildTextHint();

    const double hintEstimate = 48.0;

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

    final candidates = _positionCandidates(widget.preferPosition);
    HintPosition actualPos = candidates.first;
    for (final pos in candidates) {
      if (_fitsAt(
        pos,
        childTop,
        childBottom,
        childLeft,
        childRight,
        hintEstimate,
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

    // 入场动画曲线。
    final Animation<double> showCurve = CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _dismiss(),
          ),
        ),
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

    return Container(
      padding: widget.padding,
      decoration:
          widget.decoration ??
          BoxDecoration(
            color: color.cardBackground.withAlpha(185),
            borderRadius: BorderRadius.all(Radius.circular(4)),
            border: Border.all(color: color.border),
          ),
      child: Text(
        widget.hint!,
        style: widget.textStyle ?? theme.textTheme.labelMedium,
      ),
    );
  }
}
