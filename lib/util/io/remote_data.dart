import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hjson_dart/hjson_dart.dart' as hjson;
import 'package:path/path.dart' as p;

/// remote 数据源（不随 copper launcher 版本更新的数据，如各版本 settings 适配表）。
///
/// - 数据源仓库：`MDTCopper/launcher` main 分支的 `remote/` 目录
/// - 本地：内置一份在 assets（打包），启动时每次尝试拉取仓库 raw 覆盖缓存
///   （`AppPaths.remoteData`），拉取失败/离线回落缓存或内置
/// - 请求走统一网络入口 [cio]（自带 github 镜像回退与系统代理）；
///   github_mirrors / mmgvm / 版本快照 / 设置适配表均已接入
class RemoteData {
  /// 每次启动异步拉取 remote 数据到本地缓存。
  ///
  /// 先拉索引，再按索引的 `file` 字段拉 `setting_adapter/<file>` 各版本配置；
  /// 失败静默（保持旧缓存），不阻塞启动流程。
  static Future<void> refresh() async {
    try {
      final index = await _fetch(remoteRawBase + settingAdapterIndexFile);
      if (index == null) return;
      await _saveCache(settingAdapterIndexFile, index);

      // 拉取 github 镜像预设节点
      final mirrorContent = await _fetch(remoteRawBase + githubMirrorsFile);
      if (mirrorContent != null) {
        await _saveCache(githubMirrorsFile, mirrorContent);
      }

      // 拉取模组版本门禁（mmgvm）
      final mmgvmContent = await _fetch(remoteRawBase + mmgvmFile);
      if (mmgvmContent != null) {
        await _saveCache(mmgvmFile, mmgvmContent);
      }

      // 拉取官方版本列表快照（历史版本，改动少）
      final versionsContent = await _fetch(
        remoteRawBase + mindustryVersionsFile,
      );
      if (versionsContent != null) {
        await _saveCache(mindustryVersionsFile, versionsContent);
      }

      // 按索引拉取各版本设置 json
      try {
        final parsed = hjson.hjsonDecode(index) as Map<String, dynamic>;
        final rules = parsed['rules'] as List<dynamic>? ?? const [];
        for (final rule in rules) {
          final file = (rule as Map<String, dynamic>)['file'] as String?;
          if (file == null) continue;
          final content = await _fetch('${remoteRawBase}setting_adapter/$file');
          if (content != null) {
            await _saveCache('setting_adapter/$file', content);
          }
        }
      } catch (e) {
        addLogAndPrint(.warning, '解析 remote setting_adapter 索引失败：$e');
      }
    } catch (e) {
      addLogAndPrint(.info, 'remote 数据拉取失败，使用本地数据：$e');
    }
  }

  /// 读取 remote 文件内容：缓存（AppPaths.remoteData）优先，回退内置 assets。
  ///
  /// [relativePath] 相对 remote/ 目录，如 `setting_adapter_index.hjson`、
  /// `setting_adapter/136-999999.json`
  static Future<String?> load(String relativePath) async {
    final cacheFile = File(p.join(AppPaths.remoteData, relativePath));
    if (await cacheFile.exists()) {
      return cacheFile.readAsString();
    }
    try {
      return await rootBundle.loadString('remote/$relativePath');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _fetch(String url) async {
    final res = await cio.get<String>(
      url,
      responseType: ResponseType.plain,
    );
    return res.statusCode == 200 ? res.data : null;
  }

  static Future<void> _saveCache(String relativePath, String content) async {
    final file = File(p.join(AppPaths.remoteData, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }
}

/// 便捷解码：hjson / json 混用（remote 文件是 hjson）
dynamic decodeRemote(String content) {
  try {
    return hjson.hjsonDecode(content);
  } catch (_) {
    return jsonDecode(content);
  }
}
