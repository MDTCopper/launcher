import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'palette.dart';

///依靠`GlobalKey<CopperLauncherState>`直接调用`CopperLauncherState`的`updateState`更新整个应用主题配置
void themeSwitchTo(ThemeMode mode, ThemeColor color) {
  final setting = config.setting.personalizationOptions;
  final key = PageKeyProvider.themeKey;
  setting.themeMode = mode;
  setting.themeColor = color;
  key.currentState?.updateState();
  config.save();
}

/// 用 [AppColors] 构建完整的 [ThemeData]，同时将AppColors作为[ThemeData.extension]
///
/// [brightness] , [color] 决定 [ColorScheme] 的方向，
ThemeData buildTheme(Brightness brightness, ThemeColor color) {
  final isDark = brightness == Brightness.dark;
  final AppColors colors;
  switch (color) {
    case ThemeColor.copper:
      colors = isDark ? AppColors.dark : AppColors.light;
      break;
    case ThemeColor.tai:
      colors = isDark ? AppColors.dark : AppColors.light;
      break;
    case ThemeColor.tu:
      colors = isDark ? AppColors.dark : AppColors.light;
      break;
    case ThemeColor.suGang:
      colors = isDark ? AppColors.dark : AppColors.light;
      break;
  }

  return ThemeData(
    brightness: brightness,
    fontFamily: 'sc',

    colorScheme: ColorScheme(
      brightness: brightness,
      primary: colors.interactive,
      onPrimary: colors.textOnInteractive,
      primaryContainer: colors.elevatedBackground,
      secondary: colors.interactiveHover,
      onSecondary: colors.textOnInteractive,
      secondaryContainer: colors.cardBackground,
      surface: colors.cardBackground,
      onSurface: colors.textPrimary,
      surfaceContainerHighest: colors.elevatedBackground,
      error: colors.error,
      onError: colors.textOnInteractive,
      outline: colors.border,
    ),

    // ─────────────────────────────────────────────
    // 页面
    // ─────────────────────────────────────────────
    scaffoldBackgroundColor: colors.pageBackground,
    canvasColor: colors.pageBackground,

    textTheme: TextTheme(
      // ── Display: 超大标题，用于页面主标题、英雄文字 ──
      displayLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
        height: 1.2,
      ),
      displayMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
        height: 1.2,
      ),
      displaySmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
        height: 1.2,
      ),

      // ── Headline: 区块标题、模块名称 ──
      headlineLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
      ),

      // ── Title: 卡片标题、列表项标题、次级标题 ──
      titleLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),

      // ── Body: 正文、说明、注释 ──
      bodyLarge: TextStyle(
        fontSize: 16,
        color: colors.textPrimary,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: colors.textSecondary,
        height: 1.5,
      ),
      bodySmall: TextStyle(fontSize: 12, color: colors.textHint, height: 1.4),

      // ── Label: 按钮文字、标签、徽标 ──
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: colors.textOnInteractive,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: colors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: colors.textHint,
      ),
    ),

    // ─────────────────────────────────────────────
    // 图标
    // ─────────────────────────────────────────────
    iconTheme: IconThemeData(color: colors.interactive, size: 24),

    // ─────────────────────────────────────────────
    // 卡片
    // ─────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: colors.cardBackground,
      elevation: 1,
      shadowColor: Palette.barrier,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),

    // ─────────────────────────────────────────────
    // 输入框
    // ─────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: colors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colors.border, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colors.borderFocus, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colors.error),
        borderRadius: BorderRadius.circular(4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colors.error, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      fillColor: colors.inputBackground,
      filled: true,
      hintStyle: TextStyle(color: colors.textHint, fontSize: 14),
      labelStyle: TextStyle(color: colors.textSecondary, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    ),

    // ─────────────────────────────────────────────
    // 交互反馈
    // ─────────────────────────────────────────────
    hoverColor: colors.splash,
    highlightColor: colors.splash,
    splashColor: colors.splash,
    focusColor: colors.splash,

    // ─────────────────────────────────────────────
    // AppBar
    // ─────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: colors.interactive,
      elevation: 1,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: colors.textOnInteractive,
      ),
      toolbarTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: colors.interactiveHover,
      ),
      iconTheme: IconThemeData(color: colors.textOnInteractive),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    ),

    // ─────────────────────────────────────────────
    // 分割线
    // ─────────────────────────────────────────────
    dividerTheme: DividerThemeData(
      color: colors.border,
      space: 1,
      thickness: 1,
    ),

    // ─────────────────────────────────────────────
    // 进度条
    // ─────────────────────────────────────────────
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.interactive,
      linearTrackColor: colors.interactive.withAlpha(85),
    ),

    // ─────────────────────────────────────────────
    // 滚动条
    // ─────────────────────────────────────────────
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(8),
      thumbColor: WidgetStatePropertyAll(colors.scrollbarThumb),
    ),

    // ─────────────────────────────────────────────
    // 滑块
    // ─────────────────────────────────────────────
    sliderTheme: SliderThemeData(
      trackHeight: 8,
      activeTrackColor: colors.interactive,
      inactiveTrackColor: colors.interactive.withAlpha(85),
      disabledActiveTrackColor: colors.interactive.withAlpha(100),
      disabledInactiveTrackColor: colors.interactive.withAlpha(30),
      disabledThumbColor: colors.interactive.withAlpha(185),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      overlayColor: colors.splash,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
    ),

    // ─────────────────────────────────────────────
    // 开关
    // ─────────────────────────────────────────────
    switchTheme: SwitchThemeData(
      padding: EdgeInsets.zero,
      overlayColor: WidgetStatePropertyAll(colors.splash),
      thumbColor: WidgetStatePropertyAll(colors.interactive),
      trackOutlineColor: WidgetStatePropertyAll(colors.border),
      trackColor: WidgetStatePropertyAll(colors.interactive.withAlpha(55)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),

    // ─────────────────────────────────────────────
    // 挂载自定义 Token
    // ─────────────────────────────────────────────
    extensions: [colors],
  );
}
