import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:flutter/material.dart';

class ReboundCheckbox extends StatefulWidget {
  const ReboundCheckbox({
    super.key,
    required this.value,
    this.icon,
    this.label,
    this.onChange,
    this.itemColor,
    this.itemActiveColor,
    this.backgroundColor,
    this.backgroundActiveColor,
  });

  final String? label;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChange;

  final Color? itemColor;
  final Color? itemActiveColor;
  final Color? backgroundColor;
  final Color? backgroundActiveColor;

  @override
  State<StatefulWidget> createState() => _ReboundCheckboxState();
}

class _ReboundCheckboxState extends State<ReboundCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    if (widget.value) _controller.animateTo(1.0);
  }

  @override
  void didUpdateWidget(covariant ReboundCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final itemColor = widget.itemColor ?? theme.colorScheme.onSurface;
    final itemActiveColor =
        widget.itemActiveColor ?? theme.colorScheme.secondaryContainer;
    final backgroundColor =
        widget.backgroundColor ?? theme.colorScheme.secondaryContainer;
    final backgroundActiveColor =
        widget.backgroundActiveColor ?? theme.colorScheme.primary;

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 20, minHeight: 20),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) {
          final animation = CurvedAnimation(
            parent: _controller,
            curve: Curves.ease,
          );

          final itemColorTween = ColorTween(
            begin: itemColor,
            end: itemActiveColor,
          ).animate(animation);
          final backgroundColorTween = ColorTween(
            begin: backgroundColor,
            end: backgroundActiveColor,
          ).animate(animation);
          return ReboundButton(
            backgroundColor: backgroundColorTween.value,
            onTap: () => widget.onChange?.call(!widget.value),
            child: Row(
              spacing: 4,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null)
                  Icon(widget.icon!, color: itemColorTween.value),
                if (widget.label != null)
                  Text(
                    widget.label!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: itemColorTween.value,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ReboundCheckChangeBox extends StatefulWidget {
  const ReboundCheckChangeBox({
    super.key,
    required this.value,
    this.icon,
    this.activeIcon,
    this.label,
    this.onChange,
    this.itemColor,
    this.itemActiveColor,
    this.backgroundColor,
    this.backgroundActiveColor,
  });

  final String? label;
  final bool value;
  final ValueChanged<bool>? onChange;

  final Icon? icon;
  final Icon? activeIcon;

  final Color? itemColor;
  final Color? itemActiveColor;
  final Color? backgroundColor;
  final Color? backgroundActiveColor;

  @override
  State<StatefulWidget> createState() => _ReboundCheckChangeBoxState();
}

class _ReboundCheckChangeBoxState extends State<ReboundCheckChangeBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    if (widget.value) _controller.animateTo(1.0);
  }

  @override
  void didUpdateWidget(covariant ReboundCheckChangeBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final itemColor = widget.itemColor ?? theme.colorScheme.onSurface;
    final itemActiveColor =
        widget.itemActiveColor ?? theme.colorScheme.secondaryContainer;
    final backgroundColor =
        widget.backgroundColor ?? theme.colorScheme.secondaryContainer;
    final backgroundActiveColor =
        widget.backgroundActiveColor ?? theme.colorScheme.primary;

    final icon = widget.icon ?? Icon(Icons.close);
    final activeIcon = widget.activeIcon ?? Icon(Icons.check);

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 20, minHeight: 20),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) {
          final animation = CurvedAnimation(
            parent: _controller,
            curve: Curves.ease,
          );

          final itemColorTween = ColorTween(
            begin: itemColor,
            end: itemActiveColor,
          ).animate(animation);
          final backgroundColorTween = ColorTween(
            begin: backgroundColor,
            end: backgroundActiveColor,
          ).animate(animation);
          return ReboundButton(
            backgroundColor: backgroundColorTween.value,
            elevation: 2,
            onTap:
                widget.onChange == null
                    ? null
                    : () => widget.onChange?.call(!widget.value),
            child: Row(
              spacing: 4,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) {
                    final Animation<double> turns;

                    if (animation.isForwardOrCompleted) {
                      turns = Tween(begin: -0.25, end: 0.0).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutBack,
                        ),
                      );
                    } else {
                      turns = Tween(begin: 0.25, end: 0.0).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInBack,
                        ),
                      );
                    }

                    final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Interval(0.4, 1.0),
                        // reverseCurve: Interval(0.3, 1.0),
                      ),
                    );

                    return FadeTransition(
                      opacity: opacity,
                      child: RotationTransition(turns: turns, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(widget.value),
                    child: IconTheme(
                      data: theme.iconTheme.copyWith(
                        color: itemColorTween.value,
                      ),
                      child: widget.value ? activeIcon : icon,
                    ),
                  ),
                ),
                if (widget.label != null)
                  Text(
                    widget.label!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: itemColorTween.value,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
