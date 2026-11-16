import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/data/mindustry/mindustry.dart';
import 'package:copper_launcher/util/io/java/preview_tools.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

import 'blueprint_asset_pack.dart';

/// 蓝图预览资产包生成/加载失败：message 是给界面看的中文原因
class PreviewAssetException implements Exception {
  const PreviewAssetException(this.message);

  /// 给用户看的中文原因
  final String message;

  @override
  String toString() => message;
}

/// 按游戏版本准备蓝图预览资产包
///
/// 包目录 `<预览缓存>/assets/<tag 安全化>/`；同一 tag 只跑一次构建（并发调用共享同一个 Future），
/// meta/content 缺失或工具 jar 版本标记变化时才重建
class BlueprintAssetStore {
  static final Map<String, BlueprintAssetPack> _loaded = {};
  static final Map<String, Future<BlueprintAssetPack>> _pending = {};

  /// 取得该版本的资产包；缺失时用游戏 JRE 跑 PackBuilder 生成后加载
  static Future<BlueprintAssetPack> ensure(Mindustry version) {
    final tag = version.tag;
    final loaded = _loaded[tag];
    if (loaded != null) return Future.value(loaded);
    final pending = _pending[tag];
    if (pending != null) return pending;
    final future = _ensure(version)
        .then((pack) {
          _loaded[tag] = pack;
          return pack;
        })
        // 必须用块体返回 void：箭头函数会把 remove() 的返回值（future 自己）当 Future 等，导致死锁
        .whenComplete(() {
          _pending.remove(tag);
        });
    _pending[tag] = future;
    return future;
  }

  static Future<BlueprintAssetPack> _ensure(Mindustry version) async {
    final packDirPath = p.join(
      AppPaths.previewCache,
      'assets',
      _safeDirName(version.tag),
    );
    final String toolSignature;
    try {
      toolSignature = await PreviewTools.signature();
    } on PreviewToolsException catch (error) {
      throw PreviewAssetException(error.message);
    }
    if (await _isPackUsable(packDirPath, version, toolSignature)) {
      return BlueprintAssetPack.load(packDirPath);
    }
    await _build(version, packDirPath, toolSignature);
    return BlueprintAssetPack.load(packDirPath);
  }

  /// 包可用 = meta/content/工具标记都在，标记一致，且 jar 没被换过
  static Future<bool> _isPackUsable(
    String packDirPath,
    Mindustry version,
    String toolSignature,
  ) async {
    final metaFile = File(p.join(packDirPath, 'meta.json'));
    final contentFile = File(p.join(packDirPath, 'content.json'));
    final markerFile = File(p.join(packDirPath, 'tool.sig'));
    if (!await metaFile.exists() ||
        !await contentFile.exists() ||
        !await markerFile.exists()) {
      return false;
    }
    if ((await markerFile.readAsString()).trim() != toolSignature) {
      return false;
    }
    try {
      final meta = jsonDecode(await metaFile.readAsString());
      final jar = meta is Map<String, dynamic> ? meta['jar'] : null;
      if (jar is String && jar != p.basename(version.resolvedJarPath)) {
        return false;
      }
    } on FormatException {
      return false;
    }
    return true;
  }

  static Future<void> _build(
    Mindustry version,
    String packDirPath,
    String toolSignature,
  ) async {
    final gameJarPath = version.resolvedJarPath;
    if (!await File(gameJarPath).exists()) {
      throw PreviewAssetException('游戏本体不存在，无法生成预览资产：$gameJarPath');
    }
    try {
      final javaPath = await PreviewTools.resolveJava(version);
      addLog(
        .info,
        '开始生成蓝图预览资产包：${version.tag}（Java $javaPath）',
        tag: 'Preview',
      );
      final stopwatch = Stopwatch()..start();
      final result = await PreviewTools.run(
        'PackBuilder',
        [gameJarPath, packDirPath, version.tag],
        gameJarPath: gameJarPath,
        javaPath: javaPath,
      );
      if (!result.succeeded) {
        await _deleteQuietly(packDirPath);
        throw PreviewAssetException(
          '生成蓝图预览资产包失败（exit ${result.exitCode}）：${result.outputTail}',
        );
      }
      await File(
        p.join(packDirPath, 'tool.sig'),
      ).writeAsString(toolSignature, flush: true);
      addLog(
        .info,
        '蓝图预览资产包已生成：${version.tag}，'
        '用时 ${stopwatch.elapsed.inMilliseconds} ms',
        tag: 'Preview',
      );
    } on PreviewToolsException catch (error) {
      await _deleteQuietly(packDirPath);
      throw PreviewAssetException(error.message);
    }
  }

  /// tag 里可能有空格与非法文件名字符，换成安全目录名
  static String _safeDirName(String tag) =>
      tag.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static Future<void> _deleteQuietly(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // 清理失败不影响抛出的原始错误
    }
  }
}
