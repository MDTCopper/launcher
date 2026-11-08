import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 按游戏版本导出的蓝图预览资产包
///
/// 目录：`content.json` + `classes.json` + `icons/` + `parts/`
/// 图标来自对应版本 `.jar` 的 atlas；`parts` 是绘制规则需要的原始 region
class BlueprintAssetPack {
  BlueprintAssetPack._({
    required this.packDirPath,
    required this.versionLabel,
    required this.blocks,
    required this.blockIconPaths,
    required this.itemIconPaths,
    required this.liquidIconPaths,
    required this.itemNamesById,
    required this.liquidNamesById,
    required this.itemColorsById,
    required this.liquidColorsById,
    required this.centerIconPath,
    required this.crossIconPath,
    required this.partsDirPath,
    required this.canvases,
  });

  final String packDirPath;

  /// 版本标识，仅用于缓存键与调试
  final String versionLabel;

  final Map<String, BlueprintBlockInfo> blocks;
  final Map<String, String> blockIconPaths;
  final Map<String, String> itemIconPaths;
  final Map<String, String> liquidIconPaths;
  final Map<int, String> itemNamesById;
  final Map<int, String> liquidNamesById;
  final Map<int, int> itemColorsById;
  final Map<int, int> liquidColorsById;
  final String? centerIconPath;
  final String? crossIconPath;
  final String partsDirPath;

  /// canvas / large-canvas 的调色板与几何（导出文件 canvas.json）
  final Map<String, BlueprintCanvasInfo> canvases;

  final Map<String, ui.Image?> _regionImages = {};
  final Map<String, ui.Size?> _regionSizes = {};
  final Map<String, ui.Image?> _blockIconImages = {};

  static Future<BlueprintAssetPack> load(String packDirPath) async {
    final content =
        jsonDecode(await File('$packDirPath/content.json').readAsString())
            as Map<String, dynamic>;
    final metaFile = File('$packDirPath/meta.json');
    final meta = metaFile.existsSync()
        ? jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>
        : const <String, dynamic>{};

    final classes = <String, Map<String, dynamic>>{};
    final classesFile = File('$packDirPath/classes.json');
    if (classesFile.existsSync()) {
      final raw =
          jsonDecode(await classesFile.readAsString()) as Map<String, dynamic>;
      for (final entry in raw['classes'] as List<dynamic>) {
        final item = entry as Map<String, dynamic>;
        classes[item['name'] as String] = item;
      }
    }

    final canvases = <String, BlueprintCanvasInfo>{};
    final canvasFile = File('$packDirPath/canvas.json');
    if (canvasFile.existsSync()) {
      final raw =
          jsonDecode(await canvasFile.readAsString()) as Map<String, dynamic>;
      for (final entry in raw['canvases'] as List<dynamic>) {
        final item = entry as Map<String, dynamic>;
        final name = item['name'] as String;
        canvases[name] = BlueprintCanvasInfo(
          name: name,
          size: (item['size'] as num).toInt(),
          canvasSize: (item['canvasSize'] as num).toInt(),
          bitsPerPixel: (item['bitsPerPixel'] as num).toInt(),
          padding: (item['padding'] as num).toDouble(),
          palette: (item['palette'] as List<dynamic>)
              .map((value) => (value as num).toInt())
              .toList(),
        );
      }
    }

    final blocks = <String, BlueprintBlockInfo>{};
    for (final entry in content['blocks'] as List<dynamic>) {
      final block = entry as Map<String, dynamic>;
      final name = block['name'] as String;
      final draw = classes[name];
      blocks[name] = BlueprintBlockInfo(
        name: name,
        size: (block['size'] as num?)?.toInt() ?? 1,
        type: block['type'] as String? ?? '',
        rotate: block['rotate'] as bool? ?? false,
        rotateDraw: block['rotateDraw'] as bool? ?? false,
        mapColor: _parseColor(block['mapColor'] as String?),
        regionRuleClass: (draw?['drawPlanRegion'] as String?) ?? '',
        configRuleClass: (draw?['drawPlanConfig'] as String?) ?? '',
        configTopRuleClass: (draw?['drawPlanConfigTop'] as String?) ?? '',
        classChain: (draw?['chain'] as List<dynamic>? ?? const [])
            .cast<String>(),
        hasItems: block['hasItems'] as bool? ?? false,
        hasLiquids: block['hasLiquids'] as bool? ?? false,
        outputsLiquid: block['outputsLiquid'] as bool? ?? false,
        acceptsItems: block['acceptsItems'] as bool? ?? false,
        noSideBlend: block['noSideBlend'] as bool? ?? false,
        isDuct: block['isDuct'] as bool? ?? false,
        squareSprite: block['squareSprite'] as bool? ?? false,
      );
    }

    return BlueprintAssetPack._(
      packDirPath: packDirPath,
      versionLabel: (meta['version'] as String?) ?? 'unknown',
      blocks: blocks,
      blockIconPaths: _indexIcons('$packDirPath/icons/block'),
      itemIconPaths: _indexIcons('$packDirPath/icons/item'),
      liquidIconPaths: _indexIcons('$packDirPath/icons/liquid'),
      itemNamesById: _indexContentNames(content['items'] as List<dynamic>),
      liquidNamesById: _indexContentNames(content['liquids'] as List<dynamic>),
      itemColorsById: _indexContentColors(content['items'] as List<dynamic>),
      liquidColorsById: _indexContentColors(
        content['liquids'] as List<dynamic>,
      ),
      centerIconPath: _iconPath(packDirPath, 'generic', 'center'),
      crossIconPath: _iconPath(packDirPath, 'generic', 'cross'),
      partsDirPath: '$packDirPath/parts',
      canvases: canvases,
    );
  }

  String? itemNameOfId(int id) => itemNamesById[id];

  String? liquidNameOfId(int id) => liquidNamesById[id];

  int? itemColorOfId(int id) => itemColorsById[id];

  int? liquidColorOfId(int id) => liquidColorsById[id];

  Uint8List? centerIconBytes() => _readBytes(centerIconPath);

  Uint8List? crossIconBytes() => _readBytes(crossIconPath);

  BlueprintBlockInfo? block(String name) => blocks[name];

  BlueprintCanvasInfo? canvas(String name) => canvases[name];

  /// 按需解码绘制规则用到的 region
  Future<void> ensureRegions(Iterable<String> names) async {
    for (final name in names) {
      if (_regionImages.containsKey(name)) continue;
      if (name.startsWith('block-icon:')) {
        final blockName = name.substring('block-icon:'.length);
        if (!_blockIconImages.containsKey(blockName)) {
          final bytes = blockIconBytes(blockName);
          _blockIconImages[blockName] = bytes == null
              ? null
              : await _decode(bytes);
        }
        continue;
      }
      final file = File('$partsDirPath/$name.png');
      _regionImages[name] = file.existsSync()
          ? await _decode(file.readAsBytesSync())
          : null;
    }
  }

  ui.Image? decodedRegion(String name) => _regionImages[name];

  ui.Image? decodedBlockIcon(String name) => _blockIconImages[name];

  /// region 原始像素尺寸，从 PNG 头读，不需要完整解码
  ui.Size? regionSize(String name) {
    if (_regionSizes.containsKey(name)) return _regionSizes[name];
    final file = File('$partsDirPath/$name.png');
    if (!file.existsSync()) {
      _regionSizes[name] = null;
      return null;
    }
    final bytes = file.readAsBytesSync();
    final size = _pngSize(bytes);
    _regionSizes[name] = size;
    return size;
  }

  Uint8List? blockIconBytes(String blockName) {
    final path = blockIconPaths[blockName];
    if (path == null) return null;
    return File(path).readAsBytesSync();
  }

  Uint8List? itemIconBytes(String itemName) {
    final path = itemIconPaths[itemName];
    if (path == null) return null;
    return File(path).readAsBytesSync();
  }

  Uint8List? liquidIconBytes(String liquidName) {
    final path = liquidIconPaths[liquidName];
    if (path == null) return null;
    return File(path).readAsBytesSync();
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static ui.Size? _pngSize(Uint8List bytes) {
    if (bytes.length < 24) return null;
    final data = ByteData.sublistView(bytes, 16, 24);
    return ui.Size(data.getUint32(0).toDouble(), data.getUint32(4).toDouble());
  }

  static Map<String, String> _indexIcons(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return const {};
    final icons = <String, String>{};
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.png')) continue;
      final name = entity.uri.pathSegments.last.replaceAll('.png', '');
      icons[name] = entity.path;
    }
    return icons;
  }

  static int? _parseColor(String? hex) {
    if (hex == null || hex.length < 6) return null;
    final value = int.tryParse(hex.substring(0, 6), radix: 16);
    return value == null ? null : 0xFF000000 | value;
  }

  static Uint8List? _readBytes(String? path) {
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  static String? _iconPath(String packDirPath, String kind, String name) {
    final file = File('$packDirPath/icons/$kind/$name.png');
    return file.existsSync() ? file.path : null;
  }

  static Map<int, int> _indexContentColors(List<dynamic> entries) {
    final colors = <int, int>{};
    for (final entry in entries) {
      final content = entry as Map<String, dynamic>;
      final id = (content['id'] as num?)?.toInt();
      final color = _parseColor(content['color'] as String?);
      if (id != null && color != null) colors[id] = color;
    }
    return colors;
  }

  static Map<int, String> _indexContentNames(List<dynamic> entries) {
    final names = <int, String>{};
    for (final entry in entries) {
      final content = entry as Map<String, dynamic>;
      final id = (content['id'] as num?)?.toInt();
      final name = content['name'] as String?;
      if (id != null && name != null) names[id] = name;
    }
    return names;
  }
}

class BlueprintBlockInfo {
  const BlueprintBlockInfo({
    required this.name,
    required this.size,
    required this.type,
    required this.rotate,
    required this.rotateDraw,
    required this.mapColor,
    required this.regionRuleClass,
    required this.configRuleClass,
    required this.configTopRuleClass,
    required this.classChain,
    required this.hasItems,
    required this.hasLiquids,
    required this.outputsLiquid,
    required this.acceptsItems,
    required this.noSideBlend,
    required this.isDuct,
    required this.squareSprite,
  });

  final String name;
  final int size;

  /// 类 simpleName；匿名子类为空
  final String type;
  final bool rotate;
  final bool rotateDraw;
  final int? mapColor;

  /// 官方 `drawPlanRegion` 的声明类全名
  final String regionRuleClass;

  /// 官方 `drawPlanConfig` 的声明类全名
  final String configRuleClass;

  /// 官方 `drawPlanConfigTop` 的声明类全名
  final String configTopRuleClass;

  /// 类继承链（自身 → Block）
  final List<String> classChain;

  /// 连接/自动拼接判定用的方块标记
  final bool hasItems;
  final bool hasLiquids;
  final bool outputsLiquid;
  final bool acceptsItems;
  final bool noSideBlend;
  final bool isDuct;
  final bool squareSprite;
}

/// CanvasBlock 的调色板与像素网格参数
class BlueprintCanvasInfo {
  const BlueprintCanvasInfo({
    required this.name,
    required this.size,
    required this.canvasSize,
    required this.bitsPerPixel,
    required this.padding,
    required this.palette,
  });

  final String name;
  final int size;
  final int canvasSize;
  final int bitsPerPixel;
  final double padding;

  /// ARGB 颜色，索引即像素值
  final List<int> palette;
}
