import 'dart:ui';
import 'package:flutter/material.dart';

class PercentBar extends StatefulWidget {
  //只能固定每种数据的位置，不能随意改变
  const PercentBar({
    super.key,
    this.dataList,
    this.height,
    this.width,
    this.barColor,
    this.backgroundColor,
    required this.total,
  });

  final double total;
  final double? height;
  final double? width;
  final Color? barColor; //主色调，根据大小依次递减不透明度
  final Color? backgroundColor; //背景色
  final List<PercentBarData>? dataList;

  @override
  State<StatefulWidget> createState() => _PercentBarState();
}

class _PercentBarState extends State<PercentBar> {
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final backgroundColor = widget.backgroundColor ?? color.withAlpha(60);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = widget.height ?? 10;

        List<Widget> children = [];

        if (widget.dataList != null) {
          int noColor = 0; //标记没有标颜色的data数
          for (final data in widget.dataList!) {
            if (data.color == null) noColor++;
          }
          int noColorN = noColor;

          for (int i = 0; i < widget.dataList!.length; i++) {
            final data = widget.dataList![i];
            Color barColor =
                data.color ??
                color.withAlpha(
                  lerpDouble(60, 255, noColor / noColorN)!.toInt(),
                );
            if (data.color == null) noColor--;

            final percent = data.value / widget.total;

            children.add(
              _PercentSingleBar(
                color: barColor,
                size: Size(width, height),
                percent: percent,
              ),
            );
          }
        }

        //填充剩余部分
        children.add(
          Expanded(child: Container(color: backgroundColor, height: height)),
        );

        return Row(children: children);
      },
    );
  }
}

class _PercentSingleBar extends StatefulWidget {
  const _PercentSingleBar({
    required this.color,
    required this.size,
    this.duration = const Duration(milliseconds: 300),
    required this.percent,
  });

  final double percent;
  final Color color;
  final Size size;
  final Duration duration;
  @override
  State<StatefulWidget> createState() => _PercentSingleBarState();
}

class _PercentSingleBarState extends State<_PercentSingleBar>
    with TickerProviderStateMixin {
  late final AnimationController percentController;
  late final AnimationController colorController;

  late Color lastColor;

  @override
  void initState() {
    super.initState();
    lastColor = widget.color.withAlpha(0); //从零不透明度开始
    percentController = AnimationController.unbounded(vsync: this);
    percentController.animateTo(
      widget.percent,
      duration: const Duration(milliseconds: 500),
      curve: Curves.fastOutSlowIn,
    );
    colorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    colorController.forward().then((_) {
      lastColor = widget.color;
    });
  }

  @override
  void didUpdateWidget(covariant _PercentSingleBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.percent != widget.percent) percentAnimate();
    if (oldWidget.color != widget.color) colorAnimate();
  }

  void colorAnimate() {
    colorController.forward(from: 0.0).then((_) {
      lastColor = widget.color;
    });
  }

  void percentAnimate() {
    percentController.animateTo(
      widget.percent,
      duration: widget.duration,
      curve: Curves.fastEaseInToSlowEaseOut,
    );
  }

  @override
  void dispose() {
    percentController.dispose();
    colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([percentController, colorController]),
      builder: (_, _) {
        final colorT = ColorTween(begin: lastColor, end: widget.color).animate(
          CurvedAnimation(parent: colorController, curve: Curves.fastOutSlowIn),
        );
        Size currentSize = Size(
          percentController.value * widget.size.width,
          widget.size.height,
        );
        return CustomPaint(
          size: currentSize,
          painter: _PercentSingleBarPainter(colorT.value!),
        );
      },
    );
  }
}

class _PercentSingleBarPainter extends CustomPainter {
  _PercentSingleBarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint();
    paint.color = color;
    canvas.drawRRect(
      RRect.fromRectAndCorners(Rect.fromLTWH(0, 0, size.width, size.height)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PercentSingleBarPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class PercentBarData implements Comparable<PercentBarData> {
  PercentBarData({this.label, this.value = 0, this.color}) : assert(value >= 0);
  final double value;
  final String? label;
  final Color? color;

  @override
  int compareTo(PercentBarData o) {
    if (o.value == value) return 0;
    if (o.value > value) return 1;
    return -1;
  }

  @override
  String toString() {
    return 'data(${super.hashCode}):[value $value , label $label ]';
  }
}
