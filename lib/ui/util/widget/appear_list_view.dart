import 'dart:io';

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/widget/desktop_scroll_view.dart';
import 'package:flutter/material.dart';

import '../../feature/feature_curve.dart';
import 'feature_button.dart';

typedef ListItemAnimatedBuilder =
    Widget Function(Widget? child, Animation<double> animation);

class AppearListView extends StatefulWidget {
  final List<Widget?> items;
  final double itemSpacing;
  final EdgeInsetsGeometry? padding;

  final double interval; //item出现间隔
  final int delay; //动画延迟时间,过渡外部动画时间
  final Duration? appearDuration; //单个item出现动画的时间
  final Offset offset; //起始偏移
  final ScrollController? scrollController;

  final ScrollPhysics? physics;

  const AppearListView({
    super.key,

    this.interval = 0.3,
    this.delay = 0,
    this.appearDuration = const Duration(milliseconds: 200),

    this.itemSpacing = 4.0,
    this.padding,
    required this.offset,
    this.scrollController,
    this.physics,
    required this.items,
  });

  @override
  State<StatefulWidget> createState() => _AppearListView();
}

class _AppearListView extends State<AppearListView>
    with SingleTickerProviderStateMixin {
  late final ScrollController scrollController;
  bool showUpButton = false;

  late final AnimationController controller;
  late final double _duration;
  late final Duration? totalAppearDuration; //总时间

  @override
  void initState() {
    _duration =
        widget.delay +
        widget.appearDuration!.inMilliseconds *
            (1 + widget.interval * (widget.items.length - 1));

    totalAppearDuration = Duration(milliseconds: _duration.floor());

    controller = AnimationController(
      vsync: this,
      duration: totalAppearDuration,
    );
    controller.forward();

    scrollController = widget.scrollController ?? ScrollController()
      ..addListener(() {
        if (showUpButton == false && scrollController.offset > 1200) {
          setState(() {
            showUpButton = true;
          });
        }
        if (showUpButton == true && scrollController.offset < 600) {
          setState(() {
            showUpButton = false;
          });
        }
      });

    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    if (widget.scrollController == null) {
      scrollController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return ListView();

    final color = AppColors.of(context);
    final isDesktop = !Platform.isAndroid;

    List<Widget> items = [];

    double delay = widget.delay / _duration;
    double interval =
        widget.interval * widget.appearDuration!.inMilliseconds / _duration;
    double duration = widget.appearDuration!.inMilliseconds / _duration;

    for (int i = 0; i < widget.items.length; i++) {
      Widget? item = widget.items[i];
      if (item == null) continue;
      double begin = delay + interval * i;
      double end = begin + duration;

      final position = Tween<Offset>(begin: widget.offset, end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: controller,
              curve: Interval(begin, end, curve: FeatureCurves.reboundIn),
            ),
          );

      final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: controller,
          curve: Interval(begin, end, curve: FeatureCurves.reboundIn),
        ),
      );

      Widget animationItem = FadeTransition(
        opacity: opacity,
        child: SlideTransition(position: position, child: item),
      );

      items.add(animationItem);
    }

    Widget child = SingleChildScrollView(
      physics: widget.physics,
      controller: scrollController,
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: widget.itemSpacing,
        children: items,
      ),
    );

    if (isDesktop) {
      child = DesktopScrollViewContainer(
        controller: scrollController,
        child: child,
      );
    }

    return Stack(
      children: [
        child,
        Positioned(
          left: 40,
          bottom: 20,
          child: AnimatedOpacity(
            opacity: showUpButton ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeIn,
            child: AnimatedScale(
              scale: showUpButton ? 1.0 : 0.0,
              curve: FeatureCurves.reboundIn,
              duration: const Duration(milliseconds: 200),
              child: ReboundButton(
                hoverElevation: 4.0,
                elevation: 1.0,
                borderRadius: const BorderRadius.all(Radius.circular(50)),
                backgroundColor: color.cardBackground,
                onTap: () {
                  setState(() {
                    scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  });
                },
                child: Icon(Icons.arrow_upward),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
