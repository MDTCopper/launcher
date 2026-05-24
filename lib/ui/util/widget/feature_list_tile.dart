import 'package:copperlauncher_main/ui/util/widget/rebound_container.dart';
import 'package:flutter/material.dart';

class ReboundListTile extends StatefulWidget {
  final bool enable; //todo 暂时搁置：禁用变灰

  final Color? backgroundColor;

  //交互颜色
  final double elevation;
  final double hoverElevation;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final IconThemeData? iconThemeData;

  //回弹
  final double? pressedScale;
  final Duration duration; //回弹持续时间

  //装饰
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final ShapeBorder? shapeBorder;
  final double itemSpacing;

  //交互
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  //子组件
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;

  const ReboundListTile({
    super.key,
    this.enable = true,

    this.backgroundColor,
    this.titleStyle,
    this.subtitleStyle,
    this.iconThemeData,

    this.pressedScale = 0.95,
    this.duration = const Duration(milliseconds: 200),
    this.onTap,
    this.onLongTap,

    this.padding = const EdgeInsets.all(0),
    this.margin = const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
    this.borderRadius,
    this.shapeBorder,
    this.hoverElevation = 4.0,
    this.elevation = 0.0,

    this.leading,
    this.title,
    this.subtitle,

    this.trailing,
    this.itemSpacing = 4.0,
  });

  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    return _ReboundListTileState();
  }
}

class _ReboundListTileState extends State<ReboundListTile> {
  final trailingKey = GlobalKey();

  Size? trailingSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        trailingSize = trailingKey.currentContext?.size;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final backgroundColor =
        widget.backgroundColor ?? theme.colorScheme.secondaryContainer;

    final titleStyle = widget.titleStyle ?? theme.textTheme.bodyLarge;
    final subtitleStyle = widget.subtitleStyle ?? theme.textTheme.bodySmall;
    final iconThemeData =
        widget.iconThemeData ??
        IconThemeData(color: theme.textTheme.bodySmall?.color, size: 18);

    Widget? title = widget.title;
    if (title != null && titleStyle != null) {
      title = DefaultTextStyle(style: titleStyle, child: title);
    }
    Widget? subtitle = widget.subtitle;
    if (subtitle != null && subtitleStyle != null) {
      subtitle = DefaultTextStyle(style: subtitleStyle, child: subtitle);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 40),
      child: IconTheme(
        data: iconThemeData,
        child: ReboundContainer(
          pressedScale: widget.pressedScale,
          backgroundColor: backgroundColor,
          padding: widget.padding,
          margin: widget.margin,
          borderRadius: widget.borderRadius,
          shapeBorder: widget.shapeBorder,
          elevation: widget.elevation,
          hoverElevation: widget.hoverElevation,
          onTap: widget.onTap,
          onLongTap: widget.onLongTap,
          surfaceChild:
              widget.trailing == null
                  ? null
                  : Align(
                    alignment: Alignment.centerRight,
                    child: UnconstrainedBox(
                      key: trailingKey,
                      child: widget.trailing,
                    ),
                  ),
          child: Row(
            spacing: widget.itemSpacing,
            children: [
              if (widget.leading != null) widget.leading!,
              if (title != null || subtitle != null)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null) title,
                      if (subtitle != null) subtitle,
                    ],
                  ),
                ),
              if (widget.trailing != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: trailingSize?.width,
                    height: trailingSize?.height,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
