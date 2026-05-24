import 'dart:convert';
import 'dart:io';

import 'package:copperlauncher_main/core/app_constant.dart';
import 'package:copperlauncher_main/data/local_asset.dart';
import 'package:copperlauncher_main/util/io/run_time_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import '../util/app_paths.dart';

part 'app_config.g.dart';

/// 用于存储应用的全局配置，更改完成后需调用[save]，同步配置文件
late AppConfig config;

Future<void> initAppConfig() async {
  final File file;

  if (kDebugMode) {
    file = File(AppPaths.configJson);
    if (!await file.exists()) {
      await createAppConfig();
    }
    final jsonStr = await file.readAsString();
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    config = AppConfig.fromJson(json);
  } else {
    file = File(AppPaths.configBin);
    if (!await file.exists()) {
      await createAppConfig();
    }
    final encodedData = await file.readAsString();
    config = AppConfig.fromJson(
      jsonDecode(utf8.decode(base64Decode(encodedData))),
    );
  }
  await config.save();
}

Future<void> checkGameVersionExists() async {
  //todo 启动时，检查版本文件是否存在，若不存在，删除版本配置文件，并在软件启动完成后给用户反馈说明
}

Future<void> createAppConfig() async {
  final config = AppConfig(
    version: appVersion, // 默认版本号
    setting: Setting(customSetting: {}, githubToken: ''),
    versionOptions: VersionOptions(
      selectedVersionId: null,
      versionFolds: [], // 初始为空列表 todo 后续做一个版本列表检测
    ),
  );
  await config.save();
  debugPrint('已创建默认配置文件');
}

@JsonSerializable()
class AppConfig {
  String version;
  Setting setting;
  VersionOptions versionOptions;

  AppConfig({
    required this.version,
    required this.setting,
    required this.versionOptions,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);

  Map<String, dynamic> toJson() => _$AppConfigToJson(this);

  @override
  String toString() => jsonEncode(toJson());

  Future<void> save() async {
    if (kDebugMode) await saveAsJson();
    await saveAsBin();
  }

  /// 保存配置为JSON文件,debug用
  Future<void> saveAsJson() async {
    try {
      final file = File(AppPaths.configJson);

      await file.parent.create(recursive: true);

      final formattedJson = JsonEncoder.withIndent(
        '  ',
      ).convert(toJson()); //格式化
      await file.writeAsString(formattedJson, flush: true);
    } catch (e) {
      debugPrint('配置保存失败: $e');
      RunTimeLog.add(RunTimeLogLogType.error, '配置保存失败: $e');
    }
  }

  /// 保存配置为二进制文件,防止被意外修改
  Future<void> saveAsBin() async {
    try {
      final file = File(AppPaths.configBin);

      await file.parent.create(recursive: true);

      String encodedData = base64Encode(utf8.encode(toString()));

      await file.writeAsString(encodedData, flush: true);
    } catch (e) {
      debugPrint('配置保存失败: $e');
      RunTimeLog.add(RunTimeLogLogType.error, '配置保存失败: $e');
    }
  }
}

@JsonSerializable()
class Setting {
  Setting({required this.githubToken, required this.customSetting});

  final Map<String, dynamic> customSetting; //这个用来存储一些不太用得着的设置变量，比如某些提示的开关记忆
  final String githubToken;

  dynamic getCustomSetting(String key, dynamic defaultSetting) {
    final setting = customSetting[key] ??= defaultSetting;
    return setting;
  }

  factory Setting.fromJson(Map<String, dynamic> json) =>
      _$SettingFromJson(json);
  Map<String, dynamic> toJson() => _$SettingToJson(this);
}

enum VersionIsolation { be, copper, mindustry }

enum GameWindowSizeSet { gameDefault, maximize, custom, fullScreen }

class LaunchOptions {
  Set<VersionIsolation>? versionIsolationSet;
  GameWindowSizeSet? gameWindowSizeSet;
  Size? customWindowSize;
  JavaOptions? javaOptions;
  int? ramSize;
  bool? autoRam;
}

class JavaOptions {
  Map<String, String>? javas; // {版本:java路径}
  String? selectedJava; //选中的java版本
  String? jvmParameter; //jvm参数
  bool? useBetterGPU;
  JavaOptions({this.javas});
}

class PersonalizationOptions {
  //final themeColor;
  ThemeMode? themeMode; //空即为跟随系统
}

class DownloadOptions {}

@JsonSerializable()
class VersionOptions {
  String? selectedVersionId;
  final List<VersionFold> versionFolds;

  Mindustry? findVersion(Mindustry mindustry) {
    for (final versionFold in versionFolds) {
      if (mindustry.path != versionFold.path) continue;
      for (final version in versionFold.versions) {
        if (version.id == mindustry.id) return version;
      }
    }
    return null;
  }

  @JsonKey(includeFromJson: false)
  Mindustry? _selectedVersion; //选中版本,直接引用

  set selectedVersion(Mindustry? mindustry) {
    if (mindustry == null) _selectedVersion == null;
    _selectedVersion = findVersion(mindustry!);
    selectedVersionId = _selectedVersion?.id;
  }

  @JsonKey(includeFromJson: false)
  Mindustry? get selectedVersion => _selectedVersion;

  VersionOptions({required this.selectedVersionId, required this.versionFolds});

  factory VersionOptions.fromJson(Map<String, dynamic> json) {
    final instance = _$VersionOptionsFromJson(json);
    Mindustry? mindustry;
    final versionFolds = instance.versionFolds;
    for (final versionFold in versionFolds) {
      for (final version in versionFold.versions) {
        if (version.id == instance.selectedVersionId) {
          mindustry = version;
          break;
        }
      }
      if (mindustry != null) break;
    }
    instance._selectedVersion = mindustry;
    return instance;
  }
  Map<String, dynamic> toJson() => _$VersionOptionsToJson(this);
}

@JsonSerializable()
class VersionFold {
  String tag;
  final String path;
  final List<Mindustry> versions;

  VersionFold({required this.tag, required this.path, required this.versions});

  factory VersionFold.fromJson(Map<String, dynamic> json) =>
      _$VersionFoldFromJson(json);
  Map<String, dynamic> toJson() => _$VersionFoldToJson(this);
}
