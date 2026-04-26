import 'package:json_annotation/json_annotation.dart';

part 'net_asset.g.dart';

@JsonSerializable()
class GithubApiRelease {
  //api.github返回格式
  final String name;
  @JsonKey(name: 'tag_name')
  final String releaseNum;
  @JsonKey(name: 'published_at')
  final String releaseDate;
  final List<GithubApiReleaseAsset> assets;
  @JsonKey(name: 'body')
  final String describe;

  GithubApiRelease({
    required this.name,
    required this.releaseNum,
    required this.releaseDate,
    required this.assets,
    required this.describe,
  });
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
    required super.releaseNum, //v146
    required super.releaseDate,
    required super.assets,
    required super.describe,
  });

  factory MindustryGithubMeta.fromJson(Map<String, dynamic> json) {
    final instance = _$MindustryGithubMetaFromJson(json);
    instance.isBe = json['reactions'] == null;
    return instance;
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
    return 'ModMeta{name: $name, author:$author}';
  }
}

///模组githubAPI版本元数据
@JsonSerializable()
class ModGithubMeta extends GithubApiRelease {
  @JsonKey(name: 'zipball_url')
  final String sourceCodeUrl;
  ModGithubMeta({
    required super.name,
    required super.releaseNum,
    required super.releaseDate,
    required super.assets,
    required super.describe,
    required this.sourceCodeUrl,
  });
  factory ModGithubMeta.fromJson(Map<String, dynamic> json) =>
      _$ModGithubMetaFromJson(json);
}
