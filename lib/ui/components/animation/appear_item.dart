import 'dart:async';

import 'package:copper_launcher/ui/feature/feature_curve.dart';
import 'package:copper_launcher/ui/util/route/route_trail.dart';
import 'package:flutter/material.dart';

/// 单条目入场 / 退场动画（淡入淡出 + 位移 + 缩放）
///
/// 两种驱动模式：
/// - 传入 [slot] 且当前位于 [PageEntranceScope] 内：
///   持续绑定路由的 `animation`（入场 & 弹出退场）与 `secondaryAnimation`（被新页覆盖退场 & 返回回露），
///   零 Timer、零树结构切换，彻底对齐整页转场时间线且不会在结束时闪屏
/// - 其他情况（滚动浮现、对话框或脱离 [CuPageRoute]）：
///   回落为自持 [AnimationController]，按 [delayMs] / [duration] 独立播放
class AppearItem extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final Duration duration;

  /// 入场起始位移（路由槽位模式下为 zero 时可随转场方向自动适配）
  final Offset offset;

  /// 被新页覆盖退场时的目标位移（为空时按转场方向或 [offset] 自动推导）
  final Offset? exitOffset;

  /// 起始缩放（网格生长式用，默认 1 即不缩放）
  final double scale;
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
    this.exitOffset,
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

  // 路由主轴：前进入场 & 返回弹出退场
  Animation<double>? _primaryOpacity;
  Animation<Offset>? _primaryPosition;
  Animation<double>? _primaryScale;

  // 路由次轴：被覆盖退场 & 返回回露
  Animation<double>? _secondaryOpacity;
  Animation<Offset>? _secondaryPosition;
  Animation<double>? _secondaryScale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final scope = widget.slot != null
        ? PageEntranceScope.maybeOf(context)
        : null;
    if (widget.animate && scope != null) {
      _bindToRoute(scope);
    } else {
      _initStandalone();
    }
  }

  void _bindToRoute(PageEntranceScope scope) {
    _boundToRoute = true;
    final slot = widget.slot!;

    // 1. 主轴（animation）：forward 负责阶梯入场，reverse 负责弹出时的逆序阶梯退场
    final primaryCurved = CurvedAnimation(
      parent: scope.animation,
      curve: PageEntranceScope.enterIntervalForSlot(slot),
      reverseCurve: PageEntranceScope.popExitIntervalForSlot(slot),
    );

    final enterOffset = widget.offset != Offset.zero
        ? widget.offset
        : widget.followRouteDirection
        ? scope.defaultSlideOffset()
        : Offset.zero;

    _primaryOpacity = primaryCurved;
    _primaryPosition = enterOffset == Offset.zero
        ? null
        : Tween<Offset>(
            begin: enterOffset,
            end: Offset.zero,
          ).animate(primaryCurved);
    _primaryScale = widget.scale == 1
        ? null
        : Tween<double>(begin: widget.scale, end: 1.0).animate(primaryCurved);

    // 2. 次轴（secondaryAnimation）：forward 负责被新页覆盖时按槽位退场，reverse 负责返回时柔和落回
    final secondaryCurved = CurvedAnimation(
      parent: scope.secondaryAnimation,
      curve: PageEntranceScope.coverExitIntervalForSlot(slot),
      reverseCurve: PageEntranceScope.revealIntervalForSlot(slot),
    );

    final coverExitOffset =
        widget.exitOffset ??
        (widget.offset != Offset.zero
            ? Offset(widget.offset.dx, -widget.offset.dy * 0.7)
            : widget.followRouteDirection
            ? scope.defaultCoverExitOffset()
            : Offset.zero);

    _secondaryOpacity = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(secondaryCurved);
    _secondaryPosition = coverExitOffset == Offset.zero
        ? null
        : Tween<Offset>(
            begin: Offset.zero,
            end: coverExitOffset,
          ).animate(secondaryCurved);
    _secondaryScale = widget.scale == 1
        ? null
        : Tween<double>(
            begin: 1.0,
            end: widget.scale.clamp(0.95, 0.995),
          ).animate(secondaryCurved);
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
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_boundToRoute) {
      // 始终保持同一套过渡壳层级，只由路由 animation / secondaryAnimation 驱动，绝不拆树闪屏
      Widget result = FadeTransition(
        opacity: _primaryOpacity!,
        child: widget.child,
      );
      if (_primaryPosition != null) {
        result = SlideTransition(position: _primaryPosition!, child: result);
      }
      if (_primaryScale != null) {
        result = ScaleTransition(scale: _primaryScale!, child: result);
      }

      result = FadeTransition(opacity: _secondaryOpacity!, child: result);
      if (_secondaryPosition != null) {
        result = SlideTransition(position: _secondaryPosition!, child: result);
      }
      if (_secondaryScale != null) {
        result = ScaleTransition(scale: _secondaryScale!, child: result);
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
