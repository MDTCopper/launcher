// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mod_release.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ModOfficialListEntry _$ModOfficialListEntryFromJson(
  Map<String, dynamic> json,
) => ModOfficialListEntry(
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

Map<String, dynamic> _$ModOfficialListEntryToJson(
  ModOfficialListEntry instance,
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

ModRelease _$ModReleaseFromJson(Map<String, dynamic> json) => ModRelease(
  name: json['name'] as String,
  tag: json['tag_name'] as String,
  releaseDate: json['published_at'] as String,
  assets: (json['assets'] as List<dynamic>)
      .map((e) => GithubApiReleaseAsset.fromJson(e as Map<String, dynamic>))
      .toList(),
  describe: json['body'] as String,
);

Map<String, dynamic> _$ModReleaseToJson(ModRelease instance) =>
    <String, dynamic>{
      'name': instance.name,
      'tag_name': instance.tag,
      'published_at': instance.releaseDate,
      'assets': instance.assets,
      'body': instance.describe,
    };
