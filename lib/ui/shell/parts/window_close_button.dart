import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/vars.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowCloseButton extends StatefulWidget {
  const WindowCloseButton({super.key});

  @override
  State<StatefulWidget> createState() => _WindowCloseButtonState();
}

class _WindowCloseButtonState extends State<WindowCloseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  bool onHover = false;
  bool onTap = false;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: fastAnimationDuration,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (onHover && onTap) {
      controller.forward();
    } else if (!onHover && !onTap) {
      controller.reverse();
    } else {
      controller.animateTo(0.5, duration: fastAnimationDuration);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.of(context);
    final colorT = ColorTween(
      begin: color.error.withAlpha(0),
      end: color.error,
    );

    return GestureDetector(
      onTapDown: (_) => setState(() => onTap = true),
      onTapCancel: () => setState(() => onTap = false),
      onTapUp: (_) => setState(() => onTap = false),
      child: MouseRegion(
        onEnter: (_) => setState(() => onHover = true),
        onExit: (_) => setState(() => onHover = false),
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, child) {
            final error = colorT.animate(controller).value;
            return ReboundButton(
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              backgroundColor: error,
              child: Icon(
                Icons.close,
                color: onHover && onTap
                    ? color.interactiveHigh
                    : color.interactive,
                fontWeight: onHover && onTap
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
              onTap: () => windowManager.close(),
            );
          },
        ),
      ),
    );
  }
}
