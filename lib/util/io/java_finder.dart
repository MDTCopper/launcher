import 'dart:async';
import 'dart:io';

import 'package:copperlauncher_main/core/app_config.dart';
import 'package:path/path.dart' as path;

class JavaFinder {
  /// 版本缓存：path -> version (null 表示已验证但无效)
  static final Map<String, int?> _versionCache = {};

  /// 通配符展开结果缓存
  static final Map<String, List<String>> _expandedPathCache = {};

  /// 获取适用于当前操作系统的 Java 可执行文件名
  static String _getJavaExecutableName() {
    return Platform.isWindows ? 'java.exe' : 'java';
  }

  /// 合并校验 + 版本获取，一次 [java -version] 调用完成。
  /// 返回 null 表示该路径不是有效的 Java（或版本无法解析）。
  /// 结果会被缓存，重复查询同一路径不会再次执行进程。
  static Future<int?> _validateAndGetVersion(String javaPath) async {
    if (_versionCache.containsKey(javaPath)) {
      return _versionCache[javaPath];
    }

    // 前置安全校验
    final file = File(javaPath);
    if (!await file.exists()) {
      _versionCache[javaPath] = null;
      return null;
    }

    final fileName = path.basename(javaPath).toLowerCase();
    if (fileName != 'java' && fileName != 'java.exe') {
      _versionCache[javaPath] = null;
      return null;
    }

    try {
      final process = await Process.run(javaPath, [
        '-version',
      ], runInShell: false).timeout(const Duration(seconds: 10));

      final output = process.stdout.toString() + process.stderr.toString();

      final isValid = output.contains('java version') ||
          output.contains('openjdk version') ||
          output.contains('openjdk') ||
          process.exitCode == 0;

      if (!isValid) {
        _versionCache[javaPath] = null;
        return null;
      }

      // 提取版本号
      final version = _parseVersionString(output);
      _versionCache[javaPath] = version;
      return version;
    } on TimeoutException {
      _versionCache[javaPath] = null;
      return null;
    } catch (e) {
      _versionCache[javaPath] = null;
      return null;
    }
  }

  /// 从 java -version 输出中解析主版本号
  static int? _parseVersionString(String output) {
    final match = RegExp(r'"(\d+(?:\.\d+)*|\d+)"').firstMatch(output);
    if (match == null) return null;

    final versionStr = match.group(1)!;

    if (versionStr.startsWith('1.')) {
      final parts = versionStr.split('.');
      if (parts.length > 1) return int.tryParse(parts[1]);
    } else {
      final parts = versionStr.split('.');
      if (parts.isNotEmpty) return int.tryParse(parts[0]);
    }
    return null;
  }

  /// 清除缓存（在需要重新检测时调用，例如安装了新的 Java）
  static void clearCache() {
    _versionCache.clear();
    _expandedPathCache.clear();
  }

  /// 常见的 Java 安装路径（根据不同操作系统）
  static List<String> getCommonJavaPaths() {
    final List<String> paths = [];

    if (Platform.isWindows) {
      paths.addAll([
        r'C:\Program Files\Java\jdk-*\bin',
        r'C:\Program Files\Java\jre-*\bin',
        r'C:\Program Files\Java\*\bin',
        r'C:\Program Files\jdk-*\bin',
        r'C:\Program Files\jre-*\bin',
        r'C:\Program Files\Eclipse Adoptium\jdk-*\bin',
        r'C:\Program Files\Eclipse Adoptium\*\bin',
        r'C:\Program Files\AdoptOpenJDK\jdk-*\bin',
        r'C:\Program Files\AdoptOpenJDK\*\bin',
        r'C:\Program Files\Azul\Zulu\*\bin',
        r'C:\Program Files\Amazon Corretto\jdk*\bin',
        r'C:\Program Files\Microsoft\jdk-*\bin',
        r'C:\Program Files\BellSoft\LibericaJDK*\bin',
        r'C:\Program Files\GraalVM\graalvm*\bin',
        r'C:\Program Files\Oracle\JDK*\bin',
        r'C:\jdk*\bin',
        r'C:\java*\bin',
        r'C:\Program Files\JavaSoft\*\bin',
        r'C:\Program Files\IBM\*\bin',
        r'C:\Program Files\RedHat\*\bin',
        r'D:\Program Files\Java\*\bin',
        r'E:\Program Files\Java\*\bin',
        r'C:\Tools\Java\*\bin',
        r'C:\Software\jdk*\bin',
        r'C:\Development\Java\*\bin',
      ]);
    } else if (Platform.isLinux) {
      paths.addAll([
        '/usr/lib/jvm/*',
        '/usr/java/latest/bin',
        '/usr/lib/jvm/default-java/bin',
        '/usr/lib/jvm/java-8-openjdk-*/bin',
        '/usr/lib/jvm/java-11-openjdk-*/bin',
        '/usr/lib/jvm/java-17-openjdk-*/bin',
        '/usr/lib/jvm/java-21-openjdk-*/bin',
        '/opt/java/openjdk/bin',
        '/opt/adoptopenjdk/*/bin',
        '/opt/ibm/java/*/bin',
        '/opt/oracle/jdk/*/bin',
        '/opt/amazon-corretto/*/bin',
        '/opt/microsoft/temurin/*/bin',
        '/home/*/jdk*/bin',
        '/home/*/.sdkman/candidates/java/*/bin',
        '/home/*/java*/bin',
        '/usr/local/sdkman/candidates/java/*/bin',
        '/usr/local/java*/bin',
      ]);
    } else if (Platform.isMacOS) {
      paths.addAll([
        '/Library/Java/JavaVirtualMachines/*/Contents/Home/bin',
        '/System/Library/Frameworks/JavaVM.framework/Versions/*/Commands',
        '/usr/local/Cellar/openjdk/*/libexec/openjdk.jdk/Contents/Home/bin',
        '/opt/homebrew/Cellar/openjdk/*/libexec/openjdk.jdk/Contents/Home/bin',
        '/Users/*/Library/Caches/JetBrains/*/consoles/java/*/bin',
        '/Users/*/.sdkman/candidates/java/*/bin',
        '~/Library/Java/JavaVirtualMachines/*/Contents/Home/bin',
        '/Applications/Xcode.app/Contents/Applications/Application Loader.app/Contents/itms/java/bin',
        '/System/Volumes/Data/opt/homebrew/Cellar/openjdk/*/bin',
      ]);
    }

    return paths;
  }

  /// 检查给定的 Java 可执行文件是否有效
  static Future<bool> isValidJavaExecutable(String javaPath) async {
    return await _validateAndGetVersion(javaPath) != null;
  }

  /// 获取 Java 可执行文件的主版本号
  static Future<int?> getJavaVersion(String javaPath) async {
    return _validateAndGetVersion(javaPath);
  }

  /// 在环境 PATH / JAVA_HOME 中查找 Java 可执行文件
  static Future<String?> findJavaInEnvironment() async {
    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null && javaHome.isNotEmpty) {
      final javaPath = path.join(javaHome, 'bin', _getJavaExecutableName());
      if (await _validateAndGetVersion(javaPath) != null) {
        return javaPath;
      }
    }

    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['java'],
        runInShell: false,
      ).timeout(const Duration(seconds: 10));

      if (result.exitCode == 0) {
        String javaPath =
        result.stdout.toString().trim().split('\n')[0];

        if (javaPath.isNotEmpty && javaPath != 'java') {
          javaPath = path.normalize(javaPath);
          if (await _validateAndGetVersion(javaPath) != null) {
            return javaPath;
          }
        }
      }
    } catch (e) {
      // 回退到手动搜索
    }

    final pathEnv = Platform.environment['PATH'];
    if (pathEnv != null) {
      final pathSeparator = Platform.isWindows ? ';' : ':';
      final paths = pathEnv.split(pathSeparator);

      for (final p in paths) {
        final javaPath = path.join(p, _getJavaExecutableName());
        if (await File(javaPath).exists() &&
            await _validateAndGetVersion(javaPath) != null) {
          return javaPath;
        }
      }
    }

    return null;
  }

  /// 在系统中查找所有有效的 Java 可执行文件
  static Future<List<String>> findAllJavaExecutables({
    bool deepScan = false,
  }) async {
    final Set<String> foundJavaPaths = <String>{};

    final envJava = await findJavaInEnvironment();
    if (envJava != null) {
      foundJavaPaths.add(envJava);
    }

    // 批量处理常见路径，控制并发数避免 I/O 过载
    final commonPaths = getCommonJavaPaths();
    const batchSize = 8;

    for (int i = 0; i < commonPaths.length; i += batchSize) {
      final batch = commonPaths.skip(i).take(batchSize);
      final futures = batch.map((rawPath) async {
        try {
          final expandedPaths = _expandPathPattern(rawPath);
          for (final expandedPath in expandedPaths) {
            final javaExe = path.join(
              expandedPath,
              _getJavaExecutableName(),
            );
            if (await _validateAndGetVersion(javaExe) != null) {
              return javaExe;
            }
          }
        } catch (_) {}
        return null;
      });

      final results = await Future.wait(futures);
      for (final javaExe in results) {
        if (javaExe != null) foundJavaPaths.add(javaExe);
      }
    }

    if (deepScan) {
      final deepResults = await _performDeepScan();
      foundJavaPaths.addAll(deepResults);
    }

    return foundJavaPaths.toList();
  }

  /// 根据版本要求查找最佳的 Java 可执行文件
  static Future<String?> findBestJava({
    int? minVersion,
    int? maxVersion,
    List<String>? preferredPaths,
    bool deepScan = false,
  }) async {
    bool versionMatches(int version) {
      return (minVersion == null || version >= minVersion) &&
          (maxVersion == null || version <= maxVersion);
    }

    // 首选路径
    if (preferredPaths != null) {
      for (final javaPath in preferredPaths) {
        final version = await _validateAndGetVersion(javaPath);
        if (version != null && versionMatches(version)) {
          return javaPath;
        }
      }
    }

    // 环境变量中的 Java
    final envJava = await findJavaInEnvironment();
    if (envJava != null) {
      final version = _versionCache[envJava];
      if (version != null && versionMatches(version)) {
        return envJava;
      }
    }

    // 常见安装路径 + 可选的深度扫描
    return _scanForBestJava(
      minVersion: minVersion,
      maxVersion: maxVersion,
      deepScan: deepScan,
    );
  }

  /// 批量扫描常见路径，找到第一个满足版本要求的 Java 即返回
  static Future<String?> _scanForBestJava({
    int? minVersion,
    int? maxVersion,
    bool deepScan = false,
  }) async {
    bool versionMatches(int version) {
      return (minVersion == null || version >= minVersion) &&
          (maxVersion == null || version <= maxVersion);
    }

    // 先扫描常见路径
    final commonPaths = getCommonJavaPaths();
    const batchSize = 8;

    for (int i = 0; i < commonPaths.length; i += batchSize) {
      final batch = commonPaths.skip(i).take(batchSize);
      final futures = batch.map((rawPath) async {
        try {
          final expandedPaths = _expandPathPattern(rawPath);
          for (final expandedPath in expandedPaths) {
            final javaExe = path.join(
              expandedPath,
              _getJavaExecutableName(),
            );
            final version = await _validateAndGetVersion(javaExe);
            if (version != null && versionMatches(version)) {
              return javaExe;
            }
          }
        } catch (_) {}
        return null;
      });

      final results = await Future.wait(futures);
      for (final javaExe in results) {
        if (javaExe != null) return javaExe;
      }
    }

    if (!deepScan) return null;

    // 深度扫描
    return _performDeepScanForBest(
      minVersion: minVersion,
      maxVersion: maxVersion,
    );
  }

  /// 深度扫描中查找第一个满足版本要求的 Java
  static Future<String?> _performDeepScanForBest({
    int? minVersion,
    int? maxVersion,
  }) async {
    bool versionMatches(int version) {
      return (minVersion == null || version >= minVersion) &&
          (maxVersion == null || version <= maxVersion);
    }

    if (Platform.isWindows) {
      final drives = ['C:', 'D:', 'E:', 'F:'];
      for (final drive in drives) {
        final rootDir = Directory('$drive\\');
        if (!rootDir.existsSync()) continue;

        final potentialDirs = [
          '$drive\\Program Files',
          '$drive\\Program Files (x86)',
          '$drive\\Tools',
          '$drive\\Development',
          '$drive\\Java',
        ];

        for (final dirPath in potentialDirs) {
          final dir = Directory(dirPath);
          if (!dir.existsSync()) continue;

          final result = await _searchRecursiveForBest(dir, 3, versionMatches);
          if (result != null) return result;
        }
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      final scanPaths = [
        '/opt',
        '/usr/local',
        '/usr/share',
        '/home',
        Platform.environment['HOME'] ?? '',
      ];

      for (final scanPath in scanPaths) {
        if (scanPath.isEmpty) continue;
        final dir = Directory(scanPath);
        if (!dir.existsSync()) continue;

        final result = await _searchRecursiveForBest(dir, 2, versionMatches);
        if (result != null) return result;
      }
    }

    return null;
  }

  /// 执行深度扫描，搜索更多可能的 Java 安装
  static Future<List<String>> _performDeepScan() async {
    final List<String> foundPaths = [];

    if (Platform.isWindows) {
      final drives = ['C:', 'D:', 'E:', 'F:'];
      for (final drive in drives) {
        final rootDir = Directory('$drive\\');
        if (!rootDir.existsSync()) continue;

        final potentialDirs = [
          '$drive\\Program Files',
          '$drive\\Program Files (x86)',
          '$drive\\Tools',
          '$drive\\Development',
          '$drive\\Java',
        ];

        for (final dirPath in potentialDirs) {
          final dir = Directory(dirPath);
          if (dir.existsSync()) {
            foundPaths.addAll(await _searchRecursive(dir, 3));
          }
        }
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      final scanPaths = [
        '/opt',
        '/usr/local',
        '/usr/share',
        '/home',
        Platform.environment['HOME'] ?? '',
      ];

      for (final scanPath in scanPaths) {
        if (scanPath.isEmpty) continue;
        final dir = Directory(scanPath);
        if (dir.existsSync()) {
          foundPaths.addAll(await _searchRecursive(dir, 2));
        }
      }
    }

    return foundPaths;
  }

  static const _javaDirPatterns = [
    'java', 'jdk', 'jre', 'openjdk',
    'corretto', 'zulu', 'temurin',
  ];

  static bool _isJavaRelatedDir(String dirName) {
    final lower = dirName.toLowerCase();
    for (final pattern in _javaDirPatterns) {
      if (lower.contains(pattern)) return true;
    }
    return false;
  }

  /// 递归搜索给定目录下的所有可能的 Java 安装
  static Future<List<String>> _searchRecursive(Directory dir,
      int depth,) async {
    final List<String> foundPaths = [];
    if (depth <= 0) return foundPaths;

    try {
      final entities = dir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is! Directory) continue;

        if (_isJavaRelatedDir(path.basename(entity.path))) {
          final binDir = Directory(path.join(entity.path, 'bin'));
          if (binDir.existsSync()) {
            final javaExe = path.join(
              binDir.path,
              _getJavaExecutableName(),
            );
            if (File(javaExe).existsSync() &&
                await _validateAndGetVersion(javaExe) != null) {
              foundPaths.add(javaExe);
            }
          }
        }

        if (depth > 1) {
          foundPaths.addAll(await _searchRecursive(entity, depth - 1));
        }
      }
    } catch (_) {}

    return foundPaths;
  }

  /// 递归搜索时提前返回第一个满足版本要求的 Java
  static Future<String?> _searchRecursiveForBest(Directory dir,
      int depth,
      bool Function(int) versionMatches,) async {
    if (depth <= 0) return null;

    try {
      final entities = dir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is! Directory) continue;

        if (_isJavaRelatedDir(path.basename(entity.path))) {
          final binDir = Directory(path.join(entity.path, 'bin'));
          if (binDir.existsSync()) {
            final javaExe = path.join(
              binDir.path,
              _getJavaExecutableName(),
            );
            if (File(javaExe).existsSync()) {
              final version = await _validateAndGetVersion(javaExe);
              if (version != null && versionMatches(version)) {
                return javaExe;
              }
            }
          }
        }

        if (depth > 1) {
          final result = await _searchRecursiveForBest(
            entity,
            depth - 1,
            versionMatches,
          );
          if (result != null) return result;
        }
      }
    } catch (_) {}

    return null;
  }

  /// 扩展路径模式（处理通配符），结果会被缓存
  static List<String> _expandPathPattern(String pathPattern) {
    final resolved = _resolveHome(pathPattern);
    if (_expandedPathCache.containsKey(resolved)) {
      return _expandedPathCache[resolved]!;
    }

    final separator = Platform.isWindows ? '\\' : '/';
    final parts = resolved.split(separator);
    final result = _expandParts(parts, 0, separator);
    _expandedPathCache[resolved] = result;
    return result;
  }

  static List<String> _expandParts(List<String> parts,
      int startIndex,
      String separator,) {
    int wildcardIndex = -1;
    for (int i = startIndex; i < parts.length; i++) {
      if (parts[i].contains('*')) {
        wildcardIndex = i;
        break;
      }
    }

    if (wildcardIndex == -1) {
      final resultPath = parts.join(separator);
      try {
        if (Directory(resultPath).existsSync()) {
          return [resultPath];
        }
      } catch (_) {}
      return [];
    }

    final wildcardSegment = parts[wildcardIndex];
    final parentPath = parts.sublist(0, wildcardIndex).join(separator);

    final List<String> results = [];

    try {
      final parentDir = Directory(parentPath);
      if (!parentDir.existsSync()) return [];

      // 预编译通配符正则
      final escaped = wildcardSegment.replaceAll('*', r'__STAR__');
      final escapedRegex = RegExp.escape(escaped).replaceAll(
        '__STAR__',
        r'.*',
      );
      final regex = RegExp('^$escapedRegex\$', caseSensitive: false);

      final entities = parentDir.listSync(followLinks: false);

      for (final entity in entities) {
        if (entity is! Directory) continue;

        final dirName = path.basename(entity.path);

        if (regex.hasMatch(dirName)) {
          final newParts = [...parts];
          newParts[wildcardIndex] = dirName;
          results.addAll(_expandParts(newParts, wildcardIndex + 1, separator));
        }
      }
    } catch (_) {}

    return results;
  }

  static String _resolveHome(String pathPattern) {
    if (pathPattern.startsWith('~')) {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '';
      if (home.isNotEmpty) {
        return path.join(home, pathPattern.substring(1));
      }
    }
    return pathPattern;
  }

  /// 获取 Java 安装信息（包括版本和路径）
  static Future<List<JavaInfo>> getJavaInstallationsInfo({
    bool deepScan = false,
  }) async {
    final installations = await findAllJavaExecutables(deepScan: deepScan);
    final infoList = <JavaInfo>[];

    for (final javaPath in installations) {
      final version = _versionCache[javaPath];
      infoList.add(JavaInfo(
        path: javaPath,
        version: version,
        isValid: version != null,
      ));
    }

    return infoList;
  }

  /// 根据给定的路径获取 [JavaInfo]。如果不是有效的 Java，返回 null。
  static Future<JavaInfo?> getJavaInfoFromPath(String javaPath) async {
    final version = await _validateAndGetVersion(javaPath);
    if (version == null) return null;

    return JavaInfo(
      path: javaPath,
      version: version,
      isValid: true,
    );
  }
}
