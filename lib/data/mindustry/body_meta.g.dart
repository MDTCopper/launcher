// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'body_meta.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

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
