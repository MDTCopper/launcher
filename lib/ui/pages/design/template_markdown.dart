import 'package:copper_launcher/ui/components/future/readme_source.dart';
import 'package:copper_launcher/ui/components/future/readme_view.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// README 渲染（设计层封装）
///
/// **不自己写解析器**：项目里已有 `ReadmeView`（`package:markdown` 的 AST + 直写 HTML
/// 处理 + 图片 / 相对链接解析），这里只把皮肤翻译成它要的 `AppColors` 与 `ThemeData`，
/// 换皮的问题就落在这一层。
class TemplateMarkdown extends StatelessWidget {
  const TemplateMarkdown({
    super.key,
    required this.skin,
    required this.data,
    this.source,
    this.onLinkTap,
  });

  final TemplateSkin skin;

  /// README 原文
  final String data;

  /// 相对链接 / 相对图片按哪个仓库解析；不传就按 `owner/repo` 为空处理
  final ReadmeSource? source;

  /// 链接点击；不传就用渲染器默认行为（系统浏览器 / 内嵌 webview）
  final void Function(String url)? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    // 字体族 / 字号沿用当前 Theme，只把文字颜色换成皮肤那套；
    // 标题按设计层的字号刻度收一档（README 的默认标题在最小窗口里太大）
    final text = base.textTheme.apply(
      bodyColor: skin.textPrimary,
      displayColor: skin.textPrimary,
    );
    final theme = base.copyWith(
      // 代码块底色 / 主题色也走皮肤：渲染器里用到 colorScheme 的三处（primary /
      // secondaryContainer / surfaceContainerHighest）都从这里取
      colorScheme: base.colorScheme.copyWith(
        primary: skin.accent,
        secondaryContainer: skin.selected,
        surfaceContainerHighest: skin.sunken,
        surface: skin.surface,
        onSurface: skin.textPrimary,
      ),
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: text.titleSmall?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 13, height: 1.6),
      ),
    );
    return ReadmeView(
      data: data,
      source: source ?? const ReadmeSource(repo: ''),
      onLinkTap: onLinkTap,
      colorsOverride: templateAppColorsFromSkin(skin),
      themeOverride: theme,
    );
  }
}

/// 皮肤 → `AppColors`：给暂时还在用 `AppColors` 的既有组件（如 `ReadmeView`）换皮用
///
/// 只覆盖会用到的那几个语义位，其余沿用亮 / 暗底表，避免颜色映射散得到处都是
AppColors templateAppColorsFromSkin(TemplateSkin skin) {
  final base = skin.dark ? AppColors.dark : AppColors.light;
  return base.copyWith(
    pageBackground: skin.page,
    cardBackground: skin.surface,
    inputBackground: skin.sunken,
    elevatedBackground: skin.raised,
    lowBackgroundOnCard: skin.sunken,
    highBackgroundOnCard: skin.selected,
    itemPrimary: skin.textPrimary,
    itemSecondary: skin.textSecondary,
    itemOnInteractive: skin.onAccent,
    itemHint: skin.textTertiary,
    interactive: skin.accent,
    interactiveLow: skin.accentTint,
    interactiveHigh: skin.accentText,
    splash: skin.pressed,
    border: skin.border,
    borderFocus: skin.accent,
    inputBorder: skin.controlBorder,
    inputBorderHover: skin.borderStrong,
    inputBorderFocus: skin.accent,
    inputBackgroundFocus: skin.sunken,
    scrollbarThumb: skin.scrollbarThumb,
    scrollbarThumbHover: skin.scrollbarThumbHover,
    scrollbarTrack: skin.scrollbarTrack,
    error: skin.dangerText,
    success: skin.success,
    warning: skin.warning,
    indicator: skin.accent,
    indicatorBackground: skin.sunken,
    barrier: skin.barrier,
    shadow: skin.shadow,
  );
}
