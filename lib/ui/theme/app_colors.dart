import 'package:flutter/material.dart';

import 'palette.dart';

///主题颜色类型，铜色，钛蓝色，钍粉色，塑钢绿
///配合暗色和亮色各两套

/// Widget 通过 [AppColors.of(context)] 获取，颜色
@immutable
class AppColors extends ThemeExtension<AppColors> {
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  // ── 背景 ──

  final Color pageBackground;
  final Color cardBackground;
  final Color inputBackground;
  final Color elevatedBackground; // 悬浮 / 选中浮层

  // ── 文字 ──

  final Color textPrimary;
  final Color textSecondary;
  final Color textOnInteractive; // 有色背景上的文字
  final Color textHint;

  // ── 交互 ──

  final Color interactive;
  final Color interactiveHover;
  final Color interactivePressed;
  final Color splash; // 水波纹 / 点击反馈

  // ── 边框 ──

  final Color border;
  final Color borderFocus;

  // ── 语义 ──

  final Color error;
  final Color success;
  final Color warning;

  //
  final Color indicator;
  final Color indicatorBackground;

  // ── 其他 ──

  final Color scrollbarThumb;
  final Color barrier;

  const AppColors({
    required this.pageBackground,
    required this.cardBackground,
    required this.inputBackground,
    required this.elevatedBackground,
    required this.textPrimary,
    required this.textSecondary,
    required this.textOnInteractive,
    required this.textHint,
    required this.interactive,
    required this.interactiveHover,
    required this.interactivePressed,
    required this.splash,
    required this.border,
    required this.borderFocus,
    required this.error,
    required this.success,
    required this.warning,
    required this.scrollbarThumb,
    required this.barrier,
    required this.indicator,
    required this.indicatorBackground,
  });

  // ═══════════════════════════════════════════════════════════
  // 亮色
  // ═══════════════════════════════════════════════════════════

  static const light = AppColors(
    // 背景
    pageBackground: Palette.neutral200,
    cardBackground: Palette.neutral100,
    inputBackground: Palette.neutral100,
    elevatedBackground: Palette.neutral100,

    // 文字
    textPrimary: Palette.neutral600,
    textSecondary: Palette.neutral500,
    textOnInteractive: Palette.neutral100,
    textHint: Palette.neutral400,

    // 交互
    interactive: Palette.copper500,
    interactiveHover: Palette.copper300,
    interactivePressed: Palette.copper700,
    splash: Palette.copperHoverOverlay,

    // 边框
    border: Palette.neutral300,
    borderFocus: Palette.copper500,

    // 语义
    error: Palette.error,
    success: Palette.success,
    warning: Palette.warning,

    // 其他
    scrollbarThumb: Palette.neutral400,
    barrier: Palette.barrier,
    indicator: Palette.copper500,
    indicatorBackground: Palette.copper300,
  );

  // ═══════════════════════════════════════════════════════════
  // 暗色
  // ═══════════════════════════════════════════════════════════

  static const dark = AppColors(
    // 背景
    pageBackground: Palette.darkPage,
    cardBackground: Palette.darkCard,
    inputBackground: Palette.darkCard,
    elevatedBackground: Palette.darkElevated,

    // 文字
    textPrimary: Palette.darkTextPrimary,
    textSecondary: Palette.darkTextSecondary,
    textOnInteractive: Palette.white,
    textHint: Palette.neutral500,

    // 交互
    interactive: Palette.copper600,
    interactiveHover: Palette.copper700,
    interactivePressed: Palette.copper900,
    splash: Palette.whiteHoverOverlay,

    // 边框
    border: Palette.darkBorder,
    borderFocus: Palette.copper500,

    // 语义
    error: Palette.errorDark,
    success: Palette.success,
    warning: Palette.warning,

    // 其他
    scrollbarThumb: Palette.neutral600,
    barrier: Palette.barrier,
    indicator: Palette.copper500,
    indicatorBackground: Palette.copper300,
  );

  static const blueDark = null;

  @override
  AppColors copyWith({
    Color? pageBackground,
    Color? cardBackground,
    Color? inputBackground,
    Color? elevatedBackground,
    Color? textPrimary,
    Color? textSecondary,
    Color? textOnInteractive,
    Color? textHint,
    Color? interactive,
    Color? interactiveHover,
    Color? interactivePressed,
    Color? splash,
    Color? border,
    Color? borderFocus,
    Color? error,
    Color? success,
    Color? warning,
    Color? scrollbarThumb,
    Color? barrier,
    Color? indicator,
    Color? indicatorBackground,
  }) {
    return AppColors(
      pageBackground: pageBackground ?? this.pageBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      inputBackground: inputBackground ?? this.inputBackground,
      elevatedBackground: elevatedBackground ?? this.elevatedBackground,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textOnInteractive: textOnInteractive ?? this.textOnInteractive,
      textHint: textHint ?? this.textHint,
      interactive: interactive ?? this.interactive,
      interactiveHover: interactiveHover ?? this.interactiveHover,
      interactivePressed: interactivePressed ?? this.interactivePressed,
      splash: splash ?? this.splash,
      border: border ?? this.border,
      borderFocus: borderFocus ?? this.borderFocus,
      error: error ?? this.error,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      scrollbarThumb: scrollbarThumb ?? this.scrollbarThumb,
      barrier: barrier ?? this.barrier,
      indicator: indicator ?? this.indicator,
      indicatorBackground: indicatorBackground ?? this.indicatorBackground,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      inputBackground: Color.lerp(inputBackground, other.inputBackground, t)!,
      elevatedBackground:
          Color.lerp(elevatedBackground, other.elevatedBackground, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textOnInteractive:
          Color.lerp(textOnInteractive, other.textOnInteractive, t)!,
      textHint: Color.lerp(textHint, other.textHint, t)!,
      interactive: Color.lerp(interactive, other.interactive, t)!,
      interactiveHover:
          Color.lerp(interactiveHover, other.interactiveHover, t)!,
      interactivePressed:
          Color.lerp(interactivePressed, other.interactivePressed, t)!,
      splash: Color.lerp(splash, other.splash, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      scrollbarThumb: Color.lerp(scrollbarThumb, other.scrollbarThumb, t)!,
      barrier: Color.lerp(barrier, other.barrier, t)!,
      indicator: Color.lerp(indicator, other.indicator, t)!,
      indicatorBackground:
          Color.lerp(indicatorBackground, other.indicatorBackground, t)!,
    );
  }
}
