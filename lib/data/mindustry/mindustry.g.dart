// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mindustry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Mindustry _$MindustryFromJson(Map<String, dynamic> json) =>
    Mindustry(
        id: json['id'] as String,
        tag: json['tag'] as String,
        release: json['release'] as String,
        path: json['path'] as String,
        jarPath: json['jarPath'] as String,
        launcher: $enumDecode(_$LauncherTypeEnumMap, json['launcher']),
        isBe: json['isBe'] as bool,
        isolation: json['isolation'] as bool,
        addTime: DateTime.parse(json['addTime'] as String),
        playTime: json['playTime'] == null
            ? null
            : Duration(microseconds: (json['playTime'] as num).toInt()),
        lastLaunchTime: json['lastLaunchTime'] == null
            ? null
            : DateTime.parse(json['lastLaunchTime'] as String),
        java: json['java'] as String?,
        jvmParameter: json['jvmParameter'] as String?,
        useBetterGPU: json['useBetterGPU'] as bool?,
        memorySize: (json['memorySize'] as num?)?.toInt(),
        versionNumber: (json['versionNumber'] as num?)?.toInt(),
        bodyIsUserFile: json['bodyIsUserFile'] as bool? ?? false,
        launcherPath: json['launcherPath'] as String?,
      )
      ..like = json['like'] as bool
      ..autoMemory = json['autoMemory'] as bool?;

Map<String, dynamic> _$MindustryToJson(Mindustry instance) => <String, dynamic>{
  'id': instance.id,
  'release': instance.release,
  'path': instance.path,
  'jarPath': instance.jarPath,
  'launcher': _$LauncherTypeEnumMap[instance.launcher]!,
  'isBe': instance.isBe,
  'addTime': instance.addTime.toIso8601String(),
  'playTime': instance.playTime?.inMicroseconds,
  'lastLaunchTime': instance.lastLaunchTime?.toIso8601String(),
  'tag': instance.tag,
  'like': instance.like,
  'isolation': instance.isolation,
  'java': instance.java,
  'versionNumber': instance.versionNumber,
  'bodyIsUserFile': instance.bodyIsUserFile,
  'launcherPath': instance.launcherPath,
  'memorySize': instance.memorySize,
  'autoMemory': instance.autoMemory,
  'useBetterGPU': instance.useBetterGPU,
  'jvmParameter': instance.jvmParameter,
};

const _$LauncherTypeEnumMap = {
  LauncherType.mindustry: 'mindustry',
  LauncherType.copper: 'copper',
};
