import 'dart:io';
import 'dart:typed_data';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/util/io/mindustry_save_file/save_file_codec.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;

import '../util/app_paths.dart';

part 'local_asset.g.dart';

enum LauncherType { mindustry, copper }

///配置文件存储游戏信息的数据类
///游戏版本将以文件夹的形式存储，文件夹内是版本数据，可能包含游戏本体，不包含的将使用其他文件目录下载游戏本体，这样可以省出不必要的下载
@JsonSerializable()
class Mindustry {
  final String id;

  ///资源原名
  final String name;
  final String releaseNum;

  ///存储路径
  final String path;

  ///游戏启动路径
  final String jarPath;
  final LauncherType launcher;
  final bool isBe;
  final DateTime addTime;

  /// 玩家给游戏版本的标签
  String tag;
  bool like = false;
  bool isolation;

  String? java;

  @JsonKey(includeToJson: false, includeFromJson: false)
  Memory? get memory {
    if (memorySize == null) return null;
    return Memory(bytes: memorySize);
  }

  set memory(Memory? value) => memorySize = value?.bytes;

  int? memorySize;

  bool? autoMemory;

  bool? useBetterGPU;

  String? jvmParameter;

  ///返回游戏版本号 (double)
  double get releaseDouble => double.parse(releaseNum.substring(1));

  ///返回游戏版本号 (int)
  int get releaseInt => int.parse(releaseNum.substring(1).split('.').first);

  ///游戏目录路径
  String get foldPath => p.join(path, tag);

  ///游戏数据路径mods,saves,maps,schematics
  String get dataPath {
    if (isolation) return p.join(foldPath, 'data');
    return AppPaths.defaultGameData!; //默认存储位置
  }

  String get modsPath => p.join(dataPath, 'mods');

  String get savesPath => p.join(dataPath, 'saves');

  String get schematicsPath => p.join(dataPath, 'schematics');

  String get mapsPath => p.join(dataPath, 'maps');

  ///无论是否隔离，游戏崩溃日志都存储在默认游戏数据目录下crashes文件夹
  String get crashesPath => p.join(AppPaths.defaultGameData!, 'crashes');

  String get settingPath => p.join(dataPath, 'settings.bin');

  Mindustry({
    required this.id,
    required this.tag,
    required this.name,
    required this.releaseNum,
    required this.path,
    required this.jarPath,
    required this.launcher,
    required this.isBe,
    required this.isolation,
    required this.addTime,
    this.java,
    this.jvmParameter,
    this.useBetterGPU,
    this.memorySize,
  });

  factory Mindustry.fromJson(Map<String, dynamic> json) =>
      _$MindustryFromJson(json);

  Map<String, dynamic> toJson() => _$MindustryToJson(this);

  @override
  String toString() {
    return 'Mindustry{ id:$id , name:$name , release:$releaseNum }';
  }
}

///下面的数据类通过源文件实时解析
class SaveData {
  String path;

  List<Mod>? mods;

  List<MapSave>? maps;

  List<Schematic>? schematics;

  CampaignData? campaignData;

  SaveData({required this.path});
}

// class MindustryMeta{
//
// }

@JsonSerializable()
class MindustryMeta {
  MindustryMeta({
    required this.path,
    required this.type,
    required this.version,
    required this.build,
  });

  final String? path;
  @JsonKey(name: 'number')
  final String version;
  final String build;

  /// release或beta
  @JsonKey(name: 'modifier')
  final String type;

  factory MindustryMeta.fromJson(Map<String, dynamic> json) =>
      _$MindustryMetaFromJson(json);

  Map<String, dynamic> toJson() => _$MindustryMetaToJson(this);
}

//todo 后续应该
@JsonSerializable()
class Mod {
  Mod({
    required this.java,
    required this.minGameVersion,
    required this.description,
    required this.path,
    required this.name,
    required this.version,
    required this.author,
    required this.hidden,
    required this.dependencies,
  });

  ///存储路径
  final String? path;

  @JsonKey(defaultValue: '未知模组')
  final String name;

  @JsonKey(defaultValue: '未知版本')
  final String version;

  @JsonKey(defaultValue: '未知作者')
  final String author;

  @JsonKey(defaultValue: '0')
  final String minGameVersion;

  @JsonKey(defaultValue: false)
  final bool java;

  @JsonKey(defaultValue: '')
  final String description;

  final bool? hidden;

  @JsonKey(includeFromJson: false, includeToJson: false)
  late final Uint8List? icon;

  @JsonKey(defaultValue: [])
  final List<dynamic> dependencies;

  factory Mod.fromJson(Map<String, dynamic> json, {Uint8List? icon}) {
    json['minGameVersion'] = json['minGameVersion'].toString();
    json['hidden'] = bool.tryParse(json['hidden'].toString());
    return _$ModFromJson(json)..icon = icon;
  }

  Map<String, dynamic> toJson() => _$ModToJson(this);
}

//todo 这个需要后续规范整合包标准
// class ModPack extends LocalAsset {
//   ModPack({
//     required super.path,
//     required super.name,
//     required super.version,
//     required super.author,
//   });
// }

@JsonSerializable()
class Schematic {
  ///存储路径
  final String? path;

  /// 蓝图名称 (来自 tags["name"])
  @JsonKey(defaultValue: '未知蓝图')
  final String name;

  @JsonKey(defaultValue: '未知作者')
  final String author;

  /// 蓝图描述 (来自 tags["description"])。
  @JsonKey(defaultValue: '')
  String description;

  @JsonKey(defaultValue: 0)
  int width;

  @JsonKey(defaultValue: 0)
  int height;

  /// 方块数量。
  @JsonKey(defaultValue: 0)
  int tileCount;

  /// 标签列表。
  @JsonKey(defaultValue: [])
  List<dynamic> labels;

  Schematic({
    required this.path,
    required this.name,
    required this.author,
    required this.description,
    required this.width,
    required this.height,
    required this.tileCount,
    required this.labels,
  });

  /// 从 .msch 文件路径加载。
  factory Schematic.fromFile(String path) {
    final bytes = File(path).readAsBytesSync();
    return Schematic.fromBytes(bytes, path);
  }

  /// 从 .msch 字节加载。
  factory Schematic.fromBytes(Uint8List bytes, String path) {
    final meta = SaveFileCodec.decodeSchematic(bytes);
    meta['path'] = path;
    return Schematic.fromJson(meta);
  }

  /// 从已解析的元数据 Map 构建。codec 返回平铺 Map，字段已做类型转换。
  // factory Schematic.fromMeta(Map<String, dynamic> meta, String path) {
  //   final fileName = p.basenameWithoutExtension(path);
  //   return Schematic(
  //     path: path,
  //     author: '',
  //     name: meta['name'] as String? ?? fileName,
  //     description: meta['description'] as String? ?? '',
  //     width: meta['width'] as int? ?? 0,
  //     height: meta['height'] as int? ?? 0,
  //     tileCount: meta['tileCount'] as int? ?? 0,
  //     labels: (meta['labels'] as List?)?.cast<String>() ?? [],
  //   );
  // }

  factory Schematic.fromJson(Map<String, dynamic> json) {
    json['name'] ??= p.basenameWithoutExtension(json['path']);
    return _$SchematicFromJson(json);
  }

  Map<String, dynamic> toJson() => _$SchematicToJson(this);
}

@JsonSerializable()
class MapSave {
  ///存储路径
  final String? path;

  /// 地图名称 (来自 tags["mapname"])。
  @JsonKey(defaultValue: '未知', name: 'mapname')
  final String name;

  @JsonKey(defaultValue: '未知')
  final String author;

  /// 当前波次。
  @JsonKey(defaultValue: 0)
  final int wave;

  /// 游玩时长（毫秒）。
  @JsonKey(defaultValue: 0)
  final int playtime;

  /// 存档时间戳（毫秒 since epoch）。
  @JsonKey(defaultValue: 0)
  final int saved;

  /// 游戏构建号。
  @JsonKey(defaultValue: 0)
  final int build;

  /// 游戏规则 (JSON 字符串)。
  @JsonKey(defaultValue: '')
  final String rules;

  /// 使用的 Mod 列表。
  @JsonKey(defaultValue: [])
  final List<dynamic> mods;

  MapSave({
    required this.path,
    required this.name,
    required this.author,
    required this.wave,
    required this.playtime,
    required this.saved,
    required this.build,
    required this.rules,
    required this.mods,
  });

  /// 从 .msav 文件路径加载。
  factory MapSave.fromFile(String path) {
    final bytes = File(path).readAsBytesSync();
    return MapSave.fromBytes(bytes, path);
  }

  /// 从 .msav 字节加载。
  factory MapSave.fromBytes(Uint8List bytes, String path) {
    final meta = SaveFileCodec.decodeMapMeta(bytes);
    meta['path'] = path;
    return MapSave.fromJson(meta);
  }

  /// 从已解析的元数据 Map 构建。codec 已做类型转换，直接读取。
  // factory MapSave.fromMeta(Map<String, dynamic> meta, String path) {
  //   return MapSave(
  //     path: path,
  //     author: meta['author'] as String? ?? '未知',
  //     name: meta['mapname'] as String? ?? '未知',
  //     wave: meta['wave'] as int? ?? 0,
  //     playtime: meta['playtime'] as int? ?? 0,
  //     saved: meta['saved'] as int? ?? 0,
  //     build: meta['build'] as int? ?? 0,
  //     rules: meta['rules'] as String? ?? '',
  //     mods: (meta['mods'] as List?)?.cast<String>() ?? [],
  //   );
  // }

  factory MapSave.fromJson(Map<String, dynamic> json) =>
      _$MapSaveFromJson(json);

  Map<String, dynamic> toJson() => _$MapSaveToJson(this);
}

class CampaignData {
  List<MapSave>? saves;
  //setting
}
