import 'dart:io';

import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;

part 'local_asset.g.dart';

String? defaultGameDataPath;

Future<void> initDefaultDataPath() async {
  if (Platform.isWindows) {
    final roaming = Platform.environment['APPDATA'];
    if (roaming != null) {
      defaultGameDataPath = p.join(
        Platform.environment['APPDATA']!,
        'Mindustry',
      );
    }
  } else if (Platform.isAndroid) {
    //安卓平台默认为/storage/emulated/0/Android/data/io.anuke.mindustry/files/，但安卓平台不能直接读取data
    defaultGameDataPath =
        '/storage/emulated/0/Android/data/io.anuke.mindustry/files/';
  } else if (Platform.isLinux) {
    final home = Platform.environment['HOME'];
    if (home != null) {
      defaultGameDataPath = p.join(
        Platform.environment['HOME']!,
        '.local',
        'share',
        'Mindustry',
      );
    }
  }
  if (defaultGameDataPath == null) {
    throw ('无法获取默认游戏数据存储位置');
  } else {
    print('默认数据存储路径:$defaultGameDataPath');
  }
}

abstract class LocalAsset {
  final String? name; //资源原名
  final String? releaseNum;
  final String? path; //存储路径
  final String? author;

  const LocalAsset({
    required this.author,
    required this.path,
    required this.name,
    required this.releaseNum,
  });
}

@JsonSerializable()
class Mindustry extends LocalAsset {
  final String? id;
  final String? jarPath; //游戏启动路径
  final LauncherType? launcher;
  final bool? isBe;
  final DateTime? addTime;

  String? tag; // 玩家标签
  bool? like = false;
  bool? isolation;

  String? get foldPath {
    //游戏目录路径
    if (path == null) return null;
    return p.join(path!, tag);
  }

  String? get dataPath {
    //游戏数据路径mods,saves,maps,schematics
    final notIsolation = !(isolation ?? false);
    if (notIsolation) return defaultGameDataPath; //默认存储位置
    if (foldPath == null) return null;
    return p.join(foldPath!, 'data');
  }

  String? get modsPath {
    if (dataPath == null) return null;
    return p.join(dataPath!, 'mods');
  }

  String? get savesPath {
    if (dataPath == null) return null;
    return p.join(dataPath!, 'saves');
  }

  String? get schematicsPath {
    if (dataPath == null) return null;
    return p.join(dataPath!, 'schematics');
  }

  String? get mapsPath {
    if (dataPath == null) return null;
    return p.join(dataPath!, 'maps');
  }

  String? get crashesPath {
    if (defaultGameDataPath == null) return null;
    return p.join(defaultGameDataPath!, 'crashes');
  }

  Mindustry({
    required this.id,
    required this.tag,
    required super.name,
    required super.releaseNum,
    required super.path,
    required this.jarPath,
    required this.launcher,
    required this.isBe,
    required this.isolation,
    required this.addTime,
  }) : super(author: 'anuken');

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
