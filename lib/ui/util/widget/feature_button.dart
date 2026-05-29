import 'package:copperlauncher_main/ui/util/widget/rebound_container.dart';
import 'package:flutter/material.dart';

class ReboundButton extends ReboundContainer {
  const ReboundButton({
    super.key,
    super.child,
    required super.onTap,
    super.pressedScale = 0.8,
    super.duration,
    super.onLongTap,
    super.borderRadius = const BorderRadius.all(Radius.circular(4)),
    super.shapeBorder,
    super.padding,
    super.margin = const EdgeInsets.all(4),
    super.hoverColor,
    super.splashColor,
    super.highlightColor,
    super.shadowColor,
    super.backgroundColor,
    super.elevation,
    super.hoverElevation = 2,
  });
}

class ReboundIconButton extends StatelessWidget {
  const ReboundIconButton({
    super.key,
    required this.icon,
    required this.content,
    required this.onTap,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final IconData icon;
  final String content;
  final VoidCallback onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return ReboundButton(
      margin: margin,
      onTap: onTap,
      child: Row(
        spacing: 4,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon), Text(content)],
      ),
    );
  }
}

class SegmentedReboundButton<T> extends StatefulWidget {
  const SegmentedReboundButton({
    super.key,
    required this.segments,
    this.multiSelectionEnabled = false,
    required this.onChange,
    required this.selected,
  });

  final List<ReboundButtonSegment<T>> segments;
  final bool multiSelectionEnabled;
  final void Function(Set<T>) onChange;
  final Set<T> selected;

  @override
  State<StatefulWidget> createState() => _SegmentedReboundButtonState<T>();
}

class _SegmentedReboundButtonState<T> extends State<SegmentedReboundButton<T>> {
  void _onTap(T value) {
    if (widget.multiSelectionEnabled) {
      final set = widget.selected.toSet();
      if (set.contains(value)) {
        set.remove(value);
      } else {
        set.add(value);
      }
      widget.onChange.call(set);
    } else {
      widget.onChange.call({value});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey),
        color: Theme.of(context).colorScheme.secondaryContainer,
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children:
            widget.segments.map<Widget>((it) {
              return SegmentedReboundSingleButton<T>(
                selected: widget.selected.contains(it.value),
                onTap: () => _onTap(it.value),
                child: Row(
                  spacing: 4,
                  children: [
                    if (it.icon != null) it.icon!,
                    if (it.content != null) Text(it.content!),
                    if (it.label != null) it.label!,
                  ],
                ),
              );
            }).toList(),
      ),
    );
  }
}

class ReboundButtonSegment<T> {
  ReboundButtonSegment({
    required this.value,
    this.content,
    this.icon,
    this.label,
    this.enabled = true,
  }) : assert(content != null || label != null);
  final T value;

  final String? content;
  final Widget? icon;
  final Widget? label;

  final bool enabled;
}

class SegmentedReboundSingleButton<T> extends StatefulWidget {
  const SegmentedReboundSingleButton({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final Widget child;
  final VoidCallback onTap;

  @override
  State<StatefulWidget> createState() => _SegmentedReboundSingleButtonState();
}

class _SegmentedReboundSingleButtonState<T>
    extends State<SegmentedReboundSingleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    if (widget.selected) controller.animateTo(1.0);
  }

  @override
  void didUpdateWidget(covariant SegmentedReboundSingleButton oldWidget) {
    if (widget.selected) {
      if (!controller.isForwardOrCompleted) {
        controller.forward();
      }
    } else {
      if (controller.isForwardOrCompleted) {
        controller.reverse();
      }
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textStyle = theme.textTheme.bodyLarge;
    final iconTheme = theme.iconTheme;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final animation = CurvedAnimation(
          parent: controller,
          curve: Curves.fastOutSlowIn,
        );

        final backgroundT = ColorTween(
          begin: colorScheme.secondaryContainer,
          end: colorScheme.secondary,
        ).animate(animation);
        final foregroundT = ColorTween(
          begin: colorScheme.secondary,
          end: colorScheme.secondaryContainer,
        ).animate(animation);

        return ReboundContainer(
          pressedScale: 0.8,
          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          hoverElevation: 2,
          elevation: 1,
          backgroundColor: backgroundT.value,
          borderRadius: BorderRadius.circular(4),
          onTap: widget.onTap,
          child: DefaultTextStyle(
            style: textStyle?.copyWith(color: foregroundT.value) ?? TextStyle(),
            child: IconTheme(
              data: iconTheme.copyWith(color: foregroundT.value),
              child: child!,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
