import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 标签页（下划线式，搬运自 `TemplateTabBar`）
class CuTabBar extends StatelessWidget {
  const CuTabBar({
    super.key,
    required this.tabs,
    required this.value,
    required this.onTap,
    this.trailing,
  });

  final List<String> tabs;
  final int value;
  final ValueChanged<int> onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => TemplateTabBar(
    skin: cuSkinOf(context),
    tabs: tabs,
    value: value,
    onTap: onTap,
    trailing: trailing,
  );
}
