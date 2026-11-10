import 'package:flutter/material.dart';
import 'package:material_color_utilities/hct/hct.dart';

import 'palette.dart';
import 'seed_tones.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  // ── 背景 ──

  final Color pageBackground;

  final Color cardBackground;
  //card背景下的交互色
  ///low - 亮度低于card
  final Color lowBackgroundOnCard;

  ///high - 亮度高于card
  final Color highBackgroundOnCard;

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
  final Color shadow;

  /// 当前是否暗色（派生状态色要用到方向）
  final bool isDark;

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
    required this.shadow,
    required this.lowBackgroundOnCard,
    required this.highBackgroundOnCard,
    this.isDark = false,
  });

  /// 种子色板：只给一个主题色，整套 token 由 HCT 解出来
  ///
  /// 与设计层 `TemplateSkin` 同一套算法（`TemplateTones`）：中性面色度 2.6、
  /// 实心按模式挪 −5 档、与卡面留 2 的对比度；换主题色只换种子
  factory AppColors.seeded({required Color seed, required bool dark}) {
    final seedHct = Hct.fromInt(seed.toARGB32());
    final tones = TemplateTones.of(
      hue: seedHct.hue,
      chroma: seedHct.chroma,
      dark: dark,
      neutralChroma: 2.6,
      accentTone: seedHct.tone,
      accentCardContrast: 2,
      accentModeShift: -5,
    );
    final neutralRamp = ToneRamp(seedHct.hue, 2.6);
    final accentRamp = ToneRamp(seedHct.hue, seedHct.chroma);
    final accent = Color(tones.accent);
    final accentTone = Hct.fromInt(tones.accent).tone;
    // 三档强调：实心照解出来的明度，低一档往弱侧、高一档往强侧各挪一点
    double shift(double delta) => (accentTone + delta).clamp(0.0, 100.0);
    return AppColors(
      pageBackground: Color(tones.page),
      cardBackground: Color(tones.surface),
      lowBackgroundOnCard: Color(tones.sunken),
      highBackgroundOnCard: Color(tones.raised),
      inputBackground: Color(tones.surface),
      elevatedBackground: Color(tones.raised),

      itemPrimary: Color(tones.textPrimary),
      itemSecondary: Color(tones.textSecondary),
      itemOnInteractive: Color(tones.onAccent),
      itemHint: Color(tones.textTertiary),

      interactiveLow: Color(accentRamp.at(shift(dark ? -7 : 7))),
      interactive: accent,
      interactiveHigh: Color(accentRamp.at(shift(dark ? 7 : -7))),
      splash: dark ? const Color(0x1FFFFFFF) : const Color(0x1A000000),

      border: Color(tones.border),
      borderFocus: Color(tones.accentText),

      contentBorder: Color(tones.borderStrong),
      contentBorderHover: Color(tones.textTertiary),
      contentBorderFocus: Color(tones.accentText),
      contentBackgroundFocus: Color(tones.accentTint),

      scrollbarThumb: Color(tones.borderStrong),
      scrollbarThumbHover: Color(tones.textTertiary),
      scrollbarThumbPressed: Color(tones.textSecondary),
      scrollbarTrack: Color(tones.sunken),
      scrollbarTrackHover: Color(tones.border),

      error: Color(tones.danger),
      success: Color(tones.success),
      warning: Color(tones.warning),

      indicator: accent,
      indicatorBackground: Color(tones.accentTint),
      barrier: dark ? const Color(0x99000000) : const Color(0x66000000),
      shadow: dark
          ? const Color(0x66000000)
          : Color(neutralRamp.at(25)).withAlpha(26),
      isDark: dark,
    );
  }

  /// 状态叠层：与 [TemplateSkin] 同一套算法（亮暗方向 + 位移不足时翻转），
  /// 返回**半透明叠层色**，由调用方叠在底色上（CuPressable 的反馈层就是它）
  Color hoverOn(Color base, {Color? on}) =>
      stateOn(base, on ?? cardBackground, isDark ? 0.10 : 0.08, flipped: 0.5);

  Color pressedOn(Color base, {Color? on}) =>
      stateOn(base, on ?? cardBackground, isDark ? 0.16 : 0.13, flipped: 1);

  /// 实心按钮：一律压暗（其上文字是近白），幅度更大一档
  Color solidHoverOn(Color base) =>
      Colors.black.withAlpha(((isDark ? 0.16 : 0.14) * 255).round());

  Color solidPressedOn(Color base) =>
      Colors.black.withAlpha(((isDark ? 0.24 : 0.22) * 255).round());

  Color stateOn(
    Color base,
    Color backdrop,
    double amount, {
    required double flipped,
  }) {
    if (base.a < 1) {
      return (isDark ? Colors.white : Colors.black).withAlpha(
        (amount * 255).round(),
      );
    }
    final lighter =
        toneLuminance(base.toARGB32()) > toneLuminance(backdrop.toARGB32());
    var overlay = lighter ? Colors.white : Colors.black;
    var applied = amount;
    if (_shift(base, overlay, applied) < 3) {
      overlay = lighter ? Colors.black : Colors.white;
      applied = amount * flipped;
    }
    return overlay.withAlpha((applied * 255).round());
  }

  double _shift(Color base, Color overlay, double amount) {
    final channels = [
      (base.r * 255, overlay.r * 255),
      (base.g * 255, overlay.g * 255),
      (base.b * 255, overlay.b * 255),
    ];
    var shift = 0.0;
    for (final (b, o) in channels) {
      final moved = (o * amount + b * (1 - amount) - b).abs();
      if (moved > shift) shift = moved;
    }
    return shift;
  }

  //Copper默认主题色，黄铜
  static const light = AppColors(
    // 背景
    pageBackground: Palette.neutral250,
    cardBackground: Palette.neutral150,

    lowBackgroundOnCard: Palette.neutral200,
    highBackgroundOnCard: Palette.neutral100,

    inputBackground: Palette.neutral100,
    elevatedBackground: Palette.neutral100,

    // 文本 / 图标
    itemPrimary: Palette.neutral700,
    itemSecondary: Palette.neutral600,
    itemOnInteractive: Palette.neutral100,
    itemHint: Palette.neutral500,

    // 交互（低 → 高强调）
    interactiveLow: Palette.copper600,
    interactive: Palette.copper700,
    interactiveHigh: Palette.copper900,
    splash: Palette.copperDarkHoverOverlay,

    // 边框
    border: Palette.neutral400,
    borderFocus: Palette.copper500,

    // 输入框
    contentBorder: Palette.neutral500,
    contentBorderHover: Palette.neutral600,
    contentBorderFocus: Palette.copper500,
    contentBackgroundFocus: Palette.copperInputFocusBackground,

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
    shadow: Palette.shadow,
  );

  static const dark = AppColors(
    // 背景
    pageBackground: Palette.darkPage,
    cardBackground: Palette.darkCard,

    lowBackgroundOnCard: Palette.neutral950,
    highBackgroundOnCard: Palette.neutral800,

    inputBackground: Palette.darkCard,
    elevatedBackground: Palette.darkElevated,

    // 文本 / 图标
    itemPrimary: Palette.darkTextPrimary,
    itemSecondary: Palette.darkTextSecondary,
    itemHint: Palette.neutral400,
    itemOnInteractive: Palette.neutral100,

    // 交互
    interactiveLow: Palette.copper700,
    interactive: Palette.copper600,
    interactiveHigh: Palette.copper400,
    splash: Palette.copperHoverOverlay,

    // 边框
    border: Palette.darkBorder,
    borderFocus: Palette.copper500,

    // 输入框
    contentBorder: Palette.neutral500,
    contentBorderHover: Palette.neutral400,
    contentBorderFocus: Palette.copper500,
    contentBackgroundFocus: Palette.copperInputFocusBackground,

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
    shadow: Palette.shadow,
  );

  //titanium Blue 钛蓝
  static const titaniumBlueLight = AppColors(
    // 背景
    pageBackground: Palette.neutral200,
    cardBackground: Palette.neutral100,

    lowBackgroundOnCard: Palette.neutral300,
    highBackgroundOnCard: Palette.neutral200,

    inputBackground: Palette.neutral100,
    elevatedBackground: Palette.neutral100,

    // 文本 / 图标
    itemPrimary: Palette.neutral700,
    itemSecondary: Palette.neutral600,
    itemOnInteractive: Palette.neutral100,
    itemHint: Palette.neutral500,

    // 交互（低 → 高强调）
    interactiveLow: Palette.titanium600,
    interactive: Palette.titanium700,
    interactiveHigh: Palette.titanium900,
    splash: Palette.titaniumDarkHoverOverlay,

    // 边框
    border: Palette.neutral400,
    borderFocus: Palette.titanium500,

    // 输入框
    contentBorder: Palette.neutral500,
    contentBorderHover: Palette.neutral600,
    contentBorderFocus: Palette.titanium500,
    contentBackgroundFocus: Palette.titaniumInputFocusBackground,

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
    indicator: Palette.titanium500,
    indicatorBackground: Palette.titanium300,
    barrier: Palette.barrier,
    shadow: Palette.shadow,
  );

  static const titaniumBlueDark = AppColors(
    // 背景
    pageBackground: Palette.darkPage,
    cardBackground: Palette.darkCard,

    lowBackgroundOnCard: Palette.neutral950,
    highBackgroundOnCard: Palette.neutral800,

    inputBackground: Palette.darkCard,
    elevatedBackground: Palette.darkElevated,

    // 文本 / 图标
    itemPrimary: Palette.darkTextPrimary,
    itemSecondary: Palette.darkTextSecondary,
    itemHint: Palette.neutral400,
    itemOnInteractive: Palette.neutral100,

    // 交互
    interactiveLow: Palette.titanium700,
    interactive: Palette.titanium600,
    interactiveHigh: Palette.titanium400,
    splash: Palette.titaniumHoverOverlay,

    // 边框
    border: Palette.darkBorder,
    borderFocus: Palette.titanium500,

    // 输入框
    contentBorder: Palette.neutral500,
    contentBorderHover: Palette.neutral400,
    contentBorderFocus: Palette.titanium500,
    contentBackgroundFocus: Palette.titaniumInputFocusBackground,

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
    indicator: Palette.titanium500,
    indicatorBackground: Palette.titanium300,
    barrier: Palette.barrier,
    shadow: Palette.shadow,
  );

  //thorium Pink 钍粉
  static const thoriumPinkLight = AppColors(
    // 背景
    pageBackground: Palette.neutral200,
    cardBackground: Palette.neutral100,

    lowBackgroundOnCard: Palette.neutral300,
    highBackgroundOnCard: Palette.neutral200,

    inputBackground: Palette.neutral100,
    elevatedBackground: Palette.neutral100,

    // 文本 / 图标
    itemPrimary: Palette.neutral700,
    itemSecondary: Palette.neutral600,
    itemOnInteractive: Palette.neutral100,
    itemHint: Palette.neutral500,

    // 交互（低 → 高强调）
    interactiveLow: Palette.thorium600,
    interactive: Palette.thorium700,
    interactiveHigh: Palette.thorium900,
    splash: Palette.thoriumDarkHoverOverlay,

    // 边框
    border: Palette.neutral400,
    borderFocus: Palette.thorium500,

    // 输入框
    contentBorder: Palette.neutral500,
    contentBorderHover: Palette.neutral600,
    contentBorderFocus: Palette.thorium500,
    contentBackgroundFocus: Palette.thoriumInputFocusBackground,

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
    indicator: Palette.thorium500,
    indicatorBackground: Palette.thorium300,
    barrier: Palette.barrier,
    shadow: Palette.shadow,
  );

  static const thoriumPinkDark = AppColors(
    // 背景
    pageBackground: Palette.darkPage,
    cardBackground: Palette.darkCard,

    lowBackgroundOnCard: Palette.neutral950,
    highBackgroundOnCard: Palette.neutral800,

    inputBackground: Palette.darkCard,
    elevatedBackground: Palette.darkElevated,

    // 文本 / 图标
    itemPrimary: Palette.darkTextPrimary,
    itemSecondary: Palette.darkTextSecondary,
    itemHint: Palette.neutral400,
    itemOnInteractive: Palette.neutral100,

    // 交互
    interactiveLow: Palette.thorium700,
    interactive: Palette.thorium600,
    interactiveHigh: Palette.thorium400,
    splash: Palette.thoriumHoverOverlay,

    // 边框
    border: Palette.darkBorder,
    borderFocus: Palette.thorium500,

    // 输入框
    contentBorder: Palette.neutral500,
    contentBorderHover: Palette.neutral400,
    contentBorderFocus: Palette.thorium500,
    contentBackgroundFocus: Palette.thoriumInputFocusBackground,

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
    indicator: Palette.thorium500,
    indicatorBackground: Palette.thorium300,
    barrier: Palette.barrier,
    shadow: Palette.shadow,
  );

  //plastanium Green 塑钢绿
  static const plastaniumGreenLight = AppColors(
    // 背景
    pageBackground: Palette.neutral200,
    cardBackground: Palette.neutral100,

    lowBackgroundOnCard: Palette.neutral300,
    highBackgroundOnCard: Palette.neutral200,

    inputBackground: Palette.neutral100,
    elevatedBackground: Palette.neutral100,

    // 文本 / 图标
    itemPrimary: Palette.neutral700,
    itemSecondary: Palette.neutral600,
    itemOnInteractive: Palette.neutral100,
    itemHint: Palette.neutral500,

    // 交互（低 → 高强调）
    interactiveLow: Palette.plastanium600,
    interactive: Palette.plastanium700,
    interactiveHigh: Palette.plastanium900,
    splash: Palette.plastaniumDarkHoverOverlay,

    // 边框
    border: Palette.neutral400,
    borderFocus: Palette.plastanium500,

    // 输入框
    contentBorder: Palette.neutral500,
    contentBorderHover: Palette.neutral600,
    contentBorderFocus: Palette.plastanium500,
    contentBackgroundFocus: Palette.plastaniumInputFocusBackground,

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
    indicator: Palette.plastanium500,
    indicatorBackground: Palette.plastanium300,
    barrier: Palette.barrier,
    shadow: Palette.shadow,
  );

  static const plastaniumGreenDark = AppColors(
    // 背景
    pageBackground: Palette.darkPage,
    cardBackground: Palette.darkCard,

    lowBackgroundOnCard: Palette.neutral950,
    highBackgroundOnCard: Palette.neutral800,

    inputBackground: Palette.darkCard,
    elevatedBackground: Palette.darkElevated,

    // 文本 / 图标
    itemPrimary: Palette.darkTextPrimary,
    itemSecondary: Palette.darkTextSecondary,
    itemHint: Palette.neutral400,
    itemOnInteractive: Palette.neutral100,

    // 交互
    interactiveLow: Palette.plastanium700,
    interactive: Palette.plastanium600,
    interactiveHigh: Palette.plastanium400,
    splash: Palette.plastaniumHoverOverlay,

    // 边框
    border: Palette.darkBorder,
    borderFocus: Palette.plastanium500,

    // 输入框
    contentBorder: Palette.neutral500,
    contentBorderHover: Palette.neutral400,
    contentBorderFocus: Palette.plastanium500,
    contentBackgroundFocus: Palette.plastaniumInputFocusBackground,

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
    indicator: Palette.plastanium500,
    indicatorBackground: Palette.plastanium300,
    barrier: Palette.barrier,
    shadow: Palette.shadow,
  );

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
    Color? shadow,
    Color? lowBackgroundOnCard,
    Color? highBackgroundOnCard,
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
      contentBorder: inputBorder ?? contentBorder,
      contentBorderHover: inputBorderHover ?? contentBorderHover,
      contentBorderFocus: inputBorderFocus ?? contentBorderFocus,
      contentBackgroundFocus: inputBackgroundFocus ?? contentBackgroundFocus,
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
      shadow: shadow ?? this.shadow,
      lowBackgroundOnCard: lowBackgroundOnCard ?? this.lowBackgroundOnCard,
      highBackgroundOnCard: highBackgroundOnCard ?? this.highBackgroundOnCard,
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
      shadow: Color.lerp(shadow, other.shadow, t)!,
      lowBackgroundOnCard: Color.lerp(
        lowBackgroundOnCard,
        other.lowBackgroundOnCard,
        t,
      )!,
      highBackgroundOnCard: Color.lerp(
        highBackgroundOnCard,
        other.highBackgroundOnCard,
        t,
      )!,
    );
  }
}
