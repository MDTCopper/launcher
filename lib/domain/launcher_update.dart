import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/app_constant.dart';
import '../util/format/string_cleaner.dart';
import '../util/io/copper_io.dart';
import '../util/io/log.dart';
import '../util/version_filter.dart';

/// 发布通道：正式版没有尾缀，内测 / 公测接 build number（`tool/build_release.dart` 定的）
enum LauncherChannel {
  release('正式版', 2),
  beta('公测版', 1),
  alpha('内测版', 0);

  const LauncherChannel(this.label, this.rank);

  final String label;

  /// 同一个版本号下的比较优先级：正式 > 公测 > 内测
  final int rank;

  static LauncherChannel fromSuffix(String suffix) => switch (suffix) {
    'alpha' => LauncherChannel.alpha,
    'beta' => LauncherChannel.beta,
    _ => LauncherChannel.release,
  };
}

/// 启动器版本的可比较形态：release tag 与本地显示版本号都解析成它
class LauncherVersion implements Comparable<LauncherVersion> {
  const LauncherVersion({
    required this.number,
    required this.channel,
    this.build,
  });

  /// 形如 `0.0.1` 的版本号
  final SemVer number;

  final LauncherChannel channel;

  /// 内测 / 公测的 build number；正式版不带
  final int? build;

  @override
  int compareTo(LauncherVersion other) {
    final byNumber = number.compareTo(other.number);
    if (byNumber != 0) return byNumber;

    final byChannel = channel.rank.compareTo(other.channel.rank);
    if (byChannel != 0) return byChannel;

    // 正式版不带 build number：同版本号就是同一版
    if (channel == LauncherChannel.release) return 0;
    return (build ?? 0).compareTo(other.build ?? 0);
  }

  @override
  String toString() =>
      build == null ? 'v$number' : 'v$number ${channel.name}$build';
}

/// 解析 release tag：`v0.0.1-alpha5`（内测 5）、`v0.0.2`（正式版）
LauncherVersion? parseLauncherTag(String tag) {
  final matched = RegExp(
    r'^v(\d+(?:\.\d+)*)(?:-(alpha|beta)(\d+))?$',
  ).firstMatch(tag.trim());
  if (matched == null) return null;

  final number = SemVer.tryParse(matched.group(1));
  if (number == null) return null;

  final suffix = matched.group(2);
  final buildText = matched.group(3);
  return LauncherVersion(
    number: number,
    channel: suffix == null
        ? LauncherChannel.release
        : LauncherChannel.fromSuffix(suffix),
    build: buildText == null ? null : int.tryParse(buildText),
  );
}

/// 解析本地版本：[displayVersion] 形如 `v0.0.1 alpha 5`，正式版就是 `v0.0.2`；
/// [buildNumber] 是同一份版本信息里的 build number（正式版用不上）
LauncherVersion? parseLocalVersion(String displayVersion, int? buildNumber) {
  final text = displayVersion.trim().replaceFirst(RegExp('^v'), '');
  if (text.isEmpty) return null;

  final parts = text.split(RegExp(r'\s+'));
  final number = SemVer.tryParse(parts.first);
  if (number == null) return null;

  if (parts.length == 1) {
    return LauncherVersion(number: number, channel: LauncherChannel.release);
  }
  return LauncherVersion(
    number: number,
    channel: LauncherChannel.fromSuffix(parts[1]),
    build: parts.length > 2 ? int.tryParse(parts[2]) : buildNumber,
  );
}

/// release 里的一个产物
class LauncherAsset {
  const LauncherAsset({required this.name, required this.url, this.size});

  final String name;

  final String url;

  /// 字节数（接口没给就是 null）
  final int? size;
}

/// 启动器的一次发布
class LauncherRelease {
  const LauncherRelease({
    required this.tag,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.prerelease,
    required this.assets,
  });

  final String tag;

  /// release 标题，为空时展示 [tag]
  final String name;

  /// 发布说明（markdown 原文，直接显示）
  final String body;

  final String htmlUrl;

  final bool prerelease;

  final List<LauncherAsset> assets;

  /// tag 解析出的版本；解析不出来时为 null（选最新一版时排最后）
  LauncherVersion? get version => parseLauncherTag(tag);

  /// 展示用标题
  String get displayName => name.trim().isEmpty ? tag : name.trim();
}

/// 启动器自身更新：查仓库 release、挑产物、下载、拉起安装
///
/// 只做 Windows 的产物挑选与安装拉起；其余平台交给 release 页面手动下载
class LauncherUpdate {
  /// 启动器仓库（与 [launcherRepoUrl] 同一份）
  static const String repo = 'MDTCopper/launcher';

  /// 一次查多少个 release：挑最新一版够用；预发布也要算，所以不走 `/releases/latest`
  static const int fetchLimit = 10;

  /// 当前这份的版本（`app_constant.dart` 里由构建脚本写入的版本信息）
  static LauncherVersion? get currentVersion =>
      parseLocalVersion(appVersion, appBuildNumber);

  /// 查最新一版（预发布也参与），按版本号自己排序、不吃接口返回顺序；失败返回 null
  static Future<LauncherRelease?> fetchLatest() async {
    try {
      final decoded = await fetchJsonBody(
        '$githubAPI/repos/$repo/releases?per_page=$fetchLimit',
      );
      return newestOf(parseReleases(decoded));
    } catch (e) {
      addLogAndPrint(
        .warning,
        '查询启动器版本失败：${removeNewlines('$e')}',
        tag: 'Update',
      );
      return null;
    }
  }

  /// [release] 是否比当前这份新
  static bool isNewer(LauncherRelease release) {
    final local = currentVersion;
    final remote = release.version;
    if (local == null || remote == null) return false;
    return remote.compareTo(local) > 0;
  }

  /// 该不该直接拉起安装：Windows + 下的是 Setup + 当前这份就是 Setup 装出来的
  static bool shouldRunInstaller(LauncherAsset asset) =>
      Platform.isWindows &&
      asset.name.toLowerCase().endsWith('-setup.exe') &&
      isInstalledBuild;

  /// 当前这份是不是 Setup 装出来的（解压版没有卸载器）
  static bool get isInstalledBuild =>
      isInstalledBuildIn(File(Platform.resolvedExecutable).parent.path);

  /// Inno Setup 会在程序目录里留 `unins000.exe`，用它区分「安装版」与「解压版」
  @visibleForTesting
  static bool isInstalledBuildIn(String exeDir) =>
      File(p.join(exeDir, 'unins000.exe')).existsSync();

  /// 更新包下载目录：临时目录（更新包是一次性文件，不往数据根里塞）
  static Directory get downloadDir =>
      Directory(p.join(Directory.systemTemp.path, 'copper_launcher_update'));

  /// 下载产物，返回落盘路径
  static Future<String> downloadAsset({
    required LauncherAsset asset,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
  }) async {
    final dir = downloadDir;
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, asset.name));
    // 每次重下：上一次中断留下的半截文件不能当成完整的更新包
    if (await target.exists()) await target.delete();

    await cio.download(
      url: asset.url,
      savePath: target.path,
      cancelToken: cancelToken,
      onStatus: (state) => onProgress?.call(state.progress),
    );
    return target.path;
  }

  /// 拉起 Setup：静默安装（不出向导、装完也不自动启动），并让安装器
  /// 关掉还占着文件的本进程 —— 调用方随后要退出启动器
  static Future<void> runInstaller(String setupPath) async {
    await Process.start(setupPath, const [
      '/SILENT',
      '/CLOSEAPPLICATIONS',
      '/NORESTART',
    ], mode: ProcessStartMode.detached);
  }

  /// Windows 产物：安装版取 Setup（覆盖安装）、解压版取 zip；要的那种没有时退另一种
  static LauncherAsset? pickWindowsAsset(
    List<LauncherAsset> assets, {
    required bool preferSetup,
  }) {
    LauncherAsset? setup;
    LauncherAsset? zip;
    for (final asset in assets) {
      final name = asset.name.toLowerCase();
      if (!name.contains('windows')) continue;
      if (name.endsWith('-setup.exe')) {
        setup ??= asset;
      } else if (name.endsWith('.zip')) {
        zip ??= asset;
      }
    }
    return preferSetup ? (setup ?? zip) : (zip ?? setup);
  }

  /// 版本最高的一版：tag 解析不出来的排最后；列表为空返回 null
  @visibleForTesting
  static LauncherRelease? newestOf(List<LauncherRelease> releases) {
    if (releases.isEmpty) return null;
    final sorted = [...releases]
      ..sort((a, b) {
        final left = a.version;
        final right = b.version;
        if (left == null || right == null) {
          if (left == right) return 0;
          return left == null ? 1 : -1;
        }
        return right.compareTo(left);
      });
    return sorted.first;
  }

  /// 解析 release 列表 JSON（结构不对的条目跳过）
  @visibleForTesting
  static List<LauncherRelease> parseReleases(dynamic json) {
    if (json is! List) return const [];

    final releases = <LauncherRelease>[];
    for (final item in json) {
      if (item is! Map) continue;
      final tag = item['tag_name'];
      if (tag is! String) continue;

      releases.add(
        LauncherRelease(
          tag: tag,
          name: '${item['name'] ?? ''}',
          body: '${item['body'] ?? ''}',
          htmlUrl: '${item['html_url'] ?? ''}',
          prerelease: item['prerelease'] == true,
          assets: parseAssets(item['assets']),
        ),
      );
    }
    return releases;
  }

  /// 解析产物列表（缺名字 / 下载地址的项跳过）
  @visibleForTesting
  static List<LauncherAsset> parseAssets(dynamic assets) {
    if (assets is! List) return const [];

    return [
      for (final asset in assets)
        if (asset is Map &&
            asset['name'] is String &&
            asset['browser_download_url'] is String)
          LauncherAsset(
            name: asset['name'] as String,
            url: asset['browser_download_url'] as String,
            size: asset['size'] is int ? asset['size'] as int : null,
          ),
    ];
  }
}
