import 'dart:math' as math;

import '../../../util/io/mindustry_save_file/schematic_file.dart';
import '../plan_draw_rule.dart';

/// 连线类规则（官方 `drawPlanConfigTop`）
///
/// 官方预览（`Schematics.getBuffer`）只调用 `drawPlanRegion` 与 `drawPlanConfigTop`，
/// 不调用 `drawPlanConfig`；这批规则负责的声明类：
/// - `ItemBridge`：bridge-conveyor / bridge-conduit / phase-conveyor / phase-conduit
/// - `DirectionBridge`：duct-bridge / reinforced-bridge-conduit
/// - `PowerNode`：power-node / power-node-large / surge-tower / beam-link / power-source
///
/// 另外补了 `DirectionBridge` 的 `drawPlanRegion`（本体 region + dirRegion 旋转叠加），
/// 这类方块声明了 configTop 但本体之前走 fallback 全图标
///
/// 参数与 region 命名依据 v160.7 jar 反编译源码（`tmp/bp-research/m1/src-decomp`）：
/// - `Renderer.bridgeOpacity` / `Renderer.laserOpacity` 的静态默认值分别是 0.75 / 0.5，
///   离屏预览没有跑过 `Renderer.update`，用的就是这两个静态值
/// - region 命名来自生成的 `ContentRegions`：`<name>-bridge/-arrow/-end`、
///   `<name>-dir/-bridge-bottom/-bridge-liquid`
/// - PowerNode 用通用 `laser` / `laser-end`（`<name>-laser` 不存在时的回退）
final List<PlanDrawRule> connectionLinkRules = <PlanDrawRule>[
  _ItemBridgeRule(),
  _DirectionBridgeRule(),
  _DirectionBridgeRegionRule(),
  _PowerNodeRule(),
];

/// 官方 `Renderer.bridgeOpacity` 静态默认值
const double _bridgeOpacity = 0.75;

/// 官方 `Renderer.laserOpacity` 静态默认值
const double _laserOpacity = 0.5;

/// 电力激光颜色
///
/// 官方为 `laserColor1`（白）向 `Pal.powerLight` 插值，系数是 `absin(3, 0.1)`；
/// 取预览截图时刻约 0.06 的插值结果，随时间只在这个范围内轻微变化
const int _laserColor = 0xFFFFFCF6;

/// `Geometry.d4` 的 x/y 偏移（世界坐标 y 向上）
const List<int> _d4x = <int>[1, 0, -1, 0];
const List<int> _d4y = <int>[0, 1, 0, -1];

/// 屏幕空间方向角（度）
///
/// 屏幕 y 轴向下，与官方世界角度反号
double _screenDegrees(double screenDx, double screenDy) =>
    math.atan2(screenDy, screenDx) * 180.0 / math.pi;

/// 官方 `Mathf.clamp(value, -1, 1)`
int _clampDirection(int value) => value < -1 ? -1 : (value > 1 ? 1 : value);

/// `ItemBridge.drawPlanConfigTop` + `drawBridge`
///
/// config 是目标格的相对偏移，目标必须是同种桥，桥面两端各内缩 4 世界单位
class _ItemBridgeRule extends PlanDrawRule {
  /// 各变体的连接距离（官方 `ItemBridge.range` 字段）
  static const Map<String, int> _ranges = <String, int>{
    'bridge-conveyor': 4,
    'bridge-conduit': 4,
    'phase-conveyor': 12,
    'phase-conduit': 12,
  };

  /// 未知变体按最常见的 4 格处理，超出距离的目标官方同样不画
  static const int _defaultRange = 4;

  /// 官方 `bridgeWidth` 默认 6.5 世界单位
  static const double _bridgeWidth = 6.5;

  @override
  Set<String> get configTopClasses => const <String>{'ItemBridge'};

  @override
  void drawConfigTop(PlanDrawContext context, PlanTile plan) {
    final config = plan.tile.config;
    if (config == null || config.kind != SchematicConfigKind.point) return;
    final point = config.value as SchematicPoint;
    final range = _ranges[plan.info.name] ?? _defaultRange;
    if (point.x.abs() > range ||
        point.y.abs() > range ||
        (point.x != 0 && point.y != 0)) {
      return;
    }
    // 官方 planFinder 要求目标 plan 的原点坐标与目标格完全一致
    final other = context.planAt(plan.x + point.x, plan.y + point.y);
    if (other == null || identical(other, plan)) return;
    if (other.info.name != plan.info.name) return;
    _drawBridge(context, plan, other);
  }

  void _drawBridge(PlanDrawContext context, PlanTile plan, PlanTile other) {
    final dx = other.centerX - plan.centerX;
    final dy = other.centerY - plan.centerY;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance <= 0) return;
    final ux = dx / distance;
    final uy = dy / distance;
    // 官方 `Tmp.v1.setLength(4.0f)`，1 世界单位 = 4px
    const trim = 4.0 * 4.0;
    final startX = plan.centerX + ux * trim;
    final startY = plan.centerY + uy * trim;
    final endX = other.centerX - ux * trim;
    final endY = other.centerY - uy * trim;
    final angle = _screenDegrees(dx, dy);
    final bridgeName = '${plan.info.name}-bridge';
    final bridgeSize = context.regionSize(bridgeName);
    if (bridgeSize != null) {
      context.drawRegion(
        bridgeName,
        centerX: (startX + endX) / 2.0,
        centerY: (startY + endY) / 2.0,
        angleDegrees: angle,
        scaleX: (distance - trim * 2.0) / bridgeSize.width,
        scaleY: _bridgeWidth * 4.0 / bridgeSize.height,
        alpha: _bridgeOpacity,
      );
    }
    // 官方在两端中心点的中点画一个箭头，角度是两端连线方向
    context.drawRegion(
      '${plan.info.name}-arrow',
      centerX: (plan.centerX + other.centerX) / 2.0,
      centerY: (plan.centerY + other.centerY) / 2.0,
      angleDegrees: angle,
      alpha: _bridgeOpacity,
    );
  }
}

/// `DirectionBridge.drawPlanConfigTop` + `drawBridge`
///
/// 这类桥没有 config，按自身 rotation 找同种桥的最近目标
class _DirectionBridgeRule extends PlanDrawRule {
  /// 官方 `DirectionBridge.range` 默认 4，v160.7 的两种方块都未覆写
  static const int _range = 4;

  @override
  Set<String> get configTopClasses => const <String>{'DirectionBridge'};

  @override
  void drawConfigTop(PlanDrawContext context, PlanTile plan) {
    final rotation = plan.rotation % 4;
    final dirX = _d4x[rotation];
    final dirY = _d4y[rotation];
    PlanTile? other;
    var remaining = _range;
    for (final candidate in context.placed) {
      if (identical(candidate, plan)) continue;
      if (candidate.info.name != plan.info.name) continue;
      final dx = candidate.x - plan.x;
      final dy = candidate.y - plan.y;
      // 官方 planFinder：方向分量 clamp 到 -1..1 后必须等于 rotation 的方向
      if (_clampDirection(dx) != dirX || _clampDirection(dy) != dirY) continue;
      final distance = math.max(dx.abs(), dy.abs());
      // 官方 otherDst 初值为 range，只在更近时替换
      if (distance > remaining) continue;
      other = candidate;
      remaining = distance;
    }
    if (other == null) return;
    _drawBridge(context, plan, other, dirX, dirY);
  }

  void _drawBridge(
    PlanDrawContext context,
    PlanTile plan,
    PlanTile other,
    int dirX,
    int dirY,
  ) {
    final dx = other.centerX - plan.centerX;
    final dy = other.centerY - plan.centerY;
    final angle = _screenDegrees(dx, dy);
    final centerX = (plan.centerX + other.centerX) / 2.0;
    final centerY = (plan.centerY + other.centerY) / 2.0;
    // 官方 len = max(|dx|,|dy|) - size*8（世界单位），这里把屏幕像素换算回世界单位
    final lengthPx = math.max(dx.abs(), dy.abs()) - plan.size * 32.0;
    final bridgeName = '${plan.info.name}-bridge';
    final bridgeSize = context.regionSize(bridgeName);
    if (bridgeSize != null) {
      context.drawRegion(
        bridgeName,
        centerX: centerX,
        centerY: centerY,
        angleDegrees: angle,
        scaleX: lengthPx / bridgeSize.width,
        alpha: _bridgeOpacity,
      );
    }
    // 官方 bot 层：0.4 灰、alpha 再乘 0.4
    final bottomName = '${plan.info.name}-bridge-bottom';
    final bottomSize = context.regionSize(bottomName);
    if (bottomSize != null) {
      context.drawRegion(
        bottomName,
        centerX: centerX,
        centerY: centerY,
        angleDegrees: angle,
        scaleX: lengthPx / bottomSize.width,
        alpha: 0.4 * _bridgeOpacity,
        tintColor: 0xFF666666,
      );
    }
    // 官方箭头只受 Lod.l1 控制，静态默认 Lod.alpha1 = 1，不乘 bridgeOpacity
    final reach = math.max(dx.abs(), dy.abs()) / 4.0;
    for (var i = 6.0; i <= reach - 5.0; i += 5.0) {
      context.drawRegion(
        '${plan.info.name}-arrow',
        centerX: plan.centerX + dirX * i * 4.0,
        centerY: plan.centerY - dirY * i * 4.0,
        angleDegrees: angle,
      );
    }
  }
}

/// `DirectionBridge.drawPlanRegion`
///
/// 官方画两层：`region` 不旋转，`dirRegion` 按 rotation 旋转
/// 这类方块声明了 `drawPlanConfigTop`，本体之前走 fallback 全图标（整体旋转，base 会歪）
class _DirectionBridgeRegionRule extends PlanDrawRule {
  @override
  Set<String> get blockClasses => const <String>{'DirectionBridge'};

  @override
  void drawBlock(PlanDrawContext context, PlanTile plan) {
    final baseName = plan.info.name;
    if (context.regionSize(baseName) == null) {
      // 资产包缺本体 region 时退回默认图标，避免方块消失
      context.drawBlockIcon(plan);
      return;
    }
    context.drawRegion(baseName, centerX: plan.centerX, centerY: plan.centerY);
    final dirName = '$baseName-dir';
    if (context.regionSize(dirName) == null) return;
    context.drawRegion(
      dirName,
      centerX: plan.centerX,
      centerY: plan.centerY,
      angleDegrees: -plan.rotation * 90.0,
    );
  }
}

/// `PowerNode.drawPlanConfigTop` + `drawLaser`
///
/// config 是 `Point2[]` 相对偏移，逐个找覆盖目标格的带电力方块并画激光
class _PowerNodeRule extends PlanDrawRule {
  /// 官方 `laserScale` 默认 0.25
  static const double _laserScale = 0.25;

  @override
  Set<String> get configTopClasses => const <String>{'PowerNode'};

  @override
  void drawConfigTop(PlanDrawContext context, PlanTile plan) {
    final config = plan.tile.config;
    if (config == null || config.kind != SchematicConfigKind.pointList) return;
    final points = config.value as List<SchematicPoint>;
    for (final point in points) {
      // 官方 planFinder 按占用范围匹配，多格电力建筑也能命中
      final target = context.planCovering(plan.x + point.x, plan.y + point.y);
      if (target == null || identical(target, plan)) continue;
      _drawLaser(context, plan, target);
    }
  }

  void _drawLaser(PlanDrawContext context, PlanTile plan, PlanTile target) {
    final dx = target.centerX - plan.centerX;
    final dy = target.centerY - plan.centerY;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance <= 0) return;
    final ux = dx / distance;
    final uy = dy / distance;
    // 官方 len = size*8/2 - 1.5 世界单位，端点各向内收
    final startInset = (plan.size * 8.0 / 2.0 - 1.5) * 4.0;
    final endInset = (target.size * 8.0 / 2.0 - 1.5) * 4.0;
    final startX = plan.centerX + ux * startInset;
    final startY = plan.centerY + uy * startInset;
    final endX = target.centerX - ux * endInset;
    final endY = target.centerY - uy * endInset;
    final angle = _screenDegrees(dx, dy);
    // `Drawf.laser` 的端点偏移：8 * scale * Scl = 0.5 世界单位
    final capInset = 8.0 * _laserScale * 0.25 * 4.0;
    final capName = 'laser-end';
    final capSize = context.regionSize(capName);
    if (capSize != null) {
      // 官方按 width * scale * scl() 缩放端点，两个方向尺寸一致
      final capPx = capSize.width * _laserScale * 0.25 * 4.0;
      context.drawRegion(
        capName,
        centerX: startX,
        centerY: startY,
        angleDegrees: angle + 180.0,
        scaleX: capPx / capSize.width,
        scaleY: capPx / capSize.height,
        alpha: _laserOpacity,
        tintColor: _laserColor,
      );
      context.drawRegion(
        capName,
        centerX: endX,
        centerY: endY,
        angleDegrees: angle,
        scaleX: capPx / capSize.width,
        scaleY: capPx / capSize.height,
        alpha: _laserOpacity,
        tintColor: _laserColor,
      );
    }
    final lineName = 'laser';
    final lineSize = context.regionSize(lineName);
    if (lineSize == null) return;
    final lineStartX = startX + ux * capInset;
    final lineStartY = startY + uy * capInset;
    final lineEndX = endX - ux * capInset;
    final lineEndY = endY - uy * capInset;
    final lineDx = lineEndX - lineStartX;
    final lineDy = lineEndY - lineStartY;
    final lineLength = math.sqrt(lineDx * lineDx + lineDy * lineDy);
    if (lineLength <= 0) return;
    // 官方 `Lines.stroke(12 * scale)`，即 3 世界单位宽
    final lineThickness = 12.0 * _laserScale * 4.0;
    context.drawRegion(
      lineName,
      centerX: (lineStartX + lineEndX) / 2.0,
      centerY: (lineStartY + lineEndY) / 2.0,
      angleDegrees: _screenDegrees(lineDx, lineDy),
      scaleX: lineLength / lineSize.width,
      scaleY: lineThickness / lineSize.height,
      alpha: _laserOpacity,
      tintColor: _laserColor,
    );
  }
}
