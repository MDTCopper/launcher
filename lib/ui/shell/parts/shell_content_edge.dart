import 'package:flutter/material.dart';

import 'package:copper_launcher/ui/theme/app_colors.dart';

/// 内容容器描边：只画左边 + 上边两条 1px 线，左上角跟着内容区的圆角走
///
/// 右、下边不画：那边是窗口/内容自己的边界，再描一圈会像双层框
class ShellContentEdge extends StatelessWidget {
  const ShellContentEdge({
    super.key,
    required this.cornerRadius,
  });

  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ContentEdgePainter(
        color: AppColors.of(context).border,
        cornerRadius: cornerRadius,
      ),
    );
  }
}

class _ContentEdgePainter extends CustomPainter {
  _ContentEdgePainter({required this.color, required this.cornerRadius});

  final Color color;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = cornerRadius;
    // 0.5 内缩让 1px 线落在像素上，不糊成两像素
    final path = Path()..moveTo(0.5, size.height);
    if (radius > 0) {
      path
        ..lineTo(0.5, radius + 0.5)
        ..arcToPoint(
          Offset(radius + 0.5, 0.5),
          radius: Radius.circular(radius),
          clockwise: true,
        );
    } else {
      path.lineTo(0.5, 0.5);
    }
    path.lineTo(size.width, 0.5);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ContentEdgePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}
