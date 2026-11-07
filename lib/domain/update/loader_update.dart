import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../util/io/copper_io.dart';
import '../../util/io/log.dart';
import '../../util/version_strings.dart' as version_strings;
import '../loader_library.dart';
import 'update_models.dart';

/// Copper 加载器更新检查结果
class LoaderUpdateCheck {
  const LoaderUpdateCheck({this.update, this.error});

  /// 本机加载器库的状态（装了就有，没装过时 [LoaderUpdate.hasUpdate] 为 false）
  final LoaderUpdate? update;

  /// 检查失败的原因；非空时 [update] 为 null
  final String? error;
}

/// Copper 加载器更新：加载器库里的最高版本 vs 仓库最新 tag
class LoaderUpdateService {
  /// 检查加载器有没有新版本
  ///
  /// 版本列表优先走 git ref（不消耗 GitHub API 匿名额度），失败再退 release 接口
  static Future<LoaderUpdateCheck> check() async {
    final installedNewest = _newestLocalVersion();

    final latest = await LoaderLibrary.fetchLatestDesktop();
    if (latest == null) {
      return const LoaderUpdateCheck(error: '加载器版本列表拉取失败');
    }

    return LoaderUpdateCheck(
      update: LoaderUpdate(
        installedVersion: installedNewest,
        latestVersion: latest.tag,
        downloadUrl: latest.url,
        hasUpdate: isNewerThanLocal(latest.tag, installedNewest),
      ),
    );
  }

  /// 下载最新版进加载器库，返回库内文件的绝对路径
  ///
  /// 只收进库里，不改已有版本记录的 `launcherPath`——用哪个 loader 由版本设置决定
  static Future<String> apply({
    required LoaderUpdate update,
    CancelToken? cancelToken,
    HttpStatusCallback? onStatus,
  }) async {
    addLog(
      .info,
      '更新加载器：${update.installedVersion ?? '未安装'} → ${update.latestVersion}',
      tag: 'Loader',
    );
    return LoaderLibrary.downloadDesktop(
      tag: update.latestVersion,
      url: update.downloadUrl,
      cancelToken: cancelToken,
      onStatus: onStatus,
    );
  }

  static String? _newestLocalVersion() {
    String? newest;
    for (final version in LoaderLibrary.localVersions()) {
      if (newest == null ||
          version_strings.compareVersion(version, newest) > 0) {
        newest = version;
      }
    }
    return newest;
  }

  /// [latest] 是否比本机最高版本新
  ///
  /// `snapshot` 是滚动最新：本机不是 snapshot 时算有更新；本机已经是 snapshot 时
  /// 数字版本号不再覆盖它
  @visibleForTesting
  static bool isNewerThanLocal(String latest, String? installed) {
    if (installed == null) return false;
    if (latest == installed) return false;
    if (latest == 'snapshot') return true;
    if (installed == 'snapshot') return false;
    return version_strings.compareVersion(latest, installed) > 0;
  }
}
