import 'package:flutter/material.dart';

import '../widget/appear_list_view.dart';
import '../widget/rebound_container.dart';

class SideMenuBar extends StatelessWidget {
  final List<Widget?> items;

  final double interval; //item出现间隔
  final int delay; //动画延迟时间,过渡外部动画时间
  final Duration appearDuration; //单个item出现动画的时间
  final Duration? transformDuration;
  final double width;

  const SideMenuBar({
    super.key,
    required this.items,
    this.appearDuration = const Duration(milliseconds: 200),
    this.transformDuration,
    this.interval = 0.3,
    this.delay = 300,
    this.width = 180,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: Theme.of(context).colorScheme.secondaryContainer,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).cardTheme.shadowColor??Theme.of(context).shadowColor,
            spreadRadius:0.5,
            blurRadius: 0.5,
            offset: Offset(0.0,1.5),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      margin: EdgeInsets.fromLTRB(0, 8, 8, 8),
      padding: EdgeInsets.all(10),
      child: AppearListView(
        items: items,
        interval: interval,
        delay: delay,
        appearDuration: appearDuration,

        offset: Offset(0.2, 0.0),
      ),
    );
  }
}

class MenuItem extends StatefulWidget {
  //状态
  final bool selected;
  final bool enable; //todo 暂时搁置：禁用变灰
  final bool isSide;

  //状态颜色
  final Color? itemColor;
  final Color? activeItemColor;
  final Color? backgroundColor;
  final Color? activeBackgroundColor;

  //交互颜色
  final double elevation;
  final Color? hoverColor;
  final Color? splashColor;
  final Color? highlightColor;
  final Color? shadowColor;

  //回弹
  final double? pressedScale;
  final Duration duration; //回弹持续时间

  //装饰
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final ShapeBorder? shapeBorder;
  final double itemSpacing;
  final BoxConstraints constraints;

  //交互
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  //子组件
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;

  final Widget? trailing;

  const MenuItem({
    super.key,
    this.selected = false,
    this.enable = true,
    this.isSide = true,

    this.itemColor,
    this.activeItemColor,
    this.backgroundColor,
    this.activeBackgroundColor,
    this.hoverColor,

    this.splashColor,
    this.highlightColor,
    this.shadowColor,

    this.pressedScale = 0.95,
    this.duration = const Duration(milliseconds: 200),
    this.onTap,
    this.onLongTap,

    this.padding = const EdgeInsets.all(0),
    this.margin = const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.shapeBorder,
    this.elevation = 4.0,

    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.itemSpacing = 12.0,
    this.constraints = const BoxConstraints(minHeight: 40),
  });

  @override
  State<StatefulWidget> createState() => _MenuItemState();
}

class _MenuItemState extends State<MenuItem>
    with SingleTickerProviderStateMixin {
  late final ThemeData theme = Theme.of(context);

  late final Color _itemColor = widget.itemColor ?? theme.colorScheme.primary;
  late final Color _itemActiveColor =
      widget.activeItemColor ?? theme.colorScheme.secondaryContainer;
  late final Color _backgroundColor =
      widget.backgroundColor ?? theme.colorScheme.secondaryContainer;
  late final Color _backgroundActiveColor =
      widget.activeBackgroundColor ?? theme.colorScheme.primary;

  late final AnimationController controller;
  late Animation backgroundColor;
  late Animation itemColor;

  late final VoidCallback? onTap;
  late final VoidCallback? onLongTap;

  bool isHover = false;

  @override
  void initState() {
    if (widget.onTap != null) {
      onTap = () {
        setState(() {});
        widget.onTap?.call();
      };
    }

    onLongTap =
        widget.onLongTap == null
            ? null
            : () {
              setState(() {});
              widget.onLongTap?.call();
            };

    controller = AnimationController(vsync: this, duration: widget.duration);

    if (widget.selected) controller.animateTo(1.0, duration: Duration());

    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MenuItem oldWidget) {
    if (widget.selected) {
      controller.forward();
    } else {
      controller.reverse();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    backgroundColor = ColorTween(
      begin: _backgroundColor,
      end: _backgroundActiveColor,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeIn));

    itemColor = ColorTween(
      begin: _itemColor,
      end: _itemActiveColor,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeIn));
    return ConstrainedBox(
      constraints: widget.constraints,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          Color color = itemColor.value;

          TextStyle titleTextStyle = DefaultTextStyle.of(
            context,
          ).style.copyWith(
            overflow: TextOverflow.ellipsis,
            fontSize: 16,
            fontWeight:
                controller.isForwardOrCompleted
                    ? FontWeight.w900
                    : FontWeight.bold,
            color: color,
          );

          TextStyle subtitleTextStyle = DefaultTextStyle.of(
            context,
          ).style.copyWith(
            overflow: TextOverflow.ellipsis,
            fontSize: 12,
            fontWeight:
                controller.isForwardOrCompleted
                    ? FontWeight.w900
                    : FontWeight.bold,
            color: color.withAlpha(170),
          );

          Widget content = DefaultTextStyle(
            style: TextStyle(overflow: TextOverflow.ellipsis),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.title != null)
                  DefaultTextStyle(style: titleTextStyle, child: widget.title!),
                if (widget.subtitle != null)
                  DefaultTextStyle(
                    style: subtitleTextStyle,
                    child: widget.subtitle!,
                  ),
              ],
            ),
          );
          if (widget.isSide) {
            content = Expanded(child: content);
          }

          return ReboundContainer(
            hoverElevation: widget.elevation,
            hoverColor: widget.hoverColor,
            splashColor: widget.splashColor,
            backgroundColor: backgroundColor.value,
            padding: widget.padding,
            margin: widget.margin,
            borderRadius: widget.borderRadius,
            shapeBorder: widget.shapeBorder,
            onTap: onTap,
            onLongTap: onLongTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: widget.itemSpacing,
              children: [
                //leading
                if (widget.leading != null)
                  IconTheme(
                    data: IconThemeData(color: itemColor.value, size: 30),
                    child: widget.leading!,
                  ),
                content,
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          );
        },
      ),
    );
  }
}
