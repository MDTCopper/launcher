import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

/// BE 版游戏的**自更新**结果同步
///
/// 玩家在游戏内点确认后，游戏把新 build 下载到 `<数据目录>/be_builds/`，再起一个新进程
/// 把本体**原地覆盖**回原路径；记录里的 [Mindustry.release] 不会自己变，
/// 所以启动前与退出后各核一次
class BeVersion {
  BeVersion._();

  /// `be_builds/` 里最新的 build 号；没有就返回 null
  ///
  /// 游戏把下载的 jar 命名成 `client-be-<build>.jar`，更新完仍留在目录里，
  /// 直到下一次更新才被删，可以当「刚更新过」的物证
  static String? latestDownloadedBuild(String dataPath) {
    final dir = Directory(p.join(dataPath, 'be_builds'));
    try {
      if (!dir.existsSync()) return null;

      int? latest;
      for (final entity in dir.listSync()) {
        final match = RegExp(
          r'^client-be-(\d+)\.jar$',
        ).firstMatch(p.basename(entity.path));
        final build = match == null ? null : int.tryParse(match.group(1)!);
        if (build != null && (latest == null || build > latest)) latest = build;
      }
      return latest?.toString();
    } catch (_) {
      return null;
    }
  }

  /// 读本体 jar 的 `version.properties`，build 与记录不同就返回变化（不落盘）
  static Future<BeVersionChange?> probe(Mindustry version) async {
    final jar = File(version.resolvedJarPath);
    if (!jar.existsSync()) return null;

    try {
      final meta = (await FileReader.fromPath(jar.path)).mindustry;
      if (meta == null) return null;

      final build = meta.build.trim();
      if (build.isEmpty || build == version.release.trim()) return null;
      return BeVersionChange(
        oldRelease: version.release,
        newRelease: build,
        newVersionNumber: int.tryParse(meta.version.trim()),
      );
    } catch (error) {
      addLog(.warning, '读 BE 本体版本失败：$error', tag: 'BE');
      return null;
    }
  }

  /// 把变化写进记录（不落盘）
  static void apply(Mindustry version, BeVersionChange change) {
    version.release = change.newRelease;
    version.versionNumber = change.newVersionNumber ?? version.versionNumber;
  }

  /// 启动前核一次：本体被游戏换过就把记录刷到新 build
  static Future<BeVersionChange?> refresh(Mindustry version) async {
    final change = await probe(version);
    if (change == null) return null;

    apply(version, change);
    await config.save();
    addLog(
      .info,
      'BE 本体已更新：[${version.tag}] ${change.oldRelease} → ${change.newRelease}',
      tag: 'BE',
    );
    return change;
  }

  /// 游戏退出后等一等：这次退出是不是「自更新重启」造成的
  ///
  /// 新进程把本体整份复制回来，所以拿 `be_builds` 里那份的大小卡住：大小对上了才读版本，
  /// 免得读到半截包。[since] 是这局启动的时刻：共享数据目录时 `be_builds` 里会有别的版本
  /// 早先下的包，只认这局期间下载的那份
  static Future<BeVersionChange?> watchAfterExit(
    Mindustry version, {
    DateTime? since,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final downloaded = latestDownloadedBuild(version.dataPath);
      if (downloaded == null || !isNewerBuild(downloaded, version.release)) {
        return null;
      }

      final downloadedJar = File(
        p.join(version.dataPath, 'be_builds', 'client-be-$downloaded.jar'),
      );
      if (since != null) {
        final modified = _modifiedOf(downloadedJar);
        if (modified == null || modified.isBefore(since)) return null;
      }

      final jar = File(version.resolvedJarPath);
      final expectedLength = downloadedJar.existsSync()
          ? downloadedJar.lengthSync()
          : null;

      final deadline = DateTime.now().add(timeout);
      var probes = 0;
      while (probes < 6 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (expectedLength != null && _lengthOf(jar) != expectedLength) {
          continue;
        }

        probes++;
        final change = await refresh(version);
        if (change != null) return change;
      }

      addLog(.warning, '检测到游戏自更新到 Build $downloaded，但本体还没被替换', tag: 'BE');
      return null;
    } catch (error) {
      addLog(.warning, 'BE 自更新检查失败：$error', tag: 'BE');
      return null;
    }
  }

  /// 构建号大小比较：解析不出的一律不算新
  static bool isNewerBuild(String candidate, String current) {
    final next = int.tryParse(candidate.trim());
    if (next == null) return false;

    final now = int.tryParse(current.trim().replaceFirst(RegExp('^v'), ''));
    return now == null || next > now;
  }

  static int _lengthOf(File file) {
    try {
      return file.existsSync() ? file.lengthSync() : -1;
    } catch (_) {
      return -1;
    }
  }

  static DateTime? _modifiedOf(File file) {
    try {
      return file.existsSync() ? file.lastModifiedSync() : null;
    } catch (_) {
      return null;
    }
  }
}

/// BE 本体的一次版本变化
class BeVersionChange {
  const BeVersionChange({
    required this.oldRelease,
    required this.newRelease,
    this.newVersionNumber,
  });

  final String oldRelease;
  final String newRelease;
  final int? newVersionNumber;

  /// 给通知用的一句话
  String get description => 'Build $oldRelease → Build $newRelease';
}
