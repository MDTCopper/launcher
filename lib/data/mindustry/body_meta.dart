import 'package:json_annotation/json_annotation.dart';

part 'body_meta.g.dart';

///Mindustry本体文件元数据
@JsonSerializable()
class MindustryMeta {
  MindustryMeta({
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

  factory MindustryMeta.fromJson(Map<String, dynamic> json) =>
      _$MindustryMetaFromJson(json);

  Map<String, dynamic> toJson() => _$MindustryMetaToJson(this);
}
