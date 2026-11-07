import '../../data/net/data_index/data_index_models.dart';
import '../../data/net/mindustry/mindustry_release.dart';
import '../mod_install.dart';

/// 更新检查覆盖的内容类型
///
/// `bridge` / `javaRuntime` 是预留位：接上对应的检查实现后直接进同一份报告
enum UpdateContentKind { mod, gameVersion, loader, bridge, javaRuntime }

/// 更新检查结果里的一条：各内容类型共用的只读信息
abstract interface class ContentUpdate {
  UpdateContentKind get kind;

  /// 展示名
  String get name;

  /// 本机当前版本；没装过为 null
  String? get installedVersion;

  /// 能拿到的最新版本（有更新时就是建议更新到的那个版本）
  String get latestVersion;

  /// 值不值得更新：下载 / 替换动作只对 true 的条目提供
  bool get hasUpdate;
}

/// 一个已装模组的更新检查结果
///
/// 模组列表页也可以拿它表达「已安装」状态：只有 [installed] 时是「已安装且最新」，
/// 加上 [targetVersion] 才是「有更新」
class ModUpdate implements ContentUpdate {
  const ModUpdate({
    required this.entry,
    required this.installed,
    this.targetVersion,
  });

  /// 数据索引里的模组条目（远端最新版本信息）
  final DataIndexModEntry entry;

  /// 本机已装的那份
  final InstalledModFile installed;

  /// 与本机游戏版本兼容、值得装的最新一版；没有可更新版本时为 null
  final DataIndexModVersion? targetVersion;

  @override
  UpdateContentKind get kind => UpdateContentKind.mod;

  @override
  String get name => entry.name;

  @override
  String? get installedVersion =>
      installed.version.isEmpty ? null : installed.version;

  @override
  String get latestVersion => targetVersion?.modVersion ?? entry.version;

  @override
  bool get hasUpdate => targetVersion != null;
}

/// 「更换版本」里的一款可选游戏版本
class GameVersionCandidate {
  const GameVersionCandidate({
    required this.release,
    required this.installed,
    required this.isLatest,
  });

  /// 远端这一版的完整信息（带下载资产）
  final MindustryRelease release;

  /// 本机已经装过同一版本
  final bool installed;

  /// 是不是这一族（正式版 / BE）远端最新的一版
  final bool isLatest;

  /// 版本 tag：正式版 `v160.7`，BE 是 build 号
  String get tag => release.tag;

  bool get isBe => release.isBe;
}

/// 游戏版本（Mindustry 正式版 / BE）的「更换版本」结果
///
/// 工具侧可以拿 [candidates] 列可选版本（默认最新，降级也在这里选）；[hasUpdate]
/// 只是给「可以更新」的提醒用，不提供自动替换
class GameVersionChange implements ContentUpdate {
  const GameVersionChange({
    required this.isBe,
    required this.installedVersion,
    required this.latestVersion,
    required this.hasUpdate,
    this.latestRelease,
    this.candidates = const [],
  });

  /// 是不是 BE（MindustryBuilds）版本
  final bool isBe;

  @override
  final String? installedVersion;

  /// 远端最新版本：正式版是 `v160.7`，BE 是 build 号
  @override
  final String latestVersion;

  @override
  final bool hasUpdate;

  /// 远端最新一版的完整信息（带下载资产），供「去下载」直接用
  final MindustryRelease? latestRelease;

  /// 这一族全部可选版本：远端版本、新在前，含本机已装的
  final List<GameVersionCandidate> candidates;

  @override
  UpdateContentKind get kind => UpdateContentKind.gameVersion;

  @override
  String get name => isBe ? 'Mindustry BE' : 'Mindustry 正式版';
}

/// Copper 加载器的更新检查结果
class LoaderUpdate implements ContentUpdate {
  const LoaderUpdate({
    required this.installedVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.hasUpdate,
  });

  @override
  final String? installedVersion;

  /// 远端最新 tag（如 `0.1.2`）
  @override
  final String latestVersion;

  /// 最新版桌面端 jar 的下载地址（按 tag 拼出来，见 `LoaderLibrary.desktopAssetUrlOf`）
  final String downloadUrl;

  @override
  final bool hasUpdate;

  @override
  UpdateContentKind get kind => UpdateContentKind.loader;

  @override
  String get name => 'Copper 加载器';
}

/// 全量更新检查报告：按内容类型分组；某一类失败不影响其他类
class UpdateReport {
  const UpdateReport({
    this.mods = const [],
    this.gameVersions = const [],
    this.loaders = const [],
    this.checkedModCount = 0,
    this.skippedModCount = 0,
    this.errors = const {},
  });

  /// 已装模组的检查结果：已安装的都在，带 [ModUpdate.hasUpdate]
  final List<ModUpdate> mods;

  final List<GameVersionChange> gameVersions;

  final List<LoaderUpdate> loaders;

  /// 实际检查过的已装模组数（跳过的是索引里查不到的本地模组）
  final int checkedModCount;

  final int skippedModCount;

  /// 某类内容检查失败的原因（键是内容类型）
  final Map<UpdateContentKind, String> errors;

  /// 所有类型的检查结果，按模组 → 游戏版本 → 加载器排列
  Iterable<ContentUpdate> get all sync* {
    yield* mods;
    yield* gameVersions;
    yield* loaders;
  }

  /// 有更新的条目
  Iterable<ContentUpdate> get updates =>
      all.where((update) => update.hasUpdate);

  bool get hasUpdates => updates.isNotEmpty;

  int get updateCount => updates.length;

  /// 有没有任何一类检查失败
  bool get hasErrors => errors.isNotEmpty;
}
