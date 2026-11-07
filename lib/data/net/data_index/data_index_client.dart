import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/app_constant.dart';
import '../../../core/app_paths.dart';
import '../../../util/format/string_cleaner.dart';
import '../../../util/io/copper_io.dart';
import '../../../util/io/log.dart';
import '../mindustry/mindustry_release.dart';
import '../mindustry/mindustry_release_list_snapshot.dart';
import 'data_index_models.dart';

/// 公共数据索引（[dataIndexRepo]）的读取与本地缓存
///
/// - 请求走 [cio]（自带 github 镜像回退与系统代理）
/// - 缓存落在 [AppPaths.dataIndexCache]，按远端相对路径存
///   （`index.json` / `releases/<owner>/<repo>.json` / `mindustry/versions.json`）
/// - 每类数据有自己的有效期：没过期直接用缓存，过期才重拉；拉取失败回落到旧缓存，
///   离线时仍能检查更新
class DataIndexClient {
  /// 模组索引有效期：索引每 2 小时刷新一次
  static const Duration modIndexMaxAge = Duration(hours: 2);

  /// per-mod 版本文件有效期：最新 100 个 tag 每 2 小时刷新
  static const Duration modReleasesMaxAge = Duration(hours: 2);

  /// 游戏版本列表有效期：索引每约 30 分钟刷新一次
  static const Duration mindustryVersionsMaxAge = Duration(minutes: 30);

  /// 模组索引：官方列表（默认可见项）/ 社区列表
  static Future<DataIndexModIndex?> loadModIndex({
    bool community = false,
    bool refresh = false,
  }) async {
    final content = await loadText(
      community ? 'community/index.json' : 'index.json',
      maxAge: modIndexMaxAge,
      refresh: refresh,
    );
    if (content == null) return null;

    final index = DataIndexModIndex.parse(content);
    if (index == null) {
      addLog(
        .warning,
        '模组索引解析失败（${community ? '社区' : '官方'}）',
        tag: 'DataIndex',
      );
    }
    return index;
  }

  /// 某个模组的版本文件（`releases/<owner>/<repo>.json` 或其中一页）
  static Future<DataIndexModReleases?> loadModReleases(
    String releasesPath, {
    bool refresh = false,
  }) async {
    final content = await loadText(
      releasesPath,
      maxAge: modReleasesMaxAge,
      refresh: refresh,
    );
    if (content == null) return null;

    final releases = DataIndexModReleases.parse(content);
    if (releases == null) {
      addLog(.warning, '模组版本文件解析失败：$releasesPath', tag: 'DataIndex');
    }
    return releases;
  }

  /// 游戏版本列表（正式版全量 + 最新 BE），字段与启动器快照同构，直接复用同一份解析
  static Future<List<MindustryRelease>?> loadMindustryVersions({
    bool refresh = false,
  }) async {
    final content = await loadText(
      'mindustry/versions.json',
      maxAge: mindustryVersionsMaxAge,
      refresh: refresh,
    );
    if (content == null) return null;

    final releases = MindustryReleaseListSnapshot.parse(content);
    if (releases.isEmpty) {
      addLog(.warning, '游戏版本列表解析失败', tag: 'DataIndex');
      return null;
    }
    return releases;
  }

  /// 相对数据索引根的路径 → raw 地址（地址带镜像回退，见 [cio]）
  static String urlOf(String relativePath) => '$dataIndexRawBase$relativePath';

  /// 读一份数据：缓存没过期就用缓存，否则重拉；拉取失败时回落到旧缓存
  ///
  /// [relativePath] 是相对数据索引根的路径；越界路径（绝对路径 / `..`）直接拒绝
  static Future<String?> loadText(
    String relativePath, {
    required Duration maxAge,
    bool refresh = false,
  }) async {
    final safePath = safeRelativePath(relativePath);
    if (safePath == null) {
      addLog(.warning, '数据索引路径不合法：$relativePath', tag: 'DataIndex');
      return null;
    }

    final cacheFile = File(p.join(AppPaths.dataIndexCache, safePath));
    final hasCache = await cacheFile.exists();
    if (hasCache && !refresh) {
      try {
        final modified = (await cacheFile.stat()).modified;
        if (DateTime.now().difference(modified) < maxAge) {
          return await cacheFile.readAsString();
        }
      } on FileSystemException {
        // 缓存读不出来就当没有，下面照常拉取
      }
    }

    try {
      final response = await cio.get<String>(
        urlOf(safePath),
        responseType: ResponseType.plain,
      );
      final content = response.data;
      if (response.statusCode != 200 || content == null) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      await _writeCache(cacheFile, content);
      return content;
    } catch (error) {
      if (hasCache) {
        addLog(
          .warning,
          '拉取数据索引失败，改用旧缓存（$safePath）：${removeNewlines('$error')}',
          tag: 'DataIndex',
        );
        return cacheFile.readAsString();
      }
      addLog(
        .warning,
        '拉取数据索引失败（$safePath）：${removeNewlines('$error')}',
        tag: 'DataIndex',
      );
      return null;
    }
  }

  /// 把相对路径规范成安全的缓存路径；绝对路径、`..` 越界返回 null
  static String? safeRelativePath(String relativePath) {
    final unified = relativePath.trim().replaceAll('\\', '/');
    if (unified.isEmpty) return null;
    // `p.posix` 认不出盘符，单独拦一次（`C:/x` 在 Windows 上也是绝对路径）
    if (_driveLetterPath.hasMatch(unified)) return null;
    if (p.posix.isAbsolute(unified)) return null;

    final normalized = p.posix.normalize(unified);
    if (normalized == '..' || normalized.startsWith('../')) return null;
    return normalized;
  }

  static final RegExp _driveLetterPath = RegExp(r'^[A-Za-z]:/');

  static Future<void> _writeCache(File cacheFile, String content) async {
    try {
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsString(content, flush: true);
    } catch (error) {
      addLog(
        .warning,
        '写数据索引缓存失败：${cacheFile.path}，${removeNewlines('$error')}',
        tag: 'DataIndex',
      );
    }
  }
}
