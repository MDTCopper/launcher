import 'dart:ui';

/// Primitive Token —— 整个应用所有颜色的唯一来源。
///
/// 任何 Widget 都不得直接引用这里的值，必须通过 [AppColors]（Semantic Token）间接使用。
/// 层次关系：Palette → AppColors → Widget
abstract class Palette {
  Palette._();

  // ═══════════════════════════════════════════════════════════
  // 铜色系（品牌主色，暖调）
  // ═══════════════════════════════════════════════════════════

  static const Color copper50 = Color(0xFFFDFAF6); // 近白暖调
  static const Color copper100 = Color(0xFFF9F5F0); // 米白辅色
  static const Color copper200 = Color(0xFFF5EDE5); // 极浅铜
  static const Color copper300 = Color(0xFFF0E9E0); // 浅铜过渡
  static const Color copper400 = Color(0xFFD9C1A0); // 浅铜
  static const Color copper500 = Color(0xFFC8A06E); // 主铜（品牌主色）
  static const Color copper600 = Color(0xFFC89958); // 深铜强调
  static const Color copper700 = Color(0xFFB8863E); // 中深铜
  static const Color copper800 = Color(0xFF9E6B30); // 更深铜
  static const Color copper900 = Color(0xFF7A4E22); // 最深铜

  // ═══════════════════════════════════════════════════════════
  // 中性色系（灰阶，文字 / 背景 / 边框）
  // ═══════════════════════════════════════════════════════════

  static const Color white = Color(0xFFFFFFFF);
  static const Color neutral50 = Color(0xFFFAFAFA); // 暖白页底
  static const Color neutral100 = Color(0xFFF5F5F5);
  static const Color neutral200 = Color.fromARGB(255, 223, 223, 223); // 若有若无的边框
  static const Color neutral300 = Color.fromARGB(255, 200, 200, 200); // 禁用态
  static const Color neutral400 = Color.fromARGB(255, 173, 173, 173); // 很淡的辅助文字
  static const Color neutral500 = Color.fromARGB(255, 125, 125, 125); // 次要文字
  static const Color neutral600 = Color.fromARGB(255, 98, 98, 98);
  static const Color neutral700 = Color.fromARGB(255, 76, 76, 76);
  static const Color neutral800 = Color(0xFF2D2D2D); // 主要文字（亮色）
  static const Color neutral900 = Color(0xFF1A1A1A);
  static const Color black = Color(0xFF000000);

  // ═══════════════════════════════════════════════════════════
  // 暗色模式专用灰阶
  // ═══════════════════════════════════════════════════════════

  static const Color darkPage = Color(0xFF0F0F0F); // 页面底（不纯黑）
  static const Color darkCard = Color(0xFF1A1A1A); // 卡片 / 容器
  static const Color darkElevated = Color(0xFF252525); // 悬浮 / 选中浮层
  static const Color darkBorder = Color(0xFF2A2A2A); // 边框（暗色）
  static const Color darkTextPrimary = Color.fromARGB(
    255,
    216,
    216,
    216,
  ); // 主文字
  static const Color darkTextSecondary = Color.fromARGB(
    255,
    193,
    193,
    193,
  ); // 次文字

  // ═══════════════════════════════════════════════════════════
  // 语义色
  // ═══════════════════════════════════════════════════════════

  static const Color error = Color(0xFFD96666); // 错误
  static const Color errorDark = Color(0xFFC94F4F); // 错误（暗色背景用）
  static const Color success = Color(0xFF6BAA6B); // 成功
  static const Color warning = Color(0xFFD9A64A); // 警告
  static const Color info = Color(0xFF5B9BD5); // 信息

  // ═══════════════════════════════════════════════════════════
  // 透明 / 叠加
  // ═══════════════════════════════════════════════════════════

  /// 弹窗遮罩
  static const Color barrier = Color(0x80000000);

  /// 铜色悬浮叠加
  static const Color copperHoverOverlay = Color.fromARGB(40, 188, 140, 72);

  /// 白色悬浮叠加（带一点主题铜色，暗色模式下悬浮更协调）
  static const Color whiteHoverOverlay = Color.fromARGB(32, 194, 166, 134);

  // ═══════════════════════════════════════════════════════════
  // 滚动条
  // ═══════════════════════════════════════════════════════════

  /// 亮色槽
  static const Color scrollbarTrackLight = Color.fromARGB(100, 173, 173, 173);

  /// 亮色槽
  static const Color scrollbarTrackLightHover = Color.fromARGB(
    185,
    173,
    173,
    173,
  );

  /// 暗色槽（白 8%，比滑块暗，拉开区分度）
  static const Color scrollbarTrackDark = Color(0x14FFFFFF);

  /// 暗色槽 hover（白 15%）
  static const Color scrollbarTrackDarkHover = Color(0x26FFFFFF);

  // ═══════════════════════════════════════════════════════════
  // 输入框
  // ═══════════════════════════════════════════════════════════

  /// 输入框聚焦背景（铜色 8%，略透明主题色）
  static const Color inputFocusBackground = Color(0x14C8A06E);
}
