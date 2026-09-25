import 'dart:io';
import 'dart:typed_data';

import 'package:json_annotation/json_annotation.dart';

import '../../util/io/mindustry_save_file/save_file_codec.dart';

part 'map_save.g.dart';

@JsonSerializable()
class MapSave {
  ///存储路径
  final String? path;

  /// 地图名称 (来自 tags["mapname"])。
  @JsonKey(defaultValue: '未知', name: 'mapname')
  final String name;

  @JsonKey(defaultValue: '未知')
  final String author;

  /// 当前波次。
  @JsonKey(defaultValue: 0)
  final int wave;

  /// 游玩时长（毫秒）。
  @JsonKey(defaultValue: 0)
  final int playtime;

  /// 存档时间戳（毫秒 since epoch）。
  @JsonKey(defaultValue: 0)
  final int saved;

  /// 游戏构建号。
  @JsonKey(defaultValue: 0)
  final int build;

  /// 游戏规则 (JSON 字符串)。
  @JsonKey(defaultValue: '')
  final String rules;

  /// 使用的 Mod 列表。
  @JsonKey(defaultValue: [])
  final List<dynamic> mods;

  MapSave({
    required this.path,
    required this.name,
    required this.author,
    required this.wave,
    required this.playtime,
    required this.saved,
    required this.build,
    required this.rules,
    required this.mods,
  });

  /// 从 .msav 文件路径加载。
  factory MapSave.fromFile(String path) {
    final bytes = File(path).readAsBytesSync();
    return MapSave.fromBytes(bytes, path);
  }

  /// 从 .msav 字节加载。
  factory MapSave.fromBytes(Uint8List bytes, String path) {
    final meta = SaveFileCodec.decodeMapMeta(bytes);
    meta['path'] = path;
    return MapSave.fromJson(meta);
  }

  factory MapSave.fromJson(Map<String, dynamic> json) =>
      _$MapSaveFromJson(json);

  Map<String, dynamic> toJson() => _$MapSaveToJson(this);
}
