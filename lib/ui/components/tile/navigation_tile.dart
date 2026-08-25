import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/animation/animated_opacity_size.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:flutter/material.dart';

class NavigationTile extends StatefulWidget {
  final Icon icon;
  final String content;
  final String? lable;
  final String? hint;
  final VoidCallback onTap;
  final bool selected;
  final bool collapse;
  final HintPosition hintPosition;

  const NavigationTile({
    super.key,
    required this.icon,
    required this.content,
    this.lable,
    this.hint,
    required this.onTap,
    this.selected = false,
    this.collapse = false,
    this.hintPosition = .auto,
  });
  @override
  State<StatefulWidget> createState() => NavigationTileState();
}

class NavigationTileState extends State<NavigationTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (widget.selected) controller.animateTo(1.0);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  Widget _buildTile() {
    final theme = Theme.of(context);

    Widget child;
    if (widget.lable != null) {
      child = Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          Text(widget.content),
          DefaultTextStyle(
            style: theme.textTheme.labelSmall ?? TextStyle(),
            maxLines: 1,
            overflow: .ellipsis,
            child: Text(widget.lable!),
          ),
        ],
      );
    } else {
      child = Text(widget.content);
    }

    return child;
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.of(context);
    final theme = Theme.of(context);
    final backgroundColorT = ColorTween(
      begin: color.interactive.withAlpha(0),
      end: color.interactive.withAlpha(45),
    ).animate(controller);
    final itemColorT = ColorTween(
      begin: color.itemPrimary,
      end: color.interactive,
    ).animate(controller);

    Widget child = AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final itemColor = itemColorT.value;
        final backgroundColor = backgroundColorT.value;
        return ReboundButton(
          pressedScale: 0.9,
          elevation: 0.0,
          hoverElevation: 0.0,
          padding: EdgeInsets.all(8),
          borderRadius: BorderRadius.circular(8),
          backgroundColor: backgroundColor,
          onTap: widget.onTap,
          child: IconTheme(
            data: IconTheme.of(context).copyWith(color: itemColor),
            child: DefaultTextStyle(
              maxLines: 1,
              style: theme.textTheme.labelLarge!.copyWith(
                color: itemColor,
                overflow: .ellipsis,
                fontWeight: widget.selected
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
              child: child!,
            ),
          ),
        );
      },
      child: Row(
        children: [
          widget.icon,
          Expanded(
            child: Padding(
              padding: EdgeInsetsGeometry.only(left: 8),
              child: AnimatedOpacitySize(
                duration: const Duration(milliseconds: 400),
                curve: Curves.ease,
                child: widget.collapse ? null : _buildTile(),
              ),
            ),
          ),
        ],
      ),
    );

    child = HintLayer(
      hint: widget.collapse ? (widget.hint ?? widget.content) : null,
      child: child,
    );

    return child;
  }
}
