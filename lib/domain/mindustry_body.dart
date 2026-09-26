import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 游戏本体库（`<数据根>/mindustrys/`）：下载与导入的 jar 集中放这里，
/// 多个版本（含变体）引用同一个文件，版本目录只留版本自己的数据。
///
/// **库外本体**是用户自己的文件——「添加目录」扫描到的 jar、以及早期落在各自
/// 版本目录里的那份：原地引用，启动器既不复制也不删（判定见
/// [Mindustry.isBodyInLibrary] / [Mindustry.isBodyInOwnFolder]）
class MindustryBody {
  MindustryBody._();

  /// 库内文件名：`mindustry-<身份>-<hash 前 8 位>.jar`
  ///
  /// 带 hash 是**防撞**：同一个版本号换个来源（别的镜像、用户改过的包）不会
  /// 覆盖库里已有那份；而同一份文件永远得到同一个名字，重复导入天然幂等
  static String fileName(String identity, String hash) {
    final safe = identity.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return 'mindustry-$safe-${hash.substring(0, 8)}.jar';
  }

  static final RegExp _bodyNamePattern = RegExp(
    r'^mindustry-.+-[0-9a-f]{8}\.jar$',
    caseSensitive: false,
  );

  /// 文件名是不是库里的本体（[fileName] 那个形态）
  ///
  /// 下载的临时 / 分块文件（`<目标>.temp.<i>`）与半截文件也落在同一个目录里，
  /// 判断「库内孤儿」时不能把目录里每个文件都算进来（见启动自检）
  static bool isLibraryBodyName(String fileName) =>
      _bodyNamePattern.hasMatch(fileName);

  /// 文件内容 hash（sha1 十六进制）：防撞
  static Future<String> hashFile(File file) async =>
      (await sha1.bind(file.openRead()).first).toString();

  /// 文件内容 hash（sha256 十六进制）：校验来源给的校验和用
  ///
  /// 国内 manifest 每个资产都带 sha256（GitHub API 不带），下载完拿它核对
  static Future<String> hashFileSha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  /// 文本 hash：下载时内容还没拿到，用来源 URL 当身份
  static String hashText(String text) =>
      sha1.convert(utf8.encode(text)).toString();

  /// 下载要写的库内路径。**同一 URL 永远得到同一路径**，断点续传不受影响
  static Future<String> downloadPath({
    required String identity,
    required String sourceUrl,
  }) async {
    await Directory(AppPaths.mindustrys).create(recursive: true);
    return p.join(AppPaths.mindustrys, fileName(identity, hashText(sourceUrl)));
  }

  /// 把一份本体收进库并返回库内路径；同一份文件已经在库里就直接复用那份
  static Future<String?> importIntoLibrary(
    File source, {
    required String identity,
  }) async {
    try {
      final hash = await hashFile(source);
      final target = File(
        p.join(AppPaths.mindustrys, fileName(identity, hash)),
      );
      if (await target.exists()) return target.path;

      await Directory(AppPaths.mindustrys).create(recursive: true);
      await source.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  /// 库里已有该版本的可用本体就返回那条版本记录，否则 null
  ///
  /// **只认库内引用**：库外的本体（扫描来的、用户自己目录里的）不参与比对——
  /// 否则「下载前先查有没有」会依赖用户机器上某个文件还在不在
  static Mindustry? findUsableLibraryBody({
    required bool isBe,
    required String release,
  }) {
    for (final fold in config.versionOptions.versionFolds) {
      for (final version in fold.versions) {
        if (version.isBe != isBe) continue;
        if (!_sameRelease(version.release, release)) continue;
        if (!version.isBodyInLibrary) continue;
        if (!File(version.resolvedJarPath).existsSync()) continue;
        return version;
      }
    }
    return null;
  }

  /// 版本号比对：下载侧拿到的是 github tag（`v160.4`），导入侧存的是 `160.4`，
  /// 去掉前导 v 再比，免得同一个版本被当成两个
  static bool _sameRelease(String a, String b) =>
      _normalizeRelease(a) == _normalizeRelease(b);

  static String _normalizeRelease(String release) =>
      release.toLowerCase().replaceFirst(RegExp(r'^v'), '');
}
