import 'package:copper_launcher/ui/components/core/cu_list_tile.dart';
import 'package:flutter/material.dart';

/// 列表项：兼容外壳，内部是 [CuListTile]（按压只变色、行间可加分隔线）
///
/// 参数与旧版一致；`elevation` / `hoverElevation` / `pressedScale` 只做兼容，
/// 不再生效（旧的整行缩放已退役）。
class ReboundListTile extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final bool selected;
  final bool enable;
  final BoxDecoration? decoration;
  final Color? baseColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final double itemSpacing;
  final double elevation;
  final double hoverElevation;
  final double pressedScale;

  const ReboundListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongTap,
    this.selected = false,
    this.enable = true,
    this.decoration,
    this.baseColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.margin,
    this.borderRadius,
    this.itemSpacing = 8,
    this.elevation = 0,
    this.hoverElevation = 4,
    this.pressedScale = 0.95,
  });

  @override
  Widget build(BuildContext context) {
    return CuListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: enable ? onTap : null,
      onLongPress: enable ? onLongTap : null,
      selected: selected,
      enabled: enable,
      padding: padding,
      margin: margin,
      borderRadius: borderRadius,
      decoration: decoration,
      backgroundColor: baseColor,
      itemSpacing: itemSpacing,
    );
  }
}
