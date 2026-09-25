import 'package:json_annotation/json_annotation.dart';

part 'github_release.g.dart';

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
