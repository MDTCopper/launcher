import 'dart:convert';
import 'dart:io';

import '../plan_draw_rule.dart';

/// drawer 组合绘制规则（官方 `drawPlanRegion` → `DrawBlock.drawPlan`）
///
/// 官方有一套「把方块本体拆给 drawer 组合体」的实现：`Block.drawPlanRegion` 直接调
/// `block.drawer.drawPlan(block, plan, eachable)`。全 jar 扫描后声明类只有这几类走这条链：
/// `GenericCrafter` / `Battery` / `Separator` / `PowerGenerator` / `Turret` / `HeatConductor` /
/// `RegenProjector`
///
/// 具体外观由每个方块的 drawer 树决定（`DrawMulti` 组合 `DrawRegion` / `DrawPower` /
/// `DrawHeatOutput` / `DrawTurret` 等）。树由 `DrawerDump.java` 反射导出到资产包的
/// `drawer-spec.json`，这里按官方 `drawPlan` 语义递归复刻
///
/// 依据：
/// - `javap -c` 的 `mindustry.world.draw.Draw*` 各 `drawPlan` 方法
/// - `DrawRegion.load` 的 region 命名（`name` 非空用 `name`，否则 `block.name + suffix`）
/// - `DrawTurret.load` 的 base/preview/top 回退链（`-base` → `block-<size>`，`-preview` → 方块本体 region）
final List<PlanDrawRule> drawerCompositionRules = <PlanDrawRule>[
  DrawerCompositionPlanRule(),
];

class DrawerCompositionPlanRule extends PlanDrawRule {
  /// 官方把 `drawPlanRegion` 委托给 drawer 的声明类（由全 jar 类扫描确认）
  static const Set<String> _declaringClasses = <String>{
    'Battery',
    'GenericCrafter',
    'HeatConductor',
    'PowerGenerator',
    'RegenProjector',
    'Separator',
    'Turret',
  };

  /// 官方 `drawPlan` 有实现的 drawer 类型；其余类型（DrawFlame、DrawLiquidTile 等）不画
  static const Set<String> _planDrawers = <String>{
    'DrawDefault',
    'DrawMulti',
    'DrawRegion',
    'DrawSideRegion',
    'DrawPistons',
    'DrawTurret',
    'DrawPower',
    'DrawBlockParts',
    'DrawLiquidOutputs',
    'DrawHeatOutput',
  };

  /// 资产包目录 → （方块名 → drawer 数据）；null 表示该版本没有导出文件
  static final Map<String, Map<String, _DrawerBlockSpec>?> _specCache = {};

  @override
  Set<String> get blockClasses => _declaringClasses;

  @override
  void drawBlock(PlanDrawContext context, PlanTile plan) {
    final spec = _specFor(context);
    final blockSpec = spec?[plan.info.name];
    final drawer = blockSpec?.drawer;
    if (blockSpec == null || drawer == null) {
      // 资产包未导出该方块时退回默认图标，避免整块消失
      context.drawBlockIcon(plan, angleDegrees: _defaultAngle(plan));
      return;
    }
    _drawNode(context, plan, blockSpec, drawer);
  }

  static Map<String, _DrawerBlockSpec>? _specFor(PlanDrawContext context) {
    final packDir = context.assets.packDirPath;
    if (_specCache.containsKey(packDir)) return _specCache[packDir];
    final file = File('$packDir/drawer-spec.json');
    if (!file.existsSync()) {
      _specCache[packDir] = null;
      return null;
    }
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final result = <String, _DrawerBlockSpec>{};
      for (final entry in json['blocks'] as List<dynamic>) {
        final map = entry as Map<String, dynamic>;
        result[map['name'] as String] = _DrawerBlockSpec(
          drawer: map['drawer'] as Map<String, dynamic>?,
          outputLiquids: (map['outputLiquids'] as List<dynamic>?)
              ?.map((value) => value as String)
              .toList(),
          liquidOutputDirections:
              (map['liquidOutputDirections'] as List<dynamic>?)
                  ?.map((value) => (value as num).toInt())
                  .toList(),
        );
      }
      _specCache[packDir] = result;
      return result;
    } catch (_) {
      _specCache[packDir] = null;
      return null;
    }
  }

  void _drawNode(
    PlanDrawContext context,
    PlanTile plan,
    _DrawerBlockSpec blockSpec,
    Map<String, dynamic> node,
  ) {
    switch (_effectiveType(node)) {
      case 'DrawDefault':
        context.drawBlockIcon(plan, angleDegrees: _defaultAngle(plan));
      case 'DrawMulti':
        for (final child in _children(node)) {
          _drawNode(context, plan, blockSpec, child);
        }
      case 'DrawRegion':
        _drawRegion(context, plan, node);
      case 'DrawSideRegion':
        _drawSideRegion(context, plan);
      case 'DrawHeatOutput':
        _drawHeatOutput(context, plan, node);
      case 'DrawPistons':
        _drawPistons(context, plan, node);
      case 'DrawPower':
        _drawPower(context, plan, node);
      case 'DrawBlockParts':
        _drawBlockParts(context, plan);
      case 'DrawLiquidOutputs':
        _drawLiquidOutputs(context, plan, blockSpec);
      case 'DrawTurret':
        _drawTurret(context, plan, node);
    }
  }

  /// `DrawMulti` / `DrawMultiWeave` 的子 drawer 列表字段
  Iterable<Map<String, dynamic>> _children(Map<String, dynamic> node) sync* {
    final drawers = node['drawers'];
    if (drawers is! List<dynamic>) return;
    for (final child in drawers) {
      if (child is Map<String, dynamic>) yield child;
    }
  }

  /// 匿名子类（如 `new DrawPower(){...}`）的 `class` 为空或不可识别，按继承链取第一个已知实现
  String _effectiveType(Map<String, dynamic> node) {
    final chain = node['chain'];
    if (chain is List<dynamic>) {
      for (final name in chain) {
        if (name is String && _planDrawers.contains(name)) return name;
      }
    }
    return node['class'] as String? ?? '';
  }

  /// `DrawDefault` = 官方 `Block.drawDefaultPlanRegion`：默认图标，仅 rotate+rotateDraw 的方块转
  double _defaultAngle(PlanTile plan) =>
      plan.info.rotate && plan.info.rotateDraw ? -plan.rotation * 90.0 : 0.0;

  /// `DrawRegion.drawPlan`：`drawPlan` 为假不画；偏移用世界单位，角度 =
  /// buildingRotate ? plan.rotation*90 : rotation（屏幕角度取负）
  void _drawRegion(
    PlanDrawContext context,
    PlanTile plan,
    Map<String, dynamic> node,
  ) {
    if (node['drawPlan'] == false) return;
    final customName = node['name'] as String?;
    final name = customName != null && customName.isNotEmpty
        ? customName
        : '${plan.info.name}${node['suffix'] as String? ?? ''}';
    final angle = node['buildingRotate'] == true
        ? -plan.rotation * 90.0
        : -_number(node['rotation']);
    context.drawRegion(
      name,
      centerX: plan.centerX,
      centerY: plan.centerY,
      dx: _number(node['x']),
      dy: -_number(node['y']),
      angleDegrees: angle,
    );
  }

  /// `DrawSideRegion.drawPlan`：rotation > 1 用 top2，否则 top1
  void _drawSideRegion(PlanDrawContext context, PlanTile plan) {
    final rotation = plan.rotation;
    context.drawRegion(
      rotation > 1 ? '${plan.info.name}-top2' : '${plan.info.name}-top1',
      centerX: plan.centerX,
      centerY: plan.centerY,
      angleDegrees: -rotation * 90.0,
    );
  }

  /// `DrawHeatOutput.drawPlan`：按 (rotation + rotOffset) 选 top1/top2
  void _drawHeatOutput(
    PlanDrawContext context,
    PlanTile plan,
    Map<String, dynamic> node,
  ) {
    final offset = _integer(node['rotOffset']);
    final rotation = plan.rotation + offset;
    final index = _mod(rotation, 4);
    context.drawRegion(
      index > 1 ? '${plan.info.name}-top2' : '${plan.info.name}-top1',
      centerX: plan.centerX,
      centerY: plan.centerY,
      angleDegrees: -rotation * 90.0,
    );
  }

  /// `DrawPistons.drawPlan`：只画预合成的 iconRegion（`<name><suffix>-icon`）
  void _drawPistons(
    PlanDrawContext context,
    PlanTile plan,
    Map<String, dynamic> node,
  ) {
    final name = '${plan.info.name}${node['suffix'] as String? ?? ''}-icon';
    if (context.regionSize(name) == null) return;
    context.drawRegion(name, centerX: plan.centerX, centerY: plan.centerY);
  }

  /// `DrawPower.drawPlan`：只有 drawPlan 且非 mixcol 才画空电池区（`<name><suffix>`，回退 `-empty`）
  void _drawPower(
    PlanDrawContext context,
    PlanTile plan,
    Map<String, dynamic> node,
  ) {
    if (node['drawPlan'] == false || node['mixcol'] == true) return;
    final suffix = node['suffix'] as String? ?? '';
    final name = _firstExisting(context, <String>[
      '${plan.info.name}$suffix',
      '${plan.info.name}$suffix-empty',
    ]);
    if (name == null) return;
    context.drawRegion(name, centerX: plan.centerX, centerY: plan.centerY);
  }

  /// `DrawBlockParts.drawPlan`：只画 preview（`<name>-preview`）
  void _drawBlockParts(PlanDrawContext context, PlanTile plan) {
    final name = '${plan.info.name}-preview';
    if (context.regionSize(name) == null) return;
    context.drawRegion(
      name,
      centerX: plan.centerX,
      centerY: plan.centerY,
      angleDegrees: plan.info.rotate ? -plan.rotation * 90.0 : 0.0,
    );
  }

  /// `DrawLiquidOutputs.drawPlan`：按输出液体与方向画 `<name>-<liquid>-output<1|2>`
  void _drawLiquidOutputs(
    PlanDrawContext context,
    PlanTile plan,
    _DrawerBlockSpec blockSpec,
  ) {
    final liquids = blockSpec.outputLiquids;
    if (liquids == null || liquids.isEmpty) return;
    final directions = blockSpec.liquidOutputDirections ?? const <int>[];
    for (var index = 0; index < liquids.length; index++) {
      final direction = index < directions.length ? directions[index] : -1;
      if (direction == -1) continue;
      final rotation = _mod(direction + plan.rotation, 4);
      final name =
          '${plan.info.name}-${liquids[index]}-output${rotation > 1 ? 2 : 1}';
      context.drawRegion(
        name,
        centerX: plan.centerX,
        centerY: plan.centerY,
        angleDegrees: -rotation * 90.0,
      );
    }
  }

  /// `DrawTurret.drawPlan`：base（不旋转）→ preview（`-preview`，缺省回退方块本体）→ top
  ///
  /// 官方角度是 `rotation*90 - 90`，y 翻到屏幕后取反
  void _drawTurret(
    PlanDrawContext context,
    PlanTile plan,
    Map<String, dynamic> node,
  ) {
    final basePrefix = node['basePrefix'] as String? ?? '';
    final name = plan.info.name;
    final base = _firstExisting(context, <String>[
      '$name$basePrefix-base',
      '$name-base',
    ]);
    if (base != null) {
      context.drawRegion(base, centerX: plan.centerX, centerY: plan.centerY);
    }
    final preview = _firstExisting(context, <String>['$name-preview', name]);
    final angle = plan.info.rotate ? 90.0 - plan.rotation * 90.0 : 0.0;
    if (preview != null) {
      context.drawRegion(
        preview,
        centerX: plan.centerX,
        centerY: plan.centerY,
        angleDegrees: angle,
      );
    }
    final top = '$name-top';
    if (context.regionSize(top) != null) {
      context.drawRegion(
        top,
        centerX: plan.centerX,
        centerY: plan.centerY,
        angleDegrees: angle,
      );
    }
  }

  String? _firstExisting(PlanDrawContext context, List<String> names) {
    for (final name in names) {
      if (context.regionSize(name) != null) return name;
    }
    return null;
  }

  static double _number(Object? value) => value is num ? value.toDouble() : 0.0;

  static int _integer(Object? value) => value is num ? value.toInt() : 0;

  /// 官方 `Mathf.mod`：结果始终非负
  static int _mod(int value, int modulus) {
    final result = value % modulus;
    return result < 0 ? result + modulus : result;
  }
}

/// 一个方块的 drawer 组合数据（`drawer-spec.json` 的一条记录）
class _DrawerBlockSpec {
  const _DrawerBlockSpec({
    required this.drawer,
    required this.outputLiquids,
    required this.liquidOutputDirections,
  });

  final Map<String, dynamic>? drawer;

  /// `DrawLiquidOutputs` 用到的输出液体名
  final List<String>? outputLiquids;

  /// 每种输出液体的方向（-1 表示不画）
  final List<int>? liquidOutputDirections;
}
