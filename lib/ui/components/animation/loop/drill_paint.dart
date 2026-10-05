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

  /// 钻头外接半径占控件边长的比例
  ///
  /// 给到 1.06 是"贴着控件边"：八边形四个平面正好落在控件四边，
  /// 四角的空隙留给弹出的铜粒；再大就会被控件裁掉
  static const double drillRadiusRatio = 1.06;

  // ── 线条化配色的明暗两套 ──

  /// 暗色主题：底座压暗当底、顶盖居中、钻臂压得比顶盖更沉 —— 只靠那圈亮描边勾出"在转的钻头"
  static const DrillTone darkTone = DrillTone(
    baseFill: Color(0xFF2B2E35),
    baseStroke: Color(0xFF5C636E),
    topFill: Color(0xFF31353E),
    topStroke: Color(0xFF7A828E),
    bladeFill: Color(0xFF3A4049),
    bladeStroke: Color(0xFF9AA3AF),
  );

  /// 亮色主题：同一条明度梯度，整组比页面底色深一档才看得见
  static const DrillTone lightTone = DrillTone(
    baseFill: Color(0xFF8E959F),
    baseStroke: Color(0xFF5A606A),
    topFill: Color(0xFFC2C8D0),
    topStroke: Color(0xFF6E747E),
    bladeFill: Color(0xFFF2F4F7),
    bladeStroke: Color(0xFF4E545E),
  );

  /// 出错时**线条**往红里偏的色相；填充色不动，所以是"结构线条略微变红"而不是整块泛红
  static const Color errorTint = Color(0xFFC0392B);

  /// 出错时各层描边往红里偏多少：要"略微"，偏到刚好看得出线条发红就收
  static const double errorBaseTint = 0.22;
  static const double errorTopTint = 0.2;
  static const double errorBladeTint = 0.18;

  /// 把 [color] 往 [errorTint] 混 [amount]（0~1）
  static Color tinted(Color color, double amount) {
    if (amount <= 0) return color;
    return Color.lerp(color, errorTint, amount.clamp(0, 1))!;
  }

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

  /// 并集路径按需算一次就够：路径不随动画变，变的只有画布变换
  static Path? _bladeUnionCache;

  /// 四片钻臂并成一个形状
  ///
  /// 分开画时四条臂在轮毂处两两相交，**每片各自的描边会在交叠处留下内轮廓**
  /// （顶点的尖角看着像拼错位）；先并成一条路径，描边再按它裁剪，缝就没了
  static Path bladeUnion() {
    final cached = _bladeUnionCache;
    if (cached != null) return cached;

    final single = blade();
    var union = single;
    for (var quarter = 1; quarter < 4; quarter++) {
      union = Path.combine(
        PathOperation.union,
        union,
        single.transform(Matrix4.rotationZ(math.pi / 2 * quarter).storage),
      );
    }
    return _bladeUnionCache = union;
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
