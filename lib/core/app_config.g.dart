// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppConfig _$AppConfigFromJson(Map<String, dynamic> json) => AppConfig(
  version: json['version'] as String,
  setting:
      json['setting'] == null
          ? null
          : Setting.fromJson(json['setting'] as Map<String, dynamic>),
  versionOptions:
      json['versionOptions'] == null
          ? null
          : VersionOptions.fromJson(
            json['versionOptions'] as Map<String, dynamic>,
          ),
);

Map<String, dynamic> _$AppConfigToJson(AppConfig instance) => <String, dynamic>{
  'version': instance.version,
  'setting': instance.setting,
  'versionOptions': instance.versionOptions,
};

Setting _$SettingFromJson(Map<String, dynamic> json) => Setting(
  githubToken: json['githubToken'] as String? ?? '',
  customSetting: json['customSetting'] as Map<String, dynamic>? ?? {},
  launchOptions:
      json['launchOptions'] == null
          ? null
          : LaunchOptions.fromJson(
            json['launchOptions'] as Map<String, dynamic>,
          ),
);

Map<String, dynamic> _$SettingToJson(Setting instance) => <String, dynamic>{
  'launchOptions': instance.launchOptions,
  'githubToken': instance.githubToken,
  'customSetting': instance.customSetting,
};

WindowSize _$WindowSizeFromJson(Map<String, dynamic> json) => WindowSize(
  (json['width'] as num?)?.toInt() ?? 1920,
  (json['height'] as num?)?.toInt() ?? 1080,
);

Map<String, dynamic> _$WindowSizeToJson(WindowSize instance) =>
    <String, dynamic>{'width': instance.width, 'height': instance.height};

LaunchOptions _$LaunchOptionsFromJson(Map<String, dynamic> json) =>
    LaunchOptions(
      versionIsolationSet:
          (json['versionIsolationSet'] as List<dynamic>?)
              ?.map((e) => $enumDecode(_$VersionIsolationEnumMap, e))
              .toSet() ??
          {},
      gameWindowSizeSet:
          $enumDecodeNullable(
            _$GameWindowSizeSetEnumMap,
            json['gameWindowSizeSet'],
          ) ??
          GameWindowSizeSet.gameDefault,
      customWindowSize:
          json['customWindowSize'] == null
              ? null
              : WindowSize.fromJson(
                json['customWindowSize'] as Map<String, dynamic>,
              ),
      javaOptions:
          json['javaOptions'] == null
              ? null
              : JavaOptions.fromJson(
                json['javaOptions'] as Map<String, dynamic>,
              ),
      memorySize: (json['memorySize'] as num?)?.toInt() ?? 1073741824,
      autoMemory: json['autoMemory'] as bool? ?? true,
    );

Map<String, dynamic> _$LaunchOptionsToJson(
  LaunchOptions instance,
) => <String, dynamic>{
  'customWindowSize': instance.customWindowSize,
  'javaOptions': instance.javaOptions,
  'versionIsolationSet':
      instance.versionIsolationSet
          .map((e) => _$VersionIsolationEnumMap[e]!)
          .toList(),
  'gameWindowSizeSet': _$GameWindowSizeSetEnumMap[instance.gameWindowSizeSet]!,
  'memorySize': instance.memorySize,
  'autoMemory': instance.autoMemory,
};

const _$VersionIsolationEnumMap = {
  VersionIsolation.be: 'be',
  VersionIsolation.copper: 'copper',
  VersionIsolation.mindustry: 'mindustry',
};

const _$GameWindowSizeSetEnumMap = {
  GameWindowSizeSet.gameDefault: 'gameDefault',
  GameWindowSizeSet.maximize: 'maximize',
  GameWindowSizeSet.custom: 'custom',
  GameWindowSizeSet.fullScreen: 'fullScreen',
};

JavaOptions _$JavaOptionsFromJson(Map<String, dynamic> json) => JavaOptions(
  javas:
      (json['javas'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      {},
  selectedJava: json['selectedJava'] as String? ?? '',
  jvmParameter: json['jvmParameter'] as String? ?? '',
  useBetterGPU: json['useBetterGPU'] as bool? ?? true,
);

Map<String, dynamic> _$JavaOptionsToJson(JavaOptions instance) =>
    <String, dynamic>{
      'javas': instance.javas,
      'selectedJava': instance.selectedJava,
      'jvmParameter': instance.jvmParameter,
      'useBetterGPU': instance.useBetterGPU,
    };

VersionOptions _$VersionOptionsFromJson(Map<String, dynamic> json) =>
    VersionOptions(
      selectedVersionId: json['selectedVersionId'] as String?,
      versionFolds:
          (json['versionFolds'] as List<dynamic>?)
              ?.map((e) => VersionFold.fromJson(e as Map<String, dynamic>))
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
