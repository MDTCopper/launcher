import 'package:flutter/material.dart';

class AnimatedExpansion extends StatefulWidget {
  final Widget? lead;
  final Widget? title;
  final Color? color;
  final List<Widget>? children;
  final Widget? child;
  final bool initExpanded;
  final VoidCallback? onChange;
  final Duration duration;
  final ExpansibleController? controller;

  const AnimatedExpansion({
    super.key,
    this.lead,
    this.title,
    this.children,
    this.initExpanded = false,
    this.onChange,
    this.duration = const Duration(milliseconds: 200),
    this.color,
    this.child,
    this.controller,
  }) : assert(children != null || child != null);

  @override
  State<StatefulWidget> createState() => _AnimatedExpansionState();
}

class _AnimatedExpansionState extends State<AnimatedExpansion>
    with SingleTickerProviderStateMixin {
  //todo 可能有显示性能问题

  late final AnimationController controller;
  late final Animation<double> sizeFactor;
  late final Animation<double> turns;
  late final ExpansibleController expansibleController;
  bool get expanded => expansibleController.isExpanded;

  @override
  void initState() {
    _initExpansibleController();
    controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (!expanded && status.isDismissed) {
          setState(() {});
        }
      });
    sizeFactor = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    turns = Tween(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInBack,
      ),
    );
    if (widget.initExpanded) controller.animateTo(1.0);
    super.initState();
  }

  void _initExpansibleController() {
    expansibleController = widget.controller ?? ExpansibleController();
    if (widget.initExpanded) expansibleController.expand();
    expansibleController.addListener(_update);
  }

  void _update() => setState(() {
    if (expanded) {
      controller.forward();
    } else {
      controller.reverse();
    }
  });

  void _toggle() {
    if (expanded) {
      expansibleController.collapse();
    } else {
      expansibleController.expand();
    }
    widget.onChange?.call();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      expansibleController.dispose();
    } else {
      expansibleController.removeListener(_update);
    }
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final Color backgroundColor =
        widget.color ?? theme.colorScheme.secondaryContainer;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 2,
            offset: Offset(0.0, 2.0),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            iconColor: theme.iconTheme.color,
            titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.primary,
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 16),
            leading: widget.lead,
            title: widget.title,
            trailing: RotationTransition(
              turns: turns,
              child: Icon(Icons.keyboard_arrow_down),
            ),
            onTap: _toggle,
          ),
          //if (expanded || controller.status.isAnimating)
          if (widget.child != null)
            SizeTransition(
              axisAlignment: -0.9,
              sizeFactor: sizeFactor,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: controller,
                    curve: Curves.ease,
                  ),
                  child: widget.child,
                ),
              ),
            ),
          if (widget.children != null)
            SizeTransition(
              axisAlignment: -0.95,
              sizeFactor: sizeFactor,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: controller,
                    curve: Curves.ease,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: widget.children!,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
