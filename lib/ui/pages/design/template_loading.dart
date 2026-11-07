import 'dart:math' as math;

import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:flutter/material.dart';

/// 加载动效候选（2026-11-07 用户说铜钻头「并不好看」，这里给几种新做法挑）
///
/// 每个候选都支持两种用法：
/// - 不传 [phase]：自己无限循环（App 里直接用）
/// - 传 [phase]（0~1）：画固定一帧（样张里并排出「运动分解」）
///
/// 尺寸约定：行内 16 / 20，按钮内 20，整页加载 40 / 56
abstract final class TemplateLoader {
  /// 铜色（皮肤强调色）
  static Color copper(TemplateSkin skin) => skin.accent;

  /// 轨道底色
  static Color track(TemplateSkin skin) => skin.border;
}

/// 通用相位驱动：有固定 [phase] 就静止，否则按 [duration] 循环
class _PhaseLoop extends StatefulWidget {
  const _PhaseLoop({required this.duration, required this.builder, this.phase});

  final Duration duration;
  final Widget Function(double phase) builder;
  final double? phase;

  @override
  State<_PhaseLoop> createState() => _PhaseLoopState();
}

class _PhaseLoopState extends State<_PhaseLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (widget.phase == null) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _PhaseLoop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase == null && !_controller.isAnimating) {
      _controller.repeat();
    } else if (widget.phase != null && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fixed = widget.phase;
    if (fixed != null) return widget.builder(fixed.clamp(0.0, 1.0));
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(_controller.value),
    );
  }
}

// ───────────────────────── ① 弧线环 ─────────────────────────

/// 弧线环：一根带渐隐尾巴的铜色圆弧绕圈，尾端收细
///
/// 最「安全」的一种：任何尺寸都清楚，不依赖主题色的深浅
class TemplateArcSpinner extends StatelessWidget {
  const TemplateArcSpinner({
    super.key,
    required this.skin,
    this.size = 32,
    this.stroke = 2.6,
    this.sweep = 0.72,
    this.phase,
    this.duration = const Duration(milliseconds: 900),
  });

  final TemplateSkin skin;
  final double size;
  final double stroke;

  /// 弧长占整圈的比例（0~1）
  final double sweep;
  final double? phase;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: _PhaseLoop(
        duration: duration,
        phase: phase,
        builder: (phase) => CustomPaint(
          painter: _ArcSpinnerPainter(
            phase: phase,
            stroke: stroke,
            sweep: sweep,
            accent: TemplateLoader.copper(skin),
            track: TemplateLoader.track(skin),
          ),
        ),
      ),
    );
  }
}

class _ArcSpinnerPainter extends CustomPainter {
  _ArcSpinnerPainter({
    required this.phase,
    required this.stroke,
    required this.sweep,
    required this.accent,
    required this.track,
  });

  final double phase;
  final double stroke;
  final double sweep;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track.withAlpha(70),
    );

    final start = phase * math.pi * 2 - math.pi / 2;
    final arc = sweep * math.pi * 2;

    // 尾巴：从淡到实，末端圆头
    final tail = SweepGradient(
      startAngle: 0,
      endAngle: arc,
      colors: [accent.withAlpha(0), accent.withAlpha(120), accent],
      stops: const [0, 0.55, 1],
      transform: GradientRotation(start),
    ).createShader(rect);

    canvas.drawArc(
      rect,
      start,
      arc,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = tail,
    );

    // 头上一颗更亮的小点，让「转」的方向一眼看出来
    final head = Offset(
      center.dx + radius * math.cos(start + arc),
      center.dy + radius * math.sin(start + arc),
    );
    canvas.drawCircle(
      head,
      stroke * 1.35,
      Paint()..color = accent.withAlpha(70),
    );
    canvas.drawCircle(head, stroke * 0.62, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _ArcSpinnerPainter old) =>
      old.phase != phase || old.accent != accent || old.track != track;
}

// ───────────────────────── ② 铜粒轨道 ─────────────────────────

/// 铜粒轨道：三颗铜粒沿轨道追尾旋转，头亮尾淡（最像「铜」的一种）
class TemplateOrbitDots extends StatelessWidget {
  const TemplateOrbitDots({
    super.key,
    required this.skin,
    this.size = 32,
    this.phase,
    this.duration = const Duration(milliseconds: 1200),
  });

  final TemplateSkin skin;
  final double size;
  final double? phase;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: _PhaseLoop(
        duration: duration,
        phase: phase,
        builder: (phase) => CustomPaint(
          painter: _OrbitDotsPainter(
            phase: phase,
            accent: TemplateLoader.copper(skin),
            track: TemplateLoader.track(skin),
          ),
        ),
      ),
    );
  }
}

class _OrbitDotsPainter extends CustomPainter {
  _OrbitDotsPainter({
    required this.phase,
    required this.accent,
    required this.track,
  });

  final double phase;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - size.shortestSide * 0.09;

    // 轨道：一条很淡的圆
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.055
        ..color = track.withAlpha(60),
    );

    final head = phase * math.pi * 2 - math.pi / 2;
    final dot = size.shortestSide * 0.095;
    for (var i = 2; i >= 0; i--) {
      final angle = head - i * 0.9;
      final pos = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      final fade = 1 - i * 0.32;
      // 头灯：外圈晕开
      if (i == 0) {
        canvas.drawCircle(
          pos,
          dot * 2.1,
          Paint()..color = accent.withAlpha(38),
        );
      }
      canvas.drawCircle(
        pos,
        dot * (1 - i * 0.20),
        Paint()..color = accent.withAlpha((255 * fade).round()),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitDotsPainter old) =>
      old.phase != phase || old.accent != accent;
}

// ───────────────────────── ③ 熔炉脉冲 ─────────────────────────

/// 熔炉脉冲：三圈呼吸波纹从中心荡开 + 中心铜点（Mindustry 熔炉味，静态也好看）
class TemplateFurnacePulse extends StatelessWidget {
  const TemplateFurnacePulse({
    super.key,
    required this.skin,
    this.size = 32,
    this.phase,
    this.duration = const Duration(milliseconds: 1500),
  });

  final TemplateSkin skin;
  final double size;
  final double? phase;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: _PhaseLoop(
        duration: duration,
        phase: phase,
        builder: (phase) => CustomPaint(
          painter: _FurnacePulsePainter(
            phase: phase,
            accent: TemplateLoader.copper(skin),
            track: TemplateLoader.track(skin),
          ),
        ),
      ),
    );
  }
}

class _FurnacePulsePainter extends CustomPainter {
  _FurnacePulsePainter({
    required this.phase,
    required this.accent,
    required this.track,
  });

  final double phase;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2 - 1;

    for (var i = 0; i < 3; i++) {
      final t = (phase + i / 3) % 1;
      final radius = maxRadius * (0.22 + 0.78 * t);
      final alpha = ((1 - t) * 0.75 * 255).round();
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = accent.withAlpha(alpha),
      );
    }

    // 中心铜点：轻微呼吸，别太跳
    final breathe = 0.5 + 0.5 * math.sin(phase * math.pi * 2);
    canvas.drawCircle(
      center,
      maxRadius * 0.16 * (0.85 + 0.3 * breathe),
      Paint()..color = accent,
    );
    canvas.drawCircle(
      center,
      maxRadius * 0.30,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = track.withAlpha(90),
    );
  }

  @override
  bool shouldRepaint(covariant _FurnacePulsePainter old) =>
      old.phase != phase || old.accent != accent;
}

// ───────────────────────── ④ 进度环 ─────────────────────────

/// 进度环：确定进度（下载 / 导入用）；[value] 为 null 时退化成不确定态的转圈
class TemplateRingProgress extends StatelessWidget {
  const TemplateRingProgress({
    super.key,
    required this.skin,
    this.size = 40,
    this.value,
    this.stroke = 3,
    this.label,
    this.duration = const Duration(milliseconds: 900),
  });

  final TemplateSkin skin;
  final double size;

  /// 0~1；null = 不确定
  final double? value;
  final double stroke;

  /// 环里的中间文字（通常 `42%`）；不确定态不显示
  final String? label;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final progress = value;
    return SizedBox.square(
      dimension: size,
      child: progress != null
          ? _buildFace(progress)
          : _PhaseLoop(
              duration: duration,
              builder: (phase) => _buildIndeterminate(phase),
            ),
    );
  }

  Widget _buildFace(double progress) => Stack(
    alignment: Alignment.center,
    children: [
      CustomPaint(
        size: Size.square(size),
        painter: _RingPainter(
          value: progress.clamp(0.0, 1.0),
          stroke: stroke,
          accent: TemplateLoader.copper(skin),
          track: TemplateLoader.track(skin),
        ),
      ),
      if (label != null)
        Text(
          label!,
          style: TemplateType.micro.copyWith(
            color: skin.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
    ],
  );

  Widget _buildIndeterminate(double phase) => CustomPaint(
    size: Size.square(size),
    painter: _ArcSpinnerPainter(
      phase: phase,
      stroke: stroke,
      sweep: 0.72,
      accent: TemplateLoader.copper(skin),
      track: TemplateLoader.track(skin),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.accent,
    required this.track,
  });

  final double value;
  final double stroke;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track.withAlpha(70),
    );
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      value * math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.accent != accent;
}

// ───────────────────────── ⑦ 圆点矩阵动效（统一网格） ─────────────────────────

/// 圆点矩阵的几种「抽象」动效：**一张统一网格**，只让点的亮度 / 大小变化来出图案
///
/// 参考方向（都是这类点阵加载的常见做法）：
/// - flutter_dot_loader 的 `MatrixPattern`：radial ripple / dual spiral / ring flash / manhattan pulse
/// - 以及 Dither / halftone 类点阵波纹（点只在亮度上动，网格不动）
///
/// 用户 2026-11-07：钻头那版「也不算好看」，改成这组纯点阵波纹挑
enum TemplateDotPattern {
  /// 径向波纹：一圈圈从中心荡出去
  radialRipple,

  /// 双螺旋：两道光臂绕中心扫
  dualSpiral,

  /// 环闪：一道亮环从中心往外扫，带两条拖影
  ringFlash,

  /// 菱形波：曼哈顿距离上的波（菱形向外扩）
  diamondWave,

  /// 轨道光点：一颗光点在轨道上跑，附近的点被照亮
  orbit,

  /// 随机闪烁：几颗光点在限定范围内随机亮灭（用户 2026-11-07 的想法）
  randomBlink,
}

/// 统一网格的圆点矩阵：网格密度处处一致（不再出现「轮廓更密、里面更空」）
class TemplateDotMatrix extends StatelessWidget {
  const TemplateDotMatrix({
    super.key,
    required this.skin,
    this.size = 64,
    this.dots = 16,
    this.pattern = TemplateDotPattern.radialRipple,
    this.phase,
    this.duration = const Duration(milliseconds: 1600),
    this.sparkles = 7,
    this.spread = 0.86,
    this.seed = 11,
  });

  final TemplateSkin skin;
  final double size;

  /// 横向点阵数：**所有图案、所有尺寸都用同一套网格间距**
  final int dots;
  final TemplateDotPattern pattern;
  final double? phase;
  final Duration duration;

  /// 随机闪烁的「光点」数量
  final int sparkles;

  /// 随机闪烁的限定范围（0~1，相对半径）
  final double spread;

  /// 随机种子：同一个种子每次生成的闪烁点阵一致（不会一帧一换）
  final int seed;

  @override
  Widget build(BuildContext context) {
    // 随机闪烁需要长的整圈才像「不重复」：没显式改 duration 时自动用 24s
    final loopDuration =
        pattern == TemplateDotPattern.randomBlink &&
            duration == const Duration(milliseconds: 1600)
        ? const Duration(milliseconds: 24000)
        : duration;
    return SizedBox.square(
      dimension: size,
      child: _PhaseLoop(
        duration: loopDuration,
        phase: phase,
        builder: (phase) => CustomPaint(
          painter: _DotMatrixPainter(
            phase: phase,
            dots: dots,
            pattern: pattern,
            sparkles: sparkles,
            spread: spread,
            seed: seed,
            accent: TemplateLoader.copper(skin),
            track: TemplateLoader.track(skin),
          ),
        ),
      ),
    );
  }
}

class _DotMatrixPainter extends CustomPainter {
  _DotMatrixPainter({
    required this.phase,
    required this.dots,
    required this.pattern,
    required this.sparkles,
    required this.spread,
    required this.seed,
    required this.accent,
    required this.track,
  }) : _sparkleCells = _buildSparkles(
         dots: dots,
         count: sparkles,
         spread: spread,
         seed: seed,
       );

  final double phase;
  final int dots;
  final TemplateDotPattern pattern;
  final int sparkles;
  final double spread;
  final int seed;
  final Color accent;
  final Color track;

  /// 每颗光点落在哪个格子上 + 各自的周期（整数分频，保证整条动画无缝循环）
  final List<({int col, int row, int k, double offset})> _sparkleCells;

  /// 随机挑格子：同一个种子 → 同一批格子；k 是周期分频（整圈的 1/1、1/2）
  ///
  /// 用户 2026-11-07：频率要慢、像呼吸；效果直接照「轨道光点」那套高斯光斑，
  /// 只是光斑位置固定（不绕圈跑）；循环是不随机的固定序列，只是整圈很长
  static List<({int col, int row, int k, double offset})> _buildSparkles({
    required int dots,
    required int count,
    required double spread,
    required int seed,
  }) {
    final random = math.Random(seed);
    final cells = <({int col, int row, int k, double offset})>[];
    final used = <int>{};
    var guard = 0;
    while (cells.length < count && guard < count * 40) {
      guard++;
      final col = random.nextInt(dots);
      final row = random.nextInt(dots);
      final key = row * dots + col;
      if (used.contains(key)) continue;
      // 限定范围：只取圆内且半径不超过 spread 的格子
      final gx = (col + 0.5) / dots * 2 - 1;
      final gy = (row + 0.5) / dots * 2 - 1;
      final r = math.sqrt(gx * gx + gy * gy);
      if (r > spread) continue;
      used.add(key);
      cells.add((
        col: col,
        row: row,
        // 1..2：一圈里呼吸 1~2 次（整圈 24s → 单次 12~24s）
        k: 1 + random.nextInt(2),
        offset: random.nextDouble(),
      ));
    }
    return cells;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;
    final spacing = radius * 2 / dots;
    final baseDot = spacing * 0.30;

    // 底层：统一网格的淡点，密度哪里都一样
    for (var row = 0; row < dots; row++) {
      for (var col = 0; col < dots; col++) {
        final dx = -radius + spacing * (col + 0.5);
        final dy = -radius + spacing * (row + 0.5);
        if (dx * dx + dy * dy > radius * radius) continue;
        canvas.drawCircle(
          Offset(center.dx + dx, center.dy + dy),
          baseDot * 0.40,
          Paint()..color = track.withAlpha(24),
        );
      }
    }

    // 随机闪烁：先把「这一帧哪些格子亮」算成一张表（含邻近格子的光晕）
    Map<int, double>? blink;
    if (pattern == TemplateDotPattern.randomBlink) {
      blink = _blinkFrame();
    }

    // 亮层：按图案算每颗点的强度
    for (var row = 0; row < dots; row++) {
      for (var col = 0; col < dots; col++) {
        final dx = -radius + spacing * (col + 0.5);
        final dy = -radius + spacing * (row + 0.5);
        final gx = dx / radius;
        final gy = dy / radius;
        final r = math.sqrt(gx * gx + gy * gy);
        if (r > 1) continue;

        final theta = math.atan2(gy, gx);
        final v = blink != null
            ? (blink[row * dots + col] ?? 0)
            : _intensity(r, theta, gx, gy).clamp(0.0, 1.0);
        if (v <= 0.05) continue;

        final pos = Offset(center.dx + dx, center.dy + dy);
        // 随机闪烁走「高斯光斑」：亮的是**一片格子**（半径大），不再叠模糊
        canvas.drawCircle(
          pos,
          baseDot * (0.55 + 0.85 * v),
          Paint()..color = accent.withAlpha((v * 250).round()),
        );
      }
    }
  }

  /// 这一帧的闪烁表：每颗光点按**轨道光点同样的高斯光斑**铺到周围格子上
  ///
  /// 用户 2026-11-07：照抄轨道光点的光斑（不是模糊泛光），只是光斑位置固定在随机格子上；
  /// 频率再放慢（整圈 16s、单次呼吸 8~16s），但仍是**固定序列**的循环
  Map<int, double> _blinkFrame() {
    final table = <int, double>{};
    for (final s in _sparkleCells) {
      // 用「整数分频 × 整圈相位」保证循环接缝不跳
      final local = (phase * s.k + s.offset) % 1.0;
      // 呼吸：0.10 起步（不完全灭），峰值 1.0；余弦包络，慢慢吸/呼
      final breath = 0.5 - 0.5 * math.cos(math.pi * 2 * local);
      final pulse = 0.10 + 0.90 * math.pow(breath, 1.8).toDouble();
      if (pulse <= 0.02) continue;

      // 光斑半径：σ ≈ 1.25 格 → 亮到 2~3 格，跟轨道光点一个观感
      const sigma = 1.25;
      final reach = (sigma * 2.6).ceil();
      for (var dy = -reach; dy <= reach; dy++) {
        for (var dx = -reach; dx <= reach; dx++) {
          final c = s.col + dx;
          final r = s.row + dy;
          if (c < 0 || r < 0 || c >= dots || r >= dots) continue;
          final d2 = (dx * dx + dy * dy) / (sigma * sigma);
          final falloff = math.exp(-d2 / 2);
          if (falloff <= 0.02) continue;
          final key = rowKey(c, r);
          table[key] = math.max(table[key] ?? 0, pulse * falloff);
        }
      }
    }
    return table;
  }

  int rowKey(int col, int row) => row * dots + col;

  double _intensity(double r, double theta, double gx, double gy) {
    final t = phase;
    switch (pattern) {
      case TemplateDotPattern.radialRipple:
        final wave = 0.5 + 0.5 * math.sin(math.pi * 2 * (1.7 * r - t));
        return wave * math.pow(1 - r, 0.35).toDouble();
      case TemplateDotPattern.dualSpiral:
        final wave =
            0.5 + 0.5 * math.sin(2 * theta + math.pi * 2 * (1.1 * r - 2 * t));
        return wave * math.pow(1 - r, 0.20).toDouble();
      case TemplateDotPattern.ringFlash:
        final head = t % 1.0;
        var v = _ring(r, head, 0.14);
        // 两条拖影
        v = math.max(v, _ring(r, head - 0.33, 0.14) * 0.45);
        v = math.max(v, _ring(r, head - 0.66, 0.14) * 0.22);
        return math.max(v, 0.12 * (1 - r));
      case TemplateDotPattern.diamondWave:
        final d = (gx.abs() + gy.abs()) / 2;
        final wave = 0.5 + 0.5 * math.sin(math.pi * 2 * (1.6 * d - t));
        return wave * (1 - d * 0.75);
      case TemplateDotPattern.orbit:
        final angle = math.pi * 2 * t - math.pi / 2;
        final ox = math.cos(angle) * 0.58;
        final oy = math.sin(angle) * 0.58;
        // 正对面再放一颗小一号的，画面才不空
        final ox2 = -ox * 0.92;
        final oy2 = -oy * 0.92;
        final d1 = math.sqrt((gx - ox) * (gx - ox) + (gy - oy) * (gy - oy));
        final d2 = math.sqrt((gx - ox2) * (gx - ox2) + (gy - oy2) * (gy - oy2));
        final head = math.exp(-math.pow(d1 / 0.30, 2).toDouble());
        final tail = math.exp(-math.pow(d2 / 0.22, 2).toDouble()) * 0.55;
        return math.max(head, tail);
      case TemplateDotPattern.randomBlink:
        // 闪烁在 paint 里按格子算（见 _blinkFrame），这里不走
        return 0;
    }
  }

  /// 高斯亮环：半径中心 [center]、宽度 [width]
  double _ring(double r, double center, double width) {
    final d = (r - center) / width;
    return math.exp(-(d * d));
  }

  @override
  bool shouldRepaint(covariant _DotMatrixPainter old) =>
      old.phase != phase ||
      old.pattern != pattern ||
      old.accent != accent ||
      old.track != track ||
      old.dots != dots ||
      old.sparkles != sparkles ||
      old.spread != spread ||
      old.seed != seed;
}

// ───────────────────────── ⑥ 圆点阵列钻头 ─────────────────────────

/// 圆点阵列钻头：整块「像素点阵」里，四片钻臂按角度亮起来形成旋转的叶片
///
/// 用户 2026-11-07：「想做一个圆点阵列的钻头叶片」——点阵不转，**叶片在点阵里转**：
/// 每颗点的亮度由「它相对旋转后钻臂中线的角度差」平滑决定，所以不会闪成一格一格的
///
/// - [dots] 横向点阵数（16~22 比较像「点阵」，再密就糊成实心）
/// - [ring] 外面那圈暗点（勾出钻头圆盘边界），关掉就只剩叶片
/// - [twist] 叶片往外扭的弧度（0 = 正十字，0.5~0.8 才有「钻头」的螺旋感）
class TemplateDotDrill extends StatelessWidget {
  const TemplateDotDrill({
    super.key,
    required this.skin,
    this.size = 64,
    this.dots = 18,
    this.ring = true,
    this.twist = 0.45,
    this.phase,
    this.duration = const Duration(milliseconds: 1400),
  });

  final TemplateSkin skin;
  final double size;
  final int dots;
  final bool ring;
  final double twist;
  final double? phase;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: _PhaseLoop(
        duration: duration,
        phase: phase,
        builder: (phase) => CustomPaint(
          painter: _DotDrillPainter(
            phase: phase,
            dots: dots,
            ring: ring,
            twist: twist,
            accent: TemplateLoader.copper(skin),
            track: TemplateLoader.track(skin),
          ),
        ),
      ),
    );
  }
}

class _DotDrillPainter extends CustomPainter {
  _DotDrillPainter({
    required this.phase,
    required this.dots,
    required this.ring,
    required this.twist,
    required this.accent,
    required this.track,
  });

  final double phase;
  final int dots;
  final bool ring;
  final double twist;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;
    final spacing = radius * 2 / dots;
    final baseDot = spacing * 0.30;
    final rotation = phase * math.pi * 2;
    // 定子正八边形的「内切半径」（apothem）；叶片从它外面起
    final statorApothem = radius * 0.32;

    // ── 圆盘：整块淡淡的「托盘点」+ 一圈明显的盘沿 ──
    for (var row = 0; row < dots; row++) {
      for (var col = 0; col < dots; col++) {
        final dx = -radius + spacing * (col + 0.5);
        final dy = -radius + spacing * (row + 0.5);
        final distance = math.sqrt(dx * dx + dy * dy) / radius;
        if (distance > 1.02) continue;
        final pos = Offset(center.dx + dx, center.dy + dy);

        if (ring) {
          // 盘沿：两圈亮点，一眼就能看出「这是个圆盘」
          final rim = (distance - 0.94).abs() < spacing / radius * 0.8;
          final inner = (distance - 0.82).abs() < spacing / radius * 0.6;
          if (rim) {
            canvas.drawCircle(
              pos,
              baseDot * 0.68,
              Paint()..color = track.withAlpha(150),
            );
            continue;
          }
          if (inner) {
            canvas.drawCircle(
              pos,
              baseDot * 0.45,
              Paint()..color = track.withAlpha(80),
            );
            continue;
          }
        }
        // 盘面：极淡的点，让「盘」有底但不抢叶片
        canvas.drawCircle(
          pos,
          baseDot * 0.42,
          Paint()..color = track.withAlpha(26),
        );
      }
    }

    // ── 叶片：点阵不动，叶片在点阵里转 ──
    for (var row = 0; row < dots; row++) {
      for (var col = 0; col < dots; col++) {
        final dx = -radius + spacing * (col + 0.5);
        final dy = -radius + spacing * (row + 0.5);
        final distance = math.sqrt(dx * dx + dy * dy) / radius;
        if (distance > 0.94 || distance * radius <= statorApothem) continue;

        // 往外扭：同一个半径上的点整体偏一个角度，四片直刃就变成螺旋刃
        final angle =
            math.atan2(dy, dx) + rotation + twist * math.pow(distance, 1.25);
        final sector = angle % (math.pi / 2);
        // 钻臂压在 0° / 90° / 180° / 270°（正十字，正好落在点阵的行列上，边缘干净）
        final signed = sector <= math.pi / 4 ? -sector : (math.pi / 2 - sector);
        final offset = signed.abs();
        // 越往外越收窄，像真钻头的斜刃
        final half = 0.50 * (1 - 0.30 * distance);

        final angular = (1 - offset / half).clamp(0.0, 1.0);
        final rise = ((distance - 0.34) / 0.10).clamp(0.0, 1.0);
        final fall = ((0.90 - distance) / 0.14).clamp(0.0, 1.0);
        final radial = math.min(rise, fall);
        // 顺着转动方向的前缘亮一档，静态帧也看得出往哪边转
        final lead = 0.82 + 0.18 * (signed / half).clamp(-1.0, 1.0);
        final strength = math.pow(angular, 0.55).toDouble() * radial * lead;
        if (strength <= 0.10) continue;

        final pos = Offset(center.dx + dx, center.dy + dy);
        final dotRadius =
            baseDot * (0.70 + 0.30 * strength) * (1 - 0.14 * distance);
        canvas.drawCircle(
          pos,
          dotRadius,
          Paint()..color = accent.withAlpha((strength * 255).round()),
        );
      }
    }

    // ── 定子：正八边形，**同一套网格、实心填满**（不空心、不加密度） ──
    //
    // 八边形内切半径 / cos(到最近边法线的角度差) = 该方向上的边界；
    // 格点落在里面就画，点径与网格一致，斜边自然被量化成阶梯 —— 点阵该有的样子
    final statorEdge = statorApothem / radius;
    for (var row = 0; row < dots; row++) {
      for (var col = 0; col < dots; col++) {
        final dx = -radius + spacing * (col + 0.5);
        final dy = -radius + spacing * (row + 0.5);
        final r = math.sqrt(dx * dx + dy * dy);
        if (r > statorApothem * 1.5) continue;

        final theta = math.atan2(dy, dx);
        final wrapped = ((theta % (math.pi / 4)) + math.pi / 4) % (math.pi / 4);
        final delta = math.min(wrapped, math.pi / 4 - wrapped);
        if (r / radius > statorEdge / math.cos(delta)) continue;

        canvas.drawCircle(
          Offset(center.dx + dx, center.dy + dy),
          baseDot * 0.88,
          Paint()..color = accent,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotDrillPainter old) =>
      old.phase != phase ||
      old.accent != accent ||
      old.track != track ||
      old.dots != dots ||
      old.ring != ring ||
      old.twist != twist;
}

// ───────────────────────── ⑤ 行内传送带 ─────────────────────────

/// 行内传送带：一排小矿石沿轨道往前挪（列表行 / 按钮里当行内 loading）
class TemplateBeltLoader extends StatelessWidget {
  const TemplateBeltLoader({
    super.key,
    required this.skin,
    this.width = 72,
    this.height = 10,
    this.count = 5,
    this.phase,
    this.duration = const Duration(milliseconds: 1100),
  });

  final TemplateSkin skin;
  final double width;
  final double height;
  final int count;
  final double? phase;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: _PhaseLoop(
        duration: duration,
        phase: phase,
        builder: (phase) => CustomPaint(
          painter: _BeltPainter(
            phase: phase,
            count: count,
            accent: TemplateLoader.copper(skin),
            track: TemplateLoader.track(skin),
          ),
        ),
      ),
    );
  }
}

class _BeltPainter extends CustomPainter {
  _BeltPainter({
    required this.phase,
    required this.count,
    required this.accent,
    required this.track,
  });

  final double phase;
  final int count;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    // 轨道
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, cy - 0.75, size.width, 1.5),
        const Radius.circular(1),
      ),
      Paint()..color = track.withAlpha(80),
    );

    final step = size.width / count;
    final item = math.min(step * 0.42, size.height * 0.9);
    final travel = (phase * step) % step;
    for (var i = 0; i < count; i++) {
      final x = i * step + travel;
      if (x > size.width - item / 2) continue;
      final t = x / size.width;
      // 越靠右越亮，像刚被送出来
      final alpha = (90 + 165 * t).round();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + item / 2, cy),
            width: item,
            height: item,
          ),
          Radius.circular(item * 0.28),
        ),
        Paint()..color = accent.withAlpha(alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BeltPainter old) =>
      old.phase != phase || old.accent != accent;
}
