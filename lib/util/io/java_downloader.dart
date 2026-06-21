import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:copperlauncher_main/util/io/http_helper.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;

class JavaReleaseInfo {
  final int majorVersion;
  final String version;
  final String downloadUrl;
  final int size;

  const JavaReleaseInfo({
    required this.majorVersion,
    required this.version,
    required this.downloadUrl,
    required this.size,
  });
}

class EnvironmentConfigResult {
  bool javaHomeSet = false;
  bool javaHomeAlreadySet = false;
  bool pathUpdated = false;
  String? javaHome;
  String? existingJavaHome;

  bool get isFullyConfigured =>
      (javaHomeSet || javaHomeAlreadySet) && pathUpdated;
}

class JavaDownloader {
  static const String _apiBase = 'https://api.adoptium.net/v3';

  /// 获取可用的 Java 主版本号列表（8 及以上）
  static Future<List<int>> getAvailableVersions() async {
    try {
      final response = await HttpHelper().get(
        '$_apiBase/info/available_releases',
        responseType: ResponseType.json,
      );
      final data = response.data;
      if (data != null && data['available_releases'] is List) {
        final releases = data['available_releases'] as List;
        return releases
            .map((v) => (v as num).toInt())
            .where((v) => v >= 8)
            .toList()
          ..sort();
      }
    } catch (_) {}
    return [8, 11, 17, 21];
  }

  /// 获取某个主版本的发布信息（下载链接、大小等）
  static Future<JavaReleaseInfo?> getReleaseInfo(int version) async {
    try {
      final platformStr = _getPlatformString();
      final arch = _getArchString();

      final response = await HttpHelper().get(
        '$_apiBase/assets/latest/$version/hotspot',
        responseType: ResponseType.json,
      );

      final List releases = response.data as List;
      for (final release in releases) {
        if (release is! Map) continue;

        final binaries = release['binaries'] as List?;
        if (binaries == null) continue;

        for (final binary in binaries) {
          if (binary is! Map) continue;

          final os = binary['os']?.toString();
          final architecture = binary['architecture']?.toString();
          final imageType = binary['image_type']?.toString();
          final pkg = binary['package'] as Map<String, dynamic>?;

          if (os == platformStr &&
              architecture == arch &&
              imageType == 'jdk' &&
              pkg != null) {
            final versionData =
                release['version_data'] as Map<String, dynamic>?;

            return JavaReleaseInfo(
              majorVersion: version,
              version: versionData?['semver']?.toString() ?? version.toString(),
              downloadUrl: pkg['link']?.toString() ?? '',
              size: (pkg['size'] as num?)?.toInt() ?? 0,
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 下载并解压 Java，返回 java 可执行文件的路径
  static Future<String?> downloadAndInstall({
    required int version,
    required String installDir,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('正在获取Java版本信息...');
    final info = await getReleaseInfo(version);
    if (info == null) {
      onStatus?.call('无法获取Java $version 的版本信息');
      return null;
    }

    onStatus?.call('正在下载Java ${info.version}...');

    final archiveName =
        Platform.isWindows
            ? 'java-$version-temp.zip'
            : 'java-$version-temp.tar.gz';
    final archivePath = path.join(installDir, archiveName);
    final extractDir = path.join(installDir, 'jdk-$version');

    await Directory(installDir).create(recursive: true);

    try {
      await HttpHelper().download(
        url: info.downloadUrl,
        savePath: archivePath,
        cancelToken: cancelToken,
        onStatus: (state) {
          onProgress?.call(state.progress);
        },
      );

      onStatus?.call('正在解压Java...');
      await _extractArchive(archivePath, extractDir);

      await File(archivePath).delete();

      final javaExe = _findJavaExecutable(extractDir);
      if (javaExe == null) {
        onStatus?.call('解压完成但未找到Java可执行文件');
        return null;
      }

      onStatus?.call('Java ${info.version} 安装完成');
      return javaExe;
    } catch (e) {
      onStatus?.call('安装失败: $e');
      if (await File(archivePath).exists()) {
        await File(archivePath).delete();
      }
      if (await Directory(extractDir).exists()) {
        await Directory(extractDir).delete(recursive: true);
      }
      return null;
    }
  }

  /// 解压 zip 存档到指定目录
  static Future<void> _extractArchive(
    String archivePath,
    String extractDir,
  ) async {
    final bytes = await File(archivePath).readAsBytes();

    if (archivePath.endsWith('.zip')) {
      final decoder = ZipDecoder();
      final archive = decoder.decodeBytes(bytes);
      await _extractToDisk(archive, extractDir);
    } else if (archivePath.endsWith('.tar.gz')) {
      // tar.gz 暂未实现
      throw UnsupportedError('暂不支持 tar.gz 解压');
    }
  }

  static Future<void> _extractToDisk(Archive archive, String extractDir) async {
    for (final file in archive.files) {
      if (file.isFile) {
        final outputPath = path.normalize(path.join(extractDir, file.name));
        final outputFile = File(outputPath);
        if (!await outputFile.parent.exists()) {
          await outputFile.parent.create(recursive: true);
        }
        await outputFile.writeAsBytes(file.content as List<int>);
      }
    }
  }

  /// 在解压目录中查找 java 可执行文件
  static String? _findJavaExecutable(String dir) {
    final javaExeName = Platform.isWindows ? 'java.exe' : 'java';
    final directory = Directory(dir);
    if (!directory.existsSync()) return null;

    // 检查目录本身
    final directPath = path.join(dir, 'bin', javaExeName);
    if (File(directPath).existsSync()) return directPath;

    // 检查一层子目录（解压后通常有一层顶层文件夹）
    for (final entity in directory.listSync()) {
      if (entity is Directory) {
        final javaPath = path.join(entity.path, 'bin', javaExeName);
        if (File(javaPath).existsSync()) return javaPath;
      }
    }

    return null;
  }

  /// 配置 JAVA_HOME 和 PATH 环境变量
  ///
  /// JAVA_HOME 只能有一个，如果已经存在则不会覆盖。
  /// PATH 中可以存在多个 Java 路径，如果当前 bin 目录不在 PATH 中则追加。
  static Future<EnvironmentConfigResult> configureEnvironmentVariables(
    String javaHomePath,
  ) async {
    // javaHomePath 是 java.exe 的路径，需要取其上层 bin 的上级目录作为 JAVA_HOME
    final javaExeName = Platform.isWindows ? 'java.exe' : 'java';
    final javaHome =
        javaHomePath.endsWith(javaExeName)
            ? path.dirname(path.dirname(javaHomePath))
            : javaHomePath;

    final result = EnvironmentConfigResult();

    if (Platform.isWindows) {
      final existingJavaHome = Platform.environment['JAVA_HOME'];

      if (existingJavaHome != null && existingJavaHome.isNotEmpty) {
        result.javaHomeAlreadySet = true;
        result.existingJavaHome = existingJavaHome;
      } else {
        try {
          await Process.run('setx', [
            'JAVA_HOME',
            javaHome,
          ], runInShell: false).timeout(const Duration(seconds: 10));
          result.javaHomeSet = true;
          result.javaHome = javaHome;
        } catch (_) {}
      }

      // 追加 Java bin 到 PATH
      final binDir = path.join(javaHome, 'bin');
      final existingPath = Platform.environment['PATH'] ?? '';

      if (!existingPath.toLowerCase().contains(binDir.toLowerCase())) {
        try {
          final newPath =
              existingPath.endsWith(';')
                  ? '$existingPath$binDir'
                  : '$existingPath;$binDir';
          await Process.run('setx', [
            'PATH',
            newPath,
          ], runInShell: false).timeout(const Duration(seconds: 10));
          result.pathUpdated = true;
        } catch (_) {}
      } else {
        result.pathUpdated = true;
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      final existingJavaHome = Platform.environment['JAVA_HOME'];

      if (existingJavaHome != null && existingJavaHome.isNotEmpty) {
        result.javaHomeAlreadySet = true;
        result.existingJavaHome = existingJavaHome;
      } else {
        result.javaHomeSet = true;
        result.javaHome = javaHome;
        await _appendToShellProfiles(javaHome);
      }
    }

    return result;
  }

  /// 将 JAVA_HOME 导出语句追加到 shell 配置文件
  static Future<void> _appendToShellProfiles(String javaHome) async {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    if (home.isEmpty) return;

    final exportLine =
        '\n# Java - Added by CopperLauncher\n'
        'export JAVA_HOME="$javaHome"\n'
        'export PATH="\$JAVA_HOME/bin:\$PATH"\n';

    final profiles = [
      path.join(home, '.bashrc'),
      path.join(home, '.zshrc'),
      path.join(home, '.profile'),
    ];

    for (final profile in profiles) {
      final file = File(profile);
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          if (!content.contains('JAVA_HOME')) {
            await file.writeAsString(
              '$content$exportLine',
              mode: FileMode.append,
            );
          }
        } catch (_) {}
      }
    }
  }

  static String _getPlatformString() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'mac';
    return 'linux';
  }

  static String _getArchString() {
    if (Platform.isWindows) {
      final arch =
          Platform.environment['PROCESSOR_ARCHITECTURE']?.toLowerCase();
      if (arch == 'arm64') return 'aarch64';
      return 'x64';
    }
    if (Platform.isMacOS) {
      try {
        final result = Process.runSync('uname', ['-m'], runInShell: false);
        if (result.stdout.toString().trim() == 'arm64') return 'aarch64';
      } catch (_) {}
      return 'x64';
    }
    if (Platform.isLinux) {
      try {
        final result = Process.runSync('uname', ['-m'], runInShell: false);
        final machine = result.stdout.toString().trim();
        if (machine == 'aarch64') return 'aarch64';
      } catch (_) {}
      return 'x64';
    }
    return 'x64';
  }
}
