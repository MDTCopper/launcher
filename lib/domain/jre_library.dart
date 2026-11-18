import 'dart:io';

import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/domain/bridge_runtime_options.dart';
import 'package:copper_launcher/domain/payload_import.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/archive_extract.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

/// Android 桥的 **Java 运行环境库**（`<桥载荷根>/bridge/java/<Java 大版本>/`）
///
/// 每个子目录一份 JRE 根（`bin/java` + `lib/modules`），目录名就是 **Java 大版本**
/// （`17` / `25` …），多版本并存。用哪一份由 `runtime.json` 的 `jreVersion` 钉住，
/// 没钉就自动挑最大版本的那份。
///
/// 版本只认 Java 大版本，不再用上游 release 里 `version` 文件的构建号：
/// - 上游按大版本打 release tag（`jre17` / `jre25`），装哪份由 tag 决定；
/// - 目录名与钉住的值都是大版本，换构建不再产生新的“版本”；
/// - 旧布局（`bridge/java/<构建号>` 与平铺的 `bridge/jre`）在读取库时按 JRE 根里的
///   `release` 文件认出版本，改名归位到 `bridge/java/<大版本>/`，认不出来就原样留着。
class JreLibrary {
  JreLibrary._();

  /// 能当 JRE 导入的压缩包后缀：与 [extractArchive] 支持的形态一致
  static const _archiveSuffixes = [
    '.zip',
    '.tar.xz',
    '.txz',
    '.tar.gz',
    '.tgz',
  ];

  /// 库目录 `bridge/java`；[bridgeDirPath] 只为用例注入，正常走 [AppPaths.bridge]
  static String javaDirPath({String? bridgeDirPath}) =>
      p.join(bridgeDirPath ?? AppPaths.bridge, 'java');

  /// 旧装法的 JRE 根 `bridge/jre`（兼容用；第一次读库时会尝试归位到 `java/<版本>`）
  static String legacyJreRootPath({String? bridgeDirPath}) =>
      bridgeDirPath == null ? AppPaths.bridgeJre : p.join(bridgeDirPath, 'jre');

  /// 某个 Java 大版本的 JRE 根
  static String jreRootPathOf(String version, {String? bridgeDirPath}) =>
      p.join(javaDirPath(bridgeDirPath: bridgeDirPath), version);

  /// 库里已有的 Java 大版本（只算 `bin/java` 与 `lib/modules` 都在的目录），高的在前
  static List<String> localVersions({String? bridgeDirPath}) =>
      _installedRoots(bridgeDirPath: bridgeDirPath).keys.toList()
        ..sort((a, b) => _compareVersions(b, a));

  /// 当前选的 Java 大版本：钉住的优先（**即使还没装**，启动时也要按它装）→ 库里最高的
  /// → 一份都没有返回 null
  static String? selectedVersion({String? bridgeDirPath}) {
    final pinned = BridgeRuntimeOptions.load(
      bridgeDirPath: bridgeDirPath,
    ).jreVersion;
    if (pinned != null && pinned.isNotEmpty) return pinned;

    final versions = localVersions(bridgeDirPath: bridgeDirPath);
    return versions.isEmpty ? null : versions.first;
  }

  /// 选中那份 JRE 的根路径
  ///
  /// 一份都没有时给旧装法路径 `bridge/jre`，`--java` 有个确定落点
  static String selectedJreRoot({String? bridgeDirPath}) {
    final version = selectedVersion(bridgeDirPath: bridgeDirPath);
    if (version == null) {
      return legacyJreRootPath(bridgeDirPath: bridgeDirPath);
    }
    final roots = _installedRoots(bridgeDirPath: bridgeDirPath);
    return roots[version] ??
        jreRootPathOf(version, bridgeDirPath: bridgeDirPath);
  }

  /// 钉住用哪个 Java 大版本（null = 跟随最新）：只写 runtime.json，不动库里的文件
  static Future<void> selectJreVersion(
    String? version, {
    String? bridgeDirPath,
  }) async {
    final options = BridgeRuntimeOptions.load(bridgeDirPath: bridgeDirPath);
    options.jreVersion = version;
    await options.save(bridgeDirPath: bridgeDirPath);
  }

  /// 选中的那份齐不齐：钉住的版本没装也算不齐（启动时按它装）
  static bool isReady({String? bridgeDirPath}) {
    final version = selectedVersion(bridgeDirPath: bridgeDirPath);
    return version != null && hasVersion(version, bridgeDirPath: bridgeDirPath);
  }

  /// 指定 Java 大版本那份齐不齐（联网安装前判断要不要重下）
  static bool hasVersion(String version, {String? bridgeDirPath}) =>
      _installedRoots(bridgeDirPath: bridgeDirPath).containsKey(version);

  /// 本地导入 Java 运行环境：压缩包（zip / tar.xz）或已经解压好的目录
  ///
  /// 先收进与库同层的临时目录，验过 `bin/java` 与 `lib/modules` 才换到
  /// `bridge/java/<版本>/`；中途失败旧的那份原样留着，返回落到的 JRE 根路径
  ///
  /// [version] 不给就从导入内容里的 `release` 文件（或目录名）认版本；
  /// 认不出来直接拒绝 —— 库里按 Java 大版本组织，没版本号的目录没法参与选择
  static Future<String> importJre(
    String sourcePath, {
    String? version,
    void Function(String status)? onStatus,
    String? bridgeDirPath,
  }) async {
    final sourceType = FileSystemEntity.typeSync(sourcePath);
    if (sourceType == FileSystemEntityType.notFound) {
      throw const PayloadImportException('选的路径不在了，重新选一次');
    }
    if (sourceType == FileSystemEntityType.file &&
        !_archiveSuffixes.any(
          (suffix) => sourcePath.toLowerCase().endsWith(suffix),
        )) {
      throw const PayloadImportException('只收 zip / tar.xz 压缩包，或者已经解压好的 JRE 目录');
    }

    final rootPath = bridgeDirPath ?? AppPaths.bridge;
    Directory(rootPath).createSync(recursive: true);
    // 临时目录与库同一层：换到位靠改名，不跨文件系统复制
    final stagingDir = Directory(p.join(rootPath, 'tmp', 'jre-importing'));
    _deleteQuietly(stagingDir);
    stagingDir.createSync(recursive: true);

    late final String targetVersion;
    try {
      final String stagedJreRootPath;
      if (sourceType == FileSystemEntityType.directory) {
        onStatus?.call('正在收集本地 Java 运行环境…');
        final sourceJreRootPath = _jreRootIn(sourcePath);
        if (sourceJreRootPath == null) {
          throw const PayloadImportException(
            '这个目录里没有 bin/java 和 lib/modules，不是可用的 Java 运行环境',
          );
        }
        await _copyDirectoryContents(Directory(sourceJreRootPath), stagingDir);
        stagedJreRootPath = stagingDir.path;
      } else {
        onStatus?.call('正在解压 Java 运行环境…');
        await extractArchive(sourcePath, stagingDir.path);
        final extractedJreRootPath = _jreRootIn(stagingDir.path);
        if (extractedJreRootPath == null) {
          throw const PayloadImportException(
            '这个压缩包里没有 bin/java 和 lib/modules，不是可用的 Java 运行环境',
          );
        }
        stagedJreRootPath = extractedJreRootPath;
      }

      targetVersion = _resolveImportVersion(
        explicit: version,
        stagedJreRootPath: stagedJreRootPath,
        sourcePath: sourcePath,
        fromDirectory: sourceType == FileSystemEntityType.directory,
      );

      onStatus?.call('正在放入 Java 运行环境…');
      await _replaceVersionDirectory(
        stagedJreRootPath,
        targetVersion,
        bridgeDirPath: bridgeDirPath,
      );
    } on PayloadImportException {
      rethrow;
    } catch (error) {
      addLogAndPrint(
        .warning,
        '本地导入 Java 运行环境失败：${removeNewlines('$error')}',
        tag: 'Bridge',
      );
      throw const PayloadImportException('这份文件收不进来：解压或复制出错，换一份再试');
    } finally {
      // 换到位后这里只剩空壳或压缩包自带的散件
      _deleteQuietly(stagingDir);
    }

    final jreRootPath = jreRootPathOf(
      targetVersion,
      bridgeDirPath: bridgeDirPath,
    );
    await _ensureJavaExecutable(jreRootPath);
    await selectJreVersion(targetVersion, bridgeDirPath: bridgeDirPath);
    addLogAndPrint(
      .info,
      'Android 桥：本地导入了 Java $targetVersion 运行环境',
      tag: 'Bridge',
    );
    return jreRootPath;
  }

  /// 联网安装用：把下好的两个包叠在同一棵树解开，落到 `bridge/java/<版本>/`
  ///
  /// [version] 是 Java 大版本（release tag `jre<版本>` 决定的那个）；解完写一份
  /// `.installed-version` 标记便于排查；[archivePaths] 解完就删。先解到临时目录，
  /// 验过才换到位，中途失败旧的同版本那份原样留着
  static Future<String> installJreFromArchive({
    required String version,
    required List<String> archivePaths,
    void Function(String status)? onStatus,
    String? bridgeDirPath,
  }) async {
    final targetVersion = _normalizeVersion(version);
    final rootPath = bridgeDirPath ?? AppPaths.bridge;
    final stagingDir = Directory(p.join(rootPath, 'tmp', 'jre-installing'));
    _deleteQuietly(stagingDir);
    stagingDir.createSync(recursive: true);

    try {
      onStatus?.call('正在解压 Java 运行环境…');
      for (final archivePath in archivePaths) {
        // 两个包都对着 JRE 根打的，直接叠在同一棵树
        await extractArchive(archivePath, stagingDir.path);
      }
      final extractedJreRootPath = _jreRootIn(stagingDir.path);
      if (extractedJreRootPath == null) {
        throw const PayloadImportException(
          '解出来的文件里没有 bin/java 和 lib/modules，下载可能不完整',
        );
      }

      onStatus?.call('正在放入 Java 运行环境…');
      await _replaceVersionDirectory(
        extractedJreRootPath,
        targetVersion,
        bridgeDirPath: bridgeDirPath,
      );
    } finally {
      // 留着解压到一半的树只会占地方；压缩包不动，失败时还能直接重试
      _deleteQuietly(stagingDir);
    }

    final jreRootPath = jreRootPathOf(
      targetVersion,
      bridgeDirPath: bridgeDirPath,
    );
    await File(
      p.join(jreRootPath, '.installed-version'),
    ).writeAsString(targetVersion);
    await _ensureJavaExecutable(jreRootPath);
    for (final archivePath in archivePaths) {
      _deleteQuietly(File(archivePath));
    }
    return jreRootPath;
  }

  /// 导入内容的 Java 大版本：显式给的 → `release` 文件 / 目录名，认不出来就拒绝
  static String _resolveImportVersion({
    required String? explicit,
    required String stagedJreRootPath,
    required String sourcePath,
    required bool fromDirectory,
  }) {
    if (explicit != null && explicit.trim().isNotEmpty) {
      return _normalizeVersion(explicit);
    }
    final version = _javaMajorOfJre(
      stagedJreRootPath,
      dirName: fromDirectory ? p.basename(p.normalize(sourcePath)) : null,
    );
    if (version == null) {
      throw const PayloadImportException(
        '认不出这份 Java 的版本：JRE 根里没有 release 文件，目录名里也没有版本号；'
        '可以把它改成 jdk-17 / jre25 这类名字再导入',
      );
    }
    return version;
  }

  /// Java 大版本要当目录名：只收纯数字（`17` / `25`），其余按非法参数拒绝
  static String _normalizeVersion(String raw) {
    final cleaned = raw.trim();
    if (!RegExp(r'^\d+$').hasMatch(cleaned) || int.parse(cleaned) < 8) {
      throw const PayloadImportException('Java 版本要写成大版本号，例如 17、25');
    }
    return cleaned;
  }

  /// 一份 JRE 的 Java 大版本：`release` 里的 `JAVA_VERSION="25.0.1"` → `25`；
  /// 没有就退回目录名（纯数字，或 `jdk-17` / `jre25` 这类形态）
  static String? _javaMajorOfJre(String rootPath, {String? dirName}) {
    final release = File(p.join(rootPath, 'release'));
    if (release.existsSync()) {
      try {
        final match = _releaseVersionPattern.firstMatch(
          release.readAsStringSync(),
        );
        if (match != null) return match.group(1);
      } catch (_) {
        // 读不出来就退回目录名
      }
    }
    return _majorFromName(dirName ?? p.basename(rootPath));
  }

  static String? _majorFromName(String name) {
    final trimmed = name.trim();
    final pure = RegExp(r'^(\d+)$').firstMatch(trimmed);
    final tagged = RegExp(
      r'^(?:jre|jdk|java)[-_]?(\d+)(?:\D|$)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final raw = pure?.group(1) ?? tagged?.group(1);
    if (raw == null) return null;
    final value = int.tryParse(raw);
    // 旧装法的目录名是构建号（可能是 6 这种小数字），不当版本用
    return value != null && value >= 8 ? '$value' : null;
  }

  /// 库里的版本 → JRE 根。读之前先把旧布局归位；同版本有多份时优先规范目录名
  static Map<String, String> _installedRoots({String? bridgeDirPath}) {
    _migrateLegacyLayout(bridgeDirPath: bridgeDirPath);
    final roots = <String, String>{};

    final javaDir = Directory(javaDirPath(bridgeDirPath: bridgeDirPath));
    if (javaDir.existsSync()) {
      for (final entity in javaDir.listSync()) {
        if (entity is! Directory || !_looksLikeJre(entity.path)) continue;
        final name = p.basename(entity.path);
        final version = _javaMajorOfJre(entity.path, dirName: name);
        if (version == null) continue;
        if (roots[version] == null || name == version) {
          roots[version] = entity.path;
        }
      }
    }

    // 迁移失败 / 还没搬的平铺那份：仍算已安装，只是根还在 bridge/jre
    final legacyRoot = legacyJreRootPath(bridgeDirPath: bridgeDirPath);
    if (_looksLikeJre(legacyRoot)) {
      final version = _javaMajorOfJre(legacyRoot, dirName: null);
      if (version != null) roots.putIfAbsent(version, () => legacyRoot);
    }
    return roots;
  }

  /// 把旧布局按 Java 大版本归位：`bridge/jre` 与 `java/<构建号>` → `java/<大版本>`
  ///
  /// 只改目录名，不动内容；同一版本已有一份规范目录时删掉旧构建号那份。
  /// 失败只记日志 —— 读库不能因为一次改名失败就报错，旧目录仍会被 [_installedRoots] 认出来
  static void _migrateLegacyLayout({String? bridgeDirPath}) {
    final javaDir = Directory(javaDirPath(bridgeDirPath: bridgeDirPath));
    if (!_migratedDirs.add(javaDir.path)) return;
    try {
      javaDir.createSync(recursive: true);
    } catch (_) {
      return;
    }

    final legacyRoot = legacyJreRootPath(bridgeDirPath: bridgeDirPath);
    if (_looksLikeJre(legacyRoot)) {
      final version = _javaMajorOfJre(legacyRoot, dirName: null);
      if (version != null) {
        final target = Directory(
          jreRootPathOf(version, bridgeDirPath: bridgeDirPath),
        );
        if (!_looksLikeJre(target.path)) {
          _moveJreDirectory(Directory(legacyRoot), target);
        }
      }
    }

    final entities = javaDir.listSync();
    for (final entity in entities) {
      if (entity is! Directory || !_looksLikeJre(entity.path)) continue;
      final name = p.basename(entity.path);
      final version = _javaMajorOfJre(entity.path, dirName: name);
      if (version == null || version == name) continue;
      final target = Directory(
        jreRootPathOf(version, bridgeDirPath: bridgeDirPath),
      );
      if (_looksLikeJre(target.path)) {
        // 同一版本已有一份规范目录，旧构建号这份是重复的
        _deleteQuietly(entity);
        addLogAndPrint(
          .info,
          'Android 桥：删掉重复的 Java 运行环境 ${entity.path}（已有 Java $version）',
          tag: 'Bridge',
        );
        continue;
      }
      _moveJreDirectory(entity, target);
    }
  }

  static void _moveJreDirectory(Directory from, Directory to) {
    try {
      if (to.existsSync()) _deleteQuietly(to);
      from.renameSync(to.path);
      addLogAndPrint(
        .info,
        'Android 桥：Java 运行环境按大版本归位 '
        '${p.basename(from.path)} → ${p.basename(to.path)}',
        tag: 'Bridge',
      );
    } catch (error) {
      addLogAndPrint(
        .warning,
        'Java 运行环境归位失败（${from.path}）：${removeNewlines('$error')}',
        tag: 'Bridge',
      );
    }
  }

  /// 找 JRE 根：含 `bin/java` 与 `lib/modules` 的那一层，压缩包里常还套一层目录
  static String? _jreRootIn(String rootPath) {
    if (_looksLikeJre(rootPath)) return rootPath;
    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) return null;
    for (final entity in rootDir.listSync()) {
      if (entity is Directory && _looksLikeJre(entity.path)) {
        return entity.path;
      }
    }
    return null;
  }

  /// 这一层是不是 JRE：`bin/java`（ABI 分包给的）与 `lib/modules`（ABI 无关包给的）都在
  static bool _looksLikeJre(String dirPath) =>
      File(p.join(dirPath, 'bin', 'java')).existsSync() &&
      File(p.join(dirPath, 'lib', 'modules')).existsSync();

  /// 把 [sourceDir] 里的内容按相对结构复制到 [targetDir]
  static Future<void> _copyDirectoryContents(
    Directory sourceDir,
    Directory targetDir,
  ) async {
    await targetDir.create(recursive: true);
    await for (final entity in sourceDir.list(
      recursive: true,
      followLinks: false,
    )) {
      final relativePath = p.relative(entity.path, from: sourceDir.path);
      final targetPath = p.join(targetDir.path, relativePath);
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(targetPath)).create(recursive: true);
        await entity.copy(targetPath);
      }
    }
  }

  /// 把验过的目录换到 `bridge/java/<版本>`：旧的先挪到临时目录，新的挪过去再删旧的
  static Future<void> _replaceVersionDirectory(
    String stagedJreRootPath,
    String version, {
    String? bridgeDirPath,
  }) async {
    final targetDir = Directory(
      jreRootPathOf(version, bridgeDirPath: bridgeDirPath),
    );
    final backupDir = Directory(
      p.join(bridgeDirPath ?? AppPaths.bridge, 'tmp', 'jre-old'),
    );
    _deleteQuietly(backupDir);
    await targetDir.parent.create(recursive: true);

    final hasOldJre = targetDir.existsSync();
    if (hasOldJre) await targetDir.rename(backupDir.path);
    try {
      await Directory(stagedJreRootPath).rename(targetDir.path);
    } catch (error) {
      // 新的没挪过去就把旧的挪回来，别让这个版本凭空没了
      if (hasOldJre && backupDir.existsSync()) {
        await backupDir.rename(targetDir.path);
      }
      rethrow;
    }
    if (hasOldJre) _deleteQuietly(backupDir);
  }

  /// 解压 / 复制都不带权限位，非 Windows 上给 `bin/java` 补个可执行位
  static Future<void> _ensureJavaExecutable(String jreRootPath) async {
    if (Platform.isWindows) return;
    final javaPath = p.join(jreRootPath, 'bin', 'java');
    if (!File(javaPath).existsSync()) return;

    try {
      final result = await Process.run('chmod', ['755', javaPath]);
      if (result.exitCode == 0) return;
    } catch (_) {
      // 没有 chmod 的环境（沙箱）不让导入因此失败
    }
    addLogAndPrint(
      .warning,
      'Java 运行环境的 bin/java 没补上可执行位，启动前要确认权限',
      tag: 'Bridge',
    );
  }

  static int _compareVersions(String a, String b) {
    final left = int.tryParse(a);
    final right = int.tryParse(b);
    if (left != null && right != null) return left.compareTo(right);
    return a.compareTo(b);
  }

  static void _deleteQuietly(FileSystemEntity entity) {
    try {
      if (entity.existsSync()) entity.deleteSync(recursive: true);
    } catch (error) {
      addLogAndPrint(
        .warning,
        '整理 Java 运行环境时删不掉 ${entity.path}：${removeNewlines('$error')}',
        tag: 'Bridge',
      );
    }
  }

  /// 已经扫过旧布局的库目录（同一进程只归位一次，避免每次读都碰文件系统）
  static final Set<String> _migratedDirs = <String>{};

  /// `release` 里的 `JAVA_VERSION="25.0.1"` → `25`
  static final RegExp _releaseVersionPattern = RegExp(
    r'^JAVA_VERSION="?(\d+)',
    multiLine: true,
  );
}
