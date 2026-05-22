import 'dart:io';

import 'package:path/path.dart' as path;

class JavaFinder {
  /// 常见的 Java 安装路径（根据不同操作系统）
  static List<String> getCommonJavaPaths() {
    final List<String> paths = [];

    if (Platform.isWindows) {
      // Windows 常见 Java 安装路径
      paths.addAll([
        // Oracle JDK/JRE
        r'C:\Program Files\Java\jdk-*\bin',
        r'C:\Program Files\Java\jre-*\bin',
        r'C:\Program Files\Java\*\bin',
        r'C:\Program Files\jdk-*\bin',
        r'C:\Program Files\jre-*\bin',
        // OpenJDK distributions
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

        // Alternative locations
        r'C:\jdk*\bin',
        r'C:\java*\bin',
        r'C:\Program Files\JavaSoft\*\bin',
        r'C:\Program Files\IBM\*\bin',
        r'C:\Program Files\RedHat\*\bin',

        // Portable installations
        r'D:\Program Files\Java\*\bin',
        r'E:\Program Files\Java\*\bin',
        r'C:\Tools\Java\*\bin',
        r'C:\Software\jdk*\bin',
        r'C:\Development\Java\*\bin',
      ]);
    } else if (Platform.isLinux) {
      // Linux 常见 Java 安装路径
      paths.addAll([
        // Standard locations
        '/usr/lib/jvm/*',
        '/usr/java/latest/bin',
        '/usr/lib/jvm/default-java/bin',

        // OpenJDK versions
        '/usr/lib/jvm/java-8-openjdk-*/bin',
        '/usr/lib/jvm/java-11-openjdk-*/bin',
        '/usr/lib/jvm/java-17-openjdk-*/bin',
        '/usr/lib/jvm/java-21-openjdk-*/bin',

        // Alternative locations
        '/opt/java/openjdk/bin',
        '/opt/adoptopenjdk/*/bin',
        '/opt/ibm/java/*/bin',
        '/opt/oracle/jdk/*/bin',
        '/opt/amazon-corretto/*/bin',
        '/opt/microsoft/temurin/*/bin',

        // Home directory installations
        '/home/*/jdk*/bin',
        '/home/*/.sdkman/candidates/java/*/bin',
        '/home/*/java*/bin',

        // Development tools
        '/usr/local/sdkman/candidates/java/*/bin',
        '/usr/local/java*/bin',
      ]);
    } else if (Platform.isMacOS) {
      // macOS 常见 Java 安装路径
      paths.addAll([
        // Standard locations
        '/Library/Java/JavaVirtualMachines/*/Contents/Home/bin',
        '/System/Library/Frameworks/JavaVM.framework/Versions/*/Commands',

        // Homebrew installations
        '/usr/local/Cellar/openjdk/*/libexec/openjdk.jdk/Contents/Home/bin',
        '/opt/homebrew/Cellar/openjdk/*/libexec/openjdk.jdk/Contents/Home/bin',

        // SDKMAN installations
        '/Users/*/Library/Caches/JetBrains/*/consoles/java/*/bin',
        '/Users/*/.sdkman/candidates/java/*/bin',

        // Alternative locations
        '~/Library/Java/JavaVirtualMachines/*/Contents/Home/bin',
        '/Applications/Xcode.app/Contents/Applications/Application Loader.app/Contents/itms/java/bin',
        '/System/Volumes/Data/opt/homebrew/Cellar/openjdk/*/bin',
      ]);
    }

    return paths;
  }

  /// 递归搜索给定目录下的所有可能的 Java 安装
  static Future<List<String>> _searchRecursive(Directory dir, int depth) async {
    final List<String> foundPaths = [];

    if (depth <= 0) return foundPaths;

    try {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          // 检查当前目录是否可能是 Java 安装目录
          final dirName = path.basename(entity.path).toLowerCase();

          if (dirName.contains('java') ||
              dirName.contains('jdk') ||
              dirName.contains('jre') ||
              dirName.contains('openjdk') ||
              dirName.contains('corretto') ||
              dirName.contains('zulu') ||
              dirName.contains('temurin')) {
            // 检查该目录下是否有 bin 目录
            final binDir = Directory(path.join(entity.path, 'bin'));
            if (await binDir.exists()) {
              final javaExe = path.join(binDir.path, _getJavaExecutableName());
              if (await File(javaExe).exists()) {
                foundPaths.add(javaExe);
              }
            }
          }

          // 递归搜索子目录，但限制深度
          if (depth > 1) {
            foundPaths.addAll(await _searchRecursive(entity, depth - 1));
          }
        }
      }
    } catch (e) {
      // 忽略权限错误或其他访问错误
    }

    return foundPaths;
  }

  /// 检查给定的 Java 可执行文件是否有效
  static Future<bool> isValidJavaExecutable(String javaPath) async {
    try {
      final process = await Process.run(javaPath, [
        '-version',
      ], runInShell: true);

      // Java -version 输出到 stderr，所以我们检查两个输出流
      final output = process.stdout.toString() + process.stderr.toString();

      return output.contains('java version') ||
          output.contains('openjdk version') ||
          process.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// 在系统中查找所有有效的 Java 可执行文件（扩大搜索范围）
  static Future<List<String>> findAllJavaExecutables({
    bool deepScan = false,
  }) async {
    final Set<String> foundJavaPaths = <String>{};

    // 首先检查环境变量中的 Java
    final envJava = await findJavaInEnvironment();
    if (envJava != null) {
      foundJavaPaths.add(envJava);
    }

    // 搜索常见安装路径
    final commonPaths = getCommonJavaPaths();
    for (final rawPathPattern in commonPaths) {
      try {
        final expandedPaths = _expandPathPattern(rawPathPattern);
        for (final expandedPath in expandedPaths) {
          final javaExe = path.join(expandedPath, _getJavaExecutableName());
          if (await File(javaExe).exists() &&
              await isValidJavaExecutable(javaExe)) {
            foundJavaPaths.add(javaExe);
          }
        }
      } catch (e) {
        // 如果当前路径导致错误，则继续下一个路径
        continue;
      }
    }

    // 如果启用了深度扫描，则进行更广泛的搜索
    if (deepScan) {
      final deepResults = await _performDeepScan();
      foundJavaPaths.addAll(deepResults);
    }

    return foundJavaPaths.toList();
  }

  /// 执行深度扫描，搜索更多可能的 Java 安装
  static Future<List<String>> _performDeepScan() async {
    final List<String> foundPaths = [];

    if (Platform.isWindows) {
      // 在 Windows 上扫描常用驱动器
      final drives = ['C:', 'D:', 'E:', 'F:'];
      for (final drive in drives) {
        final rootDir = Directory('$drive\\');
        if (rootDir.existsSync()) {
          // 搜索特定的目录名称
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
              foundPaths.addAll(await _searchRecursive(dir, 3)); // 限制搜索深度为3
            }
          }
        }
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      // 在类 Unix 系统上扫描更多位置
      final scanPaths = [
        '/opt',
        '/usr/local',
        '/usr/share',
        '/home',
        Platform.environment['HOME'] ?? '',
      ];

      for (final scanPath in scanPaths) {
        if (scanPath.isNotEmpty) {
          final dir = Directory(scanPath);
          if (dir.existsSync()) {
            foundPaths.addAll(await _searchRecursive(dir, 2)); // 限制搜索深度为2
          }
        }
      }
    }

    return foundPaths;
  }

  /// 扩展路径模式（处理通配符）
  static List<String> _expandPathPattern(String pathPattern) {
    final List<String> results = [];

    if (pathPattern.contains('*')) {
      // 分割路径并找到通配符的位置
      final parts =
          Platform.isWindows ? pathPattern.split('\\') : pathPattern.split('/');

      int wildcardIndex = -1;
      for (int i = 0; i < parts.length; i++) {
        if (parts[i] == '*') {
          wildcardIndex = i;
          break;
        }
      }

      if (wildcardIndex != -1) {
        // 构建父目录路径
        final parentParts = parts.sublist(0, wildcardIndex);
        final parentPath =
            Platform.isWindows ? parentParts.join('\\') : parentParts.join('/');

        try {
          final parentDir = Directory(parentPath);
          if (parentDir.existsSync()) {
            final entities = parentDir.listSync();

            for (final entity in entities) {
              if (entity is Directory) {
                // 替换通配符部分并构建完整路径
                final newPathParts = [...parts];
                newPathParts[wildcardIndex] = path.basename(entity.path);

                final resultPath =
                    Platform.isWindows
                        ? newPathParts.join('\\')
                        : newPathParts.join('/');

                if (Directory(resultPath).existsSync()) {
                  results.add(resultPath);
                }
              }
            }
          }
        } catch (e) {
          // 如果访问目录时出错，则跳过
        }
      }
    } else {
      // 如果没有通配符，直接添加路径
      results.add(pathPattern);
    }

    return results;
  }

  /// 获取适用于当前操作系统的 Java 可执行文件名
  static String _getJavaExecutableName() {
    return Platform.isWindows ? 'java.exe' : 'java';
  }

  /// 在环境 PATH 中查找 Java 可执行文件
  static Future<String?> findJavaInEnvironment() async {
    try {
      // 首先尝试通过 Process.run 方式查找
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'java',
      ], runInShell: true);

      if (result.exitCode == 0) {
        String javaPath =
            result.stdout.toString().trim().split('\n')[0]; // 取第一个结果

        if (javaPath.isNotEmpty && javaPath != 'java') {
          // 规范化路径
          javaPath = path.normalize(javaPath);

          // 如果已经是完整的 Java 可执行文件路径，返回它
          if (await isValidJavaExecutable(javaPath)) {
            return javaPath;
          }
        }
      }
    } catch (e) {
      // 如果环境查找失败，回退到手动搜索
    }

    // 回退：手动检查 PATH 环境变量
    final pathEnv = Platform.environment['PATH'];
    if (pathEnv != null) {
      final pathSeparator = Platform.isWindows ? ';' : ':';
      final paths = pathEnv.split(pathSeparator);

      for (final p in paths) {
        final javaPath = path.join(p, _getJavaExecutableName());
        if (await File(javaPath).exists() &&
            await isValidJavaExecutable(javaPath)) {
          return javaPath;
        }
      }
    }

    return null;
  }

  /// 根据版本要求查找最佳的 Java 可执行文件
  static Future<String?> findBestJava({
    int? minVersion,
    int? maxVersion,
    List<String>? preferredPaths,
    bool deepScan = false,
  }) async {
    // 首先尝试首选路径（如果有）
    if (preferredPaths != null) {
      for (final javaPath in preferredPaths) {
        if (await isValidJavaExecutable(javaPath)) {
          final version = await getJavaVersion(javaPath);
          if (version != null) {
            if ((minVersion == null || version >= minVersion) &&
                (maxVersion == null || version <= maxVersion)) {
              return javaPath;
            }
          }
        }
      }
    }

    // 尝试环境中的 Java
    final envJava = await findJavaInEnvironment();
    if (envJava != null) {
      final version = await getJavaVersion(envJava);
      if (version != null) {
        if ((minVersion == null || version >= minVersion) &&
            (maxVersion == null || version <= maxVersion)) {
          return envJava;
        }
      }
    }

    // 最后搜索所有可能的位置（包括深度扫描）
    final allJavaPaths = await findAllJavaExecutables(deepScan: deepScan);
    for (final javaPath in allJavaPaths) {
      final version = await getJavaVersion(javaPath);
      if (version != null) {
        if ((minVersion == null || version >= minVersion) &&
            (maxVersion == null || version <= maxVersion)) {
          return javaPath;
        }
      }
    }

    return null;
  }

  /// 获取 Java 可执行文件的版本
  static Future<int?> getJavaVersion(String javaPath) async {
    try {
      final process = await Process.run(javaPath, [
        '-version',
      ], runInShell: true);

      // Java 版本信息通过 stderr 输出
      final output = process.stderr.toString();

      // 提取版本号，例如：
      // openjdk version "17.0.2" 2022-01-18
      // java version "1.8.0_311"
      RegExp exp = RegExp(r'"(\d+(?:\.\d+)*|\d+)"');
      final match = exp.firstMatch(output);

      if (match != null) {
        String versionStr = match.group(1)!;

        // 处理旧版本格式如 "1.8.0_311" -> 主版本号是 8
        // 或新版本格式如 "17.0.2" -> 主版本号是 17
        if (versionStr.startsWith('1.')) {
          // 对于旧版版本号（1.8、1.7 等），提取第二个数字
          final parts = versionStr.split('.');
          if (parts.length > 1) {
            return int.tryParse(parts[1]);
          }
        } else {
          // 对于新版版本号（9、10、11 等），提取第一个数字
          final parts = versionStr.split('.');
          if (parts.isNotEmpty) {
            return int.tryParse(parts[0]);
          }
        }
      }
    } catch (e) {
      // 如果获取版本失败，返回 null
    }

    return null;
  }

  /// 获取 Java 安装信息（包括版本和路径）
  static Future<List<Map<String, dynamic>>> getJavaInstallationsInfo({
    bool deepScan = false,
  }) async {
    final installations = await findAllJavaExecutables(deepScan: deepScan);
    final infoList = <Map<String, dynamic>>[];

    for (final javaPath in installations) {
      final version = await getJavaVersion(javaPath);
      infoList.add({
        'path': javaPath,
        'version': version,
        'isValid': await isValidJavaExecutable(javaPath),
      });
    }

    return infoList;
  }
}
