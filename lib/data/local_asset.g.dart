// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_asset.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Mindustry _$MindustryFromJson(Map<String, dynamic> json) =>
    Mindustry(
        id: json['id'] as String,
        tag: json['tag'] as String,
        name: json['name'] as String,
        releaseNum: json['releaseNum'] as String,
        path: json['path'] as String,
        jarPath: json['jarPath'] as String,
        launcher: $enumDecode(_$LauncherTypeEnumMap, json['launcher']),
        isBe: json['isBe'] as bool,
        isolation: json['isolation'] as bool,
        addTime: DateTime.parse(json['addTime'] as String),
        java: json['java'] as String?,
        jvmParameter: json['jvmParameter'] as String?,
        useBetterGPU: json['useBetterGPU'] as bool?,
        memorySize: (json['memorySize'] as num?)?.toInt(),
      )
      ..like = json['like'] as bool
      ..autoMemory = json['autoMemory'] as bool?;

Map<String, dynamic> _$MindustryToJson(Mindustry instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'releaseNum': instance.releaseNum,
  'path': instance.path,
  'jarPath': instance.jarPath,
  'launcher': _$LauncherTypeEnumMap[instance.launcher]!,
  'isBe': instance.isBe,
  'addTime': instance.addTime.toIso8601String(),
  'tag': instance.tag,
  'like': instance.like,
  'isolation': instance.isolation,
  'java': instance.java,
  'memorySize': instance.memorySize,
  'autoMemory': instance.autoMemory,
  'useBetterGPU': instance.useBetterGPU,
  'jvmParameter': instance.jvmParameter,
};

const _$LauncherTypeEnumMap = {
  LauncherType.mindustry: 'mindustry',
  LauncherType.copper: 'copper',
};

MindustryMeta _$MindustryMetaFromJson(Map<String, dynamic> json) =>
    MindustryMeta(
      path: json['path'] as String?,
      type: json['modifier'] as String,
      version: json['number'] as String,
      build: json['build'] as String,
    );

Map<String, dynamic> _$MindustryMetaToJson(MindustryMeta instance) =>
    <String, dynamic>{
      'path': instance.path,
      'number': instance.version,
      'build': instance.build,
      'modifier': instance.type,
    };

Mod _$ModFromJson(Map<String, dynamic> json) => Mod(
  java: json['java'] as bool? ?? false,
  minGameVersion: json['minGameVersion'] as String? ?? '0',
  description: json['description'] as String? ?? '',
  path: json['path'] as String?,
  name: json['name'] as String? ?? '未知模组',
  version: json['version'] as String? ?? '未知版本',
  author: json['author'] as String? ?? '未知作者',
  hidden: json['hidden'] as bool?,
  dependencies: json['dependencies'] as List<dynamic>? ?? [],
);

Map<String, dynamic> _$ModToJson(Mod instance) => <String, dynamic>{
  'path': instance.path,
  'name': instance.name,
  'version': instance.version,
  'author': instance.author,
  'minGameVersion': instance.minGameVersion,
  'java': instance.java,
  'description': instance.description,
  'hidden': instance.hidden,
  'dependencies': instance.dependencies,
};

Schematic _$SchematicFromJson(Map<String, dynamic> json) => Schematic(
  path: json['path'] as String?,
  name: json['name'] as String? ?? '未知蓝图',
  author: json['author'] as String? ?? '未知作者',
  description: json['description'] as String? ?? '',
  width: (json['width'] as num?)?.toInt() ?? 0,
  height: (json['height'] as num?)?.toInt() ?? 0,
  tileCount: (json['tileCount'] as num?)?.toInt() ?? 0,
  labels: json['labels'] as List<dynamic>? ?? [],
);

Map<String, dynamic> _$SchematicToJson(Schematic instance) => <String, dynamic>{
  'path': instance.path,
  'name': instance.name,
  'author': instance.author,
  'description': instance.description,
  'width': instance.width,
  'height': instance.height,
  'tileCount': instance.tileCount,
  'labels': instance.labels,
};

MapSave _$MapSaveFromJson(Map<String, dynamic> json) => MapSave(
  path: json['path'] as String?,
  name: json['mapname'] as String? ?? '未知',
  author: json['author'] as String? ?? '未知',
  wave: (json['wave'] as num?)?.toInt() ?? 0,
  playtime: (json['playtime'] as num?)?.toInt() ?? 0,
  saved: (json['saved'] as num?)?.toInt() ?? 0,
  build: (json['build'] as num?)?.toInt() ?? 0,
  rules: json['rules'] as String? ?? '',
  mods: json['mods'] as List<dynamic>? ?? [],
);

Map<String, dynamic> _$MapSaveToJson(MapSave instance) => <String, dynamic>{
  'path': instance.path,
  'mapname': instance.name,
  'author': instance.author,
  'wave': instance.wave,
  'playtime': instance.playtime,
  'saved': instance.saved,
  'build': instance.build,
  'rules': instance.rules,
  'mods': instance.mods,
};
