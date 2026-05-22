import 'package:flutter/material.dart';

class DrillLoading extends StatefulWidget {
  final Duration duration;
  final bool finished;

  const DrillLoading({
    super.key,
    this.duration = const Duration(seconds: 5),
    this.finished = false,
  });

  @override
  State<StatefulWidget> createState() => _DrillLoadingState();
}

class _DrillLoadingState extends State<DrillLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      animationBehavior: AnimationBehavior.preserve,
    )..repeat();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(110, 110),
            painter: _DrillBottomPainter(color: theme.colorScheme.primary),
          ),

          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return RotationTransition(
                turns: _controller,
                child: CustomPaint(
                  size: Size(100, 100),
                  painter: _DrillFansPainter(color: theme.colorScheme.primary),
                ),
              );
            },
          ),
          ClipPath(
            clipper: _DrillTopPainter(
              color: theme.colorScheme.primaryContainer,
            ),
            child: Container(width: 60,height: 60,color: Colors.transparent,),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _DrillFansPainter extends CustomPainter {
  final Color color;

  _DrillFansPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 5;

    final path = Path();
    path.moveTo(size.width * 0.45, 0);
    path.cubicTo(
      size.width * 0.45,
      0,
      size.width * 0.4,
      size.height * 0.05,
      size.width * 0.4,
      size.height * 0.05,
    );
    path.cubicTo(
      size.width * 0.4,
      size.height * 0.05,
      size.width * 0.4,
      size.height * 0.37,
      size.width * 0.4,
      size.height * 0.37,
    );
    path.cubicTo(
      size.width * 0.4,
      size.height * 0.37,
      size.width * 0.05,
      size.height * 0.37,
      size.width * 0.05,
      size.height * 0.37,
    );
    path.cubicTo(
      size.width * 0.05,
      size.height * 0.37,
      0,
      size.height * 0.42,
      0,
      size.height * 0.42,
    );
    path.cubicTo(
      0,
      size.height * 0.42,
      0,
      size.height * 0.53,
      0,
      size.height * 0.53,
    );
    path.cubicTo(
      0,
      size.height * 0.53,
      size.width * 0.05,
      size.height * 0.58,
      size.width * 0.05,
      size.height * 0.58,
    );
    path.cubicTo(
      size.width * 0.05,
      size.height * 0.58,
      size.width * 0.4,
      size.height * 0.58,
      size.width * 0.4,
      size.height * 0.58,
    );
    path.cubicTo(
      size.width * 0.4,
      size.height * 0.58,
      size.width * 0.4,
      size.height * 0.95,
      size.width * 0.4,
      size.height * 0.95,
    );
    path.cubicTo(
      size.width * 0.4,
      size.height * 0.95,
      size.width * 0.45,
      size.height,
      size.width * 0.45,
      size.height,
    );
    path.cubicTo(
      size.width * 0.45,
      size.height,
      size.width * 0.55,
      size.height,
      size.width * 0.55,
      size.height,
    );
    path.cubicTo(
      size.width * 0.55,
      size.height,
      size.width * 0.6,
      size.height * 0.95,
      size.width * 0.6,
      size.height * 0.95,
    );
    path.cubicTo(
      size.width * 0.6,
      size.height * 0.95,
      size.width * 0.6,
      size.height * 0.58,
      size.width * 0.6,
      size.height * 0.58,
    );
    path.cubicTo(
      size.width * 0.6,
      size.height * 0.58,
      size.width * 0.95,
      size.height * 0.58,
      size.width * 0.95,
      size.height * 0.58,
    );
    path.cubicTo(
      size.width * 0.95,
      size.height * 0.58,
      size.width,
      size.height * 0.53,
      size.width,
      size.height * 0.53,
    );
    path.cubicTo(
      size.width,
      size.height * 0.53,
      size.width,
      size.height * 0.42,
      size.width,
      size.height * 0.42,
    );
    path.cubicTo(
      size.width,
      size.height * 0.42,
      size.width * 0.95,
      size.height * 0.37,
      size.width * 0.95,
      size.height * 0.37,
    );
    path.cubicTo(
      size.width * 0.95,
      size.height * 0.37,
      size.width * 0.6,
      size.height * 0.37,
      size.width * 0.6,
      size.height * 0.37,
    );
    path.cubicTo(
      size.width * 0.6,
      size.height * 0.37,
      size.width * 0.6,
      size.height * 0.05,
      size.width * 0.6,
      size.height * 0.05,
    );
    path.cubicTo(
      size.width * 0.6,
      size.height * 0.05,
      size.width * 0.55,
      0,
      size.width * 0.55,
      0,
    );
    path.cubicTo(
      size.width * 0.55,
      0,
      size.width * 0.45,
      0,
      size.width * 0.45,
      0,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DrillFansPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _DrillBottomPainter extends CustomPainter {
  final Color color;

  _DrillBottomPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {//感觉也只能自己画了，软件不靠谱，暂时不知道为什么旋转轴不在中心
    Paint paint = Paint();
    Path path = Path();
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 5;
    paint.color = color;
    path = Path();
    path.moveTo(size.width / 5, 0);
    path.cubicTo(size.width / 5, 0, 0, size.height / 5, 0, size.height / 5);
    path.cubicTo(
      0,
      size.height / 5,
      0,
      size.height * 0.8,
      0,
      size.height * 0.8,
    );
    path.cubicTo(
      0,
      size.height * 0.8,
      size.width / 5,
      size.height,
      size.width / 5,
      size.height,
    );
    path.cubicTo(
      size.width / 5,
      size.height,
      size.width * 0.8,
      size.height,
      size.width * 0.8,
      size.height,
    );
    path.cubicTo(
      size.width * 0.8,
      size.height,
      size.width,
      size.height * 0.8,
      size.width,
      size.height * 0.8,
    );
    path.cubicTo(
      size.width,
      size.height * 0.8,
      size.width,
      size.height / 5,
      size.width,
      size.height / 5,
    );
    path.cubicTo(
      size.width,
      size.height / 5,
      size.width * 0.8,
      0,
      size.width * 0.8,
      0,
    );
    path.cubicTo(size.width * 0.8, 0, size.width / 5, 0, size.width / 5, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}

class _DrillTopPainter extends CustomClipper<Path> {
  final Color color;

  _DrillTopPainter({required this.color});

  void paint(Canvas canvas, Size size) {
    Paint paint = Paint();
    Path path = Path();

    paint.style = PaintingStyle.fill;
    paint.color = Colors.transparent;

    canvas.drawPath(path, paint);
    paint.style = PaintingStyle.stroke;
    paint.color = color;
    paint.strokeWidth = 5;
    canvas.drawPath(path, paint);
  }

  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }

  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width * 0.3, 0);
    path.cubicTo(
      size.width * 0.3,
      0,
      0,
      size.height * 0.3,
      0,
      size.height * 0.3,
    );
    path.cubicTo(
      0,
      size.height * 0.3,
      0,
      size.height * 0.7,
      0,
      size.height * 0.7,
    );
    path.cubicTo(
      0,
      size.height * 0.7,
      size.width * 0.3,
      size.height,
      size.width * 0.3,
      size.height,
    );
    path.cubicTo(
      size.width * 0.3,
      size.height,
      size.width * 0.7,
      size.height,
      size.width * 0.7,
      size.height,
    );
    path.cubicTo(
      size.width * 0.7,
      size.height,
      size.width,
      size.height * 0.7,
      size.width,
      size.height * 0.7,
    );
    path.cubicTo(
      size.width,
      size.height * 0.7,
      size.width,
      size.height * 0.3,
      size.width,
      size.height * 0.3,
    );
    path.cubicTo(
      size.width,
      size.height * 0.3,
      size.width * 0.7,
      0,
      size.width * 0.7,
      0,
    );
    path.cubicTo(size.width * 0.7, 0, size.width * 0.3, 0, size.width * 0.3, 0);
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
