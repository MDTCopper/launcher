import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/steam_library.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Steam 版在启动器里的**记录形态**（特化处理都在这儿）
///
/// 与下载 / 导入来的版本有三点不同：
/// ① 本体是 Steam 安装目录里的 `jre/desktop.jar`，**原地引用**（[Mindustry.bodyIsUserFile]）
/// ② 数据目录**绑 Steam 安装目录下的 `saves/`**（[Mindustry.externalDataPath]），
///    与 Steam 自己启动时用的是同一份 —— Steam 云同步的也是它
/// ③ 它是**一条就地刷新的记录**：Steam 更新会把 jar 覆盖掉、旧 build 的文件就没了，
///    所以不按 build 各占一条，只在启动前把新版本号写回（见 [refresh]）
///
/// 「认目录 → 建记录」与「读本体 → 核版本」两段逻辑都做成了**不依赖全局配置的纯函数**
/// （[findByJar] / [foldFor] / [pickTag] / [buildRecord] / [applySteamShape] / [probe]），
/// 只有 [addOrRefresh] 与 [refresh] 落盘 —— 这样用例不用碰 `config`
class SteamVersion {
  SteamVersion._();

  /// 默认 tag：不带 build —— Steam 更新后同一条记录继续用，列表里靠
  /// [Mindustry.displayRelease]（`steam v160.5`）看具体版本
  static const defaultTag = 'Mindustry Steam Build';

  /// Steam 版专用分类的名字（分类路径指向 Steam 安装目录）
  static const foldTag = 'Steam';

  /// 把检测到的 Steam 安装加进配置：**已存在就归一到 Steam 形态并刷新**
  ///
  /// 「已存在」认的是本体路径 —— 早先用「添加目录」把 Steam 安装目录扫进来的那条
  /// 记录也会被认出来（Steam 标记、数据目录、版本号都补齐），不会多出一条重复版本
  static Future<SteamVersionResult> addOrRefresh({
    required SteamInstall install,
  }) async {
    final folds = config.versionOptions.versionFolds;

    final existing = findByJar(folds: folds, jarPath: install.jarPath);
    if (existing != null) {
      final change = applySteamShape(version: existing, install: install);
      await config.save();
      return SteamVersionResult(
        version: existing,
        created: false,
        change: change,
      );
    }

    final fold = foldFor(folds: folds, installPath: install.installPath);
    final version = buildRecord(
      install: install,
      fold: fold,
      tag: pickTag(usedTags: usedTags(folds)),
    );
    fold.versions.add(version);
    await config.save();
    addLog(
      .info,
      '加入 Steam 版 [${version.tag}]：本体 ${install.jarPath}，'
      '数据目录 ${install.dataPath}（Steam 云同步的就是这份）',
      tag: 'Steam',
    );
    return SteamVersionResult(version: version, created: true);
  }

  /// 启动前的版本检查：Steam 把本体更新过了就把新版本号写回记录并落盘
  ///
  /// 返回 null 表示**什么都没变**（调用方据此决定要不要发通知）
  static Future<SteamVersionChange?> refresh(Mindustry version) async {
    final change = await probe(version);
    if (change == null) return null;
    await config.save();
    return change;
  }

  /// 读本体核一次版本（会改 [version]，**不落盘**）
  ///
  /// 不是 Steam 版、本体不在、读不出来都返回 null
  static Future<SteamVersionChange?> probe(Mindustry version) async {
    if (!version.steam) return null;

    final jar = File(version.resolvedJarPath);
    if (!jar.existsSync()) return null; // 本体没了：由启动流程报「缺少本体」

    try {
      final reader = await FileReader.fromPath(jar.path);
      final meta = reader.mindustry;
      if (meta == null) return null;

      final build = meta.build.trim();
      final change = SteamVersionChange(
        oldRelease: version.release,
        newRelease: build.isEmpty ? version.release : 'v$build',
        oldVersionNumber: version.versionNumber,
        newVersionNumber: int.tryParse(meta.version.trim()),
        newModifier: meta.type,
      );

      // 数据目录绑的是 Steam 安装目录里的 saves/：Steam 更新不动它，但记录里缺了就补上
      ensureDataBinding(version, installPath: _installPathOf(version));

      if (change.isEmpty) return null;

      version
        ..release = change.newRelease
        ..versionNumber = change.newVersionNumber ?? version.versionNumber;
      addLog(
        .info,
        'Steam 版已更新：[${version.tag}] ${change.oldRelease} → ${change.newRelease}'
        '${change.isModifierChanged ? '（本体不再是 Steam 版：${change.newModifier}）' : ''}',
        tag: 'Steam',
      );
      return change;
    } catch (error) {
      addLog(.warning, '读 Steam 版本体失败：$error', tag: 'Steam');
      return null;
    }
  }

  /// 认一个目录是不是 Steam 版 Mindustry（「添加目录」也可以用它判断）
  static Future<SteamInstall?> inspect(String path) =>
      SteamLibrary.inspect(path);

  // ── 纯逻辑（不碰全局配置，用例直接调） ──

  /// 按本体路径找已有记录；找不到返回 null
  static Mindustry? findByJar({
    required Iterable<VersionFold> folds,
    required String jarPath,
  }) {
    final normalized = p.normalize(jarPath).toLowerCase();
    for (final fold in folds) {
      for (final version in fold.versions) {
        if (p.normalize(version.resolvedJarPath).toLowerCase() == normalized) {
          return version;
        }
      }
    }
    return null;
  }

  /// 「Steam」分类：同名的或路径就是安装目录的都用现成的，否则建一个加进去
  ///
  /// 分类路径指向 Steam 安装目录是有意的 —— 它本来就是一个游戏目录，
  /// 与「添加目录」扫进来的形态一致；删这个分类**只删记录**，不碰磁盘文件
  static VersionFold foldFor({
    required List<VersionFold> folds,
    required String installPath,
  }) {
    final normalized = p.normalize(installPath).toLowerCase();
    for (final fold in folds) {
      final foldPath = p.normalize(fold.resolvedPath).toLowerCase();
      if (fold.tag == foldTag || foldPath == normalized) return fold;
    }

    final fold = VersionFold(
      tag: foldTag,
      path: AppPaths.toStoredPath(p.normalize(installPath)),
      versions: [],
    );
    folds.add(fold);
    addLog(.info, '新建 Steam 分类：${fold.resolvedPath}', tag: 'Steam');
    return fold;
  }

  /// 全部已占用的 tag（查重用）
  static Set<String> usedTags(Iterable<VersionFold> folds) => {
    for (final fold in folds)
      for (final version in fold.versions) version.tag,
  };

  /// tag 查重：默认 tag 被占了（用户自己建的版本叫这个名）就加序号
  static String pickTag({
    required Iterable<String> usedTags,
    String base = defaultTag,
  }) {
    final used = usedTags.toSet();
    if (!used.contains(base)) return base;
    var index = 2;
    while (used.contains('$base($index)')) {
      index++;
    }
    return '$base($index)';
  }

  /// 造一条 Steam 版记录（本体原地引用、数据目录绑 Steam 那份）
  static Mindustry buildRecord({
    required SteamInstall install,
    required VersionFold fold,
    required String tag,
  }) => Mindustry(
    id: const Uuid().v4(),
    tag: tag,
    release: install.release,
    path: AppPaths.toStoredPath(fold.resolvedPath),
    jarPath: AppPaths.toStoredPath(install.jarPath),
    launcher: LauncherType.mindustry,
    isBe: install.isBe,
    // Steam 版的数据在外置目录里，隔离与否对它没有意义（保持 false，别建空目录）
    isolation: false,
    addTime: DateTime.now(),
    versionNumber: install.versionNumber,
    // 本体是 Steam 的：启动器不复制、删版本也不碰
    bodyIsUserFile: true,
    steam: true,
    externalDataPath: AppPaths.toStoredPath(install.dataPath),
  );

  /// 把一条已有记录归一到 Steam 形态（不动它的 tag 与所在分类），返回变了什么
  static SteamVersionChange applySteamShape({
    required Mindustry version,
    required SteamInstall install,
  }) {
    final change = SteamVersionChange(
      oldRelease: version.release,
      newRelease: install.release,
      oldVersionNumber: version.versionNumber,
      newVersionNumber: install.versionNumber,
    );

    version
      ..steam = true
      ..bodyIsUserFile = true
      ..isolation = false
      ..release = install.release
      ..versionNumber = install.versionNumber ?? version.versionNumber
      ..jarPath = AppPaths.toStoredPath(install.jarPath)
      ..externalDataPath = AppPaths.toStoredPath(install.dataPath);
    return change;
  }

  /// 数据目录绑定缺失 / 指向不存在的地方时，按安装目录重新绑一次
  static void ensureDataBinding(Mindustry version, {String? installPath}) {
    if (installPath == null) return;

    final expected = p.join(installPath, SteamLibrary.dataFolderName);
    final current = version.externalDataPath;
    final usable =
        current != null &&
        current.trim().isNotEmpty &&
        Directory(AppPaths.resolveStoredPath(current)).existsSync();
    if (usable) return;

    version.externalDataPath = AppPaths.toStoredPath(expected);
    addLog(.info, 'Steam 版数据目录重新绑定：$expected', tag: 'Steam');
  }

  /// 从记录里推 Steam 安装目录：优先用数据目录的上一级，其次本体 jar 的上一级
  /// （本体通常在 `<安装目录>/jre/desktop.jar`）
  static String? _installPathOf(Mindustry version) {
    final external = version.externalDataPath;
    if (external != null && external.trim().isNotEmpty) {
      return p.dirname(AppPaths.resolveStoredPath(external));
    }
    final jar = version.resolvedJarPath;
    if (jar.isEmpty) return null;
    final parent = p.dirname(jar);
    return p.basename(parent).toLowerCase() == 'jre'
        ? p.dirname(parent)
        : parent;
  }
}

/// [SteamVersion.addOrRefresh] 的结果
class SteamVersionResult {
  const SteamVersionResult({
    required this.version,
    required this.created,
    this.change,
  });

  final Mindustry version;

  /// true = 新加的；false = 认出了已有记录并刷新
  final bool created;

  /// 刷新时变了什么（新建时为 null）
  final SteamVersionChange? change;
}

/// Steam 版记录的一次变化
class SteamVersionChange {
  const SteamVersionChange({
    required this.oldRelease,
    required this.newRelease,
    this.oldVersionNumber,
    this.newVersionNumber,
    this.oldModifier = 'steam',
    this.newModifier = 'steam',
  });

  final String oldRelease;
  final String newRelease;
  final int? oldVersionNumber;
  final int? newVersionNumber;
  final String oldModifier;
  final String newModifier;

  bool get isVersionChanged =>
      oldRelease != newRelease || oldVersionNumber != newVersionNumber;

  /// 本体不再是 Steam 版（被换成别的构建）—— 要提醒用户
  bool get isModifierChanged => oldModifier != newModifier;

  bool get isEmpty => !isVersionChanged && !isModifierChanged;

  /// 给通知用的一句话
  String get description {
    if (isModifierChanged) {
      return '本体已不是 Steam 版（$newModifier），数据目录仍绑在 Steam 那份';
    }
    return 'Steam 版已更新：$oldRelease → $newRelease';
  }
}
