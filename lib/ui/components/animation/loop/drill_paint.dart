import 'package:flutter/material.dart';

/// 铜钻视觉常量与几何：线条化的 Mindustry 机械钻头
///
/// 比例参照原版贴图 `sprites/blocks/drills/mechanical-drill*.png`（64x64 网格、
/// 四片钻头 90 度对称、顶盖 32x32）；线条化时把钻臂往外延长，
/// 让伸出顶盖的那一截成为"看得见在转"的部分，而不是被顶盖压成四个小方块
abstract final class DrillPaint {
  /// 贴图网格边长，所有坐标都以它为基准
  static const double grid = 64;

  /// 钻臂：根端 / 末端半宽与内外半径
  static const double toothRootHalfWidth = 20;
  static const double toothTipHalfWidth = 12;
  static const double toothInnerRadius = 8.5;
  static const double toothOuterRadius = 28.5;

  /// 顶盖八边形半宽，压住钻臂根端
  static const double topHalf = 16;

  /// 底座八边形半宽 / 切角
  static const double baseHalf = 30;
  static const double baseCorner = 6;

  /// 外环轨道离控件外沿的比例，给轨道笔宽与飞出的铜粒留出余量
  static const double arcInset = 0.08;

  /// 钻头外接半径占控件边长的比例，让底座落在环内而不是压在环上
  static const double drillRadiusRatio = (0.5 - arcInset) * 0.85;

  // ── 线条化配色的明暗两套 ──

  /// 暗色主题：整体压暗的金属，在深色页面上压得住
  static const DrillTone darkTone = DrillTone(
    baseFill: Color(0xFF2B2E35),
    baseStroke: Color(0xFF5C636E),
    topFill: Color(0xFF3C414B),
    topStroke: Color(0xFF828A96),
    bladeFill: Color(0xFF525A66),
    bladeStroke: Color(0xFFAEB6C0),
  );

  /// 亮色主题：浅灰不锈钢，深色描边保证在浅色页面上不糊
  static const DrillTone lightTone = DrillTone(
    baseFill: Color(0xFFC9CED6),
    baseStroke: Color(0xFF7E848F),
    topFill: Color(0xFFF1F3F6),
    topStroke: Color(0xFF6E747E),
    bladeFill: Color(0xFFDDE1E7),
    bladeStroke: Color(0xFF4E545E),
  );

  /// 铜块与飞出的铜粒：亮面当主色才看得出是铜，深色只用来勾边
  static const Color itemLight = Color(0xFFE8BC93);
  static const Color itemDark = Color(0xFF8A5A42);

  /// 八边形路径：四角按 [corner] 切 45 度
  static Path octagon(double half, double corner) {
    return Path()
      ..moveTo(-half + corner, -half)
      ..lineTo(half - corner, -half)
      ..lineTo(half, -half + corner)
      ..lineTo(half, half - corner)
      ..lineTo(half - corner, half)
      ..lineTo(-half + corner, half)
      ..lineTo(-half, half - corner)
      ..lineTo(-half, -half + corner)
      ..close();
  }

  /// 一片钻臂：根端宽、末端收窄，末端明显伸出顶盖
  static Path blade() {
    return Path()
      ..moveTo(-toothRootHalfWidth, toothInnerRadius)
      ..lineTo(-toothTipHalfWidth, toothOuterRadius)
      ..lineTo(toothTipHalfWidth, toothOuterRadius)
      ..lineTo(toothRootHalfWidth, toothInnerRadius)
      ..close();
  }

  /// 铜矿块：菱形切角的方块，画在顶盖之上、钻臂之下，四角收在顶盖内才不像浮在底座上
  static Path ore() => octagon(oreHalf, 4);

  /// 铜矿块的半宽；角上到中心的距离要略小于 [topHalf]，否则四角会从顶盖边上探出去
  static const double oreHalf = 11;

  /// 铜矿块：原版 `item-copper.png` 是斜置的 3D 方块，这里抽成一个矩形面 + 一个侧面
  ///
  /// [opacity] 直接乘进各面颜色，避免为了淡出再开一个图层
  static void paintItem(Canvas canvas, double scale, {double opacity = 1}) {
    final body = Rect.fromCenter(
      center: Offset.zero,
      width: 18 * scale,
      height: 10.5 * scale,
    );
    final side = 3 * scale;

    final face = Path()
      ..moveTo(body.left, body.top)
      ..lineTo(body.right, body.top)
      ..lineTo(body.right, body.bottom)
      ..lineTo(body.left, body.bottom)
      ..close();

    final flank = Path()
      ..moveTo(body.left, body.bottom)
      ..lineTo(body.right, body.bottom)
      ..lineTo(body.right - side, body.bottom + side)
      ..lineTo(body.left - side, body.bottom + side)
      ..close();

    canvas.drawPath(
      flank,
      Paint()
        ..style = PaintingStyle.fill
        ..color = _fade(itemDark, opacity),
    );
    canvas.drawPath(
      face,
      Paint()
        ..style = PaintingStyle.fill
        ..color = _fade(itemLight, opacity),
    );
    canvas.drawPath(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * scale
        ..color = _fade(itemDark, opacity),
    );
  }

  static Color _fade(Color color, double opacity) => Color.fromARGB(
    (color.a * 255 * opacity).round(),
    (color.r * 255).round(),
    (color.g * 255).round(),
    (color.b * 255).round(),
  );
}

/// 钻头各层的填充 / 描边色
@immutable
class DrillTone {
  const DrillTone({
    required this.baseFill,
    required this.baseStroke,
    required this.topFill,
    required this.topStroke,
    required this.bladeFill,
    required this.bladeStroke,
  });

  final Color baseFill;
  final Color baseStroke;
  final Color topFill;
  final Color topStroke;
  final Color bladeFill;
  final Color bladeStroke;

  static DrillTone of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? DrillPaint.darkTone
      : DrillPaint.lightTone;
}
