// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_meta.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MindustryFileMeta _$MindustryFileMetaFromJson(Map<String, dynamic> json) =>
    MindustryFileMeta(
      path: json['path'] as String?,
      type: json['modifier'] as String,
      version: json['number'] as String,
      build: json['build'] as String,
    );

Map<String, dynamic> _$MindustryFileMetaToJson(MindustryFileMeta instance) =>
    <String, dynamic>{
      'path': instance.path,
      'number': instance.version,
      'build': instance.build,
      'modifier': instance.type,
    };
