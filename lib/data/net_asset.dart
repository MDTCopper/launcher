import 'package:json_annotation/json_annotation.dart';

import '../util/mindustry_version_era.dart';

part 'net_asset.g.dart';

///api.github返回格式
@JsonSerializable()
class GithubApiRelease {
  final String name;

  @JsonKey(name: 'tag_name')
  final String tag;
  @JsonKey(name: 'published_at')
  final String releaseDate;
  final List<GithubApiReleaseAsset> assets;
  @JsonKey(name: 'body')
  final String describe;

  GithubApiRelease({
    required this.name,
    required this.tag,
    required this.releaseDate,
    required this.assets,
    required this.describe,
  });

  /// 返回指定后缀的 release asset（如 `.jar` / `.zip`），按体积从大到小排序。
  ///
  /// 体积最大的一般为 mod 本体，便于下载前让玩家在多个候选里选择。
  List<GithubApiReleaseAsset> assetsOfType(String extension) {
    final ext = extension.toLowerCase();
    final matches = [
      for (final it in assets)
        if (it.name.toLowerCase().endsWith(ext)) it,
    ];
    matches.sort((a, b) => b.size.compareTo(a.size));
    return matches;
  }
}

@JsonSerializable()
class GithubApiReleaseAsset {
  @JsonKey(name: "browser_download_url")
  final String url;
  final int size;
  @JsonKey(name: 'download_count')
  final int downloadCount;
  final String name;

  GithubApiReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.downloadCount,
  });

  factory GithubApiReleaseAsset.fromJson(Map<String, dynamic> json) =>
      _$GithubApiReleaseAssetFromJson(json);
}

///游戏版本元数据
@JsonSerializable()
class MindustryGithubMeta extends GithubApiRelease {
  @JsonKey(includeFromJson: false)
  late final bool isBe;

  MindustryGithubMeta({
    required super.name, //v8 Build 152.2 - Beta
    required super.tag, //v146
    required super.releaseDate,
    required super.assets,
    required super.describe,
  });

  factory MindustryGithubMeta.fromJson(Map<String, dynamic> json) {
    final instance = _$MindustryGithubMetaFromJson(json);
    instance.isBe = json['reactions'] == null;
    return instance;
  }

  /// 该 release 所属的版本时代，按 tag 里的 build 号判定
  ///
  /// 正式版 tag 形如 `v159.7`，be 版 tag 是 build 号本身；
  /// 解析不出的按现代版算，避免误标成远古版
  MindustryVersionEra get era =>
      MindustryVersionEra.ofTag(tag) ?? MindustryVersionEra.modern;

  /// 桌面端游戏本体 jar：正式版 asset 名为 `Mindustry.jar`，
  /// be 版（MindustryBuilds）为 `Mindustry-BE-Desktop-<build>.jar`
  ///
  /// 同一 release 里还带 `server-release.jar` / `assets.jar` / `dependencies.jar`
  /// 和 Android apk，都进不了游戏，需排除；找不到本体返回 null
  GithubApiReleaseAsset? get desktopJarAsset {
    final jarAssets = [
      for (final asset in assets)
        if (_isGameJarCandidate(asset.name)) asset,
    ];

    for (final asset in jarAssets) {
      if (asset.name.toLowerCase() == 'mindustry.jar') return asset;
    }
    for (final asset in jarAssets) {
      if (asset.name.toLowerCase().contains('desktop')) return asset;
    }
    return null;
  }

  /// 是否是本体候选：jar 且不是服务端包（server-release.jar）
  static bool _isGameJarCandidate(String assetName) {
    final name = assetName.toLowerCase();
    return name.endsWith('.jar') && !name.contains('server');
  }
}

///官方模组列表元数据
@JsonSerializable()
class ModOfficialListMeta {
  final String repo;
  final String name;
  final String author;
  final DateTime lastUpdated;
  final int stars;
  final String minGameVersion;
  final bool hasScripts;
  final bool hasJava;
  final String description;

  /// 缓存图标Url，避免反复尝试搜索
  @JsonKey(includeFromJson: false)
  String? iconUrlCache;

  @JsonKey(includeFromJson: false)
  int? starsDifferenceCache;

  /// 缓存主仓库，只存分支名(main 或 master)
  @JsonKey(includeFromJson: false)
  String? mainBranchCache;

  ModOfficialListMeta({
    required this.repo,
    required this.name,
    required this.author,
    required this.lastUpdated,
    required this.stars,
    required this.minGameVersion,
    required this.hasScripts,
    required this.hasJava,
    required this.description,
  });

  factory ModOfficialListMeta.fromJson(Map<String, dynamic> json) =>
      _$ModOfficialListMetaFromJson(json);

  Map<String, dynamic> modMetaToJson() => _$ModOfficialListMetaToJson(this);

  @override
  String toString() {
    return 'ModOfficialListMeta{name: $name, author:$author}';
  }
}

///模组githubAPI版本元数据
@JsonSerializable()
class ModGithubMeta extends GithubApiRelease {
  ModGithubMeta({
    required super.name,
    required super.tag,
    required super.releaseDate,
    required super.assets,
    required super.describe,
  });

  factory ModGithubMeta.fromJson(Map<String, dynamic> json) =>
      _$ModGithubMetaFromJson(json);
}
