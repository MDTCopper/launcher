import 'dart:io';
import 'dart:ui' as ui;
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
  key.currentState?.updateTheme();
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

  final ui.Locale systemLocale = ui.PlatformDispatcher.instance.locale;
  final String languageCode = systemLocale.languageCode.toLowerCase();
  final String? countryCode = systemLocale.countryCode?.toUpperCase();

  String? fontFamily;
  if (Platform.isWindows) {
    fontFamily = switch (languageCode) {
      'ja' => 'Yu Gothic UI',
      'ko' => 'Malgun Gothic',
      'zh' => (countryCode == 'TW' || countryCode == 'HK' || countryCode == 'MO')
          ? 'Microsoft JhengHei UI'
          : 'Microsoft YaHei UI',
      _ => 'Segoe UI Variable Display',
    };
  } else if (Platform.isLinux) {
    fontFamily = switch (languageCode) {
      'ja' => 'Noto Sans CJK JP',
      'ko' => 'Noto Sans CJK KR',
      'zh' => (countryCode == 'TW' || countryCode == 'HK' || countryCode == 'MO')
          ? 'Noto Sans CJK TC'
          : 'Noto Sans CJK SC',
      _ => 'Noto Sans',
    };
  } else {
    fontFamily = null; // macOS / iOS 等其他平台交由系统托管
  }

  return ThemeData(
    brightness: brightness,
    fontFamily: fontFamily,

    colorScheme: ColorScheme(
      brightness: brightness,
      primary: colors.interactiveLow,
      onPrimary: colors.itemOnInteractive,
      primaryContainer: colors.elevatedBackground,
      secondary: colors.interactive,
      onSecondary: colors.itemOnInteractive,
      secondaryContainer: colors.cardBackground,
      surface: colors.cardBackground,
      onSurface: colors.itemPrimary,
      surfaceContainerHighest: colors.elevatedBackground,
      error: colors.error,
      onError: colors.itemOnInteractive,
      outline: colors.border,
    ),

    // ─────────────────────────────────────────────
    // 页面
    // ─────────────────────────────────────────────
    scaffoldBackgroundColor: colors.pageBackground,
    canvasColor: colors.pageBackground,

    textTheme: TextTheme(
      // ── Display: 超大标题，强调色(interactive)，用于页面主标题、英雄文字 ──
      displayLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: colors.interactive,
        height: 1.2,
      ),
      displayMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: colors.interactive,
        height: 1.2,
      ),
      displaySmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: colors.interactive,
        height: 1.2,
      ),

      // ── Headline: 区块标题、模块名称 ──
      headlineLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: colors.itemPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: colors.itemPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: colors.itemPrimary,
      ),

      // ── Title: 卡片标题、列表项标题、次级标题 ──
      titleLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colors.itemPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colors.itemPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: colors.itemPrimary,
      ),

      // ── Body: 正文、说明、注释 ──
      bodyLarge: TextStyle(
        fontSize: 16,
        color: colors.itemSecondary,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: colors.itemSecondary,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        color: colors.itemSecondary,
        height: 1.4,
      ),

      // ── Label: 按钮文字、标签、徽标 ──
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: colors.itemHint,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: colors.itemHint,
      ),
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: colors.itemHint,
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
        borderSide: BorderSide(color: colors.contentBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colors.contentBorder, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colors.contentBorderFocus, width: 2),
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
      hintStyle: TextStyle(color: colors.itemHint, fontSize: 14),
      labelStyle: TextStyle(color: colors.itemSecondary, fontSize: 14),
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
        color: colors.itemOnInteractive,
      ),
      toolbarTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: colors.itemOnInteractive,
      ),
      iconTheme: IconThemeData(color: colors.itemOnInteractive),
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
      color: colors.indicator,
      linearTrackColor: colors.indicator.withAlpha(85),
    ),

    // ─────────────────────────────────────────────
    // 滚动条
    // ─────────────────────────────────────────────
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(8),
      // 滑块：hover 微亮 / 按压更亮（暗色）或更暗（亮色）
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.dragged)) {
          return colors.scrollbarThumbPressed;
        }
        if (states.contains(WidgetState.hovered)) {
          return colors.scrollbarThumbHover;
        }
        return colors.scrollbarThumb;
      }),
      // 槽：hover / 交互时更明显
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.dragged)) {
          return colors.scrollbarTrackHover;
        }
        return colors.scrollbarTrack;
      }),
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
