import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../util/io/mindustry_save_file/schematic_file.dart';
import 'blueprint_asset_pack.dart';

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
/// 顺序：阴影（1px/格剪影拉伸）→ 方块图标（按 tile 顺序）→ 配置图标
class BlueprintPreviewRenderer {
  BlueprintPreviewRenderer(this.assets);

  final BlueprintAssetPack assets;

  static const double tileSize = 32;
  static const double margin = 1;

  final Map<String, ui.Image?> _blockIconCache = {};
  final Map<String, ui.Image?> _genericIconCache = {};

  Future<BlueprintPreviewResult> render(SchematicFile schematic) async {
    final unknownBlocks = <String>{};
    final placed = <_PlacedBlock>[];
    for (final tile in schematic.tiles) {
      final info = assets.block(tile.blockName);
      if (info == null) {
        unknownBlocks.add(tile.blockName);
        continue;
      }
      final blockIcon = await _blockIcon(tile.blockName);
      final configMark = await _configMark(info, tile.config);
      placed.add(
        _PlacedBlock(
          tile: tile,
          info: info,
          blockIcon: blockIcon,
          configMark: configMark,
        ),
      );
    }

    final width = ((schematic.width + margin * 2) * tileSize).round();
    final height = ((schematic.height + margin * 2) * tileSize).round();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    await _drawShadow(canvas, schematic, placed, width, height);
    _drawBlocks(canvas, schematic, placed);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    return BlueprintPreviewResult(
      image: image,
      hasUnknownContent: unknownBlocks.isNotEmpty,
      unknownBlocks: unknownBlocks,
    );
  }

  /// 官方阴影：每个占用格在 (w+2)×(h+2) 的缓冲里画 1 像素，再整幅线性拉伸
  Future<void> _drawShadow(
    ui.Canvas canvas,
    SchematicFile schematic,
    List<_PlacedBlock> placed,
    int width,
    int height,
  ) async {
    final shadowRecorder = ui.PictureRecorder();
    final shadowCanvas = ui.Canvas(shadowRecorder);
    final paint = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    for (final block in placed) {
      final size = block.info.size;
      final topRow = schematic.height - block.tile.y - size + 1;
      for (var i = 0; i < size; i++) {
        for (var j = 0; j < size; j++) {
          shadowCanvas.drawRect(
            ui.Rect.fromLTWH(
              (block.tile.x + margin + i).toDouble(),
              (topRow + j).toDouble(),
              1,
              1,
            ),
            paint,
          );
        }
      }
    }
    final shadow = await shadowRecorder.endRecording().toImage(
      (schematic.width + margin * 2).round(),
      (schematic.height + margin * 2).round(),
    );
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

  void _drawBlocks(
    ui.Canvas canvas,
    SchematicFile schematic,
    List<_PlacedBlock> placed,
  ) {
    for (final block in placed) {
      final size = block.info.size;
      final centerX = (block.tile.x + margin + size / 2.0) * tileSize;
      final centerY =
          (schematic.height - block.tile.y - size + margin + size / 2.0) *
          tileSize;
      final side = size * tileSize;
      final rotate = block.info.rotate && block.info.rotateDraw
          ? -block.tile.rotation * math.pi / 2
          : 0.0;

      canvas.save();
      canvas.translate(centerX, centerY);
      canvas.rotate(rotate);
      final blockIcon = block.blockIcon;
      if (blockIcon != null) {
        canvas.drawImageRect(
          blockIcon,
          ui.Rect.fromLTWH(
            0,
            0,
            blockIcon.width.toDouble(),
            blockIcon.height.toDouble(),
          ),
          ui.Rect.fromLTWH(-side / 2, -side / 2, side, side),
          ui.Paint()..filterQuality = ui.FilterQuality.none,
        );
      } else {
        final color = block.info.mapColor ?? 0xFF888888;
        canvas.drawRect(
          ui.Rect.fromLTWH(-side / 2, -side / 2, side, side),
          ui.Paint()..color = ui.Color(color),
        );
      }
      final configMark = block.configMark;
      if (configMark != null) {
        final mark = configMark.image;
        final markSide = math.min(mark.width, mark.height).toDouble();
        final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
        final color = configMark.color;
        if (color != null) {
          paint.colorFilter = ui.ColorFilter.mode(
            ui.Color(color),
            ui.BlendMode.modulate,
          );
        }
        canvas.drawImageRect(
          mark,
          ui.Rect.fromLTWH(0, 0, mark.width.toDouble(), mark.height.toDouble()),
          ui.Rect.fromLTWH(-markSide / 2, -markSide / 2, markSide, markSide),
          paint,
        );
      }
      canvas.restore();
    }
  }

  Future<ui.Image?> _blockIcon(String blockName) async {
    if (_blockIconCache.containsKey(blockName)) {
      return _blockIconCache[blockName];
    }
    final bytes = assets.blockIconBytes(blockName);
    final image = bytes == null ? null : await decodeImage(bytes);
    _blockIconCache[blockName] = image;
    return image;
  }

  /// config 标记：官方 `drawPlanConfigCenter` 的 CPU 复刻
  ///
  /// 排序器 / 卸载器 / 钻头 / 源头：画 center 图标并染成物品或液体颜色；无 config 画 cross
  Future<_ConfigMark?> _configMark(
    BlueprintBlockInfo info,
    SchematicConfig? config,
  ) async {
    if (!_usesCenterMark(info.type)) return null;
    if (config == null) {
      final cross = await _genericIcon('cross');
      return cross == null ? null : _ConfigMark(cross, null);
    }
    if (config.kind != SchematicConfigKind.content) return null;
    final ref = config.value as SchematicContentRef;
    final center = await _genericIcon('center');
    if (center == null) return null;
    if (ref.typeOrdinal == 0) {
      return _ConfigMark(center, assets.itemColorOfId(ref.id));
    }
    if (ref.typeOrdinal == 4) {
      return _ConfigMark(center, assets.liquidColorOfId(ref.id));
    }
    return null;
  }

  Future<ui.Image?> _genericIcon(String name) async {
    if (_genericIconCache.containsKey(name)) return _genericIconCache[name];
    final bytes = name == 'center'
        ? assets.centerIconBytes()
        : assets.crossIconBytes();
    final image = bytes == null ? null : await decodeImage(bytes);
    _genericIconCache[name] = image;
    return image;
  }

  static bool _usesCenterMark(String type) {
    return const {
      'Sorter',
      'Unloader',
      'DirectionalUnloader',
      'Drill',
      'ItemSource',
      'LiquidSource',
    }.contains(type);
  }
}

class _PlacedBlock {
  _PlacedBlock({
    required this.tile,
    required this.info,
    required this.blockIcon,
    required this.configMark,
  });

  final SchematicTile tile;
  final BlueprintBlockInfo info;
  final ui.Image? blockIcon;
  final _ConfigMark? configMark;
}

class _ConfigMark {
  const _ConfigMark(this.image, this.color);

  final ui.Image image;
  final int? color;
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
