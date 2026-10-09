import 'dart:ui';

/// 游戏默认玩家色（Mindustry `Vars.playerColors[8]`）：没设过色时拿它兜底
const defaultPlayerColor = 0xFFA108FF;

/// 游戏里可选的玩家色：与 Mindustry `Vars.playerColors` 一致的 16 个
///
/// arc `rgba8888` 编码：0xRRGGBBAA
const playerColors = <int>[
  0x82759AFF, // 灰紫
  0xC0C1C5FF, // 浅灰
  0xFFFFFFFF, // 白
  0x7D2953FF, // 深酒红
  0xFF074EFF, // 玫红
  0xFF072AFF, // 红
  0xFF76A6FF, // 粉
  0xA95238FF, // 棕
  0xFFA108FF, // 橙（游戏默认）
  0xFEEB2CFF, // 黄
  0xFFCAA8FF, // 米
  0x008551FF, // 深绿
  0x00E339FF, // 绿
  0x423C7BFF, // 蓝紫
  0x4B5EF1FF, // 蓝
  0x2CABFEFF, // 天蓝
];

/// arc 0xRRGGBBAA → Flutter Color
///
/// arc `rgba8888` 的字节布局：R << 24 | G << 16 | B << 8 | A
Color arcToColor(int arc) => Color.fromARGB(
  arc & 0xFF,
  (arc >> 24) & 0xFF,
  (arc >> 16) & 0xFF,
  (arc >> 8) & 0xFF,
);

/// Flutter Color → arc `rgba8888`（取色器给的是 Color，写回要 arc 编码）
int colorToArc(Color color) {
  final argb = color.toARGB32();
  return ((argb >> 16 & 0xFF) << 24) |
      ((argb >> 8 & 0xFF) << 16) |
      ((argb & 0xFF) << 8) |
      (argb >> 24 & 0xFF);
}

/// 把「未设色」（0 / 透明）当没设，回落到游戏默认色
///
/// 全新版本没有 `settings.bin`，`color-0` 读出来是 0（全透明）；
/// 直接用会让名字渲染成全透明、看着像空的
int resolvePlayerColor(int color) =>
    (color & 0xFF) == 0 ? defaultPlayerColor : color;
