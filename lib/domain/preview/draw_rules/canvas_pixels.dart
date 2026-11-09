import 'dart:typed_data';
import 'dart:ui' as ui;

import '../blueprint_asset_pack.dart';
import '../plan_draw_rule.dart';

/// CanvasBlock 的像素画绘制
///
/// 官方 `drawPlanRegion`：调色板像素图按块大小缩放（邻接画布时铺满整格，
/// 孤立时按 `size*8-padding` 收缩），再对没有相邻画布的边画 side/corner 边角图
class CanvasPlanRule extends PlanDrawRule {
  @override
  Set<String> get blockClasses => const {'CanvasBlock'};

  static const _directions = [
    [1, 0],
    [0, 1],
    [-1, 0],
    [0, -1],
  ];

  @override
  void drawBlock(PlanDrawContext context, PlanTile plan) {
    final config = plan.tile.config;
    final canvas = context.assets.canvas(plan.info.name);
    if (config == null || config.kind.name != 'byteArray' || canvas == null) {
      context.drawBlockIcon(plan);
      return;
    }
    final bytes = config.value as List<int>;
    final blend = _blendMask(context, plan);
    final key = 'canvas:${plan.info.name}:${plan.x}:${plan.y}';
    final image = context.requestPixelImage(
      key,
      _buildPixels(canvas, bytes),
      canvas.canvasSize,
      canvas.canvasSize,
    );
    final side = blend == 0
        ? (plan.size * 8 - canvas.padding) * 4
        : plan.size * 32.0;
    if (image == null) {
      context.missingRegions.add('pending:$key');
    } else {
      context.canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(
          plan.centerX - side / 2,
          plan.centerY - side / 2,
          side,
          side,
        ),
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );
    }
    _drawEdges(context, plan, blend);
  }

  /// 相邻同种画布方块的 4 向 mask，对应官方 `tempBlend`
  int _blendMask(PlanDrawContext context, PlanTile plan) {
    var mask = 0;
    for (var i = 0; i < 4; i++) {
      final x = plan.x + _directions[i][0] * plan.size;
      final y = plan.y + _directions[i][1] * plan.size;
      for (final other in context.placed) {
        if (other.x == x && other.y == y && other.info.name == plan.info.name) {
          mask |= 1 << i;
          break;
        }
      }
    }
    return mask;
  }

  /// 官方边角拼接：没有相邻画布的边画 side，相邻边交汇处画 corner
  void _drawEdges(PlanDrawContext context, PlanTile plan, int blend) {
    final name = plan.info.name;
    for (var i = 0; i < 4; i++) {
      if (blend & (1 << i) != 0) continue;
      final angle = -i * 90.0;
      context.drawRegion(
        i < 2 ? '$name-side1' : '$name-side2',
        centerX: plan.centerX,
        centerY: plan.centerY,
        angleDegrees: angle,
      );
      final previous = (i + 3) % 4;
      final next = (i + 1) % 4;
      if (blend & (1 << next) != 0) {
        context.drawRegion(
          i < 2 ? '$name-corner1' : '$name-corner2',
          centerX: plan.centerX,
          centerY: plan.centerY,
          angleDegrees: angle,
        );
      }
      if (blend & (1 << previous) != 0) {
        context.drawRegion(
          i < 2 ? '$name-corner1' : '$name-corner2',
          centerX: plan.centerX,
          centerY: plan.centerY,
          angleDegrees: angle,
          scaleY: -1,
        );
      }
    }
  }

  Uint8List _buildPixels(BlueprintCanvasInfo canvas, List<int> bytes) {
    final size = canvas.canvasSize;
    final palette = canvas.palette;
    final rgba = Uint8List(size * size * 4);
    for (var index = 0; index < size * size; index++) {
      var value = 0;
      for (var bit = 0; bit < canvas.bitsPerPixel; bit++) {
        final absolute = index * canvas.bitsPerPixel + bit;
        final byteIndex = absolute >> 3;
        if (byteIndex >= bytes.length) continue;
        if (bytes[byteIndex] & (1 << (absolute & 7)) != 0) {
          value |= 1 << bit;
        }
      }
      final color =
          palette[value < palette.length ? value : palette.length - 1];
      final offset = index * 4;
      // 官方 Pixmap 用 RGBA8888 打包（R 在高字节）
      rgba[offset] = (color >> 24) & 0xFF;
      rgba[offset + 1] = (color >> 16) & 0xFF;
      rgba[offset + 2] = (color >> 8) & 0xFF;
      rgba[offset + 3] = color & 0xFF;
    }
    return rgba;
  }
}
