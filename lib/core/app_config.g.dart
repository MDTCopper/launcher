// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppConfig _$AppConfigFromJson(Map<String, dynamic> json) => AppConfig(
  version: json['version'] as String,
  setting: Setting.fromJson(json['setting'] as Map<String, dynamic>),
  versionOptions: VersionOptions.fromJson(
    json['versionOptions'] as Map<String, dynamic>,
  ),
);

Map<String, dynamic> _$AppConfigToJson(AppConfig instance) => <String, dynamic>{
  'version': instance.version,
  'setting': instance.setting,
  'versionOptions': instance.versionOptions,
};

Setting _$SettingFromJson(Map<String, dynamic> json) => Setting(
  githubToken: json['githubToken'] as String,
  customSetting: json['customSetting'] as Map<String, dynamic>,
);

Map<String, dynamic> _$SettingToJson(Setting instance) => <String, dynamic>{
  'customSetting': instance.customSetting,
  'githubToken': instance.githubToken,
};

VersionOptions _$VersionOptionsFromJson(Map<String, dynamic> json) =>
    VersionOptions(
      selectedVersionId: json['selectedVersionId'] as String?,
      versionFolds:
          (json['versionFolds'] as List<dynamic>)
              .map((e) => VersionFold.fromJson(e as Map<String, dynamic>))
              .toList(),
    );

Map<String, dynamic> _$VersionOptionsToJson(VersionOptions instance) =>
    <String, dynamic>{
      'selectedVersionId': instance.selectedVersionId,
      'versionFolds': instance.versionFolds,
    };

VersionFold _$VersionFoldFromJson(Map<String, dynamic> json) => VersionFold(
  tag: json['tag'] as String,
  path: json['path'] as String,
  versions:
      (json['versions'] as List<dynamic>)
          .map((e) => Mindustry.fromJson(e as Map<String, dynamic>))
          .toList(),
);

Map<String, dynamic> _$VersionFoldToJson(VersionFold instance) =>
    <String, dynamic>{
      'tag': instance.tag,
      'path': instance.path,
      'versions': instance.versions,
    };
