
import 'package:flutter/material.dart';

import '../../feature/feature_curve.dart';
import 'feature_button.dart';

typedef GridItemAnimatedBuilder =
    Widget Function(Widget? child, Animation<double> animation);

class AppearGirdView extends StatefulWidget {
  final List<Widget?> items;
  final EdgeInsetsGeometry? padding;

  final double interval; //item出现间隔
  final int delay; //动画延迟时间,过渡外部动画时间
  final Duration appearDuration; //单个item出现动画的时间
  final GridItemAnimatedBuilder gridItemAnimatedBuilder;

  final SliverGridDelegate? gridDelegate;
  final bool shrinkWrap;
  final ScrollPhysics? scrollPhysics;
  final ScrollController? scrollController;

  const AppearGirdView({
    super.key,
    required this.items,
    this.padding,
    this.interval = 0.2,
    this.delay = 0,
    this.appearDuration = const Duration(milliseconds: 300),
    this.gridDelegate,
    this.shrinkWrap = false,
    this.scrollPhysics,
    this.gridItemAnimatedBuilder = _defaultBuilder,
    this.scrollController,
  });

  static Widget _defaultBuilder(Widget? child, Animation<double> animation) {
    final scale = Tween(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: animation, curve: FeatureCurves.reboundIn),
    );
    final fade = CurvedAnimation(
      parent: animation,
      curve: FeatureCurves.reboundIn,
    );
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(scale: scale, child: child),
    );
  }

  @override
  State<StatefulWidget> createState() => _AppearGirdViewState();
}

class _AppearGirdViewState extends State<AppearGirdView>
    with SingleTickerProviderStateMixin {
  late final ScrollController scrollController;
  bool needUp = false;

  late final AnimationController controller;

  late final double _duration;
  late final Duration? totalAppearDuration; //总时间

  @override
  void initState() {
    _duration =
        widget.delay +
        widget.appearDuration.inMilliseconds *
            (1 + widget.interval * (widget.items.length - 1));
    totalAppearDuration = Duration(milliseconds: _duration.floor());

    controller = AnimationController(
      vsync: this,
      duration: totalAppearDuration,
    );
    controller.forward();

    scrollController = widget.scrollController ?? ScrollController();

    if (!widget.shrinkWrap) {
      scrollController.addListener(() {
        if (needUp == false && scrollController.offset > 1200) {
          setState(() {
            needUp = true;
          });
        }
        if (needUp == true && scrollController.offset < 600) {
          setState(() {
            needUp = false;
          });
        }
      });
    }

    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return Container();

    List<Widget> items = [];

    final double delay = widget.delay / _duration;
    final double interval =
        widget.interval * widget.appearDuration.inMilliseconds / _duration;
    final double duration = widget.appearDuration.inMilliseconds / _duration;

    for (int i = 0; i < widget.items.length; i++) {
      double begin = delay + interval * i;
      double end = begin + duration;

      Animation<double> animation = CurvedAnimation(
        parent: controller,
        curve: Interval(begin, end),
      );

      Widget? item = widget.items[i];
      item = widget.gridItemAnimatedBuilder(item, animation);
      items.add(item);
    }

    Widget child = GridView(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.scrollPhysics,
      gridDelegate:
          widget.gridDelegate ??
          SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            childAspectRatio: 0.6,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
      children: items,
    );

    if (!widget.shrinkWrap) {
      child = Stack(
        children: [
          child,
          Positioned(
            left: 40,
            bottom: 20,
            child: AnimatedOpacity(
              opacity: needUp ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeIn,
              child: AnimatedScale(
                scale: needUp ? 1.0 : 0.0,
                curve: FeatureCurves.reboundIn,
                duration: const Duration(milliseconds: 200),
                child: ReboundButton(
                  elevation: 4.0,
                  borderRadius: const BorderRadius.all(Radius.circular(50)),
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

    return child;
  }
}
