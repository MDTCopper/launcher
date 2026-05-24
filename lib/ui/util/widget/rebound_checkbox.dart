import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:flutter/material.dart';

class ReboundCheckbox extends StatefulWidget {
  const ReboundCheckbox({
    super.key,
    required this.value,
    this.icon,
    this.label,
    this.onChange,
  });

  final String? label;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChange;

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

    final itemColor = theme.colorScheme.onSurface;
    final itemActiveColor = theme.colorScheme.secondaryContainer;
    final backgroundColor = theme.colorScheme.secondaryContainer;
    final backgroundActiveColor = theme.colorScheme.primary;

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
