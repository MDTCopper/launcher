import 'dart:convert';
import 'dart:typed_data';

/// arc 框架 UBJson 编解码器。
///
/// 基于 arc `UBJsonReader.java` / `UBJsonWriter.java` 的真实格式：
///
/// **类型标记:**
///   `{` (0x7B) / `}` (0x7D) — 对象 开始/结束
///   `[` (0x5B) / `]` (0x5D) — 数组 开始/结束
///   `Z` (0x5A) — null
///   `T` (0x54) — true
///   `F` (0x46) — false
///   `i` (0x69) — int8
///   `I` (0x49) — int16
///   `l` (0x6C) — int32
///   `L` (0x4C) — int64
///   `d` (0x64) — float32
///   `D` (0x44) — float64
///   `S` (0x53) — string（后跟 `<int_type> <length> <bytes>`）
///   `s` (0x73) — 短字符串（后跟 `<uint8: length> <bytes>`）
///   `C` (0x43) — char (int16)
///
/// **对象键:** 不使用标记，直接 `<int_type> <length> <bytes>`，
///   其中 int_type = `i`/`I`/`l` 表示长度类型。
///   若首字节不匹配已知类型，回退为 4 字节 BE 长度。
///
/// **优化数组:** `[` `$` `<element_type>` `#` `<size_type> <count>` `<elements...>` `]`
///   目前仅解析，不生成优化数组。
class UbjsonCodec {
  // ── 类型标记 ──
  static const int _objBegin = 0x7B; // {
  static const int _objEnd = 0x7D; // }
  static const int _arrBegin = 0x5B; // [
  static const int _arrEnd = 0x5D; // ]
  static const int _null = 0x5A; // Z
  static const int _true = 0x54; // T
  static const int _false = 0x46; // F
  static const int _int8 = 0x69; // i
  static const int _int16 = 0x49; // I
  static const int _int32 = 0x6C; // l
  static const int _int64 = 0x4C; // L
  static const int _float32 = 0x64; // d
  static const int _float64 = 0x44; // D
  static const int _str = 0x53; // S
  static const int _shortStr = 0x73; // s
  static const int _char = 0x43; // C
  static const int _optArrayType = 0x24; // $
  static const int _optArrayCount = 0x23; // #

  // ── 解码 ──

  /// 从字节数组解码 UBJson，返回 Map 或 List 或基本类型。
  static dynamic decode(Uint8List bytes) {
    final reader = _UbjsonReader(bytes);
    final result = reader._readValue();
    if (reader._pos != bytes.length) {
      throw FormatException(
        'UBJson: trailing bytes at position ${reader._pos}',
      );
    }
    return result;
  }

  // ── 编码 ──

  /// 将 Map / List / 基本类型编码为 UBJson 字节数组。
  static Uint8List encode(dynamic value) {
    final writer = _UbjsonWriter();
    writer._writeValue(value);
    return Uint8List.fromList(writer._buffer);
  }
}

// ═══════════════════════════════════════════
// 内部读取器
// ═══════════════════════════════════════════

class _UbjsonReader {
  final Uint8List _data;
  int _pos = 0;

  _UbjsonReader(this._data);

  int _readByte() {
    if (_pos >= _data.length) {
      throw FormatException('UBJson: unexpected end of data at $_pos');
    }
    return _data[_pos++];
  }

  int _readInt8() {
    final b = _readByte();
    return b > 127 ? b - 256 : b;
  }

  int _readUint8() => _readByte();

  int _readInt16() {
    final val = (_readByte() << 8) | _readByte();
    return val > 32767 ? val - 65536 : val;
  }

  int _readInt32() {
    final val =
        (_readByte() << 24) |
        (_readByte() << 16) |
        (_readByte() << 8) |
        _readByte();
    return val > 2147483647 ? val - 4294967296 : val;
  }

  int _readInt64() {
    final high = _readInt32();
    final low = _readInt32() & 0xFFFFFFFF;
    return (high << 32) | low;
  }

  double _readFloat32() {
    final bytes = Uint8List(4);
    final buffer = ByteData.view(bytes.buffer);
    for (int i = 0; i < 4; i++) {
      bytes[3 - i] = _readByte();
    }
    return buffer.getFloat32(0, Endian.little);
  }

  double _readFloat64() {
    final bytes = Uint8List(8);
    final buffer = ByteData.view(bytes.buffer);
    for (int i = 0; i < 8; i++) {
      bytes[7 - i] = _readByte();
    }
    return buffer.getFloat64(0, Endian.little);
  }

  Uint8List _readBytes(int length) {
    if (_pos + length > _data.length) {
      throw FormatException(
        'UBJson: cannot read $length bytes at $_pos (end=${_data.length})',
      );
    }
    final result = _data.sublist(_pos, _pos + length);
    _pos += length;
    return result;
  }

  // ── 大小解析（arc 格式） ──

  /// 读取大小值。type 为大小类型标记（`i`/`I`/`l`/`L`）。
  /// 若 [useIntOnError] 为 true 且 type 不匹配已知标记，
  /// 回退为将 type 作为 4 字节 BE 长度的首字节。
  int _parseSize(
    int type, {
    bool useIntOnError = false,
    int defaultValue = -1,
  }) {
    switch (type) {
      case UbjsonCodec._int8:
        return _readUint8();
      case UbjsonCodec._int16:
        return _readUint8() << 8 | _readUint8();
      case UbjsonCodec._int32:
        return _readInt32() & 0xFFFFFFFF;
      case UbjsonCodec._int64:
        return _readInt64();
      default:
        if (useIntOnError) {
          // 回退：type 为大端 int32 的首字节
          int result = (type & 0xFF) << 24;
          result |= (_readByte() & 0xFF) << 16;
          result |= (_readByte() & 0xFF) << 8;
          result |= _readByte() & 0xFF;
          return result;
        }
        return defaultValue;
    }
  }

  // ── 字符串解析 ──

  /// 读取字符串。
  /// [sOptional] 为 true 时（用于对象键），type 直接作为大小类型标记。
  String _parseString(int type, {bool sOptional = false}) {
    int size = -1;
    if (type == UbjsonCodec._str) {
      // S: 读取大小类型，再读大小
      final sizeType = _readByte();
      size = _parseSize(sizeType, useIntOnError: true);
    } else if (type == UbjsonCodec._shortStr) {
      // s: 1 字节大小
      size = _readUint8();
    } else if (sOptional) {
      // 对象键：type 直接是大小的类型标记或回退为 int32
      size = _parseSize(type, useIntOnError: true);
    }
    if (size < 0) {
      throw FormatException(
        'UBJson: expected string at $_pos, got type 0x${type.toRadixString(16)}',
      );
    }
    return size > 0 ? utf8.decode(_readBytes(size)) : '';
  }

  // ── 值解析 ──

  dynamic _readValue() {
    final marker = _readByte();
    switch (marker) {
      case UbjsonCodec._objBegin:
        return _readObject();
      case UbjsonCodec._arrBegin:
        return _readArray();
      case UbjsonCodec._null:
        return null;
      case UbjsonCodec._true:
        return true;
      case UbjsonCodec._false:
        return false;
      case UbjsonCodec._int8:
        return _readInt8();
      case UbjsonCodec._int16:
        return _readInt16();
      case UbjsonCodec._int32:
        return _readInt32();
      case UbjsonCodec._int64:
        return _readInt64();
      case UbjsonCodec._float32:
        return _readFloat32();
      case UbjsonCodec._float64:
        return _readFloat64();
      case UbjsonCodec._str:
      case UbjsonCodec._shortStr:
        // 需要将类型传回给 _parseString
        _pos--; // 回退，让 _parseString 处理
        return _parseString(_readByte());
      case UbjsonCodec._char:
        return _readInt16();
      default:
        throw FormatException(
          'UBJson: unknown marker 0x${marker.toRadixString(16)} at $_pos',
        );
    }
  }

  // ── 对象解析 ──

  Map<String, dynamic> _readObject() {
    final map = <String, dynamic>{};
    int peek = _data[_pos];

    while (_pos < _data.length && peek != UbjsonCodec._objEnd) {
      // 对象键：直接是大小类型标记或 int32 回退
      final key = _parseString(peek, sOptional: true);
      map[key] = _readValue();
      if (_pos < _data.length) {
        peek = _data[_pos];
      }
    }

    if (_pos < _data.length && _data[_pos] == UbjsonCodec._objEnd) {
      _pos++; // 消费 }
    } else {
      throw FormatException('UBJson: unclosed object at $_pos');
    }
    return map;
  }

  // ── 数组解析 ──

  List<dynamic> _readArray() {
    final list = <dynamic>[];

    // 检查优化数组: `$` `<element_type>` `#` `<size>`
    int? elementType;
    if (_data[_pos] == UbjsonCodec._optArrayType) {
      _pos++; // 消费 $
      elementType = _readByte(); // 元素类型
      final countType = _readByte(); // 应为 #
      if (countType != UbjsonCodec._optArrayCount) {
        throw FormatException(
          'UBJson: expected # for optimized array count at $_pos',
        );
      }
      // 读取元素数量（int32 BE）
      final count = _readInt32() & 0xFFFFFFFF;
      if (count < 0)
        throw FormatException('UBJson: invalid optimized array count');

      // 读取优化数组元素
      for (int i = 0; i < count; i++) {
        list.add(_parseOptimizedValue(elementType!));
      }
    } else {
      // 普通数组
      while (_pos < _data.length && _data[_pos] != UbjsonCodec._arrEnd) {
        list.add(_readValue());
      }
    }

    // 消费 ]
    if (_pos < _data.length && _data[_pos] == UbjsonCodec._arrEnd) {
      _pos++;
    } else {
      throw FormatException('UBJson: unclosed array at $_pos');
    }
    return list;
  }

  /// 解析优化数组中的单个值（不带类型标记）。
  dynamic _parseOptimizedValue(int elementType) {
    switch (elementType) {
      case UbjsonCodec._int8:
        return _readInt8();
      case UbjsonCodec._int16:
      case UbjsonCodec._char:
        return _readInt16();
      case UbjsonCodec._int32:
        return _readInt32();
      case UbjsonCodec._int64:
        return _readInt64();
      case UbjsonCodec._float32:
        return _readFloat32();
      case UbjsonCodec._float64:
        return _readFloat64();
      case UbjsonCodec._true:
        return true;
      case UbjsonCodec._false:
        return false;
      case UbjsonCodec._str:
        // 优化数组中的字符串：大小类型 + 大小 + 数据
        final sizeType = _readByte();
        final size = _parseSize(sizeType, useIntOnError: true);
        return size > 0 ? utf8.decode(_readBytes(size)) : '';
      default:
        throw FormatException(
          'UBJson: unknown optimized array element type 0x${elementType.toRadixString(16)}',
        );
    }
  }
}

// ═══════════════════════════════════════════
// 内部写入器
// ═══════════════════════════════════════════

class _UbjsonWriter {
  final List<int> _buffer = [];

  void _writeByte(int b) => _buffer.add(b & 0xFF);

  void _writeInt8(int v) => _buffer.add(v & 0xFF);

  void _writeInt16(int v) {
    _buffer.add((v >> 8) & 0xFF);
    _buffer.add(v & 0xFF);
  }

  void _writeInt32(int v) {
    _buffer.add((v >> 24) & 0xFF);
    _buffer.add((v >> 16) & 0xFF);
    _buffer.add((v >> 8) & 0xFF);
    _buffer.add(v & 0xFF);
  }

  void _writeInt64(int v) {
    _writeInt32((v >> 32) & 0xFFFFFFFF);
    _writeInt32(v & 0xFFFFFFFF);
  }

  void _writeFloat32(double v) {
    final bytes = Uint8List(4);
    final buffer = ByteData.view(bytes.buffer);
    buffer.setFloat32(0, v, Endian.little);
    for (int i = 3; i >= 0; i--) {
      _writeByte(bytes[i]);
    }
  }

  void _writeFloat64(double v) {
    final bytes = Uint8List(8);
    final buffer = ByteData.view(bytes.buffer);
    buffer.setFloat64(0, v, Endian.little);
    for (int i = 7; i >= 0; i--) {
      _writeByte(bytes[i]);
    }
  }

  void _writeBytes(List<int> bytes) => _buffer.addAll(bytes);

  // ── 大小写入（选择最小类型） ──

  void _writeSize(int size) {
    if (size <= 127) {
      _writeByte(UbjsonCodec._int8);
      _writeInt8(size);
    } else if (size <= 32767) {
      _writeByte(UbjsonCodec._int16);
      _writeInt16(size);
    } else {
      _writeByte(UbjsonCodec._int32);
      _writeInt32(size);
    }
  }

  // ── 键写入（arc 格式：无标记，直接大小类型+大小+数据） ──

  void _writeName(String name) {
    final bytes = utf8.encode(name);
    _writeSize(bytes.length);
    _writeBytes(bytes);
  }

  // ── 字符串值写入（arc 格式：S + 大小类型+大小+数据） ──

  void _writeString(String value) {
    final bytes = utf8.encode(value);
    _writeByte(UbjsonCodec._str);
    _writeSize(bytes.length);
    _writeBytes(bytes);
  }

  // ── 值写入 ──

  void _writeValue(dynamic value) {
    if (value == null) {
      _writeByte(UbjsonCodec._null);
    } else if (value is bool) {
      _writeByte(value ? UbjsonCodec._true : UbjsonCodec._false);
    } else if (value is int) {
      if (value >= -128 && value <= 127) {
        _writeByte(UbjsonCodec._int8);
        _writeInt8(value);
      } else if (value >= -32768 && value <= 32767) {
        _writeByte(UbjsonCodec._int16);
        _writeInt16(value);
      } else {
        _writeByte(UbjsonCodec._int32);
        _writeInt32(value);
      }
    } else if (value is double) {
      _writeByte(UbjsonCodec._float64);
      _writeFloat64(value);
    } else if (value is String) {
      _writeString(value);
    } else if (value is Map) {
      _writeByte(UbjsonCodec._objBegin);
      for (final entry in value.entries) {
        _writeName(entry.key.toString());
        _writeValue(entry.value);
      }
      _writeByte(UbjsonCodec._objEnd);
    } else if (value is List) {
      _writeByte(UbjsonCodec._arrBegin);
      for (final item in value) {
        _writeValue(item);
      }
      _writeByte(UbjsonCodec._arrEnd);
    } else {
      throw ArgumentError('UBJson: unsupported type ${value.runtimeType}');
    }
  }
}
