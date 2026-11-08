import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 按游戏版本导出的蓝图预览资产包
///
/// 目录结构：`content.json` + `icons/block/*.png` + `icons/item/*.png` + `icons/liquid/*.png`
/// 内容表与图标都由对应版本的 `.jar` 导出，这里只负责读取
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
  });

  final String packDirPath;

  /// 版本标识（导出时的 tag，仅用于缓存键与调试）
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

  static Future<BlueprintAssetPack> load(String packDirPath) async {
    final contentFile = File('$packDirPath/content.json');
    final content =
        jsonDecode(await contentFile.readAsString()) as Map<String, dynamic>;
    final metaFile = File('$packDirPath/meta.json');
    final meta = metaFile.existsSync()
        ? jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>
        : const <String, dynamic>{};

    final blocks = <String, BlueprintBlockInfo>{};
    for (final entry in content['blocks'] as List<dynamic>) {
      final block = entry as Map<String, dynamic>;
      final name = block['name'] as String;
      blocks[name] = BlueprintBlockInfo(
        name: name,
        size: (block['size'] as num?)?.toInt() ?? 1,
        type: block['type'] as String? ?? '',
        rotate: block['rotate'] as bool? ?? false,
        rotateDraw: block['rotateDraw'] as bool? ?? false,
        mapColor: _parseColor(block['mapColor'] as String?),
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
    );
  }

  String? itemNameOfId(int id) => itemNamesById[id];

  int? itemColorOfId(int id) => itemColorsById[id];

  int? liquidColorOfId(int id) => liquidColorsById[id];

  Uint8List? centerIconBytes() => _readBytes(centerIconPath);

  Uint8List? crossIconBytes() => _readBytes(crossIconPath);

  String? liquidNameOfId(int id) => liquidNamesById[id];

  /// 方块图标字节；没有导出图标时返回 null
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

  BlueprintBlockInfo? block(String name) => blocks[name];

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

  /// 内容 id → 名字（渲染 config 里的物品 / 液体图标时用）
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
  });

  final String name;
  final int size;

  /// 方块类名（如 Sorter / PowerNode），config 绘制按它分派
  final String type;
  final bool rotate;
  final bool rotateDraw;
  final int? mapColor;
}
