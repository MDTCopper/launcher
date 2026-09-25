import '../core/app_constant.dart';
import '../util/mindustry_version_era.dart';

/// 一个 Mindustry 版本的元数据（**与来源无关**）
///
/// 来源各自一个构造：GitHub API 与本地快照是同一个 JSON 形状（[fromGithubJson]），
/// 国内 manifest 是另一个（[fromManifestJson]）。领域模型不带来源特有字段 ——
/// `isBe` 与资产的 `sha256` 都是显式的，不用靠占位字段猜
class MindustryRelease {
  const MindustryRelease({
    required this.tag,
    required this.name,
    required this.releaseDate,
    required this.describe,
    required this.isBe,
    required this.assets,
  });

  /// 正式版形如 `v160.5`；BE 版是 build 号本身
  final String tag;

  /// 展示名：GitHub 的 release 名 / manifest 的 `build_name`
  final String name;

  final String releaseDate;

  /// 更新说明（manifest 不提供，为空）
  final String describe;

  /// BE 版（MindustryBuilds）
  final bool isBe;

  final List<MindustryReleaseAsset> assets;

  /// 该 release 所属的版本时代，按 tag 里的 build 号判定
  ///
  /// 解析不出的按现代版算，避免误标成远古版
  MindustryVersionEra get era =>
      MindustryVersionEra.ofTag(tag) ?? MindustryVersionEra.modern;

  /// 桌面端游戏本体 jar：正式版 `Mindustry.jar`，BE 是
  /// `Mindustry-BE-Desktop-<build>.jar`
  ///
  /// 同一 release 还带 server / assets / dependencies 等，都进不了游戏；找不到返回 null
  MindustryReleaseAsset? get desktopJarAsset {
    final candidates = [
      for (final asset in assets)
        if (_isGameJarCandidate(asset.name)) asset,
    ];

    for (final asset in candidates) {
      if (asset.name.toLowerCase() == 'mindustry.jar') return asset;
    }
    for (final asset in candidates) {
      if (asset.name.toLowerCase().contains('desktop')) return asset;
    }
    return null;
  }

  /// 是否是本体候选：jar 且不是服务端包（server-release.jar）
  static bool _isGameJarCandidate(String assetName) {
    final name = assetName.toLowerCase();
    return name.endsWith('.jar') && !name.contains('server');
  }

  /// GitHub API / 本地快照的 JSON 形状
  ///
  /// 缺关键字段就抛：快照那边靠它跳过损坏的单条（解析太宽松会把坏条目当版本列出来）
  factory MindustryRelease.fromGithubJson(Map<String, dynamic> json) {
    final tag = json['tag_name']?.toString() ?? '';
    if (tag.isEmpty) throw const FormatException('release 缺 tag_name');

    final rawAssets = json['assets'];
    if (rawAssets is! List) throw const FormatException('release 缺 assets');

    return MindustryRelease(
      tag: tag,
      name: json['name']?.toString() ?? '',
      releaseDate: json['published_at']?.toString() ?? '',
      describe: json['body']?.toString() ?? '',
      // GitHub 的 release 带 reactions，BE（MindustryBuilds）那份不带
      isBe: json['reactions'] == null,
      assets: [
        for (final raw in rawAssets) ?MindustryReleaseAsset.fromGithubJson(raw),
      ],
    );
  }

  /// 国内 manifest 里的一项
  factory MindustryRelease.fromManifestJson(Map<String, dynamic> json) {
    final tag = json['tag']?.toString() ?? '';
    final buildName = json['build_name']?.toString() ?? '';
    final rawAssets = json['assets'];

    return MindustryRelease(
      tag: tag,
      // build_name 是论坛预留的 release 名，没有就退回 tag
      name: buildName.isEmpty ? tag : buildName,
      releaseDate: json['published_at']?.toString() ?? '',
      describe: '',
      // 这份 manifest 只覆盖正式版仓库（Anuken/Mindustry）
      isBe: false,
      assets: [
        if (rawAssets is List)
          for (final raw in rawAssets)
            ?MindustryReleaseAsset.fromManifestJson(raw),
      ],
    );
  }
}

/// 版本里的一份资产
class MindustryReleaseAsset {
  const MindustryReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });

  final String name;
  final String url;
  final int size;

  /// 内容 sha256（国内 manifest 提供，GitHub API 不提供）
  final String? sha256;

  static MindustryReleaseAsset? fromGithubJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['browser_download_url']?.toString() ?? '';
    if (url.isEmpty) return null;
    return MindustryReleaseAsset(
      name: raw['name']?.toString() ?? '',
      url: url,
      size: (raw['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// manifest 的资产：只有 `platform == desktop` 才是本体，地址是相对路径
  static MindustryReleaseAsset? fromManifestJson(Object? raw) {
    if (raw is! Map || raw['platform'] != 'desktop') return null;
    final path = raw['download_url']?.toString() ?? '';
    if (path.isEmpty) return null;
    return MindustryReleaseAsset(
      name: raw['file_name']?.toString() ?? '',
      url: '$mindustryManifestBase$path',
      size: (raw['size'] as num?)?.toInt() ?? 0,
      sha256: raw['sha256']?.toString(),
    );
  }
}
