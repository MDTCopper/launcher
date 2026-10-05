import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 参考模版的皮肤层：**这一层就是将来要套进 Copper 的东西**
///
/// 只有两条规则（详见 `.project_status/components.md` 的「参考模版」一节）：
/// ① 中性色跟着主题色相走 ⇒ 四个主题各得自己的冷暖
/// ② 该满足对比度的档用二分解出来 ⇒ 不写死、换色相自动重算
/// 与 `design_template_page.dart` 的组件与规则部分共用

class TemplateSkin {
  const TemplateSkin({
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
    required this.hover,
    required this.pressed,
    required this.selected,
    required this.shadow,
  });

  /// 从一个主题色相生成整套皮肤
  ///
  /// 两条规则：① **中性色跟着主题色相走**（低饱和的同一色相 ⇒ 冷主题得冷灰、
  /// 暖主题得暖灰，强调色才不会像外来物）② **该满足对比度的档不解固定值，
  /// 而是解出来** —— 浅色取「白字刚好压得住的最亮那一档」、暗色取「对卡面刚够
  /// 显眼的最暗那一档」，于是四个主题色自动得到各自合适的那一档
  factory TemplateSkin.of({required double hue, required bool dark}) {
    // 中性色的饱和度：低到不喧哗，但要够看出冷暖 —— 色温就是这个差
    Color neutral(double lightness, [double saturation = 0.07]) =>
        HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();

    if (!dark) {
      final surface = neutral(0.99, 0.035);
      final page = neutral(0.945, 0.08);
      final sunken = neutral(0.885, 0.09);
      final onAccent = neutral(0.995, 0.03);
      final tint = HSLColor.fromAHSL(1, hue, 0.38, 0.86).toColor();

      return TemplateSkin(
        page: page,
        surface: surface,
        raised: surface,
        sunken: sunken,
        border: neutral(0.86, 0.1),
        borderStrong: neutral(0.72, 0.11),
        // 控件边界按 WCAG 1.4.11 要有 3:1，容器描边不用
        controlBorder: _solveOn(
          hue: hue,
          saturation: 0.12,
          background: surface,
          target: 3,
          lighter: false,
        ),
        // 正文与次要文字目标高一些；**小字（三级）也提到 5.5 且饱和度更低** ——
        // 字号越小越吃对比度，给它带色只会更难读
        textPrimary: _solveOn(
          hue: hue,
          saturation: 0.05,
          background: surface,
          target: 13,
          lighter: false,
        ),
        textSecondary: _solveOn(
          hue: hue,
          saturation: 0.05,
          background: surface,
          target: 7,
          lighter: false,
        ),
        textTertiary: _solveOn(
          hue: hue,
          saturation: 0.03,
          background: surface,
          target: 5.5,
          lighter: false,
        ),
        // 实心：白字刚好压得住的最亮那一档（越亮越不显闷）
        accent: _solveOn(
          hue: hue,
          saturation: 0.55,
          background: onAccent,
          target: 4.8,
          lighter: false,
        ),
        accentText: _solveOn(
          hue: hue,
          saturation: 0.6,
          background: surface,
          target: 5,
          lighter: false,
        ),
        onAccent: onAccent,
        accentTint: tint,
        onAccentTint: _solveOn(
          hue: hue,
          saturation: 0.5,
          background: tint,
          target: 6.5,
          lighter: false,
        ),
        danger: _solveOn(
          hue: 2,
          saturation: 0.5,
          background: onAccent,
          target: 4.8,
          lighter: false,
        ),
        // 危险色的「文字」形态单独解：实心那一档是给白字铺底用的，
        // 直接拿去当文字色在暗色下会不达标
        dangerText: _solveOn(
          hue: 2,
          saturation: 0.5,
          background: surface,
          target: 5,
          lighter: false,
        ),
        onDanger: onAccent,
        success: _solveOn(
          hue: 145,
          saturation: 0.4,
          background: onAccent,
          target: 4.8,
          lighter: false,
        ),
        warning: _solveOn(
          hue: 36,
          saturation: 0.6,
          background: onAccent,
          target: 4.8,
          lighter: false,
        ),
        hover: const Color(0x0F000000),
        pressed: const Color(0x1A000000),
        selected: HSLColor.fromAHSL(0.16, hue, 0.6, 0.5).toColor(),
        shadow: HSLColor.fromAHSL(0.10, hue, 0.5, 0.25).toColor(),
      );
    }

    final surface = neutral(0.125, 0.07);
    final raised = neutral(0.165, 0.07);
    final onAccent = neutral(0.99, 0.03);
    final tint = HSLColor.fromAHSL(1, hue, 0.32, 0.19).toColor();

    return TemplateSkin(
      page: neutral(0.085, 0.07),
      surface: surface,
      raised: raised,
      sunken: neutral(0.065, 0.07),
      border: neutral(0.22, 0.1),
      borderStrong: neutral(0.3, 0.11),
      controlBorder: _solveOn(
        hue: hue,
        saturation: 0.12,
        background: surface,
        target: 3,
        lighter: true,
      ),
      textPrimary: _solveOn(
        hue: hue,
        saturation: 0.05,
        background: surface,
        target: 13,
        lighter: true,
      ),
      textSecondary: _solveOn(
        hue: hue,
        saturation: 0.05,
        background: surface,
        target: 7,
        lighter: true,
      ),
      textTertiary: _solveOn(
        hue: hue,
        saturation: 0.03,
        background: surface,
        target: 5.5,
        lighter: true,
      ),
      // 暗色的实心：对卡面刚够显眼的最暗那一档（旧值 6.3:1 就是「一块亮铜砸在近黑上」）
      accent: _solveOn(
        hue: hue,
        saturation: 0.5,
        background: surface,
        target: 3.4,
        lighter: true,
      ),
      accentText: _solveOn(
        hue: hue,
        saturation: 0.55,
        background: surface,
        target: 5.5,
        lighter: true,
      ),
      onAccent: onAccent,
      accentTint: tint,
      onAccentTint: _solveOn(
        hue: hue,
        saturation: 0.5,
        background: tint,
        target: 6.5,
        lighter: true,
      ),
      danger: _solveOn(
        hue: 2,
        saturation: 0.45,
        background: onAccent,
        target: 4.8,
        lighter: false,
      ),
      dangerText: _solveOn(
        hue: 2,
        saturation: 0.5,
        background: surface,
        target: 5.5,
        lighter: true,
      ),
      onDanger: onAccent,
      success: _solveOn(
        hue: 145,
        saturation: 0.45,
        background: surface,
        target: 5.5,
        lighter: true,
      ),
      warning: _solveOn(
        hue: 36,
        saturation: 0.6,
        background: surface,
        target: 5.5,
        lighter: true,
      ),
      hover: const Color(0x14FFFFFF),
      pressed: const Color(0x1FFFFFFF),
      selected: HSLColor.fromAHSL(0.18, hue, 0.6, 0.5).toColor(),
      shadow: const Color(0x66000000),
    );
  }

  final Color page;
  final Color surface;
  final Color raised;
  final Color sunken;
  final Color border;
  final Color borderStrong;

  /// 控件（输入框 / 分段 / 开关轨道）的边界：按 1.4.11 解到 3:1
  final Color controlBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// 实心强调：只用来铺底，白字必须压得住
  final Color accent;

  /// 强调色的文字 / 图标形态：与实心分开取值，浅暗各一支
  final Color accentText;
  final Color onAccent;

  /// 软底形态（待定用）：淡主题色底 + 深主题色字，块感更轻
  final Color accentTint;
  final Color onAccentTint;

  /// 破坏性：同样是「实心」与「文字」两种形态
  final Color danger;
  final Color dangerText;
  final Color onDanger;
  final Color success;
  final Color warning;
  final Color hover;
  final Color pressed;
  final Color selected;
  final Color shadow;
}

/// 文字层级：桌面密度，靠字重不靠把尺寸吹大
class TemplateType {
  static const page = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
  );
  static const section = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
  );
  static const item = TextStyle(fontSize: 14, height: 20 / 14);
  static const caption = TextStyle(fontSize: 12, height: 16 / 12);
  static const micro = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );
}

/// 几何：4 的倍数，4 / 8 / 12 / 16 / 24 / 32
class TemplateSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class TemplateRadius {
  static const control = 6.0;
  static const card = 10.0;
  static const pill = 999.0;
}

double templateContrast(Color a, Color b) {
  final la = templateLuminance(a);
  final lb = templateLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

double templateLuminance(Color color) {
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// 解出「刚好满足对比度」的一档颜色：色相与饱和度固定，对明度做二分
///
/// [lighter] 为 true ⇒ 要一个比底色亮的颜色（暗色主题），取**最小**达标的那一档；
/// false ⇒ 要一个比底色暗的颜色，取**最大**达标的那一档。
/// 于是浅色的实心是「白字将将压住的最亮铜」、暗色的实心是「刚够显眼的最暗铜」，
/// 四个主题色各自解出自己合适的那一档，不必逐个手调
Color _solveOn({
  required double hue,
  required double saturation,
  required Color background,
  required double target,
  required bool lighter,
}) {
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 22; i++) {
    final mid = (low + high) / 2;
    final candidate = HSLColor.fromAHSL(1, hue, saturation, mid).toColor();
    final ok = templateContrast(candidate, background) >= target;
    if (lighter) {
      if (ok) {
        high = mid;
      } else {
        low = mid;
      }
    } else {
      if (ok) {
        low = mid;
      } else {
        high = mid;
      }
    }
  }
  return HSLColor.fromAHSL(1, hue, saturation, lighter ? high : low).toColor();
}
