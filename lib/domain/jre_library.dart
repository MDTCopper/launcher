import 'dart:io';

import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/domain/bridge_runtime_options.dart';
import 'package:copper_launcher/domain/payload_import.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/archive_extract.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/version_strings.dart' as version_strings;
import 'package:path/path.dart' as p;

/// Android 桥的 **Java 运行环境库**（`<桥载荷根>/bridge/java/<build>/`）
///
/// 每个子目录一份 JRE 根（`bin/java` + `lib/modules`），多版本并存，用哪一份由
/// `runtime.json` 的 `jreBuild` 钉住，没钉就自动挑构建号最高的那份
///
/// 旧装法把 JRE 平铺在 `bridge/jre`：库里一份都没有时 [selectedBuild] 返回
/// [legacyBuild]、[selectedJreRoot] 原样返回那个旧目录，不强制搬家；联网安装与
/// 本地导入只会往库里放新的一份，旧目录留给还没迁移的设备继续用
class JreLibrary {
  JreLibrary._();

  /// 旧装法（`bridge/jre`）那份 JRE 的标识：它没有目录名可以当构建号
  static const legacyBuild = 'legacy';

  /// 能当 JRE 导入的压缩包后缀：与 [extractArchive] 支持的形态一致
  static const _archiveSuffixes = [
    '.zip',
    '.tar.xz',
    '.txz',
    '.tar.gz',
    '.tgz',
  ];

  /// 名字太泛、不适合当构建号的目录名
  static const _genericDirNames = {
    'jre',
    'jdk',
    'java',
    'bin',
    'lib',
    'runtime',
    'tmp',
  };

  /// 库目录 `bridge/java`；[bridgeDirPath] 只为用例注入，正常走 [AppPaths.bridge]
  static String javaDirPath({String? bridgeDirPath}) =>
      p.join(bridgeDirPath ?? AppPaths.bridge, 'java');

  /// 旧装法的 JRE 根 `bridge/jre`（兼容用；联网安装与本地导入都不清理它）
  static String legacyJreRootPath({String? bridgeDirPath}) =>
      bridgeDirPath == null ? AppPaths.bridgeJre : p.join(bridgeDirPath, 'jre');

  /// 某个构建号的 JRE 根
  static String jreRootPathOf(String build, {String? bridgeDirPath}) =>
      p.join(javaDirPath(bridgeDirPath: bridgeDirPath), build);

  /// 库里已有的构建号（只算 `bin/java` 与 `lib/modules` 都在的目录），构建号高的在前
  static List<String> localBuilds({String? bridgeDirPath}) {
    final javaDir = Directory(javaDirPath(bridgeDirPath: bridgeDirPath));
    if (!javaDir.existsSync()) return const [];
    final builds = [
      for (final entity in javaDir.listSync())
        if (entity is Directory && _looksLikeJre(entity.path))
          p.basename(entity.path),
    ]..sort((a, b) => compareBuilds(b, a));
    return builds;
  }

  /// 构建号比大小：先按数字段逐个比，读不出数字的再按字符串比
  ///
  /// `local-<时间戳>` 这类读不出数字的排在远端构建号后面，只有它们时才靠字符串定先后
  static int compareBuilds(String a, String b) {
    final byNumber = version_strings.compareVersion(a, b);
    if (byNumber != 0) return byNumber;
    return a.compareTo(b);
  }

  /// 当前选中的构建号：钉住的在库里就用它 → 库里最新的 → 只剩旧装法那份时给
  /// [legacyBuild]；都没有返回 null
  static String? selectedBuild({String? bridgeDirPath}) {
    final builds = localBuilds(bridgeDirPath: bridgeDirPath);
    if (builds.isEmpty) {
      return _looksLikeJre(legacyJreRootPath(bridgeDirPath: bridgeDirPath))
          ? legacyBuild
          : null;
    }

    final pinned = BridgeRuntimeOptions.load(
      bridgeDirPath: bridgeDirPath,
    ).jreBuild;
    if (pinned != null && builds.contains(pinned)) return pinned;
    return builds.first;
  }

  /// 选中那份 JRE 的根路径：旧装法给 `bridge/jre`
  ///
  /// 一份都没有时也给这个旧路径，`--java` 有个确定落点，与旧口径一致
  static String selectedJreRoot({String? bridgeDirPath}) {
    final build = selectedBuild(bridgeDirPath: bridgeDirPath);
    if (build == null || build == legacyBuild) {
      return legacyJreRootPath(bridgeDirPath: bridgeDirPath);
    }
    return jreRootPathOf(build, bridgeDirPath: bridgeDirPath);
  }

  /// 钉住用哪一份（[build] 为 null = 跟随最新，旧装法那份写 [legacyBuild]）：
  /// 只写 runtime.json，不动库里的文件
  static Future<void> selectJreBuild(
    String? build, {
    String? bridgeDirPath,
  }) async {
    final options = BridgeRuntimeOptions.load(bridgeDirPath: bridgeDirPath);
    options.jreBuild = build;
    await options.save(bridgeDirPath: bridgeDirPath);
  }

  /// 选中的那份齐不齐：`bin/java` 与 `lib/modules` 都在
  static bool isReady({String? bridgeDirPath}) =>
      _looksLikeJre(selectedJreRoot(bridgeDirPath: bridgeDirPath));

  /// 指定构建号那份齐不齐（联网安装前判断要不要重下）
  static bool hasBuild(String build, {String? bridgeDirPath}) =>
      _looksLikeJre(jreRootPathOf(build, bridgeDirPath: bridgeDirPath));

  /// 本地导入 Java 运行环境：压缩包（zip / tar.xz）或已经解压好的目录
  ///
  /// 先收进与库同层的临时目录，验过 `bin/java` 与 `lib/modules` 才换到
  /// `bridge/java/<build>/`；中途失败旧的那份原样留着，返回落到的 JRE 根路径
  ///
  /// 构建号按 [build] → 导入内容里的 `.installed-version`（旧装法的包里有）→
  /// 目录名（像个构建号时）→ `local-<时间戳>` 的顺序定；导入成功就钉住这一份，
  /// 与旧装法「导入即替换唯一那份」的手感一致
  static Future<String> importJre(
    String sourcePath, {
    String? build,
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

    late final String targetBuild;
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

      targetBuild = _buildOfImport(
        explicitBuild: build,
        stagedJreRootPath: stagedJreRootPath,
        sourcePath: sourcePath,
        fromDirectory: sourceType == FileSystemEntityType.directory,
      );

      onStatus?.call('正在放入 Java 运行环境…');
      await _replaceBuildDirectory(
        stagedJreRootPath,
        targetBuild,
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
      targetBuild,
      bridgeDirPath: bridgeDirPath,
    );
    await _ensureJavaExecutable(jreRootPath);
    await selectJreBuild(targetBuild, bridgeDirPath: bridgeDirPath);
    addLogAndPrint(
      .info,
      'Android 桥：本地导入了 Java 运行环境（$targetBuild）',
      tag: 'Bridge',
    );
    return jreRootPath;
  }

  /// 联网安装用：把下好的两个包叠在同一棵树解开，落到 `bridge/java/<build>/`
  ///
  /// [build] 由调用方定（远端 `version` 文件的值），解完写一份 `.installed-version`；
  /// [archivePaths] 解完就删。先解到临时目录，验过才换到位，中途失败旧的同构建号那份原样留着
  static Future<String> installJreFromArchive({
    required String build,
    required List<String> archivePaths,
    void Function(String status)? onStatus,
    String? bridgeDirPath,
  }) async {
    final rootPath = bridgeDirPath ?? AppPaths.bridge;
    final targetBuild = _sanitizeBuildName(build);
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
      await _replaceBuildDirectory(
        extractedJreRootPath,
        targetBuild,
        bridgeDirPath: bridgeDirPath,
      );
    } finally {
      // 留着解压到一半的树只会占地方；压缩包不动，失败时还能直接重试
      _deleteQuietly(stagingDir);
    }

    final jreRootPath = jreRootPathOf(
      targetBuild,
      bridgeDirPath: bridgeDirPath,
    );
    await File(
      p.join(jreRootPath, '.installed-version'),
    ).writeAsString(targetBuild);
    await _ensureJavaExecutable(jreRootPath);
    for (final archivePath in archivePaths) {
      _deleteQuietly(File(archivePath));
    }
    return jreRootPath;
  }

  /// 导入内容的构建号：显式给的 → 内容里的 `.installed-version` → 目录名 →
  /// `local-<时间戳>`
  static String _buildOfImport({
    required String? explicitBuild,
    required String stagedJreRootPath,
    required String sourcePath,
    required bool fromDirectory,
  }) {
    if (explicitBuild != null && explicitBuild.trim().isNotEmpty) {
      return _sanitizeBuildName(explicitBuild);
    }

    final markerBuild = _markerBuildOf(stagedJreRootPath);
    if (markerBuild != null) return markerBuild;

    if (fromDirectory) {
      final dirName = p.basename(p.normalize(sourcePath));
      if (_looksLikeBuildName(dirName)) return _sanitizeBuildName(dirName);
    }
    return 'local-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// 导入内容里记的构建号（旧装法的 JRE 根里带 `.installed-version`）
  static String? _markerBuildOf(String jreRootPath) {
    final marker = File(p.join(jreRootPath, '.installed-version'));
    if (!marker.existsSync()) return null;
    try {
      final value = marker.readAsStringSync().trim();
      return value.isEmpty ? null : _sanitizeBuildName(value);
    } catch (_) {
      return null;
    }
  }

  /// 目录名能不能直接当构建号：带数字、不是 `jre` 这类泛名、只用安全字符
  static bool _looksLikeBuildName(String name) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$').hasMatch(name) &&
      RegExp(r'\d').hasMatch(name) &&
      !_genericDirNames.contains(name.toLowerCase());

  /// 构建号要当目录名：去掉路径分隔符这类不合法字符
  static String _sanitizeBuildName(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9._+-]'), '-');
    return cleaned.isEmpty
        ? 'local-${DateTime.now().millisecondsSinceEpoch}'
        : cleaned;
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

  /// 把验过的目录换到 `bridge/java/<build>`：旧的先挪到临时目录，新的挪过去再删旧的
  static Future<void> _replaceBuildDirectory(
    String stagedJreRootPath,
    String build, {
    String? bridgeDirPath,
  }) async {
    final targetDir = Directory(
      jreRootPathOf(build, bridgeDirPath: bridgeDirPath),
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
      // 新的没挪过去就把旧的挪回来，别让这份构建号凭空没了
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
}
