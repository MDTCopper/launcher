import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/data/mindustry/mindustry.dart';
import 'package:copper_launcher/util/io/java/java_finder.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

/// 预览工具（`assets/preview_tools/preview_tools.jar`）调用失败：message 是给界面看的中文原因
class PreviewToolsException implements Exception {
  const PreviewToolsException(this.message);

  /// 给用户看的中文原因
  final String message;

  @override
  String toString() => message;
}

/// 一次预览工具进程的结果
class PreviewToolResult {
  const PreviewToolResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;

  bool get succeeded => exitCode == 0;

  /// 失败时给日志/界面看的尾部输出，避免把整段构建日志塞进异常
  String get outputTail {
    final text = '$stdout\n$stderr'.trim();
    if (text.length <= 800) return text;
    return text.substring(text.length - 800);
  }
}

/// 打包进 assets 的 Java 工具（PackBuilder / MapPreviewExport 等）的运行时封装
///
/// jar 解到 `<数据根>/preview_cache/tools/`；运行时 classpath 必须是
/// `游戏 jar;工具 jar` —— Boot.locateJar() 取 classpath 里第一个 .jar
class PreviewTools {
  /// 工具 jar 在 assets 里的相对路径（pubspec 已登记该目录）
  static const String _jarAssetPath = 'assets/preview_tools/preview_tools.jar';

  /// 工具要求的最低 Java 大版本（jar 用 javac --release 17 编译）
  static const int minJavaMajor = 17;

  /// 单个工具进程的默认超时；生成整个包在开发机约 5s，留足慢机器余量
  static const Duration defaultTimeout = Duration(minutes: 3);

  static Uint8List? _jarBytes;
  static String? _signature;
  static String? _toolJarPath;

  /// 工具 jar 的轻量版本标记（长度 + FNV-1a），jar 换掉就变化
  ///
  /// 资产包用它在 meta 之外判断「工具升级了，包该重建」
  ///
  /// 依赖 `rootBundle` 读 assets，调用方需在 Flutter binding 初始化之后使用
  /// （E2E 用例要先 `TestWidgetsFlutterBinding.ensureInitialized()`）
  static Future<String> signature() async {
    final cached = _signature;
    if (cached != null) return cached;
    final bytes = await _loadJarBytes();
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    _signature = '${bytes.length}-${hash.toRadixString(16).padLeft(8, '0')}';
    return _signature!;
  }

  /// 确保工具 jar 已解到 `<数据根>/preview_cache/tools/preview_tools.jar`，返回 jar 路径
  static Future<String> ensureJar() async {
    final cached = _toolJarPath;
    if (cached != null && await File(cached).exists()) return cached;
    final toolSignature = await signature();
    final toolsDirPath = p.join(AppPaths.previewCache, 'tools');
    final jarPath = p.join(toolsDirPath, 'preview_tools.jar');
    final signaturePath = '$jarPath.sig';
    final signatureFile = File(signaturePath);
    final upToDate =
        await File(jarPath).exists() &&
        await signatureFile.exists() &&
        (await signatureFile.readAsString()).trim() == toolSignature;
    if (!upToDate) {
      await Directory(toolsDirPath).create(recursive: true);
      final bytes = await _loadJarBytes();
      await File(jarPath).writeAsBytes(bytes, flush: true);
      await signatureFile.writeAsString(toolSignature, flush: true);
    }
    _toolJarPath = jarPath;
    return jarPath;
  }

  /// 解析该游戏版本可用的 Java（≥17）：优先版本配置，其次 JavaFinder 兜底
  static Future<String> resolveJava(Mindustry version) async {
    final configured = version.java;
    if (configured != null && configured != 'auto') {
      final javaPath = AppPaths.resolveStoredPath(configured);
      if (await _isSupportedJava(javaPath)) return javaPath;
    }
    final found = await JavaFinder.findBestJava(minVersion: minJavaMajor);
    if (found != null) return found;
    throw const PreviewToolsException('未找到 Java 17+，无法生成蓝图预览资产');
  }

  /// 用游戏 JRE 跑工具 main；classpath 里游戏 jar 在前、工具 jar 在后
  static Future<PreviewToolResult> run(
    String mainClass,
    List<String> arguments, {
    required String gameJarPath,
    required String javaPath,
    Duration timeout = defaultTimeout,
  }) async {
    final toolJarPath = await ensureJar();
    final classPathSeparator = Platform.isWindows ? ';' : ':';
    final classPath = '$gameJarPath$classPathSeparator$toolJarPath';
    final stopwatch = Stopwatch()..start();
    final Process process;
    try {
      process = await Process.start(javaPath, [
        '-cp',
        classPath,
        mainClass,
        ...arguments,
      ]);
    } on ProcessException catch (error) {
      throw PreviewToolsException('启动 Java 失败：${error.message}');
    }
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      throw PreviewToolsException('预览工具超时（${timeout.inSeconds}s）：$mainClass');
    }
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    stopwatch.stop();
    return PreviewToolResult(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      duration: stopwatch.elapsed,
    );
  }

  static Future<bool> _isSupportedJava(String javaPath) async {
    if (!await File(javaPath).exists()) return false;
    final major = await JavaFinder.getJavaVersion(javaPath);
    return major != null && major >= minJavaMajor;
  }

  static Future<Uint8List> _loadJarBytes() async {
    final cached = _jarBytes;
    if (cached != null) return cached;
    try {
      final data = await rootBundle.load(_jarAssetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      _jarBytes = bytes;
      return bytes;
    } on Exception catch (error) {
      throw PreviewToolsException('读取内置预览工具失败：$error');
    }
  }
}
