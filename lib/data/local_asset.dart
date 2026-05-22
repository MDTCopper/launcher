import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;

import '../util/app_paths.dart';

part 'local_asset.g.dart';

abstract class LocalAsset {
  final String? name; //资源原名
  final String? releaseNum;

  ///存储路径
  final String? path;
  final String? author;

  const LocalAsset({
    required this.author,
    required this.path,
    required this.name,
    required this.releaseNum,
  });
}

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

  ///返回游戏版本号 (double)
  double get releaseDouble => double.parse(releaseNum.substring(1));

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
  });

  factory Mindustry.fromJson(Map<String, dynamic> json) =>
      _$MindustryFromJson(json);

  Map<String, dynamic> toJson() => _$MindustryToJson(this);

  @override
  String toString() {
    return 'Mindustry{ id:$id , name:$name , release:$releaseNum }';
  }
}

enum LauncherType { mindustry, copper }

class SaveData {
  String path;

  List<Mod>? mods;

  List<MapSave>? maps;

  List<Schematic>? schematics;

  CampaignData? campaignData;

  SaveData({required this.path});
}

@JsonSerializable()
class Mod extends LocalAsset {
  Mod({
    required this.hasScripts,
    required this.hasJava,
    required this.minGameVersion,
    required this.description,
    required super.path,
    required super.name,
    required super.releaseNum,
    required super.author,
  });
  final double minGameVersion;
  final bool hasScripts;
  final bool hasJava;
  final String description;
  late final bool? hidden;

  factory Mod.fromJson(Map<String, dynamic> json) => _$ModFromJson(json);
}

//这个需要后续规范整合包标准
class ModPack extends LocalAsset {
  ModPack({
    required super.path,
    required super.name,
    required super.releaseNum,
    required super.author,
  });
}

class Schematic extends LocalAsset {
  Schematic({
    required super.path,
    required super.name,
    required super.releaseNum,
    required super.author,
  });
}

class MapSave extends LocalAsset {
  MapSave({
    required super.path,
    required super.name,
    required super.releaseNum,
    required super.author,
  });
}

class CampaignData {
  List<MapSave>? saves;
  //setting
}
