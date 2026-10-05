import 'package:flutter/material.dart';

import 'template_tones.dart';

/// Copper 四个主题色：**换一个种子，整套皮肤重算**
///
/// 2026-10-05 换到 A 路线（HCT）：这四个数是**旧 HSL 色相在 CAM16 刻度上的坐标**
/// ——用一次性探针把 `HSL 33 / 210 / 305 / 97 @ S .5 L .5` 换算过来，色度按各主题
/// 原有的浓度保留，所以观感与之前一致，只是坐标系换成了**感知均匀**的那个。
/// 与 M3 一样：种子给「色相 + 色度」，其余全部推出来
abstract final class TemplateHues {
  static const named = <({String name, double hue, double chroma})>[
    (name: '铜', hue: 68.7, chroma: 37),
    (name: '钛', hue: 253.4, chroma: 46),
    (name: '钍', hue: 336.2, chroma: 74),
    (name: '塑钢', hue: 136.9, chroma: 67),
  ];

  static const copper = 68.7;
  static const titanium = 253.4;
  static const thorium = 336.2;
  static const plastanium = 136.9;

  /// 每个色相自带的色度（种子浓度）；认不出来就给铜的
  static double chromaOf(double hue) => named
      .firstWhere((item) => item.hue == hue, orElse: () => named.first)
      .chroma;
}

/// 参考模版的皮肤层：**这一层就是将来要套进 Copper 的东西**
///
/// 色值本身全部由 [TemplateTones]（A 路线：HCT tone 档 + 按目标对比度二分反解）算出来，
/// 这里只做三件事：① 包成 Flutter 的 [Color] ② 给出叠层（hover / pressed / 选中 / 阴影
/// ——这几样业界也都是手写）③ 提供按底色算状态色的 [hoverOn] / [pressedOn]。
/// 与 `design_template_page.dart` 的组件与规则部分共用
class TemplateSkin {
  const TemplateSkin({
    required this.dark,
    required ToneRamp neutral,
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
  }) : _neutral = neutral;

  /// 从一个主题种子（色相 + 自带的色度）生成整套皮肤
  factory TemplateSkin.of({required double hue, required bool dark}) {
    final chroma = TemplateHues.chromaOf(hue);
    final tones = TemplateTones.of(hue: hue, chroma: chroma, dark: dark);
    // 阴影与选中态要一点色度：用一个低色度的色阶，别用主题色的满色度
    final shadowRamp = ToneRamp(hue, 12);
    final accent = Color(tones.accent);

    return TemplateSkin(
      dark: dark,
      neutral: ToneRamp(hue, 3),
      page: Color(tones.page),
      surface: Color(tones.surface),
      raised: Color(tones.raised),
      sunken: Color(tones.sunken),
      border: Color(tones.border),
      borderStrong: Color(tones.borderStrong),
      controlBorder: Color(tones.controlBorder),
      textPrimary: Color(tones.textPrimary),
      textSecondary: Color(tones.textSecondary),
      textTertiary: Color(tones.textTertiary),
      accent: accent,
      accentText: Color(tones.accentText),
      onAccent: Color(tones.onAccent),
      accentTint: Color(tones.accentTint),
      onAccentTint: Color(tones.onAccentTint),
      danger: Color(tones.danger),
      dangerText: Color(tones.dangerText),
      onDanger: Color(tones.onDanger),
      success: Color(tones.success),
      warning: Color(tones.warning),
      // ── 叠层：手写（业界也如此），方向按主题 ──
      hover: dark ? const Color(0x14FFFFFF) : const Color(0x0F000000),
      pressed: dark ? const Color(0x1FFFFFFF) : const Color(0x1A000000),
      // 选中态就是强调色的一层薄底（原来写的是 HSL 半饱和色，现在是解出来的强调色）
      selected: accent.withAlpha(((dark ? 0.18 : 0.16) * 255).round()),
      shadow: dark
          ? const Color(0x66000000)
          : Color(shadowRamp.at(25)).withAlpha((0.10 * 255).round()),
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

  /// 亮 / 暗：状态叠层的方向与幅度要按它算（见 [hoverOn]）
  final bool dark;

  /// 中性色阶：需要「取某一档」的控件（分段的渐变、细描边）用它，别自己写色值
  final ToneRamp _neutral;

  /// 取中性色阶的任意一档 tone（0 黑 ~ 100 白）
  Color neutralTone(double tone) => Color(_neutral.at(tone));

  /// 悬停 / 按下：压在**控件自己的底色**上算出来的一层
  ///
  /// 四条规则（前三条都是踩出来的）：
  /// ① **必须是半透明的一层** —— `ReboundContainer` 的悬浮层是 `Positioned.fill`
  ///    画在**内容之上**的，给不透明色会直接把字盖掉（用户 2026-10-05「部分按钮悬停字会消失」）
  /// ② **方向按「离开它坐着的那个面」**，不是一律按主题：同一个主题里，控件可能坐在卡面上、
  ///    也可能坐在分段的凹槽底上，一律叠白/黑会让其中一种撞上它的底
  /// ③ **推不动就反向推**：亮色下分段的选中格已经接近白色（tone 98），再提亮几乎没有
  ///    变化，而叠一层黑又会落到凹槽底（tone 90）上 —— 看着像选中格在悬停时消失
  ///    （用户 2026-10-05「激活按钮在悬停时会与背景融合」）。
  ///    反向推的幅度**按状态分**：悬停只推一半，留在自己这一侧（离底还有 1.1 以上）；
  ///    按下推满，**直接压到另一侧** —— 只推一半时按下会比悬停更贴近那个底，反而更糊
  ///    （用户 2026-10-05「激活的按钮的点击效果的融合现象更严重」）
  /// ④ 透明底：它显示的就是坐着的那个面，按主题方向给
  ///
  /// [on] 是控件实际坐着的面，默认卡面；分段里传它的凹槽底
  Color hoverOn(Color base, {Color? on}) =>
      _stateOn(base, on ?? surface, dark ? 0.10 : 0.08, flipped: 0.5);

  Color pressedOn(Color base, {Color? on}) =>
      _stateOn(base, on ?? surface, dark ? 0.16 : 0.13, flipped: 1);

  /// 实心按钮的状态：**朝远离其上文字的方向**走 —— 文字是近白，所以两个主题都压暗，
  /// 幅度再大一档（饱和实心上 6~8% 的叠层几乎看不出，用户 2026-10-05
  /// 「在主题色按钮上的悬停不够亮，几乎没感觉」）。
  /// 压暗同时把白字对比度**抬高**（实测 4.94 → 6.24），不会为了「有感觉」把可读性做掉；
  /// 反过来说，暗色下若为了「更亮」而提亮实心，白字会掉到 3.6 不达标 —— 这是**不能**走的方向
  Color solidHoverOn(Color base) =>
      _overlayOn(base, dark ? 0.16 : 0.14, Colors.black);

  Color solidPressedOn(Color base) =>
      _overlayOn(base, dark ? 0.24 : 0.22, Colors.black);

  Color _stateOn(
    Color base,
    Color backdrop,
    double amount, {
    required double flipped,
  }) {
    if (base.a < 1) {
      return _overlayOn(base, amount, dark ? Colors.white : Colors.black);
    }
    final lighter =
        toneLuminance(base.toARGB32()) > toneLuminance(backdrop.toARGB32());
    var overlay = lighter ? Colors.white : Colors.black;
    var applied = amount;
    if (_shift(base, overlay, applied) < 3) {
      overlay = lighter ? Colors.black : Colors.white;
      applied = amount * flipped;
    }
    return _overlayOn(base, applied, overlay);
  }

  /// 叠一层之后通道最大的位移（用来判断「这个方向还推得动吗」）
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

  Color _overlayOn(Color base, double amount, Color overlay) =>
      overlay.withAlpha((amount * 255).round());
}

/// 文字层级：桌面密度，靠字重不靠把尺寸吹大
///
/// **卡片标题 16 w600**（2026-10-05 用户看完样张：「标题是否有些小了」）。
/// 原来按 Fluent 的「空间紧时才用 Body Strong 14 w600」定成 14，但样张的卡里
/// 留白是足的（组间 24 / 内衬 16），14 的标题跟 14 的正文只差字重、压不住卡；
/// 16 w600 正好是项目里 `titleLarge` 那一档 ⇒ 与旧页面同尺寸，只把 bold 降成 w600、
/// 主题色换成中性主色
class TemplateType {
  static const page = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
  );
  static const section = TextStyle(
    fontSize: 16,
    height: 22 / 16,
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

/// WCAG 2.x 对比度（判定函数只能用它；APCA 仍是草案，只当诊断）
/// 计算本身在纯 Dart 的 `template_tones.dart` 里，这里只是给 Flutter 的 [Color] 用
double templateContrast(Color a, Color b) =>
    toneContrast(a.toARGB32(), b.toARGB32());

double templateLuminance(Color color) => toneLuminance(color.toARGB32());
