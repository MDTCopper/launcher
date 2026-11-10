import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 内核组件取「设计层」皮肤：颜色仍然来自 `AppColors`（种子色板），
/// 只是借用 `TemplateSkin` 里的明度/状态推导规则，保证与设计样张完全一致。
///
/// TODO(2026-11-10): 设计样张下线后，把 `TemplateSkin` 搬进 `ui/theme` 并让
/// 这里的实现直接持有，不再依赖 `pages/design`。
TemplateSkin cuSkinOf(BuildContext context) {
  final colors = AppColors.of(context);
  return TemplateSkin.fromAppColors(
    colors: colors,
    dark: Theme.of(context).brightness == Brightness.dark,
  );
}
