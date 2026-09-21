import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/data/mindustry_settings.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import '../util/app_paths.dart';
import '../util/io/token_encryptor.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';

part 'app_config.g.dart';

/// 用于存储应用的全局配置，更改完成后需调用`save`，同步配置文件
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
  //配置里记的启动器版本跟上当前构建：`AppConfig.version` 原先只在首次创建配置时
  //写入过一次（构造函数默认值），之后一直被文件里的旧值覆盖，永远停在那个版本
  config.version = appVersion;
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

  Timer? _saveTimer;

  Future<void> save() async {
    //计时器活跃就跳过这次的保存，等待计时器的延迟保存
    if (_saveTimer == null || !_saveTimer!.isActive) {
      if (kDebugMode) await saveAsJson();
      await saveAsBin();
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () async {
      if (kDebugMode) await saveAsJson();
      await saveAsBin();
    });
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
      debugPrint('配置保存失败：$e');
      addLog(.error, '配置保存失败：${removeNewlines('$e')}', tag: 'Version');
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
      debugPrint('配置保存失败：$e');
      addLog(.error, '配置保存失败：${removeNewlines('$e')}', tag: 'Version');
    }
  }
}

/// 启动器管理的游戏内用户，对应 Mindustry settings 中的玩家身份信息。
///
/// 启动游戏时，选中的用户会覆盖 settings 的 `name` / `uuid` / `color-0`。
@JsonSerializable()
class GameUser {
  /// 用户唯一标识（启动器本地生成，用于选中与区分用户）。
  @JsonKey(defaultValue: '')
  final String id;

  /// 游戏内玩家名（对应 settings `name`）。
  @JsonKey(defaultValue: '')
  String name;

  /// 玩家身份 UUID（对应 settings `uuid`）；界面不展示也不提供编辑。
  @JsonKey(defaultValue: '')
  String uuid;

  /// 玩家名字颜色（对应 settings `color-0`，arc `rgba8888` 编码 0xRRGGBBAA）。
  @JsonKey(defaultValue: 0)
  int color;

  GameUser({
    required this.id,
    required this.name,
    required this.uuid,
    this.color = 0,
  });

  factory GameUser.fromJson(Map<String, dynamic> json) =>
      _$GameUserFromJson(json);

  Map<String, dynamic> toJson() => _$GameUserToJson(this);
}

@JsonSerializable()
class Setting {
  late final LaunchOptions launchOptions;

  late final MindustrySettingsPatch mindustrySettings;
  @JsonKey(defaultValue: false)
  bool mindustrySettingsOverride;

  ///加密存储
  @JsonKey(defaultValue: '')
  late String githubToken;

  @JsonKey(defaultValue: {})
  final Map<String, dynamic> customSetting; //这个用来存储一些不太用得着置变量，比如某些提示的开关记忆

  ///已保存的游戏内用户列表（JSON 键沿用 `accounts`，避免老配置丢数据）。
  @JsonKey(name: 'accounts')
  late final List<GameUser> gameUsers;

  ///当前选中的用户 id，对应 [currentGameUser]（JSON 键沿用 `currentAccountId`）。
  @JsonKey(name: 'currentAccountId', defaultValue: '')
  String currentGameUserId;

  late final PersonalizationOptions personalizationOptions;

  late final DownloadOptions downloadOptions;

  late final ProxyOptions proxyOptions;

  late final MirrorOptions mirrorOptions;

  Setting({
    required this.githubToken,
    required this.customSetting,
    required this.mindustrySettingsOverride,
    LaunchOptions? launchOptions,
    MindustrySettingsPatch? mindustrySettings,
    PersonalizationOptions? personalizationOptions,
    DownloadOptions? downloadOptions,
    ProxyOptions? proxyOptions,
    MirrorOptions? mirrorOptions,
    List<GameUser>? gameUsers,
    this.currentGameUserId = '',
  }) {
    this.launchOptions = launchOptions ?? LaunchOptions.fromJson({});
    this.mindustrySettings = mindustrySettings ?? MindustrySettingsPatch();
    this.personalizationOptions =
        personalizationOptions ?? PersonalizationOptions.fromJson({});
    this.downloadOptions = downloadOptions ?? DownloadOptions.fromJson({});
    this.proxyOptions = proxyOptions ?? ProxyOptions.fromJson({});
    this.mirrorOptions = mirrorOptions ?? MirrorOptions.fromJson({});
    this.gameUsers = gameUsers ?? [];
  }

  ///当前选中的游戏内用户；未选择或用户不存在时返回 null。
  GameUser? get currentGameUser {
    for (final user in gameUsers) {
      if (user.id == currentGameUserId) return user;
    }
    return null;
  }

  ///选中 [user] 为当前游戏内用户。
  void selectGameUser(GameUser user) {
    currentGameUserId = user.id;
  }

  dynamic getCustomSetting(String key, dynamic defaultSetting) {
    final setting = customSetting[key] ??= defaultSetting;
    return setting;
  }

  factory Setting.fromJson(Map<String, dynamic> json) {
    var token = json['githubToken'];
    if (token is String && token.isNotEmpty) {
      token = TokenEncryptor.decryptIfNeeded(token);
      json['githubToken'] = token;
    }
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

class Memory implements Comparable<Memory> {
  final int memory;

  int get bytes => memory;

  int get kb => memory ~/ KB;

  double get inKB => memory / KB;

  int get mb => memory ~/ MB;

  double get inMB => memory / MB;

  int get gb => memory ~/ GB;

  double get inGB => memory / GB;

  Memory operator +(Memory other) => Memory(bytes: memory + other.memory);

  Memory operator -(Memory other) => Memory(bytes: memory - other.memory);

  Memory operator *(num other) => Memory(bytes: (memory * other).toInt());

  Memory operator /(num other) => Memory(bytes: (memory / other).toInt());

  Memory operator ~/(num other) => Memory(bytes: memory ~/ other);

  const Memory({int? bytes, int? kb, int? mb, int? gb})
    : memory = (bytes ?? 0) + (kb ?? 0) * KB + (mb ?? 0) * MB + (gb ?? 0) * GB;

  bool operator >(Memory o) => memory > o.memory;

  bool operator >=(Memory o) => memory >= o.memory;

  bool operator <(Memory o) => memory < o.memory;

  bool operator <=(Memory o) => memory <= o.memory;

  @override
  String toString() {
    String addtion = '';
    if (memory > 1 * 1024 * 1024 * 1024) {
      addtion = '(${(memory / 1024 / 1024 / 1024).toStringAsFixed(1)}GB)';
    } else if (memory > 1 * 1024 * 1024) {
      addtion = '(${(memory / 1024 / 1024).toStringAsFixed(1)}MB)';
    } else if (memory > 1 * 1024) {
      addtion = '(${(memory / 1024).toStringAsFixed(1)}KB)';
    }
    return 'Memory: $memory B $addtion';
  }

  @override
  int compareTo(Memory o) => o.memory - memory;
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
  Memory get memory => Memory(bytes: memorySize);

  set memory(Memory value) => memorySize = value.bytes;

  @JsonKey(defaultValue: 1 * GB)
  int memorySize;

  @JsonKey(defaultValue: true)
  bool autoMemory;

  LaunchOptions({
    required this.versionIsolationSet,
    required this.gameWindowSizeSet,
    WindowSize? customWindowSize,
    JavaOptions? javaOptions,
    required this.memorySize,
    required this.autoMemory,
  }) {
    this.customWindowSize = customWindowSize ?? WindowSize.fromJson({});
    this.javaOptions = javaOptions ?? JavaOptions.fromJson({});
  }

  /// 「游戏默认隔离设置」是否命中该版本——下载 / 导入创建版本时用它定 [Mindustry.isolation]
  ///
  /// 预览版对应 [VersionIsolation.be]，Copper 版本对应 [VersionIsolation.copper]，
  /// 其余正式版对应 [VersionIsolation.mindustry]；三项都不勾就是一律不隔离
  bool isIsolatedByDefault({
    required bool isBe,
    required LauncherType launcher,
  }) {
    if (isBe) return versionIsolationSet.contains(VersionIsolation.be);
    if (launcher == LauncherType.copper) {
      return versionIsolationSet.contains(VersionIsolation.copper);
    }
    return versionIsolationSet.contains(VersionIsolation.mindustry);
  }

  factory LaunchOptions.fromJson(Map<String, dynamic> json) {
    final instance = _$LaunchOptionsFromJson(json);
    return instance;
  }

  Map<String, dynamic> toJson() => _$LaunchOptionsToJson(this);
}

/// Java 运行时信息，存储 JavaFinder 查找到的 Java 安装信息
@JsonSerializable()
class JavaInfo {
  /// Java 可执行文件的完整路径
  final String path;

  /// Java 主版本号（如 8, 11, 17, 21），无法获取时为 null
  final int? version;

  /// 是否为有效的 Java 可执行文件
  @JsonKey(defaultValue: true)
  final bool isValid;

  const JavaInfo({required this.path, this.version, this.isValid = true});

  ///java 可执行文件的可用形态（[path] 是记录形态：数据根内记相对，见 [AppPaths]）
  String get resolvedPath => AppPaths.resolveStoredPath(path);

  factory JavaInfo.fromJson(Map<String, dynamic> json) =>
      _$JavaInfoFromJson(json);

  Map<String, dynamic> toJson() => _$JavaInfoToJson(this);

  @override
  bool operator ==(Object other) {
    if (other is JavaInfo) {
      return other.version == version || other.path == path;
    }
    return false;
  }

  @override
  int get hashCode => version.hashCode + path.hashCode;

  @override
  String toString() => 'Java[$version , Path $path]';
}

@JsonSerializable()
class JavaOptions {
  ///{ 版本 : java路径 }
  @JsonKey(defaultValue: [])
  List<JavaInfo> javas;

  @JsonKey(defaultValue: 'auto')
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

enum ThemeColor { copper, titanium, thorium, plastanium }

///游戏启动后 Launcher 的行为（桌面端）
enum LauncherPostLaunchBehavior { none, tray }

@JsonSerializable()
class PersonalizationOptions {
  @JsonKey(defaultValue: false)
  bool navigationCollapse;
  @JsonKey(defaultValue: false)
  bool subNavigationCollapse;

  @JsonKey(defaultValue: ThemeMode.system)
  ThemeMode themeMode;

  @JsonKey(defaultValue: ThemeColor.copper)
  ThemeColor themeColor;

  ///游戏启动后 Launcher 的行为：无行为 / 收进系统托盘
  @JsonKey(defaultValue: LauncherPostLaunchBehavior.none)
  LauncherPostLaunchBehavior launcherPostLaunchBehavior;

  ///托盘模式下，游戏退出后是否自动恢复主窗口（默认恢复）
  @JsonKey(defaultValue: true)
  bool restoreWindowOnGameExit;

  ///多彩背景（流光层）：关闭后不渲染流光层，只留底色（低配 / 大窗口省性能）
  @JsonKey(defaultValue: true)
  bool colorfulBackground;

  ///主窗口关闭按钮的行为：直接退出 / 收进托盘
  @JsonKey(defaultValue: WindowCloseAction.exit)
  WindowCloseAction windowCloseAction;

  PersonalizationOptions({
    this.windowCloseAction = WindowCloseAction.exit,
    required this.themeMode,
    required this.themeColor,
    required this.navigationCollapse,
    required this.subNavigationCollapse,
    required this.launcherPostLaunchBehavior,
    required this.restoreWindowOnGameExit,
    this.colorfulBackground = true,
  });

  factory PersonalizationOptions.fromJson(Map<String, dynamic> json) =>
      _$PersonalizationOptionsFromJson(json);

  Map<String, dynamic> toJson() => _$PersonalizationOptionsToJson(this);
}

@JsonSerializable()
class DownloadOptions {
  DownloadOptions({
    required this.downloadPath,
    required this.speedLimitBytes,
    required this.maxTread,
  });

  @JsonKey(defaultValue: '')
  String downloadPath;

  ///下载限速（字节/秒）；<=0 表示不限速（默认）
  @JsonKey(defaultValue: 0)
  int speedLimitBytes;

  ///分块并发数上限
  @JsonKey(defaultValue: 8)
  int maxTread;

  Memory get speedLimit => Memory(bytes: speedLimitBytes);

  factory DownloadOptions.fromJson(Map<String, dynamic> json) =>
      _$DownloadOptionsFromJson(json);

  Map<String, dynamic> toJson() => _$DownloadOptionsToJson(this);
}

///代理方式
enum ProxyMode { system, custom, off }

@JsonSerializable()
class ProxyOptions {
  ProxyOptions({
    required this.mode,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  @JsonKey(defaultValue: ProxyMode.system)
  ProxyMode mode;

  @JsonKey(defaultValue: '')
  String host;

  @JsonKey(defaultValue: 0)
  int port;

  @JsonKey(defaultValue: '')
  String username;

  @JsonKey(defaultValue: '')
  String password;

  factory ProxyOptions.fromJson(Map<String, dynamic> json) =>
      _$ProxyOptionsFromJson(json);

  Map<String, dynamic> toJson() => _$ProxyOptionsToJson(this);
}

///github 镜像加速配置。
///
///主窗口关闭按钮的行为
enum WindowCloseAction {
  ///直接退出应用
  exit,

  ///点击关闭 → 隐藏主窗口收进托盘
  minimizeToTray,
}

///镜像使用策略
enum MirrorStrategy {
  ///优先官方源：直连 GitHub，失败（连接类错误）才回退镜像（默认，最省流量）
  githubFirst,

  ///优先镜像：GitHub 地址先走镜像，失败再回退官方源（校园网 / 直连不通时更快）
  mirrorFirst,

  ///只用官方源，完全不碰镜像
  githubOnly,
}

///预设节点（官方仓库 `remote/github_mirrors.hjson` + 从 github.akams.cn 拉取的
///节点）单独管理，不落 config；只有用户手动添加的 [customNodes] 存在这里，
///与预设节点分开。
@JsonSerializable()
class MirrorOptions {
  MirrorOptions({
    required this.enabled,
    required this.customNodes,
    required this.strategy,
  });

  ///是否启用镜像加速
  @JsonKey(defaultValue: true)
  bool enabled;

  ///用户自定义节点（完整前缀，如 `https://ghfast.top/`）。
  @JsonKey(defaultValue: [])
  List<String> customNodes;

  ///镜像使用策略：优先官方源 / 优先镜像 / 只用官方源
  @JsonKey(defaultValue: MirrorStrategy.githubFirst)
  MirrorStrategy strategy;

  factory MirrorOptions.fromJson(Map<String, dynamic> json) =>
      _$MirrorOptionsFromJson(json);

  Map<String, dynamic> toJson() => _$MirrorOptionsToJson(this);
}

@JsonSerializable()
class VersionOptions {
  String? selectedVersionId;

  late final List<VersionFold> versionFolds;

  @JsonKey(includeFromJson: false)
  Mindustry? _selectedVersion; //选中版本,直接引用

  @JsonKey(includeFromJson: false, includeToJson: false)
  final ValueNotifier<Mindustry?> selectedVersionNotifier = ValueNotifier(null);

  VersionOptions({
    required this.selectedVersionId,
    required List<VersionFold>? versionFolds,
  }) {
    this.versionFolds =
        versionFolds ??
        [
          VersionFold(
            tag: isDesktop ? '默认文件夹' : '默认分类',
            path: AppPaths.toStoredPath(AppPaths.versions),
            versions: [],
          ),
        ];
  }

  set selectedVersion(Mindustry? mindustry) {
    if (mindustry == null) {
      _selectedVersion = null;
      selectedVersionId = null;
    } else {
      _selectedVersion = findVersion(mindustry);
      selectedVersionId = _selectedVersion?.id;
    }
    selectedVersionNotifier.value = _selectedVersion;
  }

  /// 在配置里找 [mindustry] 对应的**当前**记录（同一个版本可能已经换了实例）
  ///
  /// 比较必须用**解析后**的路径：记录形态可能是相对（新规则）也可能还是绝对
  /// （老配置没迁移），直接比字符串会让「绝对路径的 fold + 相对路径的新版本」
  /// 永远对不上 → 选中被清成 null（2026-09-21 用户实测：新下载的版本选不中）
  Mindustry? findVersion(Mindustry mindustry) {
    // 先收窄到同一个目录：老记录里有非 UUID 的 id（如 `146`），跨 fold 可能重号
    final versionPath = AppPaths.resolveStoredPath(mindustry.path);
    for (final versionFold in versionFolds) {
      if (versionPath != AppPaths.resolveStoredPath(versionFold.path)) continue;
      for (final version in versionFold.versions) {
        if (version.id == mindustry.id) return version;
      }
    }

    // 路径对不上（数据根搬过、fold 记的还是老绝对路径）时退一步只按 id 找
    for (final versionFold in versionFolds) {
      for (final version in versionFold.versions) {
        if (version.id == mindustry.id) return version;
      }
    }
    return null;
  }

  /// 统一删除版本：退出所有折叠中该版本的记录，并把 jarPath 引用数≥2
  /// （同一 jar 被多个版本共享）时保留 jar 本体。
  ///
  /// 本体删不删看**来源**（`Mindustry.bodyIsUserFile`）：「添加目录」扫描来的是
  /// 用户自己的文件，只删记录、不碰文件与目录；下载 / 导入 / 变体建的归启动器管，
  /// 再按位置确认一下（在本体库里或版本目录里）才动文件——老布局与扫描到的目录
  /// 形态可以长得一样，光看路径会猜错。
  ///
  /// 版本自己的目录（隔离的 mods / saves / 地图 / 蓝图等就在里面）跟着删，与确认
  /// 弹窗的承诺一致。
  ///
  /// 共享检查基于当前配置中的全部版本（跨 fold 统计）。返回 `true` 表示
  /// 配置删除成功；若唯一引用且 jar 删除失败返回 `false`（记录已移除，调用方提示）。
  Future<bool> deleteVersion(Mindustry version) async {
    // 1. 移除所有折叠中的该版本记录
    for (final fold in versionFolds) {
      fold.versions.removeWhere((v) => v.id == version.id);
    }

    // 2. 若被删版本正是当前选中：清空选中（含 notifier 同步）
    if (selectedVersionId == version.id) {
      selectedVersionId = null;
      _selectedVersion = null;
      selectedVersionNotifier.value = null;
    }

    // 3. jar 仍被其它版本引用（共享本体，变体常见）→ 只删记录，本体留着；
    //    版本目录照删（里面是它自己的隔离数据），但本体就躺在里面时不动目录
    final stillReferenced = versionFolds
        .expand((fold) => fold.versions)
        .any(
          (v) =>
              AppPaths.resolveStoredPath(v.jarPath) ==
              AppPaths.resolveStoredPath(version.jarPath),
        );
    if (stillReferenced) {
      addLog(
        .info,
        '删除版本 [${version.tag}]：游戏本体仍被其它版本引用，保留 ${version.resolvedJarPath}',
        tag: 'Version',
      );
      await _deleteVersionFolder(version, isBodyStillReferenced: true);
      return true;
    }

    // 4. 本体：扫来的是用户自己的文件，一律不动；启动器放的再按位置确认
    final canDeleteBody =
        !version.bodyIsUserFile &&
        (version.isBodyInLibrary || version.isBodyInOwnFolder);
    if (canDeleteBody) {
      final jar = File(version.resolvedJarPath);
      if (!await jar.exists()) {
        addLog(.info, '删除版本 [${version.tag}]：游戏本体已不存在，只删记录', tag: 'Version');
      } else {
        try {
          await jar.delete();
          addLog(
            .info,
            '删除版本 [${version.tag}]：已删除游戏本体 ${version.resolvedJarPath}',
            tag: 'Version',
          );
        } catch (error) {
          addLog(
            .error,
            '删除版本 [${version.tag}]：游戏本体删除失败 ${version.resolvedJarPath}，${removeNewlines('$error')}',
            tag: 'Version',
          );
          return false;
        }
      }
    } else {
      addLog(
        .info,
        '删除版本 [${version.tag}]：游戏本体是用户文件，只删记录（${version.resolvedJarPath}）',
        tag: 'Version',
      );
    }

    // 5. 版本自己的目录跟着删（隔离数据在 `<fold>/<tag>/data` 下）
    await _deleteVersionFolder(version, isBodyStillReferenced: false);
    return true;
  }

  /// 删掉版本自己的目录 `<fold>/<tag>`
  ///
  /// 两种情况不动目录：本体是用户自己的文件（扫来的版本，目录也在他的地盘里）、
  /// 本体就躺在目录里且还被别的版本引用（删了会连累那个版本的共享本体）。
  /// 其余要「目录里放着自己的本体」或「隔离且 `data` 真的存在」才删 ——
  /// 非隔离又没有本体在里面的目录不动，可能是用户自己的同名文件夹
  Future<void> _deleteVersionFolder(
    Mindustry version, {
    required bool isBodyStillReferenced,
  }) async {
    if (version.bodyIsUserFile) {
      addLog(
        .info,
        '删除版本 [${version.tag}]：游戏本体是用户文件，版本目录不动（${version.foldPath}）',
        tag: 'Version',
      );
      return;
    }
    if (isBodyStillReferenced && version.isBodyInOwnFolder) {
      addLog(
        .info,
        '删除版本 [${version.tag}]：游戏本体在版本目录里且仍被引用，目录不动（${version.foldPath}）',
        tag: 'Version',
      );
      return;
    }
    // 目录里只有这个版本的本体（老布局）→ 本体刚清掉，空目录一起收；
    // 隔离版本则要数据目录真的存在（那是启动器 / 游戏写进去的）
    final isFolderOwned =
        version.isBodyInOwnFolder ||
        (version.isolation && await Directory(version.dataPath).exists());
    if (!isFolderOwned) return;

    final folder = Directory(version.foldPath);
    if (!await folder.exists()) return;

    try {
      await folder.delete(recursive: true);
      addLog(
        .info,
        '删除版本 [${version.tag}]：已删除版本目录 ${version.foldPath}',
        tag: 'Version',
      );
    } catch (error) {
      // 目录没删掉不算删除失败：记录与本体都已处理，这里只提示残留
      addLog(
        .warning,
        '删除版本 [${version.tag}]：版本目录删除失败 ${version.foldPath}，${removeNewlines('$error')}',
        tag: 'Version',
      );
    }
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
    instance.selectedVersionNotifier.value = mindustry;
    return instance;
  }
  Map<String, dynamic> toJson() => _$VersionOptionsToJson(this);
}

@JsonSerializable()
class VersionFold {
  late String tag;

  ///分类目录（记录形态：数据根内记相对、根外记绝对，读目录请用 [resolvedPath]）
  late final String path;

  final List<Mindustry> versions;

  VersionFold({required this.tag, required this.path, required this.versions});

  ///分类目录的可用形态
  String get resolvedPath => AppPaths.resolveStoredPath(path);

  factory VersionFold.fromJson(Map<String, dynamic> json) =>
      _$VersionFoldFromJson(json);
  Map<String, dynamic> toJson() => _$VersionFoldToJson(this);
}
