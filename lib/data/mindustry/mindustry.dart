import 'package:copper_launcher/core/app_config.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;

import '../../util/app_paths.dart';
import '../../util/mindustry_version_era.dart';
import '../resource/mod.dart';

part 'mindustry.g.dart';

enum LauncherType { mindustry, copper }

/// 按 Copper 的规则算游戏版本的可比形式（2026-09-19 起**去掉了主版本号**）
///
/// - 正式版：`<大版本>.<构建号>`（`v159.7` → `159.7`、`v146` → `146`）
/// - BE：`0.<构建号>`（`0.24369`）
///
/// 解析不出数字时返回 null（未知，按「不判断」处理）
String? gameVersionOf({required String release, required bool isBe}) {
  final digits = release.trim().replaceFirst(RegExp('^v'), '');
  if (digits.isEmpty || double.tryParse(digits) == null) return null;
  return isBe ? '0.$digits' : digits;
}

///配置文件存储游戏信息的数据类
///游戏版本将以文件夹的形式存储，文件夹内是版本数据，可能包含游戏本体，不包含的将使用其他文件目录下载游戏本体，这样可以省出不必要的下载
@JsonSerializable()
class Mindustry {
  final String id;

  ///正式版 形如 v146
  ///
  /// be版 形如 28888
  ///
  /// 非 final：**Steam 版会被 Steam 就地更新**（jar 被换掉、版本号跟着变），
  /// 启动前的版本检查要把新版本号写回来（见 [SteamVersion.refresh]）
  String release;

  ///存储路径（记录形态：数据根内记相对、根外记绝对，见 [AppPaths.toStoredPath]）
  ///
  /// 非 final：启动时的路径归一化要把老的绝对路径洗成记录形态
  String path;

  ///游戏启动路径（记录形态，读文件请用 [resolvedJarPath]）

  String jarPath;

  ///用哪个加载器启动（官方 Jar / Copper 加载器）：可在版本设置里切换
  LauncherType launcher;
  final bool isBe;

  final DateTime addTime;

  /// 累计游玩时长；游戏退出时由启动任务累加本次时长
  Duration? playTime;

  /// 最近一次启动时间；游戏退出时由启动任务回写
  DateTime? lastLaunchTime;

  /// 玩家给游戏版本的标签
  String tag;
  bool like = false;

  /// 版本隔离
  bool isolation;

  /// 启动选用java路径
  String? java;

  /// 大版本号（version.properties 的 number，如 v8→8、v88→4）
  /// github tag 只有 build 号，大版本需读 jar 内的 version.properties；
  /// 下载时由 FileReader 解析填入，老配置缺失时启动会自动补读
  int? versionNumber;

  ///本体是不是**用户自己的文件**：「添加目录」扫描来的版本为 true
  ///
  ///下载 / 导入 / 变体建的版本都是 false（本体由启动器收进本体库）。
  ///删版本靠它决定动不动文件——光看路径会猜错：老布局（启动器早期下载的）与
  ///「添加目录」扫到的目录形态可以长得一模一样（`<fold>/<tag>/xxx.jar`）
  @JsonKey(defaultValue: false)
  bool bodyIsUserFile;

  ///走模组加载器时用的 loader jar（[launcher] 为 copper 时才有意义）
  ///
  ///记录形态：loader 收在 `<数据根>/copper_loader/` 里，多版本复用同一份
  String? launcherPath;

  ///是不是 **Steam 版**（本体里有 `version.properties: modifier=steam`）
  ///
  ///Steam 版要特化：本体在 Steam 安装目录里原地引用、数据目录绑安装目录下的
  ///`saves/`（见 [externalDataPath]）、启动前要查 Steam 有没有把它更新掉
  @JsonKey(defaultValue: false)
  bool steam;

  ///**外部数据目录**：不按「隔离 / 官方默认」两条口径走，固定用这份
  ///
  ///Steam 版专用：Steam 启动游戏时会传 `-Dmindustry.data.dir=<安装目录>/saves`
  ///（Steam 云同步的就是这份），启动器起 jar 时必须传同一个值，否则游戏会落到
  ///`%APPDATA%\Mindustry`、与 Steam 那份存档「看得见却不同步」。
  ///记录形态：绝对路径（在数据根外）
  String? externalDataPath;

  @JsonKey(includeToJson: false, includeFromJson: false)
  Memory? get memory {
    if (memorySize == null) return null;
    return Memory(bytes: memorySize);
  }

  set memory(Memory? value) => memorySize = value?.bytes;

  int? memorySize;

  bool? autoMemory;

  bool? useBetterGPU;

  String? jvmParameter;

  ///返回游戏版本号 (double)
  double get releaseDouble {
    if (!isBe) return double.parse(release.substring(1));
    return double.parse(release);
  }

  ///返回游戏版本号 (int)
  int get releaseInt {
    if (!isBe) return int.parse(release.substring(1).split('.').first);
    return int.parse(release.split('.').first);
  }

  ///游戏目录路径（[path] 的可用形态）
  String get resolvedPath => AppPaths.resolveStoredPath(path);

  ///游戏本体路径（[jarPath] 的可用形态）：读文件 / 起进程都用它
  String get resolvedJarPath => AppPaths.resolveStoredPath(jarPath);

  ///loader jar 的可用形态（没指定时为 null）
  String? get resolvedLauncherPath =>
      launcherPath == null ? null : AppPaths.resolveStoredPath(launcherPath!);

  ///是否通过模组加载器启动
  bool get isViaLoader => launcher == LauncherType.copper;

  ///Copper 加载器最低兼容的游戏版本（v146，对应过滤器里的 `>=146`）；
  ///拿不到适配表时用它兜底提醒
  static const int loaderMinRelease = 146;

  ///这个游戏版本能不能走 Copper 加载器
  bool get supportsLoader => isBe || releaseDouble >= loaderMinRelease;

  ///游戏版本的可比形式，按 Copper 的规则拼（见 [gameVersionOf]）
  String? get gameVersionString => gameVersionOf(release: release, isBe: isBe);

  ///游戏目录路径
  String get foldPath => p.join(resolvedPath, tag);

  ///本体是否在启动器本体库（[AppPaths.mindustrys]）里。
  ///
  ///库外的本体是**用户自己的文件**——「添加目录」扫描到的 jar、以及早期落在各自
  ///版本目录里的那份：启动器不复制，删版本时也不碰（只删记录）
  bool get isBodyInLibrary =>
      _isPathWithin(AppPaths.mindustrys, resolvedJarPath);

  ///本体就在版本自己的目录 `[foldPath]` 里：老布局的下载 / 导入落点，
  ///以及「添加目录」扫到的 `<目录>/<tag>/xxx.jar` 形态。
  ///
  ///两种都算**库外**——文件是用户自己的，删版本时本体和目录都要避开
  bool get isBodyInOwnFolder => _isPathWithin(foldPath, resolvedJarPath);

  ///游戏数据路径mods,saves,maps,schematics
  ///
  ///三种口径，优先外部绑定（Steam 版）：
  ///① [externalDataPath] 有值 → 就用它（Steam 版绑 Steam 安装目录下的 `saves/`）
  ///② 开了隔离 → `<版本目录>/data`
  ///③ 否则共享官方默认数据目录（`%APPDATA%\Mindustry` 那类）
  String get dataPath {
    if (hasExternalDataDir) {
      return AppPaths.resolveStoredPath(externalDataPath!);
    }
    if (isolation) return p.join(foldPath, 'data');
    return AppPaths.defaultGameData!; //默认存储位置
  }

  /// 数据目录绑在启动器外面（Steam 版那份），不按「隔离 / 官方默认」走
  bool get hasExternalDataDir =>
      externalDataPath != null && externalDataPath!.trim().isNotEmpty;

  /// 启动时的工作目录
  ///
  /// **Steam 版必须是 Steam 安装目录**：游戏里对 steam 版写死了
  /// `settings.setDataDirectory(Core.files.local("saves/"))`，`local` 是**相对工作目录**
  /// 解析的 ⇒ 工作目录不对，数据目录就落到别处（实测：用本体所在目录 `jre/` 起，
  /// 数据目录会变成 `jre/saves`，跟 Steam 那份完全不搭）。其余版本照旧用本体所在目录
  String get launchWorkingDirectory => steam && hasExternalDataDir
      ? p.dirname(AppPaths.resolveStoredPath(externalDataPath!))
      : p.dirname(resolvedJarPath);

  /// 启动时要不要把数据目录**告诉游戏**（`-Dmindustry.data.dir`）
  ///
  /// 隔离版要（目录在版本里）；绑了外置目录的非 Steam 版也要。
  /// **Steam 版不要**：它的数据目录由工作目录 + 游戏里写死的 `saves/` 决定，
  /// 这条参数传了也会被 `setDataDirectory` 盖掉（见 [launchWorkingDirectory]）
  bool get needsDataDirArg =>
      !isViaLoader && !steam && (isolation || hasExternalDataDir);

  ///显示用的版本号：Steam 版显示 `steam v160.5`，其余与 [release] 一致
  ///
  ///**只有显示层用它** —— [release] 必须保持 `v160.5` 这种纯数字形态，
  ///[releaseDouble] / [releaseInt] / [gameVersionOf] 与 loader 兼容门禁都靠它解析
  String get displayRelease => steam ? 'steam $release' : release;

  ///能否把资源导入到该版本：v126 之前游戏无法被指定数据目录（数据实际落在
  ///`<dataPath>/Mindustry`），导入的文件游戏读不到，因此这些版本不支持导入
  bool get supportsResourceImport =>
      MindustryVersionEra.supportsDataDirOverride(releaseDouble);

  String get modsPath => p.join(dataPath, 'mods');

  /// 某类模组该放哪个目录（Copper 原生的进 `<数据目录>/copper/mods`）
  String modsPathFor({required bool copper}) =>
      modsDirIn(dataPath, copper: copper);

  /// 模组目录（可能不止一个）：走加载器时 Copper 原生模组在
  /// `<数据目录>/copper/mods`，原版模组仍在 `<数据目录>/mods`，
  /// 加载器两个目录都扫；统计 / 扫描模组都要按这个列表来
  List<String> get modsPaths =>
      isViaLoader ? [modsPathFor(copper: true), modsPath] : [modsPath];

  String get savesPath => p.join(dataPath, 'saves');

  String get schematicsPath => p.join(dataPath, 'schematics');

  String get mapsPath => p.join(dataPath, 'maps');

  ///无论是否隔离，游戏崩溃日志都存储在默认游戏数据目录下crashes文件夹
  String get crashesPath => p.join(AppPaths.defaultGameData!, 'crashes');

  String get settingPath => p.join(dataPath, 'settings.bin');

  Mindustry({
    required this.id,
    required this.tag,
    required this.release,
    required this.path,
    required this.jarPath,
    required this.launcher,
    required this.isBe,
    required this.isolation,
    required this.addTime,
    this.playTime,
    this.lastLaunchTime,
    this.java,
    this.jvmParameter,
    this.useBetterGPU,
    this.memorySize,
    this.versionNumber,
    this.bodyIsUserFile = false,
    this.launcherPath,
    this.steam = false,
    this.externalDataPath,
  });

  factory Mindustry.fromJson(Map<String, dynamic> json) =>
      _$MindustryFromJson(json);

  Map<String, dynamic> toJson() => _$MindustryToJson(this);

  @override
  String toString() {
    return 'Mindustry{ id:$id , tag:$tag , build:$release }';
  }
}

///[child] 是否落在 [root] 目录内（Windows 路径大小写不敏感，统一小写后再比）
bool _isPathWithin(String root, String child) => p.isWithin(
  p.normalize(root).toLowerCase(),
  p.normalize(child).toLowerCase(),
);
