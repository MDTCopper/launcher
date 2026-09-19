import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/app_constant.dart';
import '../util/format/string_cleaner.dart';
import '../util/io/copper_io.dart';
import '../util/io/log.dart';
import '../util/version_filter.dart';
import 'loader_library.dart';

/// Copper 加载器的版本适配表
///
/// 表在 loader 仓库根目录的 `support.json`：**键是 loader 版本范围、值是游戏版本范围**，
/// 两边都用 Copper 的版本过滤器语法（见 loader wiki 的 `developers/versions`）
///
/// 加载器自己并不读这张表，它是给启动器判断「某个 loader 版本能不能配这个游戏版本」用的
class LoaderSupport {
  const LoaderSupport(this.entries);

  /// 每条规则：loader 版本范围 → 支持的游戏版本范围
  final List<({VersionFilter loader, VersionFilter game})> entries;

  static const String supportUrl =
      '$githubRAW/${LoaderLibrary.loaderRepo}/main/support.json';

  static LoaderSupport? _cached;
  static Future<LoaderSupport?>? _loading;

  /// 查一次适配表并缓存（一次会话只拉一次）
  ///
  /// 拉不到返回 null：调用方按「未知」处理（不拦也不推荐），
  /// 兜底还有 [Mindustry.loaderMinRelease] 那条硬编码下限
  static Future<LoaderSupport?> load({bool refresh = false}) async {
    if (refresh) {
      _cached = null;
      _loading = null;
    }
    if (_cached != null) return _cached;
    if (_loading != null) return _loading;

    _loading = _fetch();
    final loaded = await _loading;
    _cached = loaded;
    _loading = null;
    return loaded;
  }

  static Future<LoaderSupport?> _fetch() async {
    try {
      final response = await cio.get(supportUrl);
      if (response.statusCode != 200) {
        addLogAndPrint(
          .warning,
          '获取加载器适配表失败：HTTP ${response.statusCode}',
          tag: 'Loader',
        );
        return null;
      }
      final parsed = parse(jsonDecode(response.data));
      addLog(.info, '加载器适配表：${parsed.entries.length} 条规则', tag: 'Loader');
      return parsed;
    } catch (e) {
      addLogAndPrint(
        .warning,
        '获取加载器适配表失败：${removeNewlines('$e')}',
        tag: 'Loader',
      );
      return null;
    }
  }

  /// 从 `support.json` 的内容解析（纯函数，便于用例覆盖）
  @visibleForTesting
  static LoaderSupport parse(dynamic json) {
    final entries = <({VersionFilter loader, VersionFilter game})>[];
    if (json is Map) {
      json.forEach((key, value) {
        entries.add((
          loader: VersionFilter.parse(key),
          game: VersionFilter.parse(value),
        ));
      });
    }
    return LoaderSupport(entries);
  }

  /// 空的适配表（拿不到表时用它，所有判断都是「未知」）
  static const LoaderSupport empty = LoaderSupport([]);

  /// [loaderVersion] 能不能配 [gameVersion]
  ///
  /// - 命中某条 loader 范围且游戏范围也满足 → true
  /// - 命中某条 loader 范围但游戏范围不满足 → false（明确不支持）
  /// - 没有任何 loader 范围命中（或版本号不全）→ null（未知）
  bool? supports({required String? loaderVersion, required String? gameVersion}) {
    if (loaderVersion == null || gameVersion == null) return null;

    var matched = false;
    for (final entry in entries) {
      if (!entry.loader.matches(loaderVersion)) continue;
      matched = true;
      if (entry.game.matches(gameVersion)) return true;
    }
    return matched ? false : null;
  }
}
