import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../util/app_paths.dart';
import '../util/format/string_cleaner.dart';
import '../util/io/copper_io.dart';
import '../util/io/log.dart';

/// 模组加载器库（`<数据根>/copper_loader/`）：loader jar 集中放这里，
/// 多个版本复用同一份，与本体库 [AppPaths.mindustrys] 是同一套思路
///
/// 现在只有 Copper 一家；以后接别的加载器时按同样的方式扩展（键是 loader 类型）
class LoaderLibrary {
  /// Copper 加载器的仓库：release 里的 `desktop-<版本>.jar` 就是桌面端 loader
  static const String loaderRepo = 'MDTCopper/loader';

  /// 查最新一版的桌面 loader；网络 / 解析失败返回 null
  static Future<({String tag, String url})?> fetchLatestDesktop() async {
    try {
      final res = await cio.get(
        'https://api.github.com/repos/$loaderRepo/releases/latest',
      );
      if (res.statusCode != 200) {
        addLogAndPrint(.warning, '查询加载器版本失败：HTTP ${res.statusCode}', tag: 'Loader');
        return null;
      }
      return parseLatestDesktop(jsonDecode(res.data));
    } catch (e) {
      addLogAndPrint(.warning, '查询加载器版本失败：${removeNewlines('$e')}', tag: 'Loader');
      return null;
    }
  }

  /// 从 release JSON 里挑桌面产物（纯函数，便于用例覆盖）
  @visibleForTesting
  static ({String tag, String url})? parseLatestDesktop(dynamic json) {
    if (json is! Map) return null;
    final tag = json['tag_name'];
    final assets = json['assets'];
    if (tag is! String || assets is! List) return null;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is String &&
          url is String &&
          name.startsWith('desktop-') &&
          name.endsWith('.jar')) {
        return (tag: tag, url: url);
      }
    }
    return null;
  }

  /// 下载桌面 loader 到加载器库，返回库内文件的绝对路径
  static Future<String> downloadDesktop({
    required String tag,
    required String url,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
  }) async {
    final libraryDir = Directory(AppPaths.copperLoader);
    await libraryDir.create(recursive: true);
    final target = File(p.join(libraryDir.path, 'desktop-$tag.jar'));
    await cio.download(
      url: url,
      savePath: target.path,
      cancelToken: cancelToken,
      onStatus: (state) => onProgress?.call(state.progress),
    );
    return target.path;
  }

  /// 收进库里：同名文件已存在就直接复用，否则复制过去
  ///
  /// 返回库内文件的**绝对路径**（调用方按记录形态存进版本里）
  static Future<String> importIntoLibrary(File source) async {
    final libraryDir = Directory(AppPaths.copperLoader);
    await libraryDir.create(recursive: true);
    final target = File(p.join(libraryDir.path, p.basename(source.path)));
    if (!await target.exists()) {
      await source.copy(target.path);
    }
    return target.path;
  }

  /// 库里现有的 loader jar（按文件名升序）
  static List<File> list() {
    final libraryDir = Directory(AppPaths.copperLoader);
    if (!libraryDir.existsSync()) return const [];
    final jars =
        libraryDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.jar'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return jars;
  }

  /// 没指定 loader 时的兜底：库里第一个可用的 loader
  ///
  /// 按文件名升序取第一个（文件名里带版本号，升序即从旧到新）；
  /// loader 版本适配表做出来之后再按游戏版本挑
  static String? fallbackPath() {
    final jars = list();
    return jars.isEmpty ? null : jars.first.path;
  }

  /// 取可用的 loader：优先 [recordedPath] 指定的（文件真在才算），其次库里第一个
  static String? usablePath(String? recordedPath) {
    if (recordedPath != null && File(recordedPath).existsSync()) {
      return recordedPath;
    }
    return fallbackPath();
  }

  /// 从文件名里读 loader 版本：`desktop-0.1.1.jar` → `0.1.1`
  ///
  /// 取不到就返回 null（版本适配表做出来之前，版本号只用于展示与排查）
  static String? versionOf(File loader) {
    final name = p.basenameWithoutExtension(loader.path);
    final matched = RegExp(r'(\d+(?:\.\d+)*)$').firstMatch(name)?.group(1);
    return matched;
  }
}
