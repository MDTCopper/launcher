import 'package:flutter/material.dart';

import 'palette.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  // ── 背景 ──

  final Color pageBackground;
  final Color cardBackground;
  final Color inputBackground;
  final Color elevatedBackground; // 悬浮 / 选中浮层

  // ── 文本 / 图标（共色）──

  final Color itemPrimary;
  final Color itemSecondary;
  final Color itemOnInteractive; // 有色背景上的项
  final Color itemHint;

  // ── 交互（三层强调）──

  final Color interactiveLow;
  final Color interactive;
  final Color interactiveHigh;
  final Color splash; // 水波纹 / 点击反馈

  // ── 边框 ──

  final Color border;
  final Color borderFocus;

  // ── 内容框 ──

  final Color contentBorder; // 比 border 更明显
  final Color contentBorderHover;
  final Color contentBorderFocus; // 聚焦 = 主题色
  final Color contentBackgroundFocus; // 聚焦背景 = 略透明主题色

  // ── 滚动条 ──

  final Color scrollbarThumb;
  final Color scrollbarThumbHover;
  final Color scrollbarThumbPressed;
  final Color scrollbarTrack; // 槽
  final Color scrollbarTrackHover;

  // ── 语义 ──

  final Color error;
  final Color success;
  final Color warning;

  final Color indicator;
  final Color indicatorBackground;

  // ── 其他 ──

  final Color barrier;

  const AppColors({
    required this.pageBackground,
    required this.cardBackground,
    required this.inputBackground,
    required this.elevatedBackground,
    required this.itemPrimary,
    required this.itemSecondary,
    required this.itemOnInteractive,
    required this.itemHint,
    required this.interactiveLow,
    required this.interactive,
    required this.interactiveHigh,
    required this.splash,
    required this.border,
    required this.borderFocus,
    required this.contentBorder,
    required this.contentBorderHover,
    required this.contentBorderFocus,
    required this.contentBackgroundFocus,
    required this.scrollbarThumb,
    required this.scrollbarThumbHover,
    required this.scrollbarThumbPressed,
    required this.scrollbarTrack,
    required this.scrollbarTrackHover,
    required this.error,
    required this.success,
    required this.warning,
    required this.indicator,
    required this.indicatorBackground,
    required this.barrier,
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

    // 文本 / 图标
    itemPrimary: Palette.neutral700,
    itemSecondary: Palette.neutral600,
    itemOnInteractive: Palette.neutral100,
    itemHint: Palette.neutral500,

    // 交互（低 → 高强调）
    interactiveLow: Palette.copper500,
    interactive: Palette.copper600,
    interactiveHigh: Palette.copper800,
    splash: Palette.copperHoverOverlay,

    // 边框
    border: Palette.neutral400,
    borderFocus: Palette.copper500,

    // 输入框
    contentBorder: Palette.neutral500,
    contentBorderHover: Palette.neutral600,
    contentBorderFocus: Palette.copper500,
    contentBackgroundFocus: Palette.inputFocusBackground,

    // 滚动条
    scrollbarThumb: Palette.neutral400,
    scrollbarThumbHover: Palette.neutral500,
    scrollbarThumbPressed: Palette.neutral600,
    scrollbarTrack: Palette.scrollbarTrackLight,
    scrollbarTrackHover: Palette.scrollbarTrackLightHover,

    // 语义
    error: Palette.error,
    success: Palette.success,
    warning: Palette.warning,

    // 其他
    indicator: Palette.copper500,
    indicatorBackground: Palette.copper300,
    barrier: Palette.barrier,
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

    // 文本 / 图标
    itemPrimary: Palette.darkTextPrimary,
    itemSecondary: Palette.darkTextSecondary,
    itemOnInteractive: Palette.neutral100,
    itemHint: Palette.neutral400,

    // 交互（低 → 高强调，暗色下高强调更亮）
    interactiveLow: Palette.copper700,
    interactive: Palette.copper600,
    interactiveHigh: Palette.copper400,
    splash: Palette.whiteHoverOverlay,

    // 边框
    border: Palette.darkBorder,
    borderFocus: Palette.copper500,

    // 输入框
    contentBorder: Palette.neutral500,
    contentBorderHover: Palette.neutral400,
    contentBorderFocus: Palette.copper500,
    contentBackgroundFocus: Palette.inputFocusBackground,

    // 滚动条（暗色：按压稍亮，不过曝）
    scrollbarThumb: Palette.neutral600,
    scrollbarThumbHover: Palette.neutral500,
    scrollbarThumbPressed: Palette.neutral400,
    scrollbarTrack: Palette.scrollbarTrackDark,
    scrollbarTrackHover: Palette.scrollbarTrackDarkHover,

    // 语义
    error: Palette.errorDark,
    success: Palette.success,
    warning: Palette.warning,

    // 其他
    indicator: Palette.copper500,
    indicatorBackground: Palette.copper300,
    barrier: Palette.barrier,
  );

  static const blueDark = null;

  @override
  AppColors copyWith({
    Color? pageBackground,
    Color? cardBackground,
    Color? inputBackground,
    Color? elevatedBackground,
    Color? itemPrimary,
    Color? itemSecondary,
    Color? itemOnInteractive,
    Color? itemHint,
    Color? interactiveLow,
    Color? interactive,
    Color? interactiveHigh,
    Color? splash,
    Color? border,
    Color? borderFocus,
    Color? inputBorder,
    Color? inputBorderHover,
    Color? inputBorderFocus,
    Color? inputBackgroundFocus,
    Color? scrollbarThumb,
    Color? scrollbarThumbHover,
    Color? scrollbarThumbPressed,
    Color? scrollbarTrack,
    Color? scrollbarTrackHover,
    Color? error,
    Color? success,
    Color? warning,
    Color? indicator,
    Color? indicatorBackground,
    Color? barrier,
  }) {
    return AppColors(
      pageBackground: pageBackground ?? this.pageBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      inputBackground: inputBackground ?? this.inputBackground,
      elevatedBackground: elevatedBackground ?? this.elevatedBackground,
      itemPrimary: itemPrimary ?? this.itemPrimary,
      itemSecondary: itemSecondary ?? this.itemSecondary,
      itemOnInteractive: itemOnInteractive ?? this.itemOnInteractive,
      itemHint: itemHint ?? this.itemHint,
      interactiveLow: interactiveLow ?? this.interactiveLow,
      interactive: interactive ?? this.interactive,
      interactiveHigh: interactiveHigh ?? this.interactiveHigh,
      splash: splash ?? this.splash,
      border: border ?? this.border,
      borderFocus: borderFocus ?? this.borderFocus,
      contentBorder: inputBorder ?? this.contentBorder,
      contentBorderHover: inputBorderHover ?? this.contentBorderHover,
      contentBorderFocus: inputBorderFocus ?? this.contentBorderFocus,
      contentBackgroundFocus:
          inputBackgroundFocus ?? this.contentBackgroundFocus,
      scrollbarThumb: scrollbarThumb ?? this.scrollbarThumb,
      scrollbarThumbHover: scrollbarThumbHover ?? this.scrollbarThumbHover,
      scrollbarThumbPressed:
          scrollbarThumbPressed ?? this.scrollbarThumbPressed,
      scrollbarTrack: scrollbarTrack ?? this.scrollbarTrack,
      scrollbarTrackHover: scrollbarTrackHover ?? this.scrollbarTrackHover,
      error: error ?? this.error,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      indicator: indicator ?? this.indicator,
      indicatorBackground: indicatorBackground ?? this.indicatorBackground,
      barrier: barrier ?? this.barrier,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      inputBackground: Color.lerp(inputBackground, other.inputBackground, t)!,
      elevatedBackground: Color.lerp(
        elevatedBackground,
        other.elevatedBackground,
        t,
      )!,
      itemPrimary: Color.lerp(itemPrimary, other.itemPrimary, t)!,
      itemSecondary: Color.lerp(itemSecondary, other.itemSecondary, t)!,
      itemOnInteractive: Color.lerp(
        itemOnInteractive,
        other.itemOnInteractive,
        t,
      )!,
      itemHint: Color.lerp(itemHint, other.itemHint, t)!,
      interactiveLow: Color.lerp(interactiveLow, other.interactiveLow, t)!,
      interactive: Color.lerp(interactive, other.interactive, t)!,
      interactiveHigh: Color.lerp(interactiveHigh, other.interactiveHigh, t)!,
      splash: Color.lerp(splash, other.splash, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      contentBorder: Color.lerp(contentBorder, other.contentBorder, t)!,
      contentBorderHover: Color.lerp(
        contentBorderHover,
        other.contentBorderHover,
        t,
      )!,
      contentBorderFocus: Color.lerp(
        contentBorderFocus,
        other.contentBorderFocus,
        t,
      )!,
      contentBackgroundFocus: Color.lerp(
        contentBackgroundFocus,
        other.contentBackgroundFocus,
        t,
      )!,
      scrollbarThumb: Color.lerp(scrollbarThumb, other.scrollbarThumb, t)!,
      scrollbarThumbHover: Color.lerp(
        scrollbarThumbHover,
        other.scrollbarThumbHover,
        t,
      )!,
      scrollbarThumbPressed: Color.lerp(
        scrollbarThumbPressed,
        other.scrollbarThumbPressed,
        t,
      )!,
      scrollbarTrack: Color.lerp(scrollbarTrack, other.scrollbarTrack, t)!,
      scrollbarTrackHover: Color.lerp(
        scrollbarTrackHover,
        other.scrollbarTrackHover,
        t,
      )!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      indicator: Color.lerp(indicator, other.indicator, t)!,
      indicatorBackground: Color.lerp(
        indicatorBackground,
        other.indicatorBackground,
        t,
      )!,
      barrier: Color.lerp(barrier, other.barrier, t)!,
    );
  }
}
