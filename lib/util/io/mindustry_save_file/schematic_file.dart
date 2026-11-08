import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// `.msch` 蓝图完整解码：方块名、格坐标、旋转与配置
///
/// 元数据解码在 [SaveFileCodec]；这里补上渲染需要的 tile 段
/// 文件结构见 Mindustry `Schematics.read`：`msch` + 版本字节 + zlib 流
class SchematicFile {
  const SchematicFile({
    required this.width,
    required this.height,
    required this.tags,
    required this.blockNames,
    required this.tiles,
  });

  /// 格宽
  final int width;
  final int height;

  /// 原始 tags（name / description / labels 等）
  final Map<String, String> tags;

  /// 文件自带的方块字典，tile 里的索引指向它
  final List<String> blockNames;

  final List<SchematicTile> tiles;

  factory SchematicFile.fromFile(String path) {
    return SchematicFile.fromBytes(File(path).readAsBytesSync());
  }

  factory SchematicFile.fromBytes(Uint8List bytes) {
    if (bytes.length < 6) {
      throw const FormatException('不是有效的 .msch 文件');
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _header[i]) {
        throw const FormatException('不是有效的 .msch 文件（头部不匹配）');
      }
    }
    final version = bytes[4];
    if (version > 1) {
      throw FormatException('不支持的 .msch 版本 $version');
    }
    final reader = _ByteReader(_inflate(bytes.sublist(5)));
    final width = reader.i16();
    final height = reader.i16();
    if (width > 128 || height > 128) {
      throw const FormatException('蓝图尺寸超过 128x128');
    }

    final tags = <String, String>{};
    final tagCount = reader.u8();
    for (var i = 0; i < tagCount; i++) {
      tags[reader.utf()] = reader.utf();
    }

    final blockCount = reader.u8();
    final blockNames = List<String>.generate(blockCount, (_) => reader.utf());

    final tileCount = reader.i32();
    if (tileCount > 16384) {
      throw FormatException('蓝图方块数量过多 $tileCount');
    }

    final tiles = <SchematicTile>[];
    for (var i = 0; i < tileCount; i++) {
      final blockIndex = reader.i8() & 0xFF;
      final packedPosition = reader.i32();
      final config = _readConfig(reader, version);
      final rotation = reader.i8();
      final x = (packedPosition >> 16) & 0xFFFF;
      final y = packedPosition & 0xFFFF;
      if (blockIndex >= blockNames.length) {
        throw FormatException('方块索引越界 $blockIndex / ${blockNames.length}');
      }
      tiles.add(
        SchematicTile(
          blockName: blockNames[blockIndex],
          x: x,
          y: y,
          rotation: rotation,
          config: config,
        ),
      );
    }

    return SchematicFile(
      width: width,
      height: height,
      tags: tags,
      blockNames: blockNames,
      tiles: tiles,
    );
  }

  static const _header = [0x6D, 0x73, 0x63, 0x68];

  static Uint8List _inflate(Uint8List bytes) {
    try {
      return Uint8List.fromList(ZLibDecoder().convert(bytes));
    } catch (_) {
      return Uint8List.fromList(ZLibDecoder(raw: true).convert(bytes));
    }
  }
}

class SchematicTile {
  const SchematicTile({
    required this.blockName,
    required this.x,
    required this.y,
    required this.rotation,
    this.config,
  });

  final String blockName;

  /// 格坐标；多格方块按 Mindustry 约定（奇数尺寸取中心格，偶数取左下）
  final int x;
  final int y;

  /// 0=右 / 1=上 / 2=左 / 3=下
  final int rotation;

  final SchematicConfig? config;
}

enum SchematicConfigKind {
  integer,
  long,
  float,
  double,
  boolean,
  string,
  content,
  point,
  pointList,
  integerList,
  byteArray,
  booleanArray,
  other,
}

/// 蓝图里某个方块保存的配置
///
/// 只保留渲染要用的值；不认识的类型按 [SchematicConfigKind.other] 占位，避免解析中断
class SchematicConfig {
  const SchematicConfig(this.kind, this.value);

  final SchematicConfigKind kind;
  final Object? value;

  @override
  String toString() => '${kind.name}:$value';
}

/// 解析 TypeIO 的 readObject 子集，返回 null 表示无配置
SchematicConfig? _readConfig(_ByteReader reader, int schematicVersion) {
  final type = reader.u8();
  switch (type) {
    case 0:
      return null;
    case 1:
      return SchematicConfig(SchematicConfigKind.integer, reader.i32());
    case 2:
      return SchematicConfig(SchematicConfigKind.long, reader.i64());
    case 3:
      return SchematicConfig(SchematicConfigKind.float, reader.f32());
    case 4:
      final flag = reader.u8();
      if (flag == 0) return null;
      final length = reader.u16();
      return SchematicConfig(
        SchematicConfigKind.string,
        utf8.decode(reader.bytes(length), allowMalformed: true),
      );
    case 5:
      final contentType = reader.u8();
      final contentId = reader.u16();
      return SchematicConfig(
        SchematicConfigKind.content,
        SchematicContentRef(contentType, contentId),
      );
    case 6:
      final count = reader.u16();
      return SchematicConfig(
        SchematicConfigKind.integerList,
        List<int>.generate(count, (_) => reader.i32()),
      );
    case 7:
      return SchematicConfig(
        SchematicConfigKind.point,
        SchematicPoint(reader.i32(), reader.i32()),
      );
    case 8:
      final count = reader.u8();
      return SchematicConfig(
        SchematicConfigKind.pointList,
        List<SchematicPoint>.generate(count, (_) => _unpackPoint(reader.i32())),
      );
    case 9:
      // TechNode：内容类型 + 内容 id；渲染不用
      final contentType = reader.u8();
      final contentId = reader.u16();
      return SchematicConfig(
        SchematicConfigKind.other,
        'techNode($contentType,$contentId)',
      );
    case 10:
      return SchematicConfig(SchematicConfigKind.boolean, reader.u8() != 0);
    case 11:
      return SchematicConfig(
        SchematicConfigKind.double,
        ByteData.sublistView(reader.bytes(8)).getFloat64(0),
      );
    case 12:
      return SchematicConfig(
        SchematicConfigKind.other,
        'building(${reader.i32()})',
      );
    case 13:
      return SchematicConfig(
        SchematicConfigKind.other,
        'lAccess(${reader.i16()})',
      );
    case 14:
      final count = reader.i32();
      return SchematicConfig(
        SchematicConfigKind.byteArray,
        reader.bytes(count),
      );
    case 15:
      reader.u8();
      return SchematicConfig(SchematicConfigKind.other, 'legacy');
    case 16:
      final count = reader.i32();
      return SchematicConfig(
        SchematicConfigKind.booleanArray,
        reader.bytes(count),
      );
    case 17:
      return SchematicConfig(
        SchematicConfigKind.other,
        'unit(${reader.i32()})',
      );
    case 18:
      final count = reader.i16();
      for (var i = 0; i < count; i++) {
        reader.f32();
        reader.f32();
      }
      return SchematicConfig(SchematicConfigKind.other, 'vec2Array($count)');
    case 19:
      return SchematicConfig(
        SchematicConfigKind.other,
        'vec2(${reader.f32()},${reader.f32()})',
      );
    case 20:
      return SchematicConfig(SchematicConfigKind.other, 'team(${reader.u8()})');
    case 21:
      final count = reader.u16();
      return SchematicConfig(
        SchematicConfigKind.integerList,
        List<int>.generate(count, (_) => reader.i32()),
      );
    case 22:
      final count = reader.i32();
      final values = <SchematicConfig>[];
      for (var i = 0; i < count; i++) {
        final element = _readConfig(reader, schematicVersion);
        if (element != null) values.add(element);
      }
      return SchematicConfig(SchematicConfigKind.other, values);
    case 23:
      return SchematicConfig(
        SchematicConfigKind.other,
        'unitCommand(${reader.u16()})',
      );
    default:
      throw FormatException('不认识的配置类型 $type');
  }
}

SchematicPoint _unpackPoint(int packed) {
  final x = ((packed >> 16) & 0xFFFF).toSigned(16);
  final y = (packed & 0xFFFF).toSigned(16);
  return SchematicPoint(x, y);
}

class SchematicPoint {
  const SchematicPoint(this.x, this.y);

  final int x;
  final int y;

  @override
  String toString() => '$x,$y';
}

/// 配置里的内容引用（物品 / 液体 / 方块等）
class SchematicContentRef {
  const SchematicContentRef(this.typeOrdinal, this.id);

  /// Mindustry ContentType 序号：0=item / 1=block / 4=liquid
  final int typeOrdinal;
  final int id;

  @override
  String toString() => 'content($typeOrdinal,$id)';
}

class _ByteReader {
  _ByteReader(this._bytes);

  final Uint8List _bytes;
  int _position = 0;

  int u8() => _bytes[_position++] & 0xFF;

  int i8() => _bytes[_position++].toSigned(8);

  int u16() {
    final value =
        (_bytes[_position] & 0xFF) << 8 | (_bytes[_position + 1] & 0xFF);
    _position += 2;
    return value;
  }

  int i16() {
    final value = u16();
    return value.toSigned(16);
  }

  int i32() {
    final value =
        (_bytes[_position] & 0xFF) << 24 |
        (_bytes[_position + 1] & 0xFF) << 16 |
        (_bytes[_position + 2] & 0xFF) << 8 |
        (_bytes[_position + 3] & 0xFF);
    _position += 4;
    return value.toSigned(32);
  }

  int i64() {
    final high = i32();
    final low = i32() & 0xFFFFFFFF;
    return (high << 32) | low;
  }

  double f32() {
    final value = ByteData.sublistView(
      _bytes,
      _position,
      _position + 4,
    ).getFloat32(0);
    _position += 4;
    return value;
  }

  Uint8List bytes(int count) {
    if (count < 0 || _position + count > _bytes.length) {
      throw const FormatException('蓝图数据越界');
    }
    final value = Uint8List.sublistView(_bytes, _position, _position + count);
    _position += count;
    return value;
  }

  /// Java DataInputStream.readUTF：u16 长度 + modified UTF-8
  String utf() {
    final length = u16();
    if (length == 0) return '';
    final value = _decodeUtf8(_bytes, _position, length);
    _position += length;
    return value;
  }

  static String _decodeUtf8(Uint8List data, int start, int length) {
    final buffer = StringBuffer();
    var index = 0;
    while (index < length) {
      final first = data[start + index++] & 0xFF;
      if (first & 0x80 == 0) {
        buffer.writeCharCode(first);
      } else if (first & 0xE0 == 0xC0) {
        final second = data[start + index++] & 0xFF;
        buffer.writeCharCode(((first & 0x1F) << 6) | (second & 0x3F));
      } else if (first & 0xF0 == 0xE0) {
        final second = data[start + index++] & 0xFF;
        final third = data[start + index++] & 0xFF;
        buffer.writeCharCode(
          ((first & 0x0F) << 12) | ((second & 0x3F) << 6) | (third & 0x3F),
        );
      } else {
        index++;
      }
    }
    return buffer.toString();
  }
}
