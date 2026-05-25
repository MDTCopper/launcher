import 'dart:convert';
import 'dart:io';

import 'package:copperlauncher_main/core/app_constant.dart';
import 'package:copperlauncher_main/data/local_asset.dart';
import 'package:copperlauncher_main/util/format/byte_unit.dart';
import 'package:copperlauncher_main/util/io/run_time_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import '../util/app_paths.dart';
import '../util/io/token_encryptor.dart';

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
  );
  await config.save();
  debugPrint('已创建默认配置文件');
}

/// 应用配置类，存储的对象设置用late final然后在构造函数中进行默认赋值
@JsonSerializable()
class AppConfig {
  String version = appVersion;

  late final Setting setting;
  late final VersionOptions versionOptions;

  AppConfig({
    required this.version,
    Setting? setting,
    VersionOptions? versionOptions,
  }) {
    this.setting = setting ?? Setting.fromJson({});
    this.versionOptions = versionOptions ?? VersionOptions.fromJson({});
  }

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
  late final LaunchOptions launchOptions;

  ///加密存储
  @JsonKey(defaultValue: '')
  late String githubToken;

  @JsonKey(defaultValue: {})
  final Map<String, dynamic> customSetting; //这个用来存储一些不太用得着置变量，比如某些提示的开关记忆

  Setting({
    required this.githubToken,
    required this.customSetting,
    LaunchOptions? launchOptions,
  }) {
    this.launchOptions = launchOptions ?? LaunchOptions.fromJson({});
  }

  dynamic getCustomSetting(String key, dynamic defaultSetting) {
    final setting = customSetting[key] ??= defaultSetting;
    return setting;
  }

  factory Setting.fromJson(Map<String, dynamic> json) {
    final token = TokenEncryptor.decryptIfNeeded(json['githubToken']);
    json['githubToken'] = token;
    return _$SettingFromJson(json);
  }

  Map<String, dynamic> toJson() {
    final json = _$SettingToJson(this);
    json['githubToken'] = TokenEncryptor.encryptIfNeeded(json['githubToken']);
    return json;
  }
}

enum VersionIsolation { be, copper, mindustry }

enum GameWindowSizeSet { gameDefault, maximize, custom, fullScreen }

@JsonSerializable()
class WindowSize {
  @JsonKey(defaultValue: 1920)
  final int width;
  @JsonKey(defaultValue: 1080)
  final int height;

  WindowSize(this.width, this.height);

  factory WindowSize.fromJson(Map<String, dynamic> json) =>
      _$WindowSizeFromJson(json);

  Map<String, dynamic> toJson() => _$WindowSizeToJson(this);
}

class Memory {
  final int n;

  int get bytes => n;

  int get kb => n ~/ 1024;

  double get inKB => n / 1024;

  int get mb => n ~/ 1024 ~/ 1024;

  double get inMB => inKB / 1024;

  int get gb => n ~/ 1024 ~/ 1024 ~/ 1024;

  double get inGB => inMB / 1024;

  Memory operator +(Memory other) => Memory(bytes: other.n + n);

  Memory operator -(Memory other) => Memory(bytes: n - other.n);

  Memory operator *(num other) => Memory(bytes: (n * other).toInt());

  Memory operator /(num other) => Memory(bytes: (n / other).toInt());

  Memory operator ~/(num other) => Memory(bytes: n ~/ other);

  const Memory({int? bytes, int? kb, int? mb, int? gb})
    : n =
          (bytes ?? 0) +
          (kb ?? 0) * 1024 +
          (mb ?? 0) * 1024 * 1024 +
          (gb ?? 0) * 1024 * 1024 * 1024;
}

@JsonSerializable()
class LaunchOptions {
  late WindowSize customWindowSize;

  late final JavaOptions javaOptions;

  @JsonKey(defaultValue: {})
  final Set<VersionIsolation> versionIsolationSet;

  @JsonKey(defaultValue: GameWindowSizeSet.gameDefault)
  GameWindowSizeSet gameWindowSizeSet;

  @JsonKey(includeToJson: false, includeFromJson: false)
  Memory get ram => Memory(bytes: ramSize);

  set ram(Memory value) => ramSize = value.bytes;

  @JsonKey(defaultValue: gb)
  int ramSize;

  @JsonKey(defaultValue: true)
  bool autoRam;

  LaunchOptions({
    required this.versionIsolationSet,
    required this.gameWindowSizeSet,
    WindowSize? customWindowSize,
    JavaOptions? javaOptions,
    required this.ramSize,
    required this.autoRam,
  }) {
    this.customWindowSize = customWindowSize ?? WindowSize.fromJson({});
    this.javaOptions = javaOptions ?? JavaOptions.fromJson({});
  }

  factory LaunchOptions.fromJson(Map<String, dynamic> json) {
    final instance = _$LaunchOptionsFromJson(json);
    return instance;
  }

  Map<String, dynamic> toJson() => _$LaunchOptionsToJson(this);
}

@JsonSerializable()
class JavaOptions {
  ///{ 版本 : java路径 }
  @JsonKey(defaultValue: {})
  Map<String, String>? javas;

  @JsonKey(defaultValue: '')
  String selectedJava;

  @JsonKey(defaultValue: '')
  String jvmParameter;

  @JsonKey(defaultValue: true)
  bool useBetterGPU;

  JavaOptions({
    required this.javas,
    required this.selectedJava,
    required this.jvmParameter,
    required this.useBetterGPU,
  });

  factory JavaOptions.fromJson(Map<String, dynamic> json) =>
      _$JavaOptionsFromJson(json);

  Map<String, dynamic> toJson() => _$JavaOptionsToJson(this);
}

class PersonalizationOptions {
  //final themeColor;
  ThemeMode? themeMode; //空即为跟随系统
}

class DownloadOptions {}

@JsonSerializable()
class VersionOptions {
  String? selectedVersionId;

  late final List<VersionFold> versionFolds;

  @JsonKey(includeFromJson: false)
  Mindustry? _selectedVersion; //选中版本,直接引用

  VersionOptions({
    required this.selectedVersionId,
    required List<VersionFold>? versionFolds,
  }) {
    this.versionFolds =
        versionFolds ??
        [VersionFold(tag: '默认文件夹', path: AppPaths.versions, versions: [])];
  }

  set selectedVersion(Mindustry? mindustry) {
    if (mindustry == null) _selectedVersion == null;
    _selectedVersion = findVersion(mindustry!);
    selectedVersionId = _selectedVersion?.id;
  }

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
  Mindustry? get selectedVersion => _selectedVersion;

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
  late String tag;
  late final String path;
  final List<Mindustry> versions;

  VersionFold({required this.tag, required this.path, required this.versions});

  factory VersionFold.fromJson(Map<String, dynamic> json) =>
      _$VersionFoldFromJson(json);
  Map<String, dynamic> toJson() => _$VersionFoldToJson(this);
}
