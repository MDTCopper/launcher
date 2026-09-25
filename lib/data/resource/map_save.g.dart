// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'map_save.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

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
