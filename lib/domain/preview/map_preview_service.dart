import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/data/mindustry/mindustry.dart';
import 'package:copper_launcher/util/io/java/preview_tools.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

/// 地图缩略图服务：优先复用游戏已生成的 `previews/*_v2.png`，缺失时用
/// `MapPreviewExport`（纯 CPU，无 GL）生成并写入启动器缓存
///
/// 缓存分两层：`<预览缓存>/maps/<tag>/<源文件 hash>.png` 是全尺寸原图，
/// `<hash>-<maxSize>.png` 是缩略图变体；源文件 hash 由相对路径 + mtime + size 算出
/// （地图被替换后自然失效），同一目标的并发请求只跑一次
class MapPreviewService {
  static const String _logTag = 'Preview';

  /// 缩略图默认最大边
  static const int defaultMaxSize = 512;

  /// 内存里留几张已解码的图，给列表滚动时省掉重复解码；超出按插入顺序丢最旧的
  static const int _memoryCacheLimit = 8;

  static final Map<String, Future<String?>> _pending = {};
  static final Map<String, ui.Image> _memoryImages = {};

  /// 取地图缩略图；失败返回 null（只记 warning 日志，不向 UI 抛异常）
  ///
  /// 返回的 [ui.Image] 由本服务缓存持有，调用方**不要 dispose**
  static Future<ui.Image?> previewImage(
    Mindustry version,
    String mapFilePath, {
    int maxSize = defaultMaxSize,
  }) async {
    final imagePath = await _ensurePreviewFile(version, mapFilePath, maxSize);
    if (imagePath == null) return null;
    final cached = _memoryImages.remove(imagePath);
    if (cached != null) {
      // 重新插到末尾，保持「最近用过的留得久」
      _memoryImages[imagePath] = cached;
      return cached;
    }
    try {
      final image = await _decodePng(await File(imagePath).readAsBytes());
      _memoryImages[imagePath] = image;
      while (_memoryImages.length > _memoryCacheLimit) {
        // 预览图很小，被淘汰的交回 GC；显式 dispose 可能弄坏还在绘制的控件
        _memoryImages.remove(_memoryImages.keys.first);
      }
      return image;
    } on Object catch (error) {
      _warn('读取地图预览失败[$mapFilePath]：$error');
      return null;
    }
  }

  /// 取缩略图 PNG 字节（供 `Image.memory` 一类场景）；失败返回 null
  static Future<Uint8List?> previewBytes(
    Mindustry version,
    String mapFilePath, {
    int maxSize = defaultMaxSize,
  }) async {
    final imagePath = await _ensurePreviewFile(version, mapFilePath, maxSize);
    if (imagePath == null) return null;
    try {
      return await File(imagePath).readAsBytes();
    } on Object catch (error) {
      _warn('读取地图预览失败[$mapFilePath]：$error');
      return null;
    }
  }

  /// 保证目标 PNG 存在，返回可直接读取的路径；优先级：启动器缓存 → 游戏 previews → 工具生成
  static Future<String?> _ensurePreviewFile(
    Mindustry version,
    String mapFilePath,
    int maxSize,
  ) async {
    final size = maxSize <= 0 ? defaultMaxSize : maxSize;
    final mapFile = File(mapFilePath);
    if (!await mapFile.exists()) {
      _warn('地图文件不存在，跳过预览：$mapFilePath');
      return null;
    }
    final String nativePath;
    final String variantPath;
    try {
      final stat = await mapFile.stat();
      final sourceKey = _sourceKey(version, mapFilePath, stat);
      final cacheDirPath = _cacheDirPath(version);
      nativePath = p.join(cacheDirPath, '$sourceKey-native.png');
      variantPath = p.join(cacheDirPath, '$sourceKey-$size.png');
    } on Object catch (error) {
      _warn('计算地图预览缓存路径失败[$mapFilePath]：$error');
      return null;
    }

    try {
      if (await _isUsableImage(variantPath)) return variantPath;
      final native = await _singleFlight(
        nativePath,
        () => _ensureNative(version, mapFilePath, nativePath),
      );
      if (native == null) return null;
      if (!await _exceedsMaxSize(native, size)) return native;
      return await _singleFlight(variantPath, () async {
        if (await _isUsableImage(variantPath)) return variantPath;
        await _resizeInto(native, variantPath, size);
        return variantPath;
      });
    } on Object catch (error) {
      _warn('地图预览准备失败[$mapFilePath]：$error');
      return null;
    }
  }

  /// 全尺寸原图：已有缓存直接用；游戏生成过就复制过来（不启 Java）；都没有才调工具
  static Future<String?> _ensureNative(
    Mindustry version,
    String mapFilePath,
    String nativePath,
  ) async {
    if (await _isUsableImage(nativePath)) return nativePath;
    final gamePreviewPath = p.join(
      version.dataPath,
      'previews',
      '${p.basenameWithoutExtension(mapFilePath)}_v2.png',
    );
    if (await _isUsableImage(gamePreviewPath)) {
      await Directory(p.dirname(nativePath)).create(recursive: true);
      final copyTempPath = '$nativePath.copy.tmp';
      try {
        await File(gamePreviewPath).copy(copyTempPath);
        await File(copyTempPath).rename(nativePath);
      } finally {
        await _deleteQuietly(copyTempPath);
      }
      return nativePath;
    }
    return _generate(version, mapFilePath, nativePath);
  }

  /// 用游戏 jar 的 MapPreviewExport 生成全尺寸 PNG；工具结果先写临时文件再改名
  static Future<String?> _generate(
    Mindustry version,
    String mapFilePath,
    String nativePath,
  ) async {
    final gameJarPath = version.resolvedJarPath;
    if (!await File(gameJarPath).exists()) {
      _warn('游戏本体不存在，无法生成地图预览：$gameJarPath');
      return null;
    }
    final tempPath = '$nativePath.part';
    final stopwatch = Stopwatch()..start();
    try {
      final javaPath = await PreviewTools.resolveJava(version);
      addLog(
        .info,
        '开始生成地图预览：${p.basename(mapFilePath)}（Java $javaPath）',
        tag: _logTag,
      );
      await Directory(p.dirname(nativePath)).create(recursive: true);
      final result = await PreviewTools.run(
        'MapPreviewExport',
        [File(mapFilePath).absolute.path, tempPath],
        gameJarPath: gameJarPath,
        javaPath: javaPath,
      );
      if (!result.succeeded || !await File(tempPath).exists()) {
        await _deleteQuietly(tempPath);
        _warn('生成地图预览失败（exit ${result.exitCode}）：${result.outputTail}');
        return null;
      }
      await File(tempPath).rename(nativePath);
      addLog(
        .info,
        '地图预览已生成：${p.basename(mapFilePath)}，'
        '用时 ${stopwatch.elapsedMilliseconds} ms',
        tag: _logTag,
      );
      return nativePath;
    } on PreviewToolsException catch (error) {
      await _deleteQuietly(tempPath);
      _warn(error.message);
      return null;
    } on Object catch (error) {
      await _deleteQuietly(tempPath);
      _warn('生成地图预览失败[$mapFilePath]：$error');
      return null;
    }
  }

  static Future<String?> _singleFlight(
    String key,
    Future<String?> Function() action,
  ) {
    final pending = _pending[key];
    if (pending != null) return pending;
    final future = action();
    _pending[key] = future;
    return future.whenComplete(() {
      _pending.remove(key);
    });
  }

  static Future<void> _resizeInto(
    String sourcePath,
    String targetPath,
    int maxSize,
  ) async {
    final bytes = await File(sourcePath).readAsBytes();
    final size = _pngSize(bytes);
    if (size == null) throw const FormatException('无法解析 PNG 尺寸');
    final scale = maxSize / math.max(size.width, size.height);
    final width = math.max(1, (size.width * scale).round());
    final height = math.max(1, (size.height * scale).round());
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: width,
      targetHeight: height,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null) throw StateError('缩略图编码失败');
        // 先写临时文件再改名，避免半张 PNG 被下次命中
        final tempPath = '$targetPath.$pid.tmp';
        try {
          await File(tempPath).writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
          await File(tempPath).rename(targetPath);
        } finally {
          await _deleteQuietly(tempPath);
        }
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// 缓存目录按 tag 分；tag 里可能有空格与非法文件名字符
  static String _cacheDirPath(Mindustry version) {
    final safeTag = version.tag.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return p.join(
      AppPaths.previewCache,
      'maps',
      safeTag.isEmpty ? 'unknown' : safeTag,
    );
  }

  /// 源文件指纹：相对路径（版本内）+ mtime + size，FNV-1a 32
  static String _sourceKey(
    Mindustry version,
    String mapFilePath,
    FileStat stat,
  ) {
    final relativePath = p.relative(mapFilePath, from: version.mapsPath);
    final source =
        '$relativePath|${stat.modified.millisecondsSinceEpoch}|${stat.size}';
    var hash = 0x811c9dc5;
    for (final unit in source.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Future<bool> _isUsableImage(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    return await file.length() > 0;
  }

  static Future<bool> _exceedsMaxSize(String pngPath, int maxSize) async {
    final size = _pngSize(await File(pngPath).readAsBytes());
    if (size == null) return false;
    return size.width > maxSize || size.height > maxSize;
  }

  static Future<ui.Image> _decodePng(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  /// PNG 的 IHDR 固定在前 24 字节：宽度、高度各 4 字节大端
  static ui.Size? _pngSize(Uint8List bytes) {
    if (bytes.length < 24) return null;
    final data = ByteData.sublistView(bytes, 16, 24);
    return ui.Size(data.getUint32(0).toDouble(), data.getUint32(4).toDouble());
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 清理失败不影响主流程
    }
  }

  static void _warn(String message) {
    addLog(.warning, message, tag: _logTag);
  }
}
