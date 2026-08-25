import 'package:flutter/material.dart';

/// 展开/收起容器：基于 Flutter 内置 [Expansible] 的封装。
///
/// 相比手写实现的关键改进——性能：
/// [Expansible.maintainState] 为 false，收起动画完成后 body 会从树上
/// 整体移除（Offstage + 卸载），大 content（如版本列表）不再持续构建；
/// 手写版收起后子树仍挂在树上反复 build。
///
/// 自由度保留：header/body 都能拿到展开 [Animation]（[ExpansibleComponentBuilder]），
/// 标题箭头旋转、body 淡入都由它驱动，观感与手写版一致。
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
        // 性能关键：收起完成后 body 从树上移除，不再持续构建
        maintainState: false,
        animationStyle: AnimationStyle(duration: widget.duration),
        headerBuilder: (context, animation) => ListTile(
          iconColor: theme.iconTheme.color,
          titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.primary,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: widget.lead,
          title: widget.title,
          trailing: RotationTransition(
            turns: Tween(begin: 0.0, end: 0.5).animate(animation),
            child: const Icon(Icons.keyboard_arrow_down),
          ),
          onTap: _toggle,
        ),
        bodyBuilder: (context, animation) => Padding(
          padding: const EdgeInsets.all(8),
          child: FadeTransition(
            opacity: animation,
            child: widget.child ??
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