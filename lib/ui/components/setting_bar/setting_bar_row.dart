import 'package:copper_launcher/ui/components/core/cu_setting_row.dart';
import 'package:flutter/material.dart';

/// 设置条行：兼容外壳，内部是 [CuSettingRow]
///
/// 行为语义不变：宽度足够时标题取 [titleWide]、控件占满剩余；宽度不足时
/// 控件保 [controlMinWidth]、标题被挤压。行底分隔线用 [decoration] 透传。
class SettingBarRow extends StatelessWidget {
  final String title;
  final Widget control;
  final double titleWide;
  final double controlMinWidth;
  final double gap;
  final TextStyle? titleStyle;
  final BoxDecoration? decoration;

  const SettingBarRow({
    super.key,
    required this.title,
    required this.control,
    this.titleWide = 150,
    this.controlMinWidth = 100,
    this.gap = 8,
    this.titleStyle,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return CuSettingRow(
      title: title,
      control: control,
      titleWide: titleWide,
      controlMinWidth: controlMinWidth,
      gap: gap,
      titleStyle: titleStyle,
      decoration: decoration,
    );
  }
}
