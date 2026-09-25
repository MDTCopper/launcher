import 'package:json_annotation/json_annotation.dart';

part 'file_meta.g.dart';

///Mindustry本体文件元数据
@JsonSerializable()
class MindustryFileMeta {
  MindustryFileMeta({
    required this.path,
    required this.type,
    required this.version,
    required this.build,
  });

  final String? path;
  @JsonKey(name: 'number')
  final String version;
  final String build;

  /// release或beta
  @JsonKey(name: 'modifier')
  final String type;

  factory MindustryFileMeta.fromJson(Map<String, dynamic> json) =>
      _$MindustryFileMetaFromJson(json);

  Map<String, dynamic> toJson() => _$MindustryFileMetaToJson(this);
}
