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
