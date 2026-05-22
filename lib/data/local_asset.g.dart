// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_asset.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Mindustry _$MindustryFromJson(Map<String, dynamic> json) => Mindustry(
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
)..like = json['like'] as bool;

Map<String, dynamic> _$MindustryToJson(Mindustry instance) => <String, dynamic>{
  'name': instance.name,
  'releaseNum': instance.releaseNum,
  'path': instance.path,
  'id': instance.id,
  'jarPath': instance.jarPath,
  'launcher': _$LauncherTypeEnumMap[instance.launcher],
  'isBe': instance.isBe,
  'addTime': instance.addTime.toIso8601String(),
  'tag': instance.tag,
  'like': instance.like,
  'isolation': instance.isolation,
};

const _$LauncherTypeEnumMap = {
  LauncherType.mindustry: 'mindustry',
  LauncherType.copper: 'copper',
};

Mod _$ModFromJson(Map<String, dynamic> json) => Mod(
  hasScripts: json['hasScripts'] as bool,
  hasJava: json['hasJava'] as bool,
  minGameVersion: (json['minGameVersion'] as num).toDouble(),
  description: json['description'] as String,
  path: json['path'] as String?,
  name: json['name'] as String?,
  releaseNum: json['releaseNum'] as String?,
  author: json['author'] as String?,
)..hidden = json['hidden'] as bool?;

Map<String, dynamic> _$ModToJson(Mod instance) => <String, dynamic>{
  'name': instance.name,
  'releaseNum': instance.releaseNum,
  'path': instance.path,
  'author': instance.author,
  'minGameVersion': instance.minGameVersion,
  'hasScripts': instance.hasScripts,
  'hasJava': instance.hasJava,
  'description': instance.description,
  'hidden': instance.hidden,
};
