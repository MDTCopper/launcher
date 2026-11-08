import 'dart:ui' as ui;

import '../plan_draw_rule.dart';

/// CanvasBlock 的像素画绘制
///
/// config 是 3/4 bit 调色板索引的字节数组；官方预览把它还原成像素网格
/// 颜色与网格参数由 `canvas.json` 提供
class CanvasPlanRule extends PlanDrawRule {
  @override
  Set<String> get blockClasses => const {'CanvasBlock'};

  @override
  void drawBlock(PlanDrawContext context, PlanTile plan) {
    final config = plan.tile.config;
    final canvas = context.assets.canvas(plan.info.name);
    if (config == null || config.kind.name != 'byteArray' || canvas == null) {
      context.drawBlockIcon(plan);
      return;
    }
    final bytes = config.value as List<int>;
    final pixels = canvas.canvasSize * canvas.canvasSize;
    final palette = canvas.palette;
    final side = plan.size * 32.0;
    final pixelSize = side / canvas.canvasSize;
    final left = plan.centerX - side / 2;
    final top = plan.centerY - side / 2;
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
    for (var index = 0; index < pixels; index++) {
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
      paint.color = ui.Color(color);
      final x = index % canvas.canvasSize;
      final y = index ~/ canvas.canvasSize;
      context.canvas.drawRect(
        ui.Rect.fromLTWH(
          left + x * pixelSize,
          top + y * pixelSize,
          pixelSize,
          pixelSize,
        ),
        paint,
      );
    }
  }
}
