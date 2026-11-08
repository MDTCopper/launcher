import '../plan_draw_rule.dart';

/// 传输连通重绘规则（官方 `drawPlanRegion` 覆写）
///
/// 负责的官方声明类：`Conveyor` / `Duct` / `Conduit` / `StackConveyor`
/// 这类方块按相邻方块方向选 region，参考 v160.7 源码
/// `tmp/mindustry-src-probe/.../Autotiler.java` 与各 `drawPlanRegion` 实现
///
/// 官方预览（`Schematics.getBuffer`）里 `plan.tile()` 是坐标被改成 plan 原点的 fake emptyTile、
/// `plan.worldContext = false`，所以 `Autotiler.blends` 一律只走 directionals 分支，
/// `lookingAt` / `Edges.getFacingEdge` / `Tile.nearbyBuild` 拿到的全是 null —— 本文件按这个前提实现
final List<PlanDrawRule> transportConnectivityRules = <PlanDrawRule>[
  _ConveyorRule(),
  _DuctRule(),
  _StackConveyorRule(),
  _ConduitRule(),
];

/// `Geometry.d4` 的 x/y 偏移（世界坐标 y 向上）
const List<int> _d4x = <int>[1, 0, -1, 0];
const List<int> _d4y = <int>[0, 1, 0, -1];

/// 官方 rotation 值转屏幕角度（屏幕 y 轴向下，角度反向）
double _screenAngle(int rotation) => -rotation * 90.0;

/// 官方 `Autotiler.getTiling` 的结果
class _Tiling {
  const _Tiling({
    required this.index,
    required this.scaleX,
    required this.scaleY,
    required this.mask,
  });

  /// 选中的 region 下标（Conveyor 的第 0 维 / Duct、Conduit 的下标）
  final int index;

  /// x 缩放，官方恒为 1
  final int scaleX;

  /// y 缩放，官方为 1 或 -1（-1 表示纵向翻转 region）
  final int scaleY;

  /// 四向连通 mask，`bits[3]`：第 i 位表示 direction i 与相邻方块连通
  final int mask;
}

/// 带 Autotiler 逻辑的规则基类
abstract class _AutotilerRule extends PlanDrawRule {
  /// 官方 `Autotiler.blends(Tile, rotation, otherx, othery, otherrot, Block)` 的 Dart 版
  ///
  /// 只处理 preview 可达的 directionals 分支（无世界上下文）
  bool blendsWith(PlanTile plan, PlanTile other);

  /// 官方 `getTiling(BuildPlan, Eachable)`：先把四个邻格上的 plan 收进 directionals，再算 blending
  _Tiling? tiling(PlanDrawContext context, PlanTile plan) {
    final directionals = List<PlanTile?>.filled(4, null);
    for (final other in context.placed) {
      if (identical(other, plan)) continue;
      // 官方 blendFinder：邻格落在 other 的占用范围内就记到对应方向
      for (var i = 0; i < 4; i++) {
        final cellX = plan.x + _d4x[i];
        final cellY = plan.y + _d4y[i];
        if (cellX >= other.minX &&
            cellX <= other.maxX &&
            cellY >= other.minY &&
            cellY <= other.maxY) {
          directionals[i] = other;
        }
      }
    }

    bool blends(int direction) {
      final other = directionals[(plan.rotation - direction) % 4];
      return other != null && blendsWith(plan, other);
    }

    // 官方 buildBlending：按顺序判定 case 得到 bits[0]/bits[2]
    final int resultCase;
    if (blends(2) && blends(1) && blends(3)) {
      resultCase = 0;
    } else if (blends(1) && blends(3)) {
      resultCase = 1;
    } else if (blends(1) && blends(2)) {
      resultCase = 2;
    } else if (blends(3) && blends(2)) {
      resultCase = 3;
    } else if (blends(1)) {
      resultCase = 4;
    } else if (blends(3)) {
      resultCase = 5;
    } else {
      resultCase = -1;
    }

    // transformCase
    var index = 0;
    var scaleY = 1;
    switch (resultCase) {
      case 0:
        index = 3;
      case 1:
        index = 4;
      case 2:
        index = 2;
      case 3:
        index = 2;
        scaleY = -1;
      case 4:
        index = 1;
        scaleY = -1;
      case 5:
        index = 1;
      default:
        index = 0;
    }

    var mask = 0;
    for (var i = 0; i < 4; i++) {
      if (blends(i)) mask |= 1 << i;
    }
    return _Tiling(index: index, scaleX: 1, scaleY: scaleY, mask: mask);
  }
}

/// `Conveyor`（含 armored-conveyor）= 官方 `Conveyor.drawPlanRegion`
class _ConveyorRule extends _AutotilerRule {
  @override
  Set<String> get blockClasses => const <String>{'Conveyor'};

  @override
  bool blendsWith(PlanTile plan, PlanTile other) {
    if (_isClass(plan, 'ArmoredConveyor')) {
      // ArmoredConveyor.blends 的第二项要 lookingAt，preview 恒为 false
      final armored =
          _planFaces(plan, other) ||
          (_isClass(other, 'Conveyor') &&
              _rotatedOutput(other) &&
              _otherFaces(plan, other));
      return _outputsItems(other) && armored;
    }
    return _outputsItems(other) && _lookingAtEither(plan, other);
  }

  @override
  void drawBlock(PlanDrawContext context, PlanTile plan) {
    final tiling = this.tiling(context, plan);
    if (tiling == null) return;
    // regions[bits[0]][0]，宽高各乘 bits[1]/bits[2]（负值 = 纵向翻转）
    _drawTilingRegion(
      context,
      '${plan.info.name}-${tiling.index}-0',
      plan: plan,
      scaleX: tiling.scaleX,
      scaleY: tiling.scaleY,
    );
  }
}

/// `Duct`（duct / armored-duct）= 官方 `Duct.drawPlanRegion`
class _DuctRule extends _AutotilerRule {
  @override
  Set<String> get blockClasses => const <String>{'Duct'};

  @override
  bool blendsWith(PlanTile plan, PlanTile other) {
    if (plan.info.name == 'armored-duct') {
      // Duct.armored 是匿名子类里赋的实例字段，v160.7 只有 armored-duct 一个变体
      final armored =
          _planFaces(plan, other) ||
          (_rotatedOutput(other) &&
              other.info.isDuct &&
              _otherFaces(plan, other));
      return _outputsItems(other) && armored;
    }
    return _outputsItems(other) && _lookingAtEither(plan, other);
  }

  @override
  void drawBlock(PlanDrawContext context, PlanTile plan) {
    final tiling = this.tiling(context, plan);
    if (tiling == null) return;
    final name = plan.info.name;
    // botRegions 的 @Load fallback 是 duct-bottom-#；bottom 半透明 0.5，top 完全不透明
    final bottom = _pickRegion(context, <String>[
      '$name-bottom-${tiling.index}',
      'duct-bottom-${tiling.index}',
    ]);
    if (bottom != null) {
      _drawTilingRegion(
        context,
        bottom,
        plan: plan,
        scaleX: tiling.scaleX,
        scaleY: tiling.scaleY,
        alpha: 0.5,
      );
    }
    _drawTilingRegion(
      context,
      '$name-top-${tiling.index}',
      plan: plan,
      scaleX: tiling.scaleX,
      scaleY: tiling.scaleY,
    );
  }
}

/// `StackConveyor`（plastanium-conveyor / surge-conveyor）= 官方 `StackConveyor.drawPlanRegion`
class _StackConveyorRule extends _AutotilerRule {
  @override
  Set<String> get blockClasses => const <String>{'StackConveyor'};

  @override
  bool blendsWith(PlanTile plan, PlanTile other) {
    // StackConveyor.blends 在 preview 里落到最后一项：只和 StackConveyor 连通
    return _outputsItems(other) &&
        _isClass(other, 'StackConveyor') &&
        (_planFaces(plan, other) ||
            (_rotatedOutput(other) && _otherFaces(plan, other)));
  }

  @override
  void drawBlock(PlanDrawContext context, PlanTile plan) {
    final tiling = this.tiling(context, plan);
    if (tiling == null) return;
    final name = plan.info.name;
    // regions[0]（不做缩放/翻转）
    context.drawRegion(
      '$name-0',
      centerX: plan.centerX,
      centerY: plan.centerY,
      angleDegrees: _screenAngle(plan.rotation),
    );
    // 四个方向里没有连通的边补 edgeRegion
    for (var i = 0; i < 4; i++) {
      if ((tiling.mask & (1 << i)) != 0) continue;
      context.drawRegion(
        '$name-edge',
        centerX: plan.centerX,
        centerY: plan.centerY,
        angleDegrees: _screenAngle(plan.rotation - i),
      );
    }
  }
}

/// `Conduit`（conduit / pulse-conduit / plated-conduit / reinforced-conduit）
/// = 官方 `Conduit.drawPlanRegion`
class _ConduitRule extends _AutotilerRule {
  /// Conduit.botColor = Color.valueOf("565656")
  static const int _botColor = 0xFF565656;

  /// v160.7 里只有 reinforced-conduit 覆写了 botColor = Pal.darkestMetal
  static const int _reinforcedBotColor = 0xFF38393F;

  @override
  Set<String> get blockClasses => const <String>{'Conduit'};

  @override
  bool blendsWith(PlanTile plan, PlanTile other) {
    if (_isClass(plan, 'ArmoredConduit')) {
      // ArmoredConduit.blends：lookingAt 项在 preview 里为 false
      final armored =
          _planFaces(plan, other) ||
          (_rotatedOutput(other) && _otherFaces(plan, other));
      return (other.info.outputsLiquid && armored) ||
          _isClass(other, 'LiquidJunction');
    }
    return other.info.hasLiquids &&
        other.info.outputsLiquid &&
        _lookingAtEither(plan, other);
  }

  @override
  void drawBlock(PlanDrawContext context, PlanTile plan) {
    final tiling = this.tiling(context, plan);
    if (tiling == null) return;
    final name = plan.info.name;
    // botRegions 的 @Load fallback 是 conduit-bottom-#，底下那层染成 botColor
    final bottom = _pickRegion(context, <String>[
      '$name-bottom-${tiling.index}',
      'conduit-bottom-${tiling.index}',
    ]);
    if (bottom != null) {
      _drawTilingRegion(
        context,
        bottom,
        plan: plan,
        scaleX: tiling.scaleX,
        scaleY: tiling.scaleY,
        tintColor: plan.info.name == 'reinforced-conduit'
            ? _reinforcedBotColor
            : _botColor,
      );
    }
    _drawTilingRegion(
      context,
      '$name-top-${tiling.index}',
      plan: plan,
      scaleX: tiling.scaleX,
      scaleY: tiling.scaleY,
    );
  }
}

/// 按官方 `Draw.rect` 的宽高缩放语义画 region
///
/// 官方用负 height 表示纵向翻转；Flutter 的 `Canvas.drawImageRect` 对负高度 dst 不绘制，
/// 这里改用「画布关于方块水平轴镜像」的等价变换
void _drawTilingRegion(
  PlanDrawContext context,
  String name, {
  required PlanTile plan,
  int scaleX = 1,
  int scaleY = 1,
  double alpha = 1,
  int? tintColor,
}) {
  final angle = _screenAngle(plan.rotation);
  if (scaleY >= 0 || context.collecting) {
    context.drawRegion(
      name,
      centerX: plan.centerX,
      centerY: plan.centerY,
      angleDegrees: angle,
      scaleX: scaleX.toDouble(),
      scaleY: scaleY.toDouble(),
      alpha: alpha,
      tintColor: tintColor,
    );
    return;
  }
  // M = T(c) R(a) S(1,-1) R(-a) T(-c)，再交给 drawRegion 的 T(c) R(a) 后等价于 T(c) R(a) S(1,-1)
  final canvas = context.canvas;
  final radians = angle * 3.141592653589793 / 180;
  canvas.save();
  canvas.translate(plan.centerX, plan.centerY);
  canvas.rotate(radians);
  canvas.scale(1, -1);
  canvas.rotate(-radians);
  canvas.translate(-plan.centerX, -plan.centerY);
  context.drawRegion(
    name,
    centerX: plan.centerX,
    centerY: plan.centerY,
    angleDegrees: angle,
    scaleX: scaleX.toDouble(),
    alpha: alpha,
    tintColor: tintColor,
  );
  canvas.restore();
}

/// 按顺序找第一个在资产包里存在的 region；都不存在返回 null
String? _pickRegion(PlanDrawContext context, List<String> candidates) {
  for (final name in candidates) {
    if (context.regionSize(name) != null) return name;
  }
  return null;
}

/// `classChain` 里是否出现过某个类（按 simpleName 匹配）
bool _isClass(PlanTile tile, String simpleName) =>
    tile.info.classChain.any((name) => name.endsWith('.$simpleName'));

/// 官方 `Block.outputsItems()`（`hasItems` 被不少子类覆写）
///
/// 见 v160.7 源码里覆写 `outputsItems()` 的类；`GenericCrafter` 返回 `outputItems != null`，
/// 本地资产包没有这个字段，先用 `hasItems` 近似（会出现送料连到只有液体输出的工厂，影响很小）
bool _outputsItems(PlanTile tile) {
  for (final name in _outputsItemsFalseClasses) {
    if (_isClass(tile, name)) return false;
  }
  for (final name in _outputsItemsTrueClasses) {
    if (_isClass(tile, name)) return true;
  }
  return tile.info.hasItems;
}

/// 官方覆写 `outputsItems()` 返回 false 的类
const List<String> _outputsItemsFalseClasses = <String>[
  'Turret',
  'StorageBlock',
  'PayloadLoader',
  'PowerGenerator',
  'SolidPump',
  'ForceProjector',
  'MendProjector',
  'OverdriveProjector',
  'RegenProjector',
  'LaunchPad',
  'Accelerator',
  'UnitFactory',
  'UnitCargoLoader',
];

/// 官方覆写 `outputsItems()` 返回 true 的类
const List<String> _outputsItemsTrueClasses = <String>[
  'Junction',
  'Sorter',
  'DuctJunction',
  'PayloadUnloader',
  'BeamDrill',
  'WallCrafter',
  'ItemSource',
  'LandingPad',
];

/// 官方 `Block.rotatedOutput(x, y, destination)`
///
/// preview 的 fake tile 没有 build / 地图未加载，各类覆写里只有 StackConveyor 会回落到
/// `super`（= rotate）；Turret / DuctRouter / OverflowDuct / GenericCrafter 等覆写类先按 rotate 近似
bool _rotatedOutput(PlanTile tile) => tile.info.rotate;

/// `Point2.equals(tile.x + d4(rotation).x, tile.y + d4(rotation).y, otherx, othery)`
bool _planFaces(PlanTile plan, PlanTile other) =>
    plan.x + _d4x[plan.rotation] == other.x &&
    plan.y + _d4y[plan.rotation] == other.y;

/// `Point2.equals(otherx + d4(otherrot).x, othery + d4(otherrot).y, tile.x, tile.y)`
bool _otherFaces(PlanTile plan, PlanTile other) =>
    other.x + _d4x[other.rotation] == plan.x &&
    other.y + _d4y[other.rotation] == plan.y;

/// 官方 `Autotiler.lookingAtEither`（preview 里 `Edges.getFacingEdge` 恒为 null，中间项恒真）
bool _lookingAtEither(PlanTile plan, PlanTile other) =>
    _planFaces(plan, other) ||
    !_rotatedOutput(other) ||
    _otherFaces(plan, other);
