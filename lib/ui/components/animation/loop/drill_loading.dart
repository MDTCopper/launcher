import 'dart:math' as math;

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

import 'drill_paint.dart';

/// 铜钻头装载循环：线条化的 Mindustry 机械钻头
///
/// 层次照 `Drill.java` 那张机械钻头的四层（底座 / 钻头 / 顶盖 / 矿物）线条化：
/// 底座 → 四片钻臂 → 顶盖 → 轮毂亮点 → 铜粒
///
/// 一个 [cycle] 走一步：钻臂转到下一个 90 度 → 轮毂亮点闪一下 → 从中心弹出一粒铜
/// （弹铜既是这次钻探的结果，也接上下一次转动）
///
/// - [progress] 给值时用它驱动这一步（0~1），适合有真实进度的等待
/// - [progress] 给 null 时按 [cycle] 自循环，适合进度未知的等待
/// - [error] 为真时停在钻完那一步、亮点转红常亮，就是"载入失败"的样子
///
/// 纯 `CustomPaint` 绘制，不依赖任何图片资源，任意尺寸都清晰
class DrillLoading extends StatefulWidget {
  const DrillLoading({
    super.key,
    this.progress,
    this.size = 48,
    this.cycle = const Duration(milliseconds: 1100),
    this.error = false,
    this.onCycleFinished,
  }) : assert(progress == null || (progress >= 0 && progress <= 1));

  /// 确定进度（0~1）；null 为不确定态，内部自循环
  final double? progress;

  /// 边长；底座贴着它画，弹出去的那粒铜也在这范围内
  final double size;

  /// 不确定态下一步的时长（转一次 + 弹一次铜）
  final Duration cycle;

  /// 出错态：停转，中心亮点转红常亮
  final bool error;

  /// 每走完一步回调一次（只在不确定态触发）
  final VoidCallback? onCycleFinished;

  @override
  State<DrillLoading> createState() => _DrillLoadingState();
}

class _DrillLoadingState extends State<DrillLoading>
    with SingleTickerProviderStateMixin {
  /// 一轮里起转占的比例，其余作为停顿；一个 [cycle] 正好走"转一次 + 弹一次铜"
  static const double _spinPortion = 0.6;

  /// 一段停顿占的比例
  static const double _spinPausePortion = 1 - _spinPortion;

  /// 起转结束、铜粒弹出的时间点；亮点的闪光峰值与它对齐
  static const double _emitAt = _spinPortion;

  /// 铜粒在这段周期里飞出
  static const double _chipFlightPortion = 0.34;

  /// 闪光衰减后到下一轮起转之间的余量
  static const double _lightTail = 0.2;

  /// 亮点在脉冲之外的常亮底
  static const double _lightFloor = 0.15;

  late final AnimationController _controller;
  late double _cycleValue;

  /// 钻头转角：一轮从 0 平滑转到 90 度；四片钻臂 90 度一循环，正好接上下一次
  late final TweenSequence<double> _spinSequence = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: math.pi / 2,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: _spinPortion,
    ),
    TweenSequenceItem(
      tween: Tween(begin: math.pi / 2, end: math.pi / 2),
      weight: _spinPausePortion,
    ),
  ]);

  /// 轮毂亮点的亮度：起转到头时闪到最亮（就是"钻到了"那一下），随后回落
  late final TweenSequence<double> _lightSequence = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: _lightFloor,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: _spinPortion,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: _lightFloor,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 1 - _lightTail,
    ),
    TweenSequenceItem(
      tween: Tween(begin: _lightFloor, end: _lightFloor),
      weight: _lightTail,
    ),
  ]);

  @override
  void initState() {
    super.initState();
    _cycleValue = widget.progress ?? 0;
    _controller = AnimationController(vsync: this, duration: widget.cycle)
      ..addListener(_onTick);
    _syncProgressMode();
  }

  @override
  void didUpdateWidget(covariant DrillLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cycle != widget.cycle) {
      _controller.duration = widget.cycle;
    }
    if (oldWidget.progress != widget.progress) {
      _syncProgressMode();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 确定 / 不确定两种模式之间切换时，重建控制器的驱动方式
  void _syncProgressMode() {
    final value = widget.progress;
    if (value != null) {
      _controller.stop();
      _controller.removeStatusListener(_onStatus);
      _cycleValue = value;
    } else {
      _controller.repeat();
      _controller.addStatusListener(_onStatus);
      _cycleValue = _controller.value;
    }
  }

  void _onTick() {
    if (widget.progress != null) return;
    setState(() => _cycleValue = _controller.value);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onCycleFinished?.call();
  }

  /// 出错时停在这一步：起转已走完、铜粒刚弹出
  double get _frozenCycle => widget.progress ?? _emitAt;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final cycle = (widget.error ? _frozenCycle : _cycleValue).clamp(0.0, 1.0);

    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _DrillLoadingPainter(
          cycle: cycle,
          spin: _spinSequence.transform(cycle),
          light: widget.error ? 0 : _lightSequence.transform(cycle),
          chipFlightPortion: _chipFlightPortion,
          tone: DrillTone.of(context),
          hubColor: widget.error ? colors.error : colors.interactive,
          drillScale:
              widget.size * DrillPaint.drillRadiusRatio / DrillPaint.grid,
        ),
      ),
    );
  }
}

class _DrillLoadingPainter extends CustomPainter {
  _DrillLoadingPainter({
    required this.cycle,
    required this.spin,
    required this.light,
    required this.chipFlightPortion,
    required this.tone,
    required this.hubColor,
    required this.drillScale,
  });

  /// 当前周期位置（0~1）
  final double cycle;

  /// 钻头当前转角（弧度）
  final double spin;

  /// 轮毂亮点的亮度（0~1），出错态由调用方固定给 0
  final double light;

  final double chipFlightPortion;
  final DrillTone tone;

  /// 轮毂亮点的颜色：正常暖色、出错转红
  final Color hubColor;

  final double drillScale;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final drillRadius = size.shortestSide * DrillPaint.drillRadiusRatio;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    _paintBase(canvas);
    _paintBlades(canvas);
    _paintTop(canvas);
    DrillPaint.paintHubLight(canvas, drillScale, hubColor, light);
    _paintChip(canvas, drillRadius);
    canvas.restore();
  }

  /// 底座：八边形台面，四片钻臂都落在它上面
  void _paintBase(Canvas canvas) {
    final plate = DrillPaint.octagon(
      DrillPaint.baseHalf * drillScale,
      DrillPaint.baseCorner * drillScale,
    );
    canvas.drawPath(
      plate,
      Paint()
        ..style = PaintingStyle.fill
        ..color = tone.baseFill,
    );
    canvas.drawPath(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * drillScale
        ..color = tone.baseStroke,
    );
  }

  /// 四片钻臂整体绕中心旋转
  ///
  /// 描边按并集裁剪：四片各自的轮廓线会在轮毂交叠处留下内轮廓，看起来像拼错位
  void _paintBlades(Canvas canvas) {
    final union = DrillPaint.bladeUnion();
    final single = DrillPaint.blade();
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = tone.bladeFill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * drillScale
      ..color = tone.bladeStroke;

    canvas.save();
    canvas.rotate(spin);
    canvas.scale(drillScale);
    canvas.drawPath(union, fill);
    canvas.save();
    canvas.clipPath(union, doAntiAlias: true);
    for (var quarter = 0; quarter < 4; quarter++) {
      canvas.save();
      canvas.rotate(math.pi / 2 * quarter);
      canvas.drawPath(single, stroke);
      canvas.restore();
    }
    canvas.restore();
    canvas.restore();
  }

  /// 顶盖：压住钻臂的根部，只让伸出顶盖的那一截露出来当"在转的钻头"
  void _paintTop(Canvas canvas) {
    final cap = DrillPaint.octagon(
      DrillPaint.topHalf * drillScale,
      3.5 * drillScale,
    );
    canvas.drawPath(
      cap,
      Paint()
        ..style = PaintingStyle.fill
        ..color = tone.topFill,
    );
    canvas.drawPath(
      cap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * drillScale
        ..color = tone.topStroke,
    );
  }

  /// 铜粒：每轮起转结束时从中心弹出，是这次钻探的产物，也接上下一次转动
  void _paintChip(Canvas canvas, double drillRadius) {
    final flight = _chipFlight();
    if (flight == null) return;

    // 起点贴着轮毂，弹出一段距离后淡出
    final distance = drillRadius * (0.2 + 0.85 * flight);
    canvas.save();
    canvas.translate(
      distance * math.cos(-math.pi / 4),
      distance * math.sin(-math.pi / 4),
    );
    canvas.rotate(flight * math.pi / 3);
    DrillPaint.paintItem(
      canvas,
      drillScale * (1 - 0.4 * flight),
      opacity: 1 - flight,
    );
    canvas.restore();
  }

  /// 铜粒的飞行进度；不在弹出窗口内返回 null
  double? _chipFlight() {
    final start = 1 - chipFlightPortion;
    if (cycle < start) return null;
    return ((cycle - start) / chipFlightPortion).clamp(0, 1);
  }

  @override
  bool shouldRepaint(covariant _DrillLoadingPainter oldDelegate) {
    return oldDelegate.cycle != cycle ||
        oldDelegate.spin != spin ||
        oldDelegate.light != light ||
        oldDelegate.tone != tone ||
        oldDelegate.hubColor != hubColor ||
        oldDelegate.drillScale != drillScale;
  }
}
