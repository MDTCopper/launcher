// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mod.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

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
  gameVersionFilter: json['gameVersionFilter'],
  conflicts: json['conflicts'] as List<dynamic>? ?? [],
  copper: json['copper'] as bool? ?? false,
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
  'gameVersionFilter': instance.gameVersionFilter,
  'conflicts': instance.conflicts,
  'copper': instance.copper,
};
