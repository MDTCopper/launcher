import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// 多彩流光背景组件
///
/// 在 [child] 的背面堆叠若干柔和漂浮的发光点，
///
/// 光点由衬托色渐变至主题色，衬托色会随时间缓慢变化；
/// 所有颜色均由主题色 [AppColors.interactive] 通过色相偏移衍生而来，
/// 无论亮暗主题如何切换，背景始终与主题色相衬托
class ColorfulBackground extends StatefulWidget {
  const ColorfulBackground({
    super.key,
    required this.child,
    this.animate = true,
    this.duration = const Duration(seconds: 14),
    this.intensity = 1.0,
  });

  /// 前景内容，绘制在所有光效之上
  final Widget child;

  /// 是否播放缓慢的漂移 / 流动动画
  final bool animate;

  /// 单个动画周期时长
  final Duration duration;

  /// 发光强度，0.0 时几乎不可见，1.0 为默认强度
  final double intensity;

  @override
  State<ColorfulBackground> createState() => _ColorfulBackgroundState();
}

class _ColorfulBackgroundState extends State<ColorfulBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant ColorfulBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Stack(
      children: [
        // 底色
        Positioned.fill(child: ColoredBox(color: colors.pageBackground)),
        // 光效层
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, _) => CustomPaint(
                painter: _ColorfulBackgroundPainter(
                  colors: colors,
                  progress: _controller.value,
                  intensity: widget.intensity,
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// 光点配置
class _GlowSpot {
  const _GlowSpot({
    required this.alignment,
    required this.radiusFactor,
    required this.hueOffset,
    required this.hueDriftAmp,
    required this.hueDriftSpeed,
    required this.baseAlpha,
    required this.flashAlpha,
    required this.flashSpeed,
    required this.flashPower,
    required this.outerAlpha,
    required this.driftX,
    required this.driftY,
    required this.phase,
  });

  /// 基准位置（归一化坐标）
  final Alignment alignment;

  /// 光晕半径 = 短边 * radiusFactor
  final double radiusFactor;

  /// 衬托色相对主题色的色相偏移（度）
  final double hueOffset;

  /// 衬托色色相漂移幅度（度），让衬托色随时间变化
  final double hueDriftAmp;

  /// 衬托色色相漂移频率（整数倍，保证循环无缝）
  final double hueDriftSpeed;

  /// 平时亮度（0~255）
  final double baseAlpha;

  /// 偶发闪亮时的峰值亮度（0~255），仅略高于平时亮度
  final double flashAlpha;

  /// 闪亮频率（整数倍，保证循环无缝）
  final double flashSpeed;

  /// 闪亮曲线陡峭度，越大闪亮越短暂、越"偶尔"
  final double flashPower;

  /// 边缘主题色亮度（0~255）
  final double outerAlpha;

  /// 水平漂移幅度（逻辑像素）
  final double driftX;

  /// 垂直漂移幅度（逻辑像素）
  final double driftY;

  /// 动画相位（0~1）
  final double phase;
}

class _ColorfulBackgroundPainter extends CustomPainter {
  _ColorfulBackgroundPainter({
    required this.colors,
    required this.progress,
    required this.intensity,
  }) : _baseHue = HSLColor.fromColor(colors.interactive).hue;

  final AppColors colors;
  final double progress;
  final double intensity;
  final double _baseHue;

  static const _spots = [
    _GlowSpot(
      alignment: Alignment(-0.75, -0.7),
      radiusFactor: 0.55,
      hueOffset: -35,
      hueDriftAmp: 16,
      hueDriftSpeed: 1,
      baseAlpha: 24,
      flashAlpha: 34,
      flashSpeed: 1,
      flashPower: 18,
      outerAlpha: 16,
      driftX: 10,
      driftY: 6,
      phase: 0.0,
    ),
    _GlowSpot(
      alignment: Alignment(0.8, -0.6),
      radiusFactor: 0.42,
      hueOffset: 25,
      hueDriftAmp: 20,
      hueDriftSpeed: 2,
      baseAlpha: 20,
      flashAlpha: 28,
      flashSpeed: 1,
      flashPower: 20,
      outerAlpha: 14,
      driftX: 8,
      driftY: 12,
      phase: 0.35,
    ),
    _GlowSpot(
      alignment: Alignment(0.35, -0.42),
      radiusFactor: 0.6,
      hueOffset: 165,
      hueDriftAmp: 14,
      hueDriftSpeed: 1,
      baseAlpha: 18,
      flashAlpha: 25,
      flashSpeed: 1,
      flashPower: 22,
      outerAlpha: 12,
      driftX: 9,
      driftY: 5,
      phase: 0.6,
    ),
    _GlowSpot(
      alignment: Alignment(-0.4, -0.48),
      radiusFactor: 0.5,
      hueOffset: 85,
      hueDriftAmp: 18,
      hueDriftSpeed: 2,
      baseAlpha: 16,
      flashAlpha: 22,
      flashSpeed: 1,
      flashPower: 20,
      outerAlpha: 12,
      driftX: 6,
      driftY: 10,
      phase: 0.85,
    ),
  ];

  /// 由主题色按色相偏移衍生出衬托色
  Color _derivedColor(double hueOffset) => HSLColor.fromAHSL(
    1.0,
    (_baseHue + hueOffset) % 360,
    0.75,
    0.62,
  ).toColor();

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * math.pi;

    _paintSpots(canvas, size, t);
  }

  void _paintSpots(Canvas canvas, Size size, double t) {
    for (final spot in _spots) {
      final phase = spot.phase * 2 * math.pi;

      // 整数倍频率的周期函数，循环首尾衔接无缝
      final dx = math.sin(t + phase) * spot.driftX;
      final dy = math.cos(2 * t + phase) * spot.driftY;
      final center = spot.alignment.alongSize(size) + Offset(dx, dy);
      final radius = size.shortestSide * spot.radiusFactor;

      // 呼吸 + 偶发闪亮：闪亮曲线陡峭、峰值仅略高于平时，不吵闹
      final breathe = 0.88 + 0.12 * math.sin(t + phase);
      final flashCurve = math
          .pow(
            0.5 + 0.5 * math.sin(t * spot.flashSpeed + phase),
            spot.flashPower,
          )
          .toDouble();
      final alpha =
          (spot.baseAlpha * breathe +
                  (spot.flashAlpha - spot.baseAlpha * breathe) * flashCurve)
              .round()
              .clamp(0, 255)
              .toInt();

      // 衬托色随时间缓慢漂移
      final hueDrift =
          spot.hueDriftAmp * math.sin(t * spot.hueDriftSpeed + phase);
      final complement = _derivedColor(spot.hueOffset + hueDrift);
      final theme = colors.interactive;
      final outer = (spot.outerAlpha * intensity).round().clamp(0, 255).toInt();

      final paint = Paint()
        ..shader = RadialGradient(
          // 由衬托色渐变至主题色，衬托色随时间变化
          stops: const [0.0, 0.7, 1.0],
          colors: [
            complement.withAlpha(alpha),
            theme.withAlpha(outer),
            theme.withAlpha(0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ColorfulBackgroundPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.progress != progress ||
      oldDelegate.intensity != intensity;
}
