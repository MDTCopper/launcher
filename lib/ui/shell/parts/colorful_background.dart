import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
    this.colorful = true,
    this.animate = true,
    this.duration = const Duration(seconds: 14),
    this.intensity = 1.0,
  });

  /// 前景内容，绘制在所有光效之上
  final Widget child;

  /// 是否渲染流光层；false 时只留底色（零每帧开销）
  final bool colorful;

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
    with WidgetsBindingObserver {
  /// 动画进度（0~1）：由 [_ticker] 按节流后的间隔推进
  ///
  /// 用 [ValueNotifier] 而不是每帧 `setState`：只让 painter 重绘，不重建组件树
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  /// 进度按真实时间算（`duration` 走一圈）：定时器抖动不影响漂移速度
  final Stopwatch _clock = Stopwatch();

  /// 重绘定时器；不动画（流光层关着）时为 null
  Timer? _ticker;

  /// 当前的重绘间隔，按窗口大小算，见 [repaintIntervalFor]
  Duration _interval = const Duration(milliseconds: 33);

  /// 调整窗口结束后的恢复延迟
  static const _resizeResumeDelay = Duration(milliseconds: 500);

  Timer? _resizeResumeTimer;

  /// 该不该出帧：流光层开着且要动画时才转
  bool get _animating => widget.animate && widget.colorful;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_animating) _startTicking();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 窗口尺寸变了就换一档间隔（MediaQuery 依赖会走到这里）
    _updateInterval();
  }

  @override
  void didChangeMetrics() {
    // 调整窗口 / 最大化时暂停动画：每帧重绘成本 ∝ 像素数，resize 期间
    // 尺寸连续变化会让全窗口图层连续重绘，尺寸稳定一段时间后恢复
    _stopTicking();
    _resizeResumeTimer?.cancel();
    if (!_animating) return;
    _resizeResumeTimer = Timer(_resizeResumeDelay, () {
      if (!mounted || !_animating) return;
      _updateInterval();
      _startTicking();
    });
  }

  @override
  void didUpdateWidget(covariant ColorfulBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_animating) {
      // 流光层关掉时不能留着表：build 走 !colorful 的早退分支、不挂 painter，
      // 定时器空转只是白白出帧
      _resizeResumeTimer?.cancel();
      _stopTicking();
      return;
    }

    // 关掉又打开、或周期变了：按新的间隔重新起表
    final wasAnimating = oldWidget.animate && oldWidget.colorful;
    if (!wasAnimating || oldWidget.duration != widget.duration) {
      _updateInterval();
      _startTicking();
    }
  }

  @override
  void dispose() {
    _resizeResumeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _stopTicking();
    _progress.dispose();
    super.dispose();
  }

  /// 起表：每 [_interval] 推一次进度（重复调用不会叠表）
  void _startTicking() {
    _ticker?.cancel();
    _clock.start();
    _ticker = Timer.periodic(_interval, (_) => _advance());
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
    _clock.stop();
  }

  /// 按真实时间推进进度：`duration` 走完一圈
  void _advance() {
    final cycle = widget.duration.inMicroseconds;
    if (cycle <= 0) return;
    _progress.value = (_clock.elapsedMicroseconds % cycle) / cycle;
  }

  /// 按窗口大小更新重绘间隔；间隔真的变了就按新周期重新起表
  void _updateInterval() {
    final next = repaintIntervalFor(MediaQuery.sizeOf(context), widget.duration);
    if (next == _interval) return;
    _interval = next;
    if (_ticker != null) _startTicking();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (!widget.colorful) {
      // 直接关闭：只留底色，不渲染流光层（零每帧开销）
      return Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: colors.pageBackground)),
          widget.child,
        ],
      );
    }
    return Stack(
      children: [
        // 底色
        Positioned.fill(child: ColoredBox(color: colors.pageBackground)),
        // 光效层
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ColorfulBackgroundPainter(
                colors: colors,
                progress: _progress,
                intensity: widget.intensity,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// 依据窗口逻辑面积计算重绘间隔（多久推一次进度）
///
/// 窗口越大，每帧重绘的像素越多 ⇒ 间隔越长；光斑漂移缓慢，低帧率视觉上几乎无差别。
/// 这就是**出帧频率**：动画不再挂在 vsync 上（Ticker 每个刷新帧都要出帧，
/// 60Hz / 120Hz 屏上白烧 CPU），改成定时器按这个间隔推一次进度
@visibleForTesting
Duration repaintIntervalFor(Size size, Duration duration) {
  final interval = switch (size.width * size.height) {
    < 500000 => 33.0, // 小窗 ~30fps
    < 1200000 => 50.0, // ~20fps
    < 2200000 => 83.0, // ~12fps
    _ => 125.0, // 大窗 / 4K ~8fps
  };
  // 一个周期至少出一帧：周期特别短时别让间隔超过它
  final longest = math.max(1, duration.inMilliseconds);
  return Duration(milliseconds: math.min(interval.round(), longest));
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
  }) : _baseHue = HSLColor.fromColor(colors.interactive).hue,
       super(repaint: progress);

  final AppColors colors;

  /// 动画进度（0~1）：由外面的定时器推，这里只读值
  final ValueListenable<double> progress;

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
    final t = progress.value * 2 * math.pi;

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
      oldDelegate.progress.value != progress.value ||
      oldDelegate.intensity != intensity;
}
