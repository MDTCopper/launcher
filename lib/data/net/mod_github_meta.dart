import 'package:json_annotation/json_annotation.dart';

import 'github_release.dart';

part 'mod_github_meta.g.dart';

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

  /// 已经探测过、确认没有图标（与 [iconUrlCache] 互斥）
  ///
  /// 只缓存命中会有个问题：没有图标的 mod 每次重建都会把整轮 HEAD 探测重跑一遍
  @JsonKey(includeFromJson: false, includeToJson: false)
  bool iconMissingCache = false;

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
