import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/data/mindustry/mindustry.dart';
import 'package:copper_launcher/domain/preview/asset_store.dart';
import 'package:copper_launcher/domain/preview/blueprint_library.dart';
import 'package:copper_launcher/domain/preview/blueprint_preview_renderer.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/mindustry_save_file/schematic_file.dart';
import 'package:path/path.dart' as p;

/// 蓝图预览的渲染、缩放与缓存
///
/// 缓存分三层：内存里的 [ui.Image]（供列表 / 详情直接贴）、磁盘上的原生尺寸 PNG、
/// 磁盘上的按尺寸变体 PNG；同一张图同一尺寸的并发请求合并成一次
///
/// 资产包按蓝图所属版本准备（全局目录的蓝图用当前选中版本），含 mod 内容的蓝图不渲染
class BlueprintPreviewService {
  BlueprintPreviewService._();

  static final BlueprintPreviewService instance = BlueprintPreviewService._();

  /// 导出 PNG 的上限
  static const int maxExportSize = 2048;

  /// 预览尺寸上限：再大走 [exportPng]，避免把大图塞进内存 LRU
  static const int maxPreviewSize = 1024;

  static const int _maxCachedImages = 32;

  /// 键 = `<cacheKey>@<尺寸>`；Map 的插入顺序即 LRU 顺序
  final Map<String, ui.Image> _images = {};

  final Map<String, Future<String?>> _variantPending = {};
  final Map<String, Future<String?>> _nativePending = {};

  /// 列表缩略图 / 详情图；返回的图像归服务所有，调用方不要 dispose
  ///
  /// 不放大超过原生尺寸的图；含 mod 内容、资产包不可用或文件损坏时返回 null
  Future<ui.Image?> preview(
    BlueprintLibraryEntry entry, {
    int maxSize = 160,
  }) async {
    final size = _normalizeMaxSize(maxSize, maxPreviewSize);
    final key = _variantKey(entry, size);
    final cached = _images[key];
    if (cached != null) {
      _touch(key, cached);
      return cached;
    }
    final String? path;
    try {
      path = await _ensureVariantPng(entry, size);
    } catch (error) {
      _logFailure(entry, '准备预览图', error);
      return null;
    }
    if (path == null) return null;
    try {
      final image = await decodeImage(await File(path).readAsBytes());
      _remember(key, image);
      return image;
    } catch (error) {
      _logFailure(entry, '解码预览图', error);
      return null;
    }
  }

  /// 导出指定尺寸的 PNG 字节；[maxSize] 上限 [maxExportSize]
  Future<Uint8List?> exportPng(
    BlueprintLibraryEntry entry, {
    int maxSize = maxExportSize,
  }) async {
    final size = _normalizeMaxSize(maxSize, maxExportSize);
    final String? path;
    try {
      path = await _ensureVariantPng(entry, size);
    } catch (error) {
      _logFailure(entry, '准备导出的预览图', error);
      return null;
    }
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } on FileSystemException catch (error) {
      _logFailure(entry, '读取导出的预览图', error);
      return null;
    }
  }

  /// 释放内存里的全部预览图（换版本、退出预览时用）
  void clearMemoryCache() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }

  /// 某尺寸的变体 PNG；mod 内容 / 版本缺失 / 渲染失败返回 null
  Future<String?> _ensureVariantPng(BlueprintLibraryEntry entry, int size) {
    if (entry.hasModContent == true) return Future.value(null);
    final key = _variantKey(entry, size);
    final pending = _variantPending[key];
    if (pending != null) return pending;
    final future = _buildVariantPng(entry, size);
    _variantPending[key] = future;
    // 必须用块体：箭头函数会把 remove 的返回值当 Future 继续等
    return future.whenComplete(() {
      _variantPending.remove(key);
    });
  }

  Future<String?> _buildVariantPng(
    BlueprintLibraryEntry entry,
    int size,
  ) async {
    final variantPath = _variantPath(entry, size);
    ui.Image? source;
    ui.Image? scaled;
    try {
      if (await File(variantPath).exists()) return variantPath;
      final nativePath = await _ensureNativePng(entry);
      if (nativePath == null) return null;
      source = await decodeImage(await File(nativePath).readAsBytes());
      scaled = await _scaleToFit(source, size);
      await _writePngAtomic(variantPath, await encodePng(scaled));
      return variantPath;
    } catch (error) {
      _logFailure(entry, '缩放预览图', error);
      return null;
    } finally {
      scaled?.dispose();
      source?.dispose();
    }
  }

  /// 原生尺寸 PNG；同一蓝图并发请求只渲染一次
  Future<String?> _ensureNativePng(BlueprintLibraryEntry entry) {
    final pending = _nativePending[entry.cacheKey];
    if (pending != null) return pending;
    final future = _buildNativePng(entry);
    _nativePending[entry.cacheKey] = future;
    return future.whenComplete(() {
      _nativePending.remove(entry.cacheKey);
    });
  }

  Future<String?> _buildNativePng(BlueprintLibraryEntry entry) async {
    final nativePath = _nativePath(entry);
    try {
      if (await File(nativePath).exists()) return nativePath;
      if (entry.hasModContent == true) return null;
      final version = _versionFor(entry);
      if (version == null) {
        addLog(
          .warning,
          '找不到蓝图 [${entry.name}] 所属的游戏版本，跳过预览',
          tag: 'BlueprintPreview',
        );
        return null;
      }
      final assets = await BlueprintAssetStore.ensure(version);
      final schematic = SchematicFile.fromBytes(
        await File(entry.path).readAsBytes(),
      );
      // 含 mod 内容不渲染，只记录标记
      if (BlueprintLibrary.hasUnknownBlocks(schematic.blockNames, assets)) {
        entry.hasModContent = true;
        return null;
      }
      entry.hasModContent = false;
      final renderer = BlueprintPreviewRenderer(assets);
      final result = await renderer.render(schematic);
      try {
        await _writePngAtomic(nativePath, await encodePng(result.image));
      } finally {
        result.image.dispose();
      }
      return nativePath;
    } on PreviewAssetException catch (error) {
      addLog(
        .warning,
        '蓝图预览资产包不可用 [${entry.name}]：${error.message}',
        tag: 'BlueprintPreview',
      );
      return null;
    } catch (error) {
      _logFailure(entry, '渲染预览', error);
      return null;
    }
  }

  Mindustry? _versionFor(BlueprintLibraryEntry entry) =>
      entry.version ?? config.versionOptions.selectedVersion;

  /// 等比缩到最长边不超过 [maxSize]，原生尺寸更小时不放大
  Future<ui.Image> _scaleToFit(ui.Image source, int maxSize) async {
    final longest = math.max(source.width, source.height);
    final scale = longest <= maxSize ? 1.0 : maxSize / longest;
    final width = math.max(1, (source.width * scale).round());
    final height = math.max(1, (source.height * scale).round());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  void _remember(String key, ui.Image image) {
    _images.remove(key);
    _images[key] = image;
    while (_images.length > _maxCachedImages) {
      final oldestKey = _images.keys.first;
      final oldest = _images.remove(oldestKey);
      oldest?.dispose();
    }
  }

  void _touch(String key, ui.Image image) {
    _images.remove(key);
    _images[key] = image;
  }

  String _variantKey(BlueprintLibraryEntry entry, int size) =>
      '${entry.cacheKey}@$size';

  String _nativePath(BlueprintLibraryEntry entry) =>
      p.join(_cacheDirPath(entry), '${entry.cacheKey}-native.png');

  String _variantPath(BlueprintLibraryEntry entry, int size) =>
      p.join(_cacheDirPath(entry), '${entry.cacheKey}-$size.png');

  String _cacheDirPath(BlueprintLibraryEntry entry) => p.join(
    AppPaths.previewCache,
    'blueprints',
    _safeDirName(entry.versionTag),
  );

  static String _safeDirName(String tag) =>
      tag.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static int _normalizeMaxSize(int size, int limit) {
    if (size < 64) return 64;
    return size > limit ? limit : size;
  }

  /// 先写临时文件再改名，避免半张 PNG 被下次命中
  static Future<void> _writePngAtomic(String path, Uint8List bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.$pid.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(path);
  }

  static void _logFailure(
    BlueprintLibraryEntry entry,
    String action,
    Object error,
  ) {
    addLog(
      .warning,
      '$action失败 [${entry.name}]：$error',
      tag: 'BlueprintPreview',
    );
  }
}
