import 'dart:math' as math;

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
  ///
  /// 根端要落在顶盖里（[topHalf]），末端伸到底座边上，中间那 17 个单位才是看得见的钻臂
  static const double toothRootHalfWidth = 16;
  static const double toothTipHalfWidth = 11;
  static const double toothInnerRadius = 4;
  static const double toothOuterRadius = 28;

  /// 顶盖八边形半宽；占底座一半左右，压住钻臂根端又不抢主体
  static const double topHalf = 12;

  /// 底座八边形半宽 / 切角
  static const double baseHalf = 30;
  static const double baseCorner = 6;

  /// 钻头外面留的余量比例，给弹出的铜粒留出飞行空间
  static const double layoutInset = 0.08;

  /// 钻头外接半径占控件边长的比例
  static const double drillRadiusRatio = (0.5 - layoutInset) * 0.85;

  // ── 线条化配色的明暗两套 ──

  /// 暗色主题：底座压暗当底、顶盖居中、钻臂最亮 —— 三层要拉开才看得出是"在转的钻头"
  static const DrillTone darkTone = DrillTone(
    baseFill: Color(0xFF1E2127),
    baseStroke: Color(0xFF41464F),
    topFill: Color(0xFF333842),
    topStroke: Color(0xFF5A616C),
    bladeFill: Color(0xFF6E7783),
    bladeStroke: Color(0xFFC2CAD4),
  );

  /// 亮色主题：底座最深、顶盖居中、钻臂最浅，同一条明度梯度的反向
  static const DrillTone lightTone = DrillTone(
    baseFill: Color(0xFFAEB4BE),
    baseStroke: Color(0xFF6E747E),
    topFill: Color(0xFFDCE0E6),
    topStroke: Color(0xFF8D939E),
    bladeFill: Color(0xFFF4F6F9),
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

  /// 四片钻臂并成一个形状
  ///
  /// 分开画时四条臂在轮毂处两两相交，**每片各自的描边会在交叠处留下内轮廓**
  /// （顶点的尖角看着像拼错位）；先并成一条路径，描边再按它裁剪，缝就没了
  static Path bladeUnion() {
    final single = blade();
    var union = single;
    for (var quarter = 1; quarter < 4; quarter++) {
      union = Path.combine(
        PathOperation.union,
        union,
        single.transform(Matrix4.rotationZ(math.pi / 2 * quarter).storage),
      );
    }
    return union;
  }

  /// 轮毂亮点的实心半径与柔光半径；实心点要盖过顶盖中央，柔光再往外化开
  static const double hubRadius = 7;
  static const double hubGlowRadius = 17;

  /// 轮毂亮点：中心一个实心点 + 一圈柔光，明暗由 [pulse] 决定
  ///
  /// 这是整个动画唯一的"状态灯" —— 正常时暖色随每轮钻探闪一下，出错时转红常亮
  static void paintHubLight(
    Canvas canvas,
    double scale,
    Color color,
    double pulse,
  ) {
    final glow = hubGlowRadius * scale;
    canvas.drawCircle(
      Offset.zero,
      glow,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _fade(color, pulse),
            _fade(color, pulse * 0.35),
            _fade(color, 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: glow)),
    );
    canvas.drawCircle(
      Offset.zero,
      hubRadius * scale,
      Paint()..color = _fade(color, (0.35 + 0.65 * pulse).clamp(0, 1)),
    );
  }

  /// 铜粒：从轮毂弹出的小铜块
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
