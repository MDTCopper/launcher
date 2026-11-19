import 'dart:async';
import 'dart:math' as math;

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:flutter/material.dart';

/// 全局常驻的「若隐若现」漂移网格背景层
///
/// 挂在 [AppShell] 的流光背景之上、路由栈之下，切页时网格保持连续不动；
/// 沿对角线缓慢平推并在稀疏交叉点附加微光，重绘按窗口面积低频节流，缩放窗口期间暂停重绘
class HomeDriftingGrid extends StatefulWidget {
  const HomeDriftingGrid({
    super.key,
    this.animate = true,
    this.cycleDuration = const Duration(seconds: 26),
    this.staticPhase = 0.25,
  });

  static const String settingKey = 'home_grid_enabled';

  /// 全局开关状态：AppShell 监听它决定是否挂载漂移网格，主页「背景」菜单负责切换
  static final ValueNotifier<bool> enabledNotifier = ValueNotifier<bool>(true);

  static void syncFromConfig() {
    enabledNotifier.value =
        config.setting.getCustomSetting(settingKey, true) == true;
  }

  static void setEnabled(bool value) {
    if (enabledNotifier.value == value) return;
    enabledNotifier.value = value;
    config.setting.customSetting[settingKey] = value;
    config.save();
  }

  /// 是否播放缓慢漂移；关闭或单帧渲染时定格在 [staticPhase]
  final bool animate;

  /// 网格沿水平方向平移一格所需的周期
  final Duration cycleDuration;

  /// 静态定格时的相位（0~1）
  final double staticPhase;

  @override
  State<HomeDriftingGrid> createState() => _HomeDriftingGridState();
}

class _HomeDriftingGridState extends State<HomeDriftingGrid>
    with WidgetsBindingObserver {
  late final ValueNotifier<double> _phase = ValueNotifier<double>(
    widget.staticPhase,
  );
  final Stopwatch _clock = Stopwatch();

  Timer? _ticker;
  Timer? _resizeResumeTimer;
  Duration _interval = const Duration(milliseconds: 33);

  static const _resizeResumeDelay = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTickerState();
  }

  @override
  void didChangeMetrics() {
    // 窗口拖拽缩放时暂停重绘，避免每帧整页重画
    _stopTicking();
    _resizeResumeTimer?.cancel();
    if (!widget.animate) return;
    _resizeResumeTimer = Timer(_resizeResumeDelay, () {
      if (!mounted || !widget.animate) return;
      _syncTickerState();
    });
  }

  @override
  void didUpdateWidget(covariant HomeDriftingGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate) {
      _resizeResumeTimer?.cancel();
      _stopTicking();
      _phase.value = widget.staticPhase;
      return;
    }
    if (!oldWidget.animate || oldWidget.cycleDuration != widget.cycleDuration) {
      _syncTickerState();
    }
  }

  void _syncTickerState() {
    final enabled = widget.animate && TickerMode.valuesOf(context).enabled;
    if (!enabled) {
      _stopTicking();
      return;
    }
    final next = _repaintIntervalFor(
      MediaQuery.sizeOf(context),
      widget.cycleDuration,
    );
    if (next != _interval || _ticker == null) {
      _interval = next;
      _startTicking();
    }
  }

  /// 按窗口面积节流重绘间隔，大窗自动降频以控制后台重绘开销
  Duration _repaintIntervalFor(Size size, Duration duration) {
    final intervalMs = switch (size.width * size.height) {
      < 500000 => 33,
      < 1200000 => 50,
      < 2200000 => 83,
      _ => 125,
    };
    final longest = math.max(1, duration.inMilliseconds);
    return Duration(milliseconds: math.min(intervalMs, longest));
  }

  @override
  void dispose() {
    _resizeResumeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _stopTicking();
    _phase.dispose();
    super.dispose();
  }

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

  void _advance() {
    if (!mounted) return;
    final cycle = widget.cycleDuration.inMicroseconds;
    if (cycle <= 0) return;
    final offset = (_clock.elapsedMicroseconds % cycle) / cycle;
    _phase.value = (widget.staticPhase + offset) % 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final skin = cuSkinOf(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _DriftingGridPainter(
            phase: _phase,
            dark: skin.dark,
            accent: skin.accent,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DriftingGridPainter extends CustomPainter {
  _DriftingGridPainter({
    required this.phase,
    required this.dark,
    required this.accent,
  }) : super(repaint: phase);

  final ValueNotifier<double> phase;
  final bool dark;
  final Color accent;

  static const double _cellSize = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final progress = phase.value % 1.0;
    final dx = progress * _cellSize;
    final dy = ((progress * 0.65) % 1.0) * _cellSize;
    final rect = Offset.zero & size;

    // 经由离屏层叠径向 dstIn 遮罩，使边缘自然消隐而非生硬裁切
    canvas.saveLayer(rect, Paint());

    final linePaint = Paint()
      ..color = dark
          ? Colors.white.withAlpha(18)
          : const Color(0xFF4A3423).withAlpha(15)
      ..strokeWidth = 1.0;

    for (
      double x = -_cellSize + dx;
      x <= size.width + _cellSize;
      x += _cellSize
    ) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (
      double y = -_cellSize + dy;
      y <= size.height + _cellSize;
      y += _cellSize
    ) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // 在稀疏交叉点绘制缓慢呼吸的微光点
    final dotPaint = Paint();
    final columns = (size.width / _cellSize).ceil() + 2;
    final rows = (size.height / _cellSize).ceil() + 2;
    for (var col = -1; col <= columns; col++) {
      for (var row = -1; row <= rows; row++) {
        final hash = (col * 37 + row * 17) % 11;
        if (hash != 0 && hash != 4) continue;
        final x = col * _cellSize + dx;
        final y = row * _cellSize + dy;
        final wave =
            0.5 +
            0.5 * math.sin((progress * 2 * math.pi) + col * 0.7 + row * 0.5);
        final alpha = ((dark ? 58 : 42) * (0.35 + 0.65 * wave)).round();
        dotPaint.color = accent.withAlpha(alpha);
        canvas.drawCircle(Offset(x, y), 1.6, dotPaint);
      }
    }

    final maskPaint = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = const RadialGradient(
        center: Alignment(0.15, -0.05),
        radius: 0.92,
        colors: [Color(0xF0FFFFFF), Color(0x98FFFFFF), Color(0x18FFFFFF)],
        stops: [0.0, 0.58, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, maskPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DriftingGridPainter oldDelegate) =>
      oldDelegate.dark != dark ||
      oldDelegate.accent != accent ||
      oldDelegate.phase != phase;
}
