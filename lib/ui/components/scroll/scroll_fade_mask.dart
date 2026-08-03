import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

class ScrollFadeMask extends StatefulWidget {
  final Widget child;
  final ScrollController controller;

  const ScrollFadeMask({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  State<StatefulWidget> createState() => _ScrollFadeMaskState();
}

class _ScrollFadeMaskState extends State<ScrollFadeMask>
    with WidgetsBindingObserver {
  bool showTopFade = false;
  bool showBottomFade = false;

  @override
  initState() {
    super.initState();
    widget.controller.addListener(() {
      final maxScroll = widget.controller.position.maxScrollExtent;
      final offset = widget.controller.offset;
      setState(() {
        showTopFade = offset > 0;
        showBottomFade = offset < maxScroll;
      });
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final maxScroll = widget.controller.position.maxScrollExtent;
    final offset = widget.controller.offset;
    setState(() {
      showTopFade = offset > 0;
      showBottomFade = offset < maxScroll;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: showTopFade ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 100),
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentGeometry.topCenter,
                  end: AlignmentGeometry.bottomCenter,
                  colors: [
                    colors.cardBackground,
                    colors.cardBackground.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: showBottomFade ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 100),
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentGeometry.bottomCenter,
                  end: AlignmentGeometry.topCenter,
                  colors: [
                    colors.cardBackground,
                    colors.cardBackground.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
