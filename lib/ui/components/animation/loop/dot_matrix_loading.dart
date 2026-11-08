import 'dart:math' as math;

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 圆点矩阵闪烁：几颗光点在限定范围内按节奏亮灭（呼吸 / 依次亮 + 留白）
///
/// 设计来源：设计层 `template_loading.dart` 的 `randomBlink`（2026-11-08 定稿）
/// - 一张统一网格，网格不动，只让点的亮度变
/// - 节奏：一波 **3~5 颗**光点相隔 [stagger] 依次亮起，每颗亮 [light]，然后留白 [pause]
/// - 每次换一组光点（固定种子 → 固定序列，整圈 [duration] 循环，18s）
/// - 光斑是高斯分布（σ≈1.25 格），跟「轨道光点」观感一致
class DotMatrixLoading extends StatefulWidget {
  const DotMatrixLoading({
    super.key,
    this.size = 40,
    this.seed = 11,
    this.sparkles = 7,
    this.spread = 0.58,
    this.duration = const Duration(milliseconds: 18000),
  });

  /// 边长；网格密度会随尺寸自动取（16 / 20 格）
  final double size;

  /// 固定种子：同一个种子每次生成的光点位置 / 节奏一样
  final int seed;

  /// 候选光点数量
  final int sparkles;

  /// 光点分布半径（0~1）
  final double spread;

  /// 整圈时长
  final Duration duration;

  @override
  State<DotMatrixLoading> createState() => _DotMatrixLoadingState();
}

class _DotMatrixLoadingState extends State<DotMatrixLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant DotMatrixLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
      if (!_controller.isAnimating) _controller.repeat();
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
    // 小尺寸用更稀的网格，否则 16px 上点太小认不出
    final dots = widget.size >= 100
        ? 20
        : widget.size >= 32
        ? 16
        : 10;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _DotMatrixLoadingPainter(
            phase: _controller.value,
            dots: dots,
            seed: widget.seed,
            sparkles: widget.sparkles,
            spread: widget.spread,
            loopMs: widget.duration.inMilliseconds.toDouble(),
            accent: colors.interactive,
            track: colors.border,
          ),
        ),
      ),
    );
  }
}

/// 一颗按节奏亮起的光点
class _Light {
  const _Light(this.col, this.row, this.startMs, this.durMs);

  final int col;
  final int row;
  final double startMs;
  final double durMs;
}

/// 整条节奏表
class _Schedule {
  const _Schedule(this.lights, this.loopMs);

  final List<_Light> lights;
  final double loopMs;
}

class _DotMatrixLoadingPainter extends CustomPainter {
  _DotMatrixLoadingPainter({
    required this.phase,
    required this.dots,
    required this.seed,
    required this.sparkles,
    required this.spread,
    required this.loopMs,
    required this.accent,
    required this.track,
  }) : _schedule = _buildSchedule(
         dots: dots,
         count: sparkles,
         spread: spread,
         seed: seed,
         loopMs: loopMs,
       );

  final double phase;
  final int dots;
  final int seed;
  final int sparkles;
  final double spread;
  final double loopMs;
  final Color accent;
  final Color track;

  final _Schedule _schedule;

  static _Schedule _buildSchedule({
    required int dots,
    required int count,
    required double spread,
    required int seed,
    required double loopMs,
  }) {
    final random = math.Random(seed);
    // 候选格子：限定范围 + 相互至少隔 2 格
    final pool = <({int col, int row})>[];
    var guard = 0;
    while (pool.length < count && guard < count * 60) {
      guard++;
      final col = random.nextInt(dots);
      final row = random.nextInt(dots);
      final gx = (col + 0.5) / dots * 2 - 1;
      final gy = (row + 0.5) / dots * 2 - 1;
      if (math.sqrt(gx * gx + gy * gy) > spread) continue;
      var tooClose = false;
      for (final other in pool) {
        final ddx = (other.col - col).toDouble();
        final ddy = (other.row - row).toDouble();
        if (ddx * ddx + ddy * ddy < 4.0) {
          tooClose = true;
          break;
        }
      }
      if (tooClose) continue;
      pool.add((col: col, row: row));
    }
    if (pool.isEmpty) return const _Schedule([], 0);

    const minPerWave = 3;
    const maxPerWave = 5;
    const staggerMs = 220.0;
    const lightMs = 760.0;
    const pauseMs = 350.0;

    final lights = <_Light>[];
    Set<int> lastPick = {};
    var timeMs = 0.0;
    while (true) {
      final want = math.min(
        minPerWave + random.nextInt(maxPerWave - minPerWave + 1),
        pool.length,
      );
      final waveEnd = timeMs + (want - 1) * staggerMs + lightMs;
      if (waveEnd > loopMs) break;

      Set<int> pick;
      do {
        pick = <int>{};
        var tries = 0;
        while (pick.length < want && tries < 400) {
          tries++;
          pick.add(random.nextInt(pool.length));
        }
      } while (pool.length > want &&
          pick.length == lastPick.length &&
          pick.difference(lastPick).isEmpty);
      lastPick = pick;

      final ordered = pick.toList()..sort();
      for (var i = 0; i < ordered.length; i++) {
        final cell = pool[ordered[i]];
        lights.add(_Light(cell.col, cell.row, timeMs + i * staggerMs, lightMs));
      }
      timeMs = waveEnd + pauseMs;
      if (timeMs >= loopMs) break;
    }
    return _Schedule(lights, loopMs);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;
    final spacing = radius * 2 / dots;
    final baseDot = spacing * 0.30;

    // 底层：统一网格淡点
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

    if (_schedule.loopMs <= 0) return;
    final nowMs = phase * _schedule.loopMs;
    final table = <int, double>{};
    for (final light in _schedule.lights) {
      final local = (nowMs - light.startMs) / light.durMs;
      if (local <= 0 || local >= 1) continue;
      final pulse = math.pow(math.sin(math.pi * local), 1.1).toDouble();
      if (pulse <= 0.02) continue;
      const sigma = 1.25;
      final reach = (sigma * 2.6).ceil();
      for (var dy = -reach; dy <= reach; dy++) {
        for (var dx = -reach; dx <= reach; dx++) {
          final c = light.col + dx;
          final r = light.row + dy;
          if (c < 0 || r < 0 || c >= dots || r >= dots) continue;
          final d2 = (dx * dx + dy * dy) / (sigma * sigma);
          final falloff = math.exp(-d2 / 2);
          if (falloff <= 0.02) continue;
          final key = r * dots + c;
          table[key] = math.max(table[key] ?? 0, pulse * falloff);
        }
      }
    }

    for (var row = 0; row < dots; row++) {
      for (var col = 0; col < dots; col++) {
        final v = table[row * dots + col] ?? 0;
        if (v <= 0.05) continue;
        final dx = -radius + spacing * (col + 0.5);
        final dy = -radius + spacing * (row + 0.5);
        canvas.drawCircle(
          Offset(center.dx + dx, center.dy + dy),
          baseDot * (0.55 + 0.85 * v),
          Paint()..color = accent.withAlpha((v * 250).round()),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotMatrixLoadingPainter old) =>
      old.phase != phase ||
      old.accent != accent ||
      old.track != track ||
      old.dots != dots ||
      old.seed != seed ||
      old.sparkles != sparkles ||
      old.spread != spread ||
      old.loopMs != loopMs;
}
