import 'package:copperlauncher_main/ui/util/widget/rebound_container.dart';
import 'package:flutter/material.dart';

class ReboundListTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final backgroundColor = this.backgroundColor??theme.colorScheme.secondaryContainer;

    final titleStyle = this.titleStyle ?? theme.textTheme.bodyLarge;
    final subtitleStyle = this.subtitleStyle ?? theme.textTheme.bodySmall;
    final iconThemeData =
        this.iconThemeData ??
        IconThemeData(color: theme.textTheme.bodySmall?.color, size: 18);

    late Widget? title = this.title;
    if (title != null && titleStyle != null) {
      title = DefaultTextStyle(style: titleStyle, child: title);
    }
    late Widget? subtitle = this.subtitle;
    if (subtitle != null && subtitleStyle != null) {
      subtitle = DefaultTextStyle(style: subtitleStyle, child: subtitle);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 40),
      child: IconTheme(
        data: iconThemeData,
        child: ReboundContainer(
          pressedScale: pressedScale,
          backgroundColor: backgroundColor,
          padding: padding,
          margin: margin,
          borderRadius: borderRadius,
          shapeBorder: shapeBorder,
          elevation: elevation,
          hoverElevation: hoverElevation,
          onTap: onTap,
          onLongTap: onLongTap,
          surfaceChild:
              trailing == null
                  ? null
                  : Align(alignment: Alignment.centerRight, child: trailing!),
          child: Row(
            spacing: itemSpacing,
            children: [
              if (leading != null) leading!,
              if (title != null || subtitle != null)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if(title!=null)
                      title,
                      if(subtitle!=null)
                      subtitle,
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
