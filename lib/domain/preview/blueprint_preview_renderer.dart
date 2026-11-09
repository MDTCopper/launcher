import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../util/io/mindustry_save_file/schematic_file.dart';
import 'blueprint_asset_pack.dart';
import 'draw_rules/rules.dart';
import 'plan_draw_rule.dart';

/// 蓝图预览渲染结果
class BlueprintPreviewResult {
  const BlueprintPreviewResult({
    required this.image,
    required this.hasUnknownContent,
    required this.unknownBlocks,
  });

  final ui.Image image;

  /// 含内容表里没有的方块（mod / 旧版本方块），列表应标注「含 mod 内容」
  final bool hasUnknownContent;

  final Set<String> unknownBlocks;
}

/// CPU 自绘蓝图预览
///
/// 布局来自官方 `Schematics.getBuffer`：画布 `(w+2)*32 × (h+2)*32`，四周 1 格边距
/// 两批绘制：`drawPlanRegion`（方块本体，按声明类分派规则）→ `drawPlanConfigTop`（连线等）
class BlueprintPreviewRenderer {
  BlueprintPreviewRenderer(this.assets);

  final BlueprintAssetPack assets;

  static const double tileSize = 32;
  static const double margin = 1;

  final List<PlanDrawRule> _rules = buildPlanDrawRules();
  final PlanDrawRule _fallbackRule = FallbackPlanDrawRule();

  Future<BlueprintPreviewResult> render(SchematicFile schematic) async {
    final unknownBlocks = <String>{};
    final placed = <PlanTile>[];
    for (final tile in schematic.tiles) {
      final info = assets.block(tile.blockName);
      if (info == null) {
        unknownBlocks.add(tile.blockName);
        continue;
      }
      final size = info.size;
      // 官方 drawx = x*8 + offset，偶数尺寸 offset 4；换算到像素与尺寸无关
      final centerX = (tile.x + margin + (size.isOdd ? 0.5 : 1.0)) * tileSize;
      final centerY =
          (schematic.height - tile.y + (size.isOdd ? 0.5 : 0.0)) * tileSize;
      placed.add(
        PlanTile(tile: tile, info: info, centerX: centerX, centerY: centerY),
      );
    }

    final missingRegions = <String>{};
    final imageRequests = <String, PendingPixelImage>{};
    _collectRegions(schematic, placed, missingRegions, imageRequests);
    if (missingRegions.isNotEmpty) {
      await assets.ensureRegions(missingRegions);
    }
    final decodedImages = <String, ui.Image>{};
    for (final entry in imageRequests.entries) {
      final pending = entry.value;
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pending.rgba,
        pending.width,
        pending.height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      decodedImages[entry.key] = await completer.future;
    }

    final width = ((schematic.width + margin * 2) * tileSize).round();
    final height = ((schematic.height + margin * 2) * tileSize).round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final context = PlanDrawContext(
      canvas: canvas,
      schematic: schematic,
      assets: assets,
      placed: placed,
      collecting: false,
      missingRegions: {},
      decodedImages: decodedImages,
    );
    _drawShadow(
      canvas,
      schematic,
      width,
      height,
      await _createShadow(schematic),
    );
    for (final plan in placed) {
      _blockRule(plan.info).drawBlock(context, plan);
      _configRule(plan.info)?.drawConfig(context, plan);
    }
    for (final plan in placed) {
      _configTopRule(plan.info)?.drawConfigTop(context, plan);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    return BlueprintPreviewResult(
      image: image,
      hasUnknownContent: unknownBlocks.isNotEmpty,
      unknownBlocks: unknownBlocks,
    );
  }

  void _collectRegions(
    SchematicFile schematic,
    List<PlanTile> placed,
    Set<String> missingRegions,
    Map<String, PendingPixelImage> imageRequests,
  ) {
    final context = PlanDrawContext(
      canvas: ui.Canvas(ui.PictureRecorder()),
      schematic: schematic,
      assets: assets,
      placed: placed,
      collecting: true,
      missingRegions: missingRegions,
      imageRequests: imageRequests,
    );
    for (final plan in placed) {
      _blockRule(plan.info).drawBlock(context, plan);
      _configRule(plan.info)?.drawConfig(context, plan);
    }
    for (final plan in placed) {
      _configTopRule(plan.info)?.drawConfigTop(context, plan);
    }
  }

  PlanDrawRule _blockRule(BlueprintBlockInfo info) {
    final declaringClass = info.regionRuleClass;
    for (final rule in _rules) {
      if (rule.blockClasses.contains(declaringClass)) return rule;
      if (rule.blockClasses.contains(_simpleName(declaringClass))) return rule;
    }
    return _fallbackRule;
  }

  PlanDrawRule? _configRule(BlueprintBlockInfo info) {
    final declaringClass = info.configRuleClass;
    for (final rule in _rules) {
      if (rule.configClasses.contains(declaringClass)) return rule;
      if (rule.configClasses.contains(_simpleName(declaringClass))) return rule;
    }
    return null;
  }

  PlanDrawRule? _configTopRule(BlueprintBlockInfo info) {
    final declaringClass = info.configTopRuleClass;
    for (final rule in _rules) {
      if (rule.configTopClasses.contains(declaringClass)) return rule;
      if (rule.configTopClasses.contains(_simpleName(declaringClass))) {
        return rule;
      }
    }
    return null;
  }

  static String _simpleName(String className) => className.split('.').last;

  /// 官方阴影：每个占用格在 (w+2)×(h+2) 的缓冲里画 1 像素，再整幅线性拉伸
  Future<ui.Image> _createShadow(SchematicFile schematic) async {
    final shadowRecorder = ui.PictureRecorder();
    final shadowCanvas = ui.Canvas(shadowRecorder);
    final paint = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    for (final tile in schematic.tiles) {
      final info = assets.block(tile.blockName);
      if (info == null) continue;
      final size = info.size;
      // 与官方阴影一致：从 x - (size-1)/2 起铺 size 格
      final offset = (size - 1) ~/ 2;
      final minX = tile.x - offset;
      final maxX = minX + size - 1;
      final minY = tile.y - offset;
      final maxY = minY + size - 1;
      for (var cellX = minX; cellX <= maxX; cellX++) {
        for (var cellY = minY; cellY <= maxY; cellY++) {
          shadowCanvas.drawRect(
            ui.Rect.fromLTWH(
              (cellX + margin).toDouble(),
              (schematic.height - cellY).toDouble() * 1,
              1,
              1,
            ),
            paint,
          );
        }
      }
    }
    return shadowRecorder.endRecording().toImage(
      (schematic.width + margin * 2).round(),
      (schematic.height + margin * 2).round(),
    );
  }

  void _drawShadow(
    ui.Canvas canvas,
    SchematicFile schematic,
    int width,
    int height,
    ui.Image shadow,
  ) {
    canvas.drawImageRect(
      shadow,
      ui.Rect.fromLTWH(0, 0, shadow.width.toDouble(), shadow.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()
        ..colorFilter = const ui.ColorFilter.mode(
          ui.Color(0xB3000000),
          ui.BlendMode.srcIn,
        )
        ..filterQuality = ui.FilterQuality.low,
    );
    shadow.dispose();
  }
}

/// 没有官方 drawPlanRegion 覆写的方块：默认按 fullIcon 画并处理旋转
class FallbackPlanDrawRule extends PlanDrawRule {
  @override
  Set<String> get blockClasses => const {};

  @override
  void drawBlock(PlanDrawContext context, PlanTile plan) {
    final angle = plan.info.rotate && plan.info.rotateDraw
        ? -plan.rotation * 90.0
        : 0.0;
    context.drawBlockIcon(plan, angleDegrees: angle);
  }
}

Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<Uint8List> encodePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// 官方 rotation 值转屏幕角度
double rotationToScreenDegrees(int rotation) => -rotation * 90.0;
