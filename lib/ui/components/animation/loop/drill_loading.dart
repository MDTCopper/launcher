import 'dart:math' as math;

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

import 'drill_paint.dart';

/// 铜钻头装载循环：线条化的 Mindustry 机械钻头，边钻边把铜矿收走
///
/// 层次照 `Drill.java` 的四层（底座 / 钻头 / 顶盖 / 矿物）再加外环：
/// 底座 → 四片钻臂 → 顶盖 → 铜块 → 飞出的铜粒 + 一圈周期进度
///
/// 钻臂伸出顶盖的那一截是"看得见在转的钻头"，走一段停一下；
/// 铜块在钻臂底下被反复扫过，一个周期走完被收走并弹出一粒铜飞到环外
///
/// - [progress] 给值时用它驱动**一个周期**（外环描边同步显示该值），适合有真实进度的等待
/// - [progress] 给 null 时按 [cycle] 自循环，适合进度未知的等待
///
/// 纯 `CustomPaint` 绘制，不依赖任何图片资源，任意尺寸都清晰
class DrillLoading extends StatefulWidget {
  const DrillLoading({
    super.key,
    this.progress,
    this.size = 48,
    this.cycle = const Duration(milliseconds: 2400),
    this.color,
    this.trackColor,
    this.onCycleFinished,
  }) : assert(progress == null || (progress >= 0 && progress <= 1));

  /// 确定进度（0~1）；null 为不确定态，内部自循环
  final double? progress;

  /// 边长；外环贴着它画，钻头落在环内
  final double size;

  /// 不确定态下一个周期的时长
  final Duration cycle;

  /// 外环进度的强调色，默认取主题的 `interactive`
  final Color? color;

  /// 外环轨道色，默认取主题的 `border`
  final Color? trackColor;

  /// 每走完一个周期回调一次（只在不确定态触发）
  final VoidCallback? onCycleFinished;

  @override
  State<DrillLoading> createState() => _DrillLoadingState();
}

class _DrillLoadingState extends State<DrillLoading>
    with SingleTickerProviderStateMixin {
  /// 每次起转占的比例，其余作为间歇，凑成一顿一转的节奏
  static const double _spinPortion = 0.6;

  /// 每次停顿占的比例
  static const double _spinPausePortion = 1 - _spinPortion;

  /// 铜块浮现的时间点；往后一直留在盘上，直到被收走
  static const double _oreRiseAt = 0.06;

  /// 铜块被收走的时间点；留出最后 0.14 个周期给铜粒飞完，收走动作才跟着转速落地
  static const double _oreCollectedAt = 0.86;

  /// 弹出的铜粒在这段周期里飞出
  static const double _chipFlightPortion = 0.16;

  late final AnimationController _controller;
  late double _cycleValue;

  /// 钻头的转角序列：每段起转占 [_spinPortion]，其余停顿
  late final TweenSequence<double> _spinSequence = TweenSequence<double>([
    _spinLeg(0),
    _spinPause(math.pi / 2),
    _spinLeg(math.pi / 2),
    _spinPause(math.pi),
    _spinLeg(math.pi),
    _spinPause(math.pi * 3 / 2),
  ]);

  /// 一段起转：从 [from] 平滑转到 [from] + 90 度
  static TweenSequenceItem<double> _spinLeg(double from) => TweenSequenceItem(
    tween: Tween(
      begin: from,
      end: from + math.pi / 2,
    ).chain(CurveTween(curve: Curves.easeInOutCubic)),
    weight: _spinPortion,
  );

  /// 一段停顿：转角保持不变，让矿条在间隙里被完整看见
  static TweenSequenceItem<double> _spinPause(double at) => TweenSequenceItem(
    tween: Tween(begin: at, end: at),
    weight: _spinPausePortion,
  );

  @override
  void initState() {
    super.initState();
    _cycleValue = widget.progress ?? 0;
    _controller = AnimationController(vsync: this, duration: widget.cycle)
      ..addListener(_onTick);
    if (widget.progress == null) {
      _controller.repeat();
      _controller.addStatusListener(_onStatus);
    }
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
    }
  }

  void _onTick() {
    if (widget.progress != null) return;
    setState(() => _cycleValue = _controller.value);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onCycleFinished?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _DrillLoadingPainter(
          cycle: _cycleValue,
          spin: _spinSequence.transform(_cycleValue.clamp(0.0, 1.0)),
          oreRiseAt: _oreRiseAt,
          oreCollectedAt: _oreCollectedAt,
          chipFlightPortion: _chipFlightPortion,
          tone: DrillTone.of(context),
          accent: widget.color ?? colors.interactive,
          track: widget.trackColor ?? colors.border,
          trackWidth: math.max(1.5, widget.size * 0.028),
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
    required this.oreRiseAt,
    required this.oreCollectedAt,
    required this.chipFlightPortion,
    required this.tone,
    required this.accent,
    required this.track,
    required this.trackWidth,
    required this.drillScale,
  });

  final double cycle;

  /// 钻头当前转角（弧度）
  final double spin;

  /// 铜块开始浮现 / 被收走的时间点
  final double oreRiseAt;
  final double oreCollectedAt;

  final double chipFlightPortion;
  final DrillTone tone;
  final Color accent;
  final Color track;
  final double trackWidth;
  final double drillScale;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final arcRadius = size.shortestSide / 2 * (1 - DrillPaint.arcInset * 2);
    final drillRadius = size.shortestSide * DrillPaint.drillRadiusRatio;

    _paintArc(canvas, center, arcRadius);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    _paintBase(canvas);
    _paintBlades(canvas);
    _paintTop(canvas);
    _paintOre(canvas);
    _paintChip(canvas, drillRadius);
    canvas.restore();
  }

  /// 外环：轨道 + 当前周期的进度段，从正上方顺时针走
  void _paintArc(Canvas canvas, Offset center, double radius) {
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackWidth
        ..color = track,
    );
    if (cycle <= 0) return;

    canvas.drawArc(
      bounds,
      -math.pi / 2,
      math.pi * 2 * cycle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackWidth
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );
  }

  /// 底座：八边形台面，钻臂与铜块都落在它上面
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

  /// 铜块：压在顶盖之上，转动的钻臂从它上面扫过去，就是"边钻边被啃掉"的读数
  ///
  /// 最后一段起转走完时整个收走，并由 [_paintChip] 弹出一粒铜
  void _paintOre(Canvas canvas) {
    final visibility = _oreVisibility();
    if (visibility <= 0) return;

    final block = DrillPaint.ore();
    final alpha = (visibility * 255).round();
    canvas.save();
    canvas.scale(drillScale);
    canvas.drawPath(
      block,
      Paint()
        ..style = PaintingStyle.fill
        ..color = DrillPaint.itemLight.withAlpha(alpha),
    );
    canvas.drawPath(
      block,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = DrillPaint.itemDark.withAlpha(alpha),
    );
    canvas.restore();
  }

  /// 四片钻头绕中心一顿一转，停顿间隙里铜块被完整看见
  void _paintBlades(Canvas canvas) {
    final blade = DrillPaint.blade();
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = tone.bladeFill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * drillScale
      ..color = tone.bladeStroke;

    canvas.save();
    canvas.rotate(spin);
    for (var quarter = 0; quarter < 4; quarter++) {
      canvas.save();
      canvas.rotate(math.pi / 2 * quarter);
      canvas.scale(drillScale);
      canvas.drawPath(blade, fill);
      canvas.drawPath(blade, stroke);
      canvas.restore();
    }
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

  /// 铜粒：周期末从矿里沿径向往外飞出并淡出
  void _paintChip(Canvas canvas, double drillRadius) {
    final flight = _chipFlight();
    if (flight == null) return;

    // 起点落在顶盖边缘，看起来是从矿里被拔出来的
    final distance = drillRadius * (0.45 + 0.73 * flight);
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

  /// 铜块的可见度：周期开头浮现，第三轮起转走完被收走
  double _oreVisibility() {
    if (cycle >= oreCollectedAt) return 0;
    if (cycle <= oreRiseAt) return 0;
    const riseLength = 0.06;
    final since = cycle - oreRiseAt;
    if (since < riseLength) return (since / riseLength).clamp(0, 1);
    return 1;
  }

  /// 铜粒的飞行进度；不在飞出窗口内返回 null
  double? _chipFlight() {
    final start = 1 - chipFlightPortion;
    if (cycle < start) return null;
    return ((cycle - start) / chipFlightPortion).clamp(0, 1);
  }

  @override
  bool shouldRepaint(covariant _DrillLoadingPainter oldDelegate) {
    return oldDelegate.cycle != cycle ||
        oldDelegate.spin != spin ||
        oldDelegate.tone != tone ||
        oldDelegate.accent != accent ||
        oldDelegate.track != track ||
        oldDelegate.trackWidth != trackWidth ||
        oldDelegate.drillScale != drillScale;
  }
}
