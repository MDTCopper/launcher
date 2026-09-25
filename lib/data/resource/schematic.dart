import 'dart:io';
import 'dart:typed_data';

import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;

import '../../util/io/mindustry_save_file/save_file_codec.dart';

part 'schematic.g.dart';

@JsonSerializable()
class Schematic {
  ///存储路径
  final String? path;

  /// 蓝图名称 (来自 tags["name"])
  @JsonKey(defaultValue: '未知蓝图')
  final String name;

  @JsonKey(defaultValue: '未知作者')
  final String author;

  /// 蓝图描述 (来自 tags["description"])。
  @JsonKey(defaultValue: '')
  String description;

  @JsonKey(defaultValue: 0)
  int width;

  @JsonKey(defaultValue: 0)
  int height;

  /// 方块数量。
  @JsonKey(defaultValue: 0)
  int tileCount;

  /// 标签列表。
  @JsonKey(defaultValue: [])
  List<dynamic> labels;

  Schematic({
    required this.path,
    required this.name,
    required this.author,
    required this.description,
    required this.width,
    required this.height,
    required this.tileCount,
    required this.labels,
  });

  /// 从 .msch 文件路径加载。
  factory Schematic.fromFile(String path) {
    final bytes = File(path).readAsBytesSync();
    return Schematic.fromBytes(bytes, path);
  }

  /// 从 .msch 字节加载。
  factory Schematic.fromBytes(Uint8List bytes, String path) {
    final meta = SaveFileCodec.decodeSchematic(bytes);
    meta['path'] = path;
    return Schematic.fromJson(meta);
  }

  factory Schematic.fromJson(Map<String, dynamic> json) {
    json['name'] ??= p.basenameWithoutExtension(json['path']);
    return _$SchematicFromJson(json);
  }

  Map<String, dynamic> toJson() => _$SchematicToJson(this);
}
