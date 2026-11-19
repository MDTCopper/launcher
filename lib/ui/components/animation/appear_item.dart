import 'dart:async';

import 'package:copper_launcher/ui/feature/feature_curve.dart';
import 'package:copper_launcher/ui/util/route/route_trail.dart';
import 'package:flutter/material.dart';

/// 单条目入场动画（淡入 + 位移 + 生长）
///
/// 两种驱动模式：
/// - 传入 [slot] 且当前处于 [PageEntranceScope] 路由首次入场期间：
///   直接绑定路由 `animation` 的时间区间（零 Timer、与页面退场 100% 锁帧对齐），
///   路由完成后自动保持静态（返回该页不会重复播放波浪）
/// - 其他情况（滚动浮现、对话框或脱离 [CuPageRoute]）：
///   回落为自持 [AnimationController]，按 [delayMs] / [duration] 独立播放
class AppearItem extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final Duration duration;
  final Offset offset; // 起始位移（列表用；route 槽位模式下为 zero 时可随转场方向适配）
  final double scale; // 起始缩放（网格生长式用，默认 1 即不缩放）
  final Curve curve;
  final bool animate;

  /// 可选的路由时间轴槽位号（0~4+）；非空时优先挂接 [PageEntranceScope]
  final int? slot;

  /// 当走路由槽位模式且未显式给 [offset] 时，是否跟随路由方向给轻微位移
  final bool followRouteDirection;

  const AppearItem({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.duration = const Duration(milliseconds: 200),
    this.offset = Offset.zero,
    this.scale = 1,
    this.curve = FeatureCurves.reboundIn,
    this.animate = true,
    this.slot,
    this.followRouteDirection = false,
  });

  @override
  State<StatefulWidget> createState() => _AppearItemState();
}

class _AppearItemState extends State<AppearItem>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _fade;
  Animation<Offset>? _position;
  Animation<double>? _scale;
  Timer? _timer;

  bool _initialized = false;
  bool _boundToRoute = false;
  PageEntranceScope? _scope;
  Animation<double>? _routeProgress;
  Animation<Offset>? _routePosition;
  Animation<double>? _routeScale;
  bool _routeEnteredOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      _checkRouteCompleted();
      return;
    }
    _initialized = true;

    final scope = widget.slot != null
        ? PageEntranceScope.maybeOf(context)
        : null;
    if (widget.animate && scope != null && !scope.animation.isCompleted) {
      _bindToRoute(scope);
    } else {
      _initStandalone();
    }
  }

  void _bindToRoute(PageEntranceScope scope) {
    _boundToRoute = true;
    _scope = scope;
    scope.animation.addStatusListener(_onRouteStatusChanged);

    final interval = PageEntranceScope.intervalForSlot(
      widget.slot!,
      curve: Curves.easeOutCubic,
    );
    final curved = CurvedAnimation(
      parent: scope.animation,
      curve: interval,
      // 返回时顶层由路由整体快速退清，不让页内单个槽位拆散倒退
      reverseCurve: const Interval(0.99, 1.0),
    );

    final beginOffset = widget.offset != Offset.zero
        ? widget.offset
        : widget.followRouteDirection
        ? scope.defaultSlideOffset()
        : Offset.zero;

    _routeProgress = curved;
    _routePosition = beginOffset == Offset.zero
        ? null
        : Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(curved);
    _routeScale = widget.scale == 1
        ? null
        : Tween<double>(begin: widget.scale, end: 1.0).animate(curved);
  }

  void _onRouteStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_routeEnteredOnce) {
      _routeEnteredOnce = true;
      if (mounted) setState(() {});
    }
  }

  void _checkRouteCompleted() {
    if (_boundToRoute &&
        !_routeEnteredOnce &&
        (_scope?.animation.isCompleted ?? false)) {
      _routeEnteredOnce = true;
    }
  }

  void _initStandalone() {
    final controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    final curved = CurvedAnimation(parent: controller, curve: widget.curve);
    _controller = controller;
    _fade = curved;
    _position = Tween(begin: widget.offset, end: Offset.zero).animate(curved);
    _scale = Tween(begin: widget.scale, end: 1.0).animate(curved);

    if (widget.animate && widget.delayMs > 0) {
      _timer = Timer(Duration(milliseconds: widget.delayMs), () {
        if (mounted) controller.forward();
      });
    } else if (widget.animate) {
      // 延迟到首帧布局完成后才播放：立即 forward 会在布局期间触发动画 paint，
      // 导致 shrinkWrap 列表中未布局的 item RepaintBoundary 崩溃（hasSize 断言）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.forward();
      });
    } else {
      controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _scope?.animation.removeStatusListener(_onRouteStatusChanged);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_boundToRoute) {
      // 路由首次入场完成后锁定为静止态，但保持过渡壳层级不变，
      // 避免拆掉 Fade/Slide/ScaleTransition 导致子树重建闪屏
      final opacity = _routeEnteredOnce
          ? const AlwaysStoppedAnimation<double>(1.0)
          : _routeProgress!;
      Widget result = FadeTransition(opacity: opacity, child: widget.child);
      if (_routePosition != null) {
        result = SlideTransition(
          position: _routeEnteredOnce
              ? const AlwaysStoppedAnimation<Offset>(Offset.zero)
              : _routePosition!,
          child: result,
        );
      }
      if (_routeScale != null) {
        result = ScaleTransition(
          scale: _routeEnteredOnce
              ? const AlwaysStoppedAnimation<double>(1.0)
              : _routeScale!,
          child: result,
        );
      }
      return result;
    }

    Widget result = FadeTransition(opacity: _fade!, child: widget.child);
    if (widget.offset != Offset.zero) {
      result = SlideTransition(position: _position!, child: result);
    }
    if (widget.scale != 1) {
      result = ScaleTransition(scale: _scale!, child: result);
    }
    return result;
  }
}
