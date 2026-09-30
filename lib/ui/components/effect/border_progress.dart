import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 描边进度：沿子组件的外沿画一圈进度
///
/// - 轨道与进度都画在**子组件外面**（由 [strokeWidth] 的内边距让出位置），不遮内容
/// - 进度从左上角起、顺时针走一圈；[progress] 给 null 表示不确定（只画轨道）
/// - 颜色默认取主题语义色：轨道 [AppColors.border]、进度 [AppColors.interactive]
class BorderProgress extends StatelessWidget {
  const BorderProgress({
    super.key,
    required this.progress,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.strokeWidth = 2,
    this.trackColor,
    this.progressColor,
  });

  /// 0~1；null 表示不确定态（只画轨道）
  final double? progress;

  /// 被描边包住的组件
  final Widget child;

  /// 描边形状，应与子组件自己的圆角一致
  final BorderRadius borderRadius;

  /// 描边粗细，也是给描边让出的外边距
  final double strokeWidth;

  final Color? trackColor;
  final Color? progressColor;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return CustomPaint(
      painter: _BorderProgressPainter(
        progress: progress?.clamp(0, 1).toDouble(),
        borderRadius: borderRadius,
        strokeWidth: strokeWidth,
        trackColor: trackColor ?? colors.border,
        progressColor: progressColor ?? colors.interactive,
      ),
      child: Padding(
        padding: EdgeInsets.all(strokeWidth),
        child: child,
      ),
    );
  }
}

class _BorderProgressPainter extends CustomPainter {
  _BorderProgressPainter({
    required this.progress,
    required this.borderRadius,
    required this.strokeWidth,
    required this.trackColor,
    required this.progressColor,
  });

  final double? progress;
  final BorderRadius borderRadius;
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 笔宽的一半收进来，整条描边就落在子组件外侧，不会压到内容
    final strokeArea = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height,
    ).deflate(strokeWidth / 2);
    final trackShape = borderRadius.toRRect(strokeArea);

    canvas.drawRRect(
      trackShape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    final value = progress;
    if (value == null || value <= 0) return;

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = progressColor;

    final shapePath = Path()..addRRect(trackShape);
    for (final metric in shapePath.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * value), progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BorderProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor;
  }
}
