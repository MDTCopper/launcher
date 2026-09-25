// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schematic.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

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
