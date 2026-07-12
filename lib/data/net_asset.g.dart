// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'net_asset.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GithubApiRelease _$GithubApiReleaseFromJson(Map<String, dynamic> json) =>
    GithubApiRelease(
      name: json['name'] as String,
      releaseNum: json['tag_name'] as String,
      releaseDate: json['published_at'] as String,
      assets: (json['assets'] as List<dynamic>)
          .map((e) => GithubApiReleaseAsset.fromJson(e as Map<String, dynamic>))
          .toList(),
      describe: json['body'] as String,
    );

Map<String, dynamic> _$GithubApiReleaseToJson(GithubApiRelease instance) =>
    <String, dynamic>{
      'name': instance.name,
      'tag_name': instance.releaseNum,
      'published_at': instance.releaseDate,
      'assets': instance.assets,
      'body': instance.describe,
    };

GithubApiReleaseAsset _$GithubApiReleaseAssetFromJson(
  Map<String, dynamic> json,
) => GithubApiReleaseAsset(
  name: json['name'] as String,
  url: json['browser_download_url'] as String,
  size: (json['size'] as num).toInt(),
  downloadCount: (json['download_count'] as num).toInt(),
);

Map<String, dynamic> _$GithubApiReleaseAssetToJson(
  GithubApiReleaseAsset instance,
) => <String, dynamic>{
  'browser_download_url': instance.url,
  'size': instance.size,
  'download_count': instance.downloadCount,
  'name': instance.name,
};

MindustryGithubMeta _$MindustryGithubMetaFromJson(Map<String, dynamic> json) =>
    MindustryGithubMeta(
      name: json['name'] as String,
      releaseNum: json['tag_name'] as String,
      releaseDate: json['published_at'] as String,
      assets: (json['assets'] as List<dynamic>)
          .map((e) => GithubApiReleaseAsset.fromJson(e as Map<String, dynamic>))
          .toList(),
      describe: json['body'] as String,
    );

Map<String, dynamic> _$MindustryGithubMetaToJson(
  MindustryGithubMeta instance,
) => <String, dynamic>{
  'name': instance.name,
  'tag_name': instance.releaseNum,
  'published_at': instance.releaseDate,
  'assets': instance.assets,
  'body': instance.describe,
};

ModOfficialListMeta _$ModOfficialListMetaFromJson(Map<String, dynamic> json) =>
    ModOfficialListMeta(
      repo: json['repo'] as String,
      name: json['name'] as String,
      author: json['author'] as String,
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      stars: (json['stars'] as num).toInt(),
      minGameVersion: json['minGameVersion'] as String,
      hasScripts: json['hasScripts'] as bool,
      hasJava: json['hasJava'] as bool,
      description: json['description'] as String,
    );

Map<String, dynamic> _$ModOfficialListMetaToJson(
  ModOfficialListMeta instance,
) => <String, dynamic>{
  'repo': instance.repo,
  'name': instance.name,
  'author': instance.author,
  'lastUpdated': instance.lastUpdated.toIso8601String(),
  'stars': instance.stars,
  'minGameVersion': instance.minGameVersion,
  'hasScripts': instance.hasScripts,
  'hasJava': instance.hasJava,
  'description': instance.description,
};

ModGithubMeta _$ModGithubMetaFromJson(Map<String, dynamic> json) =>
    ModGithubMeta(
      name: json['name'] as String,
      releaseNum: json['tag_name'] as String,
      releaseDate: json['published_at'] as String,
      assets: (json['assets'] as List<dynamic>)
          .map((e) => GithubApiReleaseAsset.fromJson(e as Map<String, dynamic>))
          .toList(),
      describe: json['body'] as String,
    );

Map<String, dynamic> _$ModGithubMetaToJson(ModGithubMeta instance) =>
    <String, dynamic>{
      'name': instance.name,
      'tag_name': instance.releaseNum,
      'published_at': instance.releaseDate,
      'assets': instance.assets,
      'body': instance.describe,
    };
