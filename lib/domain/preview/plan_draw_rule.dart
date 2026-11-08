import 'dart:ui' as ui;

import '../../util/io/mindustry_save_file/schematic_file.dart';
import 'blueprint_asset_pack.dart';

/// 预览绘制过程中一个已定位的方块
class PlanTile {
  PlanTile({
    required this.tile,
    required this.info,
    required this.centerX,
    required this.centerY,
  });

  final SchematicTile tile;
  final BlueprintBlockInfo info;

  /// 屏幕像素坐标下该方块的中心点
  final double centerX;
  final double centerY;

  int get x => tile.x;
  int get y => tile.y;
  int get rotation => tile.rotation;
  int get size => info.size;

  bool get isOddSize => size.isOdd;

  /// 占用格范围（含端点，Mindustry 世界坐标，y 向上）
  ///
  /// 官方阴影按 `x - (size-1)/2` 起点铺 size 格，奇偶同一公式
  int get minX => x - (size - 1) ~/ 2;
  int get maxX => minX + size - 1;
  int get minY => y - (size - 1) ~/ 2;
  int get maxY => minY + size - 1;
}

/// 绘制规则拿到的上下文
///
/// 坐标约定：方块中心是像素坐标，y 轴向下；[drawRegion] 里的偏移用世界单位，1 单位 = 4px
class PlanDrawContext {
  PlanDrawContext({
    required this.canvas,
    required this.schematic,
    required this.assets,
    required this.placed,
    required this.collecting,
    required this.missingRegions,
  }) : _originIndex = {
         for (final plan in placed) _cellKey(plan.x, plan.y): plan,
       };

  final ui.Canvas canvas;
  final SchematicFile schematic;
  final BlueprintAssetPack assets;
  final List<PlanTile> placed;

  /// 收集阶段只登记需要的 region，不真正绘制
  final bool collecting;

  /// 收集阶段登记到的 region 名
  final Set<String> missingRegions;

  final Map<int, PlanTile> _originIndex;

  static int _cellKey(int x, int y) => (x << 8) | y;

  /// 原点在 (x,y) 的方块；多格方块只登记原点
  PlanTile? planAt(int x, int y) => _originIndex[_cellKey(x, y)];

  /// 覆盖 (x,y) 格的方块（多格方块按占用范围查）
  PlanTile? planCovering(int x, int y) {
    for (final plan in placed) {
      if (x >= plan.minX &&
          x <= plan.maxX &&
          y >= plan.minY &&
          y <= plan.maxY) {
        return plan;
      }
    }
    return null;
  }

  /// 与 (x,y) 距离 [radius] 格以内的方块（含原点坐标）
  Iterable<PlanTile> plansNear(int x, int y, int radius) sync* {
    for (final plan in placed) {
      if ((plan.x - x).abs() <= radius && (plan.y - y).abs() <= radius) {
        yield plan;
      }
    }
  }

  /// 世界单位转屏幕像素
  static double worldToPixel(double worldUnits) => worldUnits * 4;

  /// region 的原始像素尺寸；未导出时返回 null
  ui.Size? regionSize(String name) => assets.regionSize(name);

  /// 画一个按原始像素尺寸居中的 region
  ///
  /// [dx] / [dy] 为世界单位偏移，[scaleX]/[scaleY] 为额外缩放，[angleDegrees] 为屏幕角度
  void drawRegion(
    String name, {
    required double centerX,
    required double centerY,
    double dx = 0,
    double dy = 0,
    double angleDegrees = 0,
    double scaleX = 1,
    double scaleY = 1,
    double alpha = 1,
    int? tintColor,
  }) {
    if (collecting) {
      missingRegions.add(name);
      return;
    }
    final image = assets.decodedRegion(name);
    if (image == null) {
      missingRegions.add(name);
      return;
    }
    final width = image.width * scaleX.abs();
    final height = image.height * scaleY.abs();
    canvas.save();
    canvas.translate(centerX + worldToPixel(dx), centerY + worldToPixel(dy));
    if (angleDegrees != 0) {
      canvas.rotate(angleDegrees * 3.141592653589793 / 180);
    }
    // Flutter 的 drawImageRect 不接受负 dst 尺寸，负缩放用画布镜像实现
    if (scaleX < 0 || scaleY < 0) {
      canvas.scale(scaleX < 0 ? -1 : 1, scaleY < 0 ? -1 : 1);
    }
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
    if (alpha != 1) paint.color = ui.Color.fromRGBO(255, 255, 255, alpha);
    if (tintColor != null) {
      paint.colorFilter = ui.ColorFilter.mode(
        ui.Color(tintColor),
        ui.BlendMode.modulate,
      );
    }
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(-width / 2, -height / 2, width, height),
      paint,
    );
    canvas.restore();
  }

  /// 方块默认图标；多格方块按 size*32 铺满
  void drawBlockIcon(
    PlanTile plan, {
    double angleDegrees = 0,
    double alpha = 1,
    bool useRotation = true,
  }) {
    final icon = assets.decodedBlockIcon(plan.info.name);
    final side = plan.size * 32.0;
    if (collecting) {
      if (icon == null) missingRegions.add('block-icon:${plan.info.name}');
      return;
    }
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
    if (alpha != 1) paint.color = ui.Color.fromRGBO(255, 255, 255, alpha);
    canvas.save();
    canvas.translate(plan.centerX, plan.centerY);
    if (angleDegrees != 0) {
      canvas.rotate(angleDegrees * 3.141592653589793 / 180);
    }
    if (icon != null) {
      canvas.drawImageRect(
        icon,
        ui.Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
        ui.Rect.fromLTWH(-side / 2, -side / 2, side, side),
        paint,
      );
    } else {
      canvas.drawRect(
        ui.Rect.fromLTWH(-side / 2, -side / 2, side, side),
        ui.Paint()..color = ui.Color(plan.info.mapColor ?? 0xFF888888),
      );
    }
    canvas.restore();
  }
}

/// 一个方块的预览绘制规则
///
/// 分派依据是官方 `drawPlanRegion` / `drawPlanConfigTop` 的声明类；没匹配到就走默认规则
abstract class PlanDrawRule {
  /// 本规则负责的 `drawPlanRegion` 声明类（包名简写或全名，如 `Conveyor`）
  Set<String> get blockClasses => const {};

  /// 本规则负责的 `drawPlanConfigTop` 声明类（如 `ItemBridge`）
  Set<String> get configTopClasses => const {};

  /// 第一批：方块本体
  void drawBlock(PlanDrawContext context, PlanTile plan) {
    context.drawBlockIcon(plan);
  }

  /// 第二批：官方 `drawPlanConfigTop`，连线等画在所有方块之上
  void drawConfigTop(PlanDrawContext context, PlanTile plan) {}
}
