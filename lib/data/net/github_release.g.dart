// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'github_release.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GithubApiRelease _$GithubApiReleaseFromJson(Map<String, dynamic> json) =>
    GithubApiRelease(
      name: json['name'] as String,
      tag: json['tag_name'] as String,
      releaseDate: json['published_at'] as String,
      assets: (json['assets'] as List<dynamic>)
          .map((e) => GithubApiReleaseAsset.fromJson(e as Map<String, dynamic>))
          .toList(),
      describe: json['body'] as String,
    );

Map<String, dynamic> _$GithubApiReleaseToJson(GithubApiRelease instance) =>
    <String, dynamic>{
      'name': instance.name,
      'tag_name': instance.tag,
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
