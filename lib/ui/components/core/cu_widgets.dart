import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 这一层是「设计层组件 → 内核入口」的机械搬运：
/// 每个 `Cu*` 都直接复用对应的 `Template*`，只把 `skin` 换成 `cuSkinOf(context)`。
///
/// 后续微调时**改设计层实现**（或不满意再搬实现进 core），不要在这里另写样式。

/// 行：内衬 + 可选点击 / 选中
class CuRow extends StatelessWidget {
  const CuRow({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.enabled = true,
    this.padding,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: cuSkinOf(context),
      onTap: onTap,
      selected: selected,
      enabled: enabled,
      padding: padding,
      child: child,
    );
  }
}

/// 两行文本：标题 + 说明
class CuTwoLine extends StatelessWidget {
  const CuTwoLine({
    super.key,
    required this.title,
    this.desc,
    this.enabled = true,
  });

  final String title;
  final String? desc;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TemplateTwoLine(
    skin: cuSkinOf(context),
    title: title,
    desc: desc,
    enabled: enabled,
  );
}

/// 键值行：左标题右值
class CuKeyRow extends StatelessWidget {
  const CuKeyRow({super.key, required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) =>
      TemplateKeyRow(skin: cuSkinOf(context), title: title, value: value);
}

/// 字段块：标题 + 说明 + 任意控件
class CuFieldBlock extends StatelessWidget {
  const CuFieldBlock({
    super.key,
    required this.title,
    required this.child,
    this.desc,
    this.enabled = true,
  });

  final String title;
  final Widget child;
  final String? desc;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TemplateFieldBlock(
    skin: cuSkinOf(context),
    title: title,
    desc: desc,
    enabled: enabled,
    child: child,
  );
}

/// 开关行：标题 + 说明 + 右侧开关
class CuSwitchRow extends StatelessWidget {
  const CuSwitchRow({
    super.key,
    required this.title,
    required this.desc,
    required this.value,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String desc;
  final bool value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TemplateSwitchRow(
    skin: cuSkinOf(context),
    title: title,
    desc: desc,
    value: value,
    onTap: onTap,
    enabled: enabled,
  );
}

/// 设置小条：单行标题 + 右侧控件（高度取开关热区）
class CuSettingTile extends StatelessWidget {
  const CuSettingTile({
    super.key,
    required this.title,
    this.trailing,
    this.onTap,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TemplateSettingTile(
    skin: cuSkinOf(context),
    title: title,
    trailing: trailing,
    onTap: onTap,
  );
}

/// 快捷入口方块
class CuShortcut extends StatelessWidget {
  const CuShortcut({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TemplateShortcut(
    skin: cuSkinOf(context),
    icon: icon,
    label: label,
    onTap: onTap,
    enabled: enabled,
  );
}

/// 下拉行（外观）：左标签 + 右侧值框
class CuSelectRow extends StatelessWidget {
  const CuSelectRow({
    super.key,
    required this.title,
    required this.value,
    this.onTap,
    this.enabled = true,
    this.labelWidth = 150,
  });

  final String title;
  final String value;
  final VoidCallback? onTap;
  final bool enabled;
  final double labelWidth;

  @override
  Widget build(BuildContext context) => TemplateSelectRow(
    skin: cuSkinOf(context),
    title: title,
    value: value,
    onTap: onTap,
    enabled: enabled,
    labelWidth: labelWidth,
  );
}

/// 滑条行：标题 + 实时值 + 轨道
class CuSliderRow extends StatelessWidget {
  const CuSliderRow({
    super.key,
    required this.title,
    required this.value,
    required this.label,
    this.onChanged,
    this.divisions = 20,
    this.enabled = true,
    this.minLabel,
    this.maxLabel,
    this.showTicks = false,
  });

  final String title;
  final double value;
  final String label;
  final ValueChanged<double>? onChanged;
  final int divisions;
  final bool enabled;
  final String? minLabel;
  final String? maxLabel;
  final bool showTicks;

  @override
  Widget build(BuildContext context) => TemplateSliderRow(
    skin: cuSkinOf(context),
    title: title,
    value: value,
    label: label,
    onChanged: onChanged,
    divisions: divisions,
    enabled: enabled,
    minLabel: minLabel,
    maxLabel: maxLabel,
    showTicks: showTicks,
  );
}

/// 分页
class CuPager extends StatelessWidget {
  const CuPager({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onPage,
    this.firstLast = false,
  });

  final int page;
  final int pageCount;
  final ValueChanged<int> onPage;
  final bool firstLast;

  @override
  Widget build(BuildContext context) => TemplatePager(
    skin: cuSkinOf(context),
    page: page,
    pageCount: pageCount,
    onPage: onPage,
    firstLast: firstLast,
  );
}

/// 折叠块
class CuCollapse extends StatelessWidget {
  const CuCollapse({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final String? subtitle;
  final Widget? trailing;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => TemplateCollapse(
    skin: cuSkinOf(context),
    title: title,
    subtitle: subtitle,
    trailing: trailing,
    initiallyExpanded: initiallyExpanded,
    child: child,
  );
}

/// 列表卡（行内卡片）
class CuListCard extends StatelessWidget {
  const CuListCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.cover,
    this.badge,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? cover;
  final Widget? badge;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TemplateListCard(
    skin: cuSkinOf(context),
    title: title,
    subtitle: subtitle,
    icon: icon,
    cover: cover,
    badge: badge,
    trailing: trailing,
    onTap: onTap,
    selected: selected,
    enabled: enabled,
  );
}

/// 网格卡
class CuGridCard extends StatelessWidget {
  const CuGridCard({
    super.key,
    required this.title,
    this.subtitle,
    this.cover,
    this.icon,
    this.badge,
    this.onTap,
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final Widget? cover;
  final IconData? icon;
  final Widget? badge;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => TemplateGridCard(
    skin: cuSkinOf(context),
    title: title,
    subtitle: subtitle,
    cover: cover,
    icon: icon,
    badge: badge,
    onTap: onTap,
    selected: selected,
  );
}

/// 输入行：标题 + 输入框
class CuInputRow extends StatelessWidget {
  const CuInputRow({
    super.key,
    required this.title,
    required this.controller,
    this.hint = '',
    this.enabled = true,
    this.multiline = false,
    this.obscure = false,
    this.error,
    this.maxLength,
    this.suffix,
  });

  final String title;
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final bool multiline;
  final bool obscure;
  final String? error;
  final int? maxLength;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) => TemplateInputRow(
    skin: cuSkinOf(context),
    title: title,
    controller: controller,
    hint: hint,
    enabled: enabled,
    multiline: multiline,
    obscure: obscure,
    error: error,
    maxLength: maxLength,
    suffix: suffix,
  );
}
