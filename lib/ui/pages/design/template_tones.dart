import 'dart:math' as math;

import 'package:material_color_utilities/hct/hct.dart';

/// WCAG 2.x 的相对亮度（0~1）——**对比度的判定函数只能用它**，
/// APCA 至今仍是草案（2023-07 被移出 WCAG 3 工作草案），只适合当诊断
double toneLuminance(int argb) {
  double channel(int value) {
    final v = value / 255;
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel((argb >> 16) & 0xFF) +
      0.7152 * channel((argb >> 8) & 0xFF) +
      0.0722 * channel(argb & 0xFF);
}

/// WCAG 2.x 的对比度：(L亮 + 0.05) / (L暗 + 0.05)
double toneContrast(int a, int b) {
  final la = toneLuminance(a);
  final lb = toneLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// 一条色阶：HCT 的色相 + 色度固定，取任意 **tone**
///
/// tone 就是 CIE L\*（0~100，0 黑 100 白）——M3 的 tonal palette 用的就是这条轴，
/// 与 HSL 的 L 不同：它才是**感知**明度，所以同色相不同 tone 的深浅观感一致，
/// 不会出现「紫色与绿色取同一个 L 却一个看着深一个看着浅」
class ToneRamp {
  ToneRamp(this.hue, this.chroma);

  final double hue;
  final double chroma;

  /// 取这一档 tone 的颜色（ARGB）。
  /// 缓存一层：一次皮肤构建要解十几个档、每档七次二分，不缓存会重复算上百次 CAM16
  static final _cache = <(int, int, int), int>{};

  int at(double tone) {
    final key = (
      (hue * 10).round(),
      (chroma * 10).round(),
      tone.round().clamp(0, 100),
    );
    return _cache.putIfAbsent(
      key,
      () => Hct.from(hue, chroma, key.$3.toDouble()).toInt(),
    );
  }

  /// 解出「刚好满足对比度」的那一档 tone
  ///
  /// 对比度随 tone 离底色的距离单调上升（在底色两侧各是一个单调段），
  /// 所以在上下两半各二分一次：要亮的取「达标的最小 tone」，要暗的取「达标的最大 tone」。
  /// 这一条就是 Leonardo 的「以对比度为起点」——先定目标比值，再反解颜色
  int solveOn(int background, double target, {required bool lighter}) {
    final backgroundTone = Hct.fromInt(background).tone.round().clamp(0, 100);
    var low = lighter ? backgroundTone : 0;
    var high = lighter ? 100 : backgroundTone;
    final edge = lighter ? 100 : 0;
    // 连端点都不达标：给端点（宁可对比度更高，也不给一个看不见的颜色）
    if (toneContrast(at(edge.toDouble()), background) < target) {
      return at(edge.toDouble());
    }
    while (low < high) {
      final mid = lighter ? (low + high) ~/ 2 : (low + high + 1) ~/ 2;
      final ok = toneContrast(at(mid.toDouble()), background) >= target;
      if (lighter) {
        if (ok) {
          high = mid;
        } else {
          low = mid + 1;
        }
      } else {
        if (ok) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
    }
    return at(low.toDouble());
  }
}

/// A 路线：**一个主题色种子（HCT 色相 + 色度）推出整套颜色**
///
/// 两条规则：
/// ① **中性色走固定 tone 档**：页底 / 卡面 / 凹槽 / 描边各自取一个 tone（数值就是 L\*），
///    色度固定 ⇒ 冷主题得冷灰、暖主题得暖灰，强调色不会像外来物
/// ② **需要满足对比度的档用二分 tone 解**：实心强调 4.8、强调文字 5.5、三级小字 5.5、
///    控件边界 3（WCAG 1.4.11）、正文 13、次要文字 7 —— 换主题只换种子
///
/// 仍**写死**的（业界也是手写）：语义色（危险 / 成功 / 警告）的色相，以及
/// hover / pressed / 阴影这类叠层；`onAccent` 这一版固定取中性色的高 tone
class TemplateTones {
  const TemplateTones({
    required this.hue,
    required this.chroma,
    required this.dark,
    required this.page,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.border,
    required this.borderStrong,
    required this.controlBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.accentTint,
    required this.onAccentTint,
    required this.danger,
    required this.dangerText,
    required this.onDanger,
    required this.success,
    required this.warning,
  });

  /// 从一个种子（HCT 色相 + 色度）解出整套色值，返回的都是 ARGB
  factory TemplateTones.of({
    required double hue,
    required double chroma,
    required bool dark,
  }) {
    // 中性色：色度压到几乎不带色（3），只留一点色温；描边/强描边给 6
    final neutral = ToneRamp(hue, 3);
    final strong = ToneRamp(hue, 6);
    final text = ToneRamp(hue, 3);
    // 越小的字越不该带色：三级小字用更低的色度
    final microText = ToneRamp(hue, 2);
    final accentRamp = ToneRamp(hue, chroma);
    // 强调色的「文字形态」用更低的色度：小字上高色度会吵（暗色尤其）
    final accentSoft = ToneRamp(hue, chroma * 0.68);
    final tintRamp = ToneRamp(hue, 12);
    // 语义色是固定的三个色相（与主题色无关），各自一条色阶 —— 与 M3 把 error
    // 独立于种子、Radix 用固定语义色相是同一个做法
    final dangerRamp = ToneRamp(22.8, 55);
    final successRamp = ToneRamp(156.1, 50);
    final warningRamp = ToneRamp(73.3, 45);

    // ── 表面：tone 档位，数值由旧观感量过来（见 .project_status/components.md）──
    // **tone 最高只到 98**：material_color_utilities 自己注明 tone > 98 时色度会受
    // 已知问题影响（issue 140），实测 tone 99 的铜翻成 `#FFFBFF` 这种发粉的白，
    // 98 才是正常的暖白 `#FFF8F4`
    final page = neutral.at(dark ? 7 : 95);
    final surface = neutral.at(dark ? 12 : 98);
    final raised = neutral.at(dark ? 17 : 98);
    final sunken = neutral.at(dark ? 5 : 90);
    final border = neutral.at(dark ? 24 : 88);
    final borderStrong = strong.at(dark ? 33 : 75);
    final onAccent = neutral.at(98);
    final accentTint = dark ? tintRamp.at(22) : strong.at(89);

    // ── 要满足对比度的档：二分 tone ──
    final controlBorder = strong.solveOn(surface, 3, lighter: dark);
    final textPrimary = text.solveOn(surface, 13, lighter: dark);
    final textSecondary = text.solveOn(surface, 7, lighter: dark);
    final textTertiary = microText.solveOn(surface, 5.5, lighter: dark);
    // 实心：**两个约束一起看** —— 其上文字要 ≥4.5，同时它自己要从卡面里跳出来（≥3，1.4.11）。
    // 浅色解「白字刚好压得住的最亮那档」；暗色反过来解「刚压得住白字的那档」，
    // 它同时就落在卡面上方 3.3 左右（先前的写法只盯卡面 3.4，白字会掉到 4.40 不达标）
    final accent = accentRamp.solveOn(onAccent, 4.8, lighter: false);
    // 强调文字：浅色可以用足色度（深色本身压得住），暗色换成低色度那支
    final accentText = dark
        ? accentSoft.solveOn(surface, 5.5, lighter: true)
        : accentRamp.solveOn(surface, 5, lighter: false);
    final onAccentTint = accentSoft.solveOn(accentTint, 6.5, lighter: dark);
    final danger = dangerRamp.solveOn(onAccent, 4.8, lighter: false);
    final dangerText = dangerRamp.solveOn(
      surface,
      dark ? 5.5 : 5,
      lighter: dark,
    );
    final success = dark
        ? successRamp.solveOn(surface, 5.5, lighter: true)
        : successRamp.solveOn(onAccent, 4.8, lighter: false);
    final warning = dark
        ? warningRamp.solveOn(surface, 5.5, lighter: true)
        : warningRamp.solveOn(onAccent, 4.8, lighter: false);

    return TemplateTones(
      hue: hue,
      chroma: chroma,
      dark: dark,
      page: page,
      surface: surface,
      raised: raised,
      sunken: sunken,
      border: border,
      borderStrong: borderStrong,
      controlBorder: controlBorder,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textTertiary: textTertiary,
      accent: accent,
      accentText: accentText,
      onAccent: onAccent,
      accentTint: accentTint,
      onAccentTint: onAccentTint,
      danger: danger,
      dangerText: dangerText,
      onDanger: onAccent,
      success: success,
      warning: warning,
    );
  }

  final double hue;
  final double chroma;
  final bool dark;

  final int page;
  final int surface;
  final int raised;
  final int sunken;
  final int border;
  final int borderStrong;

  /// 控件（输入框 / 分段 / 开关轨道）的边界：解到 3:1
  final int controlBorder;
  final int textPrimary;
  final int textSecondary;
  final int textTertiary;

  /// 实心强调：只用来铺底，其上文字必须压得住
  final int accent;

  /// 强调色的文字 / 图标形态
  final int accentText;
  final int onAccent;

  /// 软底形态（淡主题色底 + 深主题色字）
  final int accentTint;
  final int onAccentTint;

  /// 破坏性：实心与文字两种形态
  final int danger;
  final int dangerText;
  final int onDanger;
  final int success;
  final int warning;
}
