import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../data/models.dart';
import '../../data/net/data_index/data_index_client.dart';
import '../../util/format/string_cleaner.dart';
import '../../util/io/copper_io.dart';
import '../../util/io/file_reader.dart';
import '../../util/io/log.dart';
import '../../util/validate/windows_file_name_validator.dart';
import '../../util/version_strings.dart' as version_strings;
import '../mod_install.dart';
import 'update_models.dart';

/// 模组更新检查结果
class ModUpdateCheck {
  const ModUpdateCheck({
    this.mods = const [],
    this.checkedCount = 0,
    this.skippedCount = 0,
    this.error,
  });

  /// 已装模组逐条的检查结果（含「已是最新」的）
  final List<ModUpdate> mods;

  /// 索引里查得到、实际对比过的模组数
  final int checkedCount;

  /// 索引里查不到的本地模组数（私装 / 自编译，没有更新来源）
  final int skippedCount;

  /// 整类检查失败的原因（索引拉不到等）；非空时 [mods] 为空
  final String? error;
}

/// 「更换版本」里的一款可选模组版本
class ModVersionCandidate {
  const ModVersionCandidate({
    required this.version,
    required this.supportsGameVersion,
    required this.installed,
  });

  /// 远端这一版的完整信息（下载地址 / 体积 / 适配区间）
  final DataIndexModVersion version;

  /// 与目标游戏版本兼容
  final bool supportsGameVersion;

  /// 与本机已装版本相同
  final bool installed;

  String get tag => version.tag;

  String get modVersion => version.modVersion;
}

/// 模组更新：拿数据索引里的版本信息对比本机已装模组，并执行下载 / 替换
class ModUpdateService {
  /// 检查某个游戏版本（它自己的数据目录）里已装模组的更新
  ///
  /// 兼容性按该游戏版本号判定：优先挑「与它兼容的最新一版」，最新版不兼容时
  /// 退到更老的兼容版本；一条都不兼容或已是最新时不产生更新。
  static Future<ModUpdateCheck> checkInstalled({
    required Mindustry gameVersion,
    bool community = false,
    bool refresh = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final index = await DataIndexClient.loadModIndex(
      community: community,
      refresh: refresh,
    );
    if (index == null) {
      return const ModUpdateCheck(error: '模组索引拉取失败');
    }

    final installed = await scanInstalledMods(gameVersion.modsPaths);
    return checkInIndex(
      index: index,
      gameVersion: gameVersion.gameVersionString,
      installedMods: installed,
      refresh: refresh,
      onProgress: onProgress,
    );
  }

  /// 用已扫好的已装模组列表检查（模组页一次扫描后逐条查状态时复用）
  static Future<ModUpdateCheck> checkInIndex({
    required DataIndexModIndex index,
    required String? gameVersion,
    required List<InstalledModFile> installedMods,
    bool refresh = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final mods = <ModUpdate>[];
    final seenInternalNames = <String>{};
    var checked = 0;
    var skipped = 0;

    for (final installed in installedMods) {
      // 同一个模组在 mods/ 与 copper/mods/ 可能各有一份：更新时一起去重，
      // 检查按第一次出现的算
      if (!seenInternalNames.add(installed.internalName)) continue;

      final entry = await _matchEntry(
        index: index,
        installed: installed,
        refresh: refresh,
      );
      if (entry == null) {
        skipped++;
        continue;
      }

      checked++;
      onProgress?.call(checked, installedMods.length);

      final targetVersion = await _findTargetVersion(
        entry: entry,
        gameVersion: gameVersion,
        installedVersion: installed.version,
        refresh: refresh,
      );
      mods.add(
        ModUpdate(
          entry: entry,
          installed: installed,
          targetVersion: targetVersion,
        ),
      );
    }

    return ModUpdateCheck(
      mods: mods,
      checkedCount: checked,
      skippedCount: skipped,
    );
  }

  /// 给一份已装模组找索引条目
  ///
  /// 同一个内部名可能对应多个仓库（同一个模组被重新发布）：优先文件名里带仓库名、
  /// 其次本机版本号在那个仓库的版本列表里出现过的——免得把 A 仓库的版本装到
  /// B 仓库的模组上
  static Future<DataIndexModEntry?> _matchEntry({
    required DataIndexModIndex index,
    required InstalledModFile installed,
    bool refresh = false,
  }) async {
    final candidates = index.findAllByInternalName(installed.internalName);
    if (candidates.length <= 1) {
      return candidates.isEmpty ? null : candidates.single;
    }

    final fileName = p.basename(installed.path).toLowerCase();
    DataIndexModEntry? best;
    var bestScore = -1;
    for (final candidate in candidates) {
      var score = 0;
      final repoName = candidate.repo.toLowerCase().split('/').last;
      if (repoName.isNotEmpty && fileName.contains(repoName)) score += 2;

      if (sameModVersion(candidate.version, installed.version)) score += 2;

      final releasesPath = candidate.releasesPath;
      if (releasesPath != null) {
        final releases = await DataIndexClient.loadModReleases(
          releasesPath,
          refresh: refresh,
        );
        if (releases != null &&
            releases.versions.any(
              (version) =>
                  sameModVersion(version.modVersion, installed.version),
            )) {
          score += 3;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  /// 查索引里某一个模组在给定游戏版本下的安装状态：本机没装返回 null
  ///
  /// 模组列表页逐条拿「已安装 / 有更新」用；[installedMods] 可传一次扫描的结果复用
  static Future<ModUpdate?> checkEntry({
    required DataIndexModEntry entry,
    required Mindustry gameVersion,
    List<InstalledModFile>? installedMods,
    bool refresh = false,
  }) async {
    final installed =
        installedMods ?? await scanInstalledMods(gameVersion.modsPaths);
    InstalledModFile? match;
    for (final file in installed) {
      if (file.internalName == entry.internalName) {
        match = file;
        break;
      }
    }
    if (match == null) return null;

    final targetVersion = await _findTargetVersion(
      entry: entry,
      gameVersion: gameVersion.gameVersionString,
      installedVersion: match.version,
      refresh: refresh,
    );
    return ModUpdate(
      entry: entry,
      installed: match,
      targetVersion: targetVersion,
    );
  }

  /// 列一个模组可更换的版本（远端可下载的全部版本，新在前）
  ///
  /// 「更换版本」工具用：默认选最新一版，降级也在这里挑；[gameVersion] 给目标游戏版本
  /// 用来标记兼容性，[installedVersion] 给本机版本用来标记当前版本
  static Future<List<ModVersionCandidate>> availableVersions({
    required DataIndexModEntry entry,
    String? gameVersion,
    String? installedVersion,
    bool refresh = false,
  }) async {
    final versions = await _loadAllVersions(entry, refresh: refresh);
    return candidatesFromVersions(
      versions,
      gameVersion: gameVersion,
      installedVersion: installedVersion,
    );
  }

  /// 把远端版本列表映射成可选项（纯函数）
  @visibleForTesting
  static List<ModVersionCandidate> candidatesFromVersions(
    List<DataIndexModVersion> versions, {
    String? gameVersion,
    String? installedVersion,
  }) => [
    for (final version in versions)
      if (version.downloadable)
        ModVersionCandidate(
          version: version,
          supportsGameVersion: version.supportsGameVersion(gameVersion),
          installed: sameModVersion(version.modVersion, installedVersion ?? ''),
        ),
  ];

  /// 执行模组更新：下载目标版本、替换掉本机旧文件
  static Future<ModInstallOutcome> apply({
    required Mindustry gameVersion,
    required ModUpdate update,
    CancelToken? cancelToken,
    HttpStatusCallback? onStatus,
  }) {
    final target = update.targetVersion;
    if (target == null) {
      throw StateError('这条模组更新没有可下载的版本');
    }
    return changeVersion(
      gameVersion: gameVersion,
      entry: update.entry,
      version: target,
      installed: update.installed,
      cancelToken: cancelToken,
      onStatus: onStatus,
    );
  }

  /// 更换模组版本：下载指定版本并替换本机文件（可升可降，供「更换版本」工具用）
  ///
  /// [installed] 传本机已装的那份时沿用它的目录与禁用态；没装过就落到原版模组目录
  static Future<ModInstallOutcome> changeVersion({
    required Mindustry gameVersion,
    required DataIndexModEntry entry,
    required DataIndexModVersion version,
    InstalledModFile? installed,
    CancelToken? cancelToken,
    HttpStatusCallback? onStatus,
  }) async {
    final url = version.downloadUrl;
    if (url == null || url.isEmpty || version.removed) {
      throw StateError('这个版本没有可下载的文件');
    }

    final targetDirPath = installed == null
        ? gameVersion.modsPath
        : p.dirname(installed.path);
    final tempDirPath = p.join(Directory.systemTemp.path, 'copper_mod_update');
    await Directory(tempDirPath).create(recursive: true);
    final fileName = WindowsFileNameValidator.sanitizeFileName(
      _fileNameOf(url, fallback: '${entry.name}-${version.tag}.zip'),
    );
    final tempPath = p.join(
      tempDirPath,
      '${DateTime.now().microsecondsSinceEpoch}-$fileName',
    );

    addLog(
      .info,
      '更换模组版本 [${entry.name}] ${installed?.version ?? '未安装'} → '
      '${version.modVersion}（${version.tag}）',
      tag: 'ModUpdate',
    );

    try {
      await cio.download(
        url: url,
        savePath: tempPath,
        cancelToken: cancelToken,
        onStatus: onStatus,
      );

      final reader = await FileReader.fromPath(tempPath);
      final mod = reader.mod;
      if (mod == null) {
        throw const FormatException('下载的模组文件解析不出模组信息');
      }
      // 索引条目与文件对不上通常是数据源的错（下载地址指向了别的模组），只记一笔
      if (mod.internalName != entry.internalName) {
        addLog(
          .warning,
          '下载的模组内部名与索引不一致：文件 ${mod.internalName}，索引 '
          '${entry.internalName}（${entry.repo}）',
          tag: 'ModUpdate',
        );
      }

      return await installModFile(
        sourcePath: tempPath,
        mod: mod,
        targetDirPath: targetDirPath,
        modsDirs: gameVersion.modsPaths,
        tempDirPath: tempDirPath,
        modStates: await readInstalledModStates(gameVersion.settingPath),
      );
    } finally {
      try {
        final file = File(tempPath);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // 临时文件删不掉不影响结果，下次启动会自然清掉
      }
    }
  }

  /// 找值得装的最新一版：与游戏版本兼容、且比本机版本新
  ///
  /// 先比索引里的最新版本与本机版本——一样就不用拉 per-mod 文件；
  /// 拉下来后按「新在前」挑第一个兼容且可下载的版本
  static Future<DataIndexModVersion?> _findTargetVersion({
    required DataIndexModEntry entry,
    required String? gameVersion,
    required String installedVersion,
    bool refresh = false,
  }) async {
    if (entry.releasesPath == null) return null;
    if (!isNewerModVersion(entry.version, installedVersion)) return null;

    final versions = await _loadAllVersions(entry, refresh: refresh);
    for (final candidate in candidatesFromVersions(
      versions,
      gameVersion: gameVersion,
    )) {
      if (!candidate.supportsGameVersion) continue;
      return isNewerModVersion(candidate.modVersion, installedVersion)
          ? candidate.version
          : null;
    }
    return null;
  }

  /// 读一个模组全部可下载版本（含分页，按页序去重、保持新在前）
  static Future<List<DataIndexModVersion>> _loadAllVersions(
    DataIndexModEntry entry, {
    bool refresh = false,
  }) async {
    final releasesPath = entry.releasesPath;
    if (releasesPath == null) return const [];

    // page-1 可能单独成文件，也可能就是 releasesPath；按页序去重
    final paths = <String>{
      releasesPath,
      for (final page in entry.pages) page.path,
    };
    final versions = <DataIndexModVersion>[];
    final seenTags = <String>{};
    for (final path in paths) {
      final releases = await DataIndexClient.loadModReleases(
        path,
        refresh: refresh,
      );
      if (releases == null) continue;
      for (final version in releases.versions) {
        if (version.removed) continue;
        if (seenTags.add(version.tag)) versions.add(version);
      }
    }
    return versions;
  }

  /// [latest] 是否比 [installed] 新
  ///
  /// 版本号先去掉颜色标记与 `v` 前缀再比；两边都是纯数字段时按数字段比，
  /// 形态不可比的只判「是否不同」——远端是索引里的最新版本，不同就该更新
  static bool isNewerModVersion(String latest, String installed) {
    final left = normalizeModVersion(latest);
    final right = normalizeModVersion(installed);
    if (left == right) return false;
    if (left.isEmpty) return false;
    if (right.isEmpty) return true;
    if (_numericVersion.hasMatch(left) && _numericVersion.hasMatch(right)) {
      return version_strings.compareVersion(left, right) > 0;
    }
    return true;
  }

  /// 两个模组版本号是不是同一个（按归一化后的字符串比）
  static bool sameModVersion(String a, String b) {
    final left = normalizeModVersion(a);
    final right = normalizeModVersion(b);
    return left.isNotEmpty && left == right;
  }

  /// 归一化模组版本号：去颜色标记、去首尾空白、小写、去掉前缀 `v`
  static String normalizeModVersion(String version) => removeColorTags(
    version,
  ).trim().toLowerCase().replaceFirst(RegExp('^v'), '');

  static final RegExp _numericVersion = RegExp(r'^\d+(?:\.\d+)*$');

  static String _fileNameOf(String url, {required String fallback}) {
    final uri = Uri.tryParse(url);
    final segments = uri?.pathSegments ?? const <String>[];
    final name = segments.isEmpty ? '' : segments.last.trim();
    if (name.isEmpty) return fallback;
    return name;
  }
}
