import 'package:copper_launcher/ui/vars.dart';
import 'package:flutter/material.dart';

/// 展开/收起容器：基于 Flutter 内置 [Expansible] 的封装

class AnimatedExpansion extends StatefulWidget {
  final Widget? lead;
  final Widget? title;
  final Color? color;
  final List<Widget>? children;
  final Widget? child;
  final bool initExpanded;
  final VoidCallback? onChange;
  final Duration? duration;
  final ExpansibleController? controller;

  const AnimatedExpansion({
    super.key,
    this.lead,
    this.title,
    this.children,
    this.initExpanded = false,
    this.onChange,
    this.duration,
    this.color,
    this.child,
    this.controller,
  }) : assert(children != null || child != null);

  @override
  State<StatefulWidget> createState() => _AnimatedExpansionState();
}

class _AnimatedExpansionState extends State<AnimatedExpansion> {
  late final ExpansibleController controller;

  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? ExpansibleController();
    if (widget.initExpanded) controller.expand();
  }

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (controller.isExpanded) {
      controller.collapse();
    } else {
      controller.expand();
    }
    widget.onChange?.call();
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
      child: Expansible(
        controller: controller,
        // 收起完成后 body 从树上移除，不再持续构建
        maintainState: false,
        animationStyle: AnimationStyle(
          duration: widget.duration ?? animationDuration,
        ),
        // ListTile 的水波纹画在最近的 Material 上；外层 Container 带背景色会夹在中间
        // 使墨水效果不可见并触发 Flutter 调试警告，故包一层透明 Material 承接
        headerBuilder: (context, animation) => Material(
          type: MaterialType.transparency,
          child: ListTile(
            iconColor: theme.iconTheme.color,
            titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.primary,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: widget.lead,
            title: widget.title,
            trailing: RotationTransition(
              turns: Tween(begin: 0.0, end: 0.5).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                  reverseCurve: Curves.easeInBack,
                ),
              ),
              child: const Icon(Icons.keyboard_arrow_down),
            ),
            onTap: _toggle,
          ),
        ),
        bodyBuilder: (context, animation) => Padding(
          padding: const EdgeInsets.all(8),
          child: FadeTransition(
            opacity: animation,
            child:
                widget.child ??
                Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: widget.children!,
                ),
          ),
        ),
      ),
    );
  }
}
