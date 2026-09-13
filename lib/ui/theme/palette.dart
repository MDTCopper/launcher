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

  static const copper50 = Color(0xFFFDFAF6); // 近白暖调
  static const copper100 = Color(0xFFF9F5F0); // 米白辅色
  static const copper200 = Color(0xFFF5EDE5); // 极浅铜
  static const copper300 = Color(0xFFF0E9E0); // 浅铜过渡
  static const copper400 = Color(0xFFD9C1A0); // 浅铜
  static const copper500 = Color(0xFFC8A06E); // 主铜（品牌主色）
  static const copper600 = Color(0xFFC89958); // 深铜强调
  static const copper700 = Color(0xFFB8863E); // 中深铜
  static const copper800 = Color(0xFF9E6B30); // 更深铜
  static const copper900 = Color(0xFF7A4E22); // 最深铜

  // ═══════════════════════════════════════════════════════════
  // 钛色系
  // ═══════════════════════════════════════════════════════════

  static const titanium50 = Color.fromARGB(255, 246, 249, 253);
  static const titanium100 = Color.fromARGB(255, 240, 244, 249);
  static const titanium200 = Color.fromARGB(255, 229, 237, 245);
  static const titanium300 = Color.fromARGB(255, 214, 227, 241);
  static const titanium400 = Color.fromARGB(255, 173, 199, 233);
  static const titanium500 = Color.fromARGB(255, 129, 176, 227);
  static const titanium600 = Color.fromARGB(255, 101, 147, 216);
  static const titanium700 = Color.fromARGB(255, 75, 117, 207);
  static const titanium800 = Color.fromARGB(255, 37, 76, 175);
  static const titanium900 = Color.fromARGB(255, 17, 56, 165);

  // ═══════════════════════════════════════════════════════════
  // 钍色系
  // ═══════════════════════════════════════════════════════════

  static const thorium50 = Color.fromARGB(255, 253, 246, 253);
  static const thorium100 = Color.fromARGB(255, 249, 240, 248);
  static const thorium200 = Color.fromARGB(255, 245, 229, 244);
  static const thorium300 = Color.fromARGB(255, 240, 209, 240);
  static const thorium400 = Color.fromARGB(255, 228, 164, 221);
  static const thorium500 = Color.fromARGB(255, 229, 135, 221);
  static const thorium600 = Color.fromARGB(255, 230, 113, 224);
  static const thorium700 = Color.fromARGB(255, 214, 80, 219);
  static const thorium800 = Color.fromARGB(255, 206, 48, 201);
  static const thorium900 = Color.fromARGB(255, 191, 19, 177);

  // ═══════════════════════════════════════════════════════════
  // 塑钢色系
  // ═══════════════════════════════════════════════════════════

  static const plastanium50 = Color.fromARGB(255, 248, 253, 246);
  static const plastanium100 = Color.fromARGB(255, 242, 249, 240);
  static const plastanium200 = Color.fromARGB(255, 234, 245, 229);
  static const plastanium300 = Color.fromARGB(255, 229, 240, 224);
  static const plastanium400 = Color.fromARGB(255, 180, 217, 160);
  static const plastanium500 = Color.fromARGB(255, 144, 200, 110);
  static const plastanium600 = Color.fromARGB(255, 114, 200, 88);
  static const plastanium700 = Color.fromARGB(255, 103, 184, 62);
  static const plastanium800 = Color.fromARGB(255, 101, 158, 48);
  static const plastanium900 = Color.fromARGB(255, 88, 122, 34);

  // ═══════════════════════════════════════════════════════════
  // 中性色系（灰阶，文字 / 背景 / 边框）
  // ═══════════════════════════════════════════════════════════

  static const white = Color(0xFFFFFFFF);
  static const neutral50 = Color(0xFFFAFAFA); // 暖白页底
  static const neutral100 = Color(0xFFF5F5F5);
  static const neutral200 = Color.fromARGB(255, 223, 223, 223); // 若有若无的边框
  static const neutral300 = Color.fromARGB(255, 200, 200, 200); // 禁用态
  static const neutral400 = Color.fromARGB(255, 173, 173, 173); // 很淡的辅助文字
  static const neutral500 = Color.fromARGB(255, 125, 125, 125); // 次要文字
  static const neutral600 = Color.fromARGB(255, 98, 98, 98);
  static const neutral700 = Color.fromARGB(255, 76, 76, 76);
  static const neutral800 = Color(0xFF2D2D2D); // 主要文字（亮色）
  static const neutral900 = Color(0xFF1A1A1A);
  static const black = Color(0xFF000000);

  // ═══════════════════════════════════════════════════════════
  // 暗色模式专用灰阶
  // ═══════════════════════════════════════════════════════════

  static const darkPage = Color.fromARGB(255, 18, 18, 18); // 页面底（不纯黑）
  static const darkCard = Color(0xFF1A1A1A); // 卡片 / 容器
  static const darkElevated = Color(0xFF252525); // 悬浮 / 选中浮层
  static const darkBorder = Color(0xFF2A2A2A); // 边框（暗色）
  static const darkTextPrimary = Color.fromARGB(255, 216, 216, 216); // 主文字
  static const darkTextSecondary = Color.fromARGB(255, 193, 193, 193); // 次文字

  // ═══════════════════════════════════════════════════════════
  // 语义色
  // ═══════════════════════════════════════════════════════════

  static const error = Color(0xFFD96666); // 错误
  static const errorDark = Color(0xFFC94F4F); // 错误（暗色背景用）
  static const success = Color(0xFF6BAA6B); // 成功
  static const warning = Color(0xFFD9A64A); // 警告
  static const info = Color(0xFF5B9BD5); // 信息

  // ═══════════════════════════════════════════════════════════
  // 透明 / 叠加
  // ═══════════════════════════════════════════════════════════

  /// 弹窗遮罩
  static const barrier = Color(0x80000000);

  //悬浮叠加
  static const copperDarkHoverOverlay = Color.fromARGB(40, 188, 140, 72);
  static const copperHoverOverlay = Color.fromARGB(32, 194, 166, 134);

  static const titaniumDarkHoverOverlay = Color.fromARGB(40, 72, 109, 188);
  static const titaniumHoverOverlay = Color.fromARGB(31, 134, 150, 194);

  static const thoriumDarkHoverOverlay = Color.fromARGB(40, 178, 72, 188);
  static const thoriumHoverOverlay = Color.fromARGB(31, 194, 134, 188);

  static const plastaniumDarkHoverOverlay = Color.fromARGB(40, 130, 188, 72);
  static const plastaniumHoverOverlay = Color.fromARGB(31, 164, 194, 134);

  // ═══════════════════════════════════════════════════════════
  // 滚动条
  // ═══════════════════════════════════════════════════════════

  /// 亮色槽
  static const scrollbarTrackLight = Color.fromARGB(100, 173, 173, 173);

  /// 亮色槽
  static const scrollbarTrackLightHover = Color.fromARGB(185, 173, 173, 173);

  /// 暗色槽（白 8%，比滑块暗，拉开区分度）
  static const scrollbarTrackDark = Color(0x14FFFFFF);

  /// 暗色槽 hover（白 15%）
  static const scrollbarTrackDarkHover = Color(0x26FFFFFF);

  // ═══════════════════════════════════════════════════════════
  // 输入框
  // ═══════════════════════════════════════════════════════════

  /// 输入框聚焦背景（铜色 8%，略透明主题色）
  static const copperInputFocusBackground = Color(0x14C8A06E);
  static const titaniumInputFocusBackground = Color.fromARGB(19, 110, 128, 200);
  static const thoriumInputFocusBackground = Color.fromARGB(19, 200, 110, 195);
  static const plastaniumInputFocusBackground = Color.fromARGB(
    19,
    143,
    200,
    110,
  );
}
