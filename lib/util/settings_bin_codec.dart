import 'dart:io';
import 'dart:typed_data';

import 'package:copperlauncher_main/util/ubjson_codec.dart';

/// arc 框架 Settings 二进制格式编解码器。
///
/// 基于 arc `Settings.java` 的真实格式：
/// ```text
/// // 压缩检测: 若前2字节为 zlib magic (0x78 0x01/0x5E/0x9C/0xDA)，则数据为 deflate 压缩
///
/// HEADER: int32 BE = 条目数量
///
/// 每个条目:
///   <uint16_be: key_length>              // Java modified UTF-8 字节长度
///   <bytes[N]: key_modified_utf8>        // Java modified UTF-8 编码的键
///   <uint8: value_type>
///     00 = boolean: <uint8: 0=false, 1=true>
///     01 = int32:   <int32_be: value>
///     02 = int64:   <int64_be: value>
///     03 = float32: <float32_be: value>
///     04 = string:  <uint16_be: length> <bytes: value_modified_utf8>
///     05 = binary:  <int32_be: length>  <bytes: raw_data>
/// ```
///
/// Java modified UTF-8 与标准 UTF-8 的区别：
///   - U+0000 (null) 编码为 0xC0 0x80（而非 0x00）
///   - U+10000~U+10FFFF 使用代理对（6字节），而非标准 UTF-8 的 4 字节
class SettingsBinCodec {
  static const int _typeBool = 0;
  static const int _typeInt = 1;
  static const int _typeLong = 2;
  static const int _typeFloat = 3;
  static const int _typeString = 4;
  static const int _typeBinary = 5;

  // zlib magic bytes
  static const int _zlibMagic = 0x78;

  // ── 解码 ──

  /// 从字节数组解码 settings.bin，返回 Map<String, dynamic>。
  static Map<String, dynamic> decode(Uint8List bytes) {
    final data = _maybeDecompress(bytes);
    final reader = _SettingsBinReader(data);
    return reader._readAll();
  }

  /// 检测并解压 zlib 压缩的数据。
  static Uint8List _maybeDecompress(Uint8List bytes) {
    if (bytes.length < 2) return bytes;

    final b0 = bytes[0];
    final b1 = bytes[1];

    // 检查 zlib magic: 0x78 + (0x01, 0x5E, 0x9C, 0xDA)
    if (b0 == _zlibMagic &&
        (b1 == 0x01 || b1 == 0x5E || b1 == 0x9C || b1 == 0xDA)) {
      // 前2字节是 zlib header，剩余是 deflate 数据
      final deflateData = bytes.sublist(2);
      // 使用系统 zlib 解压（Dart 的 ZLibDecoder 需要完整的 zlib stream，
      // 但这里只有 raw deflate，所以使用 raw inflate）
      try {
        final decompressed = ZLibDecoder(raw: true).convert(deflateData);
        return Uint8List.fromList(decompressed);
      } catch (_) {
        // 如果 raw deflate 失败，尝试带 header 的 zlib
        try {
          final decompressed = ZLibDecoder().convert(deflateData);
          return Uint8List.fromList(decompressed);
        } catch (_) {
          // 解压失败，返回原始数据
          return bytes;
        }
      }
    }

    return bytes;
  }

  // ── 编码 ──

  /// 将 Map<String, dynamic> 编码为 settings.bin 字节数组。
  static Uint8List encode(Map<String, dynamic> data) {
    final writer = _SettingsBinWriter();
    writer._writeAll(data);
    return Uint8List.fromList(writer._buffer);
  }
}

// ═══════════════════════════════════════════
// 内部读取器
// ═══════════════════════════════════════════

class _SettingsBinReader {
  final Uint8List _data;
  int _pos = 0;

  _SettingsBinReader(this._data);

  int _readByte() {
    if (_pos >= _data.length) {
      throw FormatException('SettingsBin: unexpected end of data at $_pos');
    }
    return _data[_pos++];
  }

  int _readUint16() {
    final b1 = _readByte();
    final b2 = _readByte();
    return (b1 << 8) | b2;
  }

  int _readInt32() {
    final b1 = _readByte();
    final b2 = _readByte();
    final b3 = _readByte();
    final b4 = _readByte();
    return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
  }

  int _readInt64() {
    final high = _readInt32();
    final low = _readInt32();
    // BigInt 转 int（低32位可能丢失，但 Mindustry 设置值不会超过 int32 范围）
    return (high << 32) | (low & 0xFFFFFFFF);
  }

  double _readFloat32() {
    final bytes = Uint8List(4);
    final buffer = ByteData.view(bytes.buffer);
    for (int i = 0; i < 4; i++) {
      bytes[3 - i] = _readByte(); // big-endian → little-endian
    }
    return buffer.getFloat32(0, Endian.little);
  }

  Uint8List _readBytes(int length) {
    if (_pos + length > _data.length) {
      throw FormatException(
        'SettingsBin: cannot read $length bytes at $_pos (end=${_data.length})',
      );
    }
    final result = _data.sublist(_pos, _pos + length);
    _pos += length;
    return result;
  }

  // ── Java modified UTF-8 解码 ──

  /// 读取 Java modified UTF-8 字符串（2字节BE长度 + 数据）。
  String _readJavaUTF() {
    final byteLength = _readUint16();
    if (byteLength == 0) return '';

    if (_pos + byteLength > _data.length) {
      throw FormatException(
        'SettingsBin: cannot read $byteLength bytes for UTF string at $_pos',
      );
    }

    final result = _decodeJavaModifiedUtf8(_data, _pos, byteLength);
    _pos += byteLength;
    return result;
  }

  /// 解码 Java modified UTF-8。
  ///
  /// 与标准 UTF-8 的区别：
  ///   1. U+0000 → 0xC0 0x80（而非 0x00）
  ///   2. U+10000~U+10FFFF → 代理对，6字节：
  ///      0xED 0xAx 0xBx 0xED 0xBx 0xBx
  ///      解码为 U+10000 + ((H-0xD800)<<10 | (L-0xDC00))
  static String _decodeJavaModifiedUtf8(Uint8List data, int start, int length) {
    final buf = StringBuffer();
    int i = 0;
    final end = start + length;

    while (start + i < end) {
      final b0 = data[start + i] & 0xFF;
      i++;

      if ((b0 & 0x80) == 0) {
        // 1字节: U+0001 ~ U+007F (ASCII)
        buf.writeCharCode(b0);
      } else if ((b0 & 0xE0) == 0xC0) {
        // 2字节
        if (start + i >= end) break;
        final b1 = data[start + i] & 0xFF;
        i++;
        if (b0 == 0xC0 && b1 == 0x80) {
          // Java modified UTF-8: 0xC0 0x80 → U+0000 (null char)
          buf.writeCharCode(0);
        } else {
          buf.writeCharCode(((b0 & 0x1F) << 6) | (b1 & 0x3F));
        }
      } else if ((b0 & 0xF0) == 0xE0) {
        // 3字节: U+0800 ~ U+FFFF
        if (start + i + 1 >= end) break;
        final b1 = data[start + i] & 0xFF;
        final b2 = data[start + i + 1] & 0xFF;
        i += 2;

        final codepoint =
            ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);

        // 检查是否为代理对（Java modified UTF-8 处理 U+10000+）
        if (codepoint >= 0xD800 && codepoint <= 0xDBFF) {
          // 高位代理 → 接下来应跟低位代理
          if (start + i + 2 >= end) break;
          final c0 = data[start + i] & 0xFF;
          final c1 = data[start + i + 1] & 0xFF;
          final c2 = data[start + i + 2] & 0xFF;
          i += 3;

          if (c0 == 0xED && (c1 & 0xF0) == 0xB0) {
            final low = ((c1 & 0x0F) << 6) | (c2 & 0x3F);
            final high = codepoint;
            if (low >= 0xDC00 && low <= 0xDFFF) {
              // 合法代理对
              final cp = 0x10000 + ((high - 0xD800) << 10) | (low - 0xDC00);
              buf.writeCharCode(cp);
            } else {
              // 无效，按原样写入
              buf.writeCharCode(high);
              buf.writeCharCode(low);
            }
          } else {
            buf.writeCharCode(codepoint);
          }
        } else {
          buf.writeCharCode(codepoint);
        }
      }
    }

    return buf.toString();
  }

  // ── 主读取逻辑 ──

  Map<String, dynamic> _readAll() {
    final map = <String, dynamic>{};

    if (_data.length < 4) {
      throw FormatException('SettingsBin: file too short (no header)');
    }

    final entryCount = _readInt32();

    for (int i = 0; i < entryCount; i++) {
      // 读取 key（Java modified UTF-8）
      final key = _readJavaUTF();

      // 读取 value type
      final valueType = _readByte();
      dynamic value;

      switch (valueType) {
        case SettingsBinCodec._typeBool:
          value = _readByte() != 0;
          break;
        case SettingsBinCodec._typeInt:
          value = _readInt32();
          break;
        case SettingsBinCodec._typeLong:
          value = _readInt64();
          break;
        case SettingsBinCodec._typeFloat:
          value = _readFloat32();
          break;
        case SettingsBinCodec._typeString:
          value = _readJavaUTF();
          break;
        case SettingsBinCodec._typeBinary:
          final binLen = _readInt32();
          value = _readBytes(binLen);
          break;
        default:
          throw FormatException(
            'SettingsBin: unknown value type 0x${valueType.toRadixString(16)} '
            'at $_pos (key="$key", entry $i/$entryCount)',
          );
      }

      map[key] = value;
    }

    return map;
  }
}

// ═══════════════════════════════════════════
// 内部写入器
// ═══════════════════════════════════════════

class _SettingsBinWriter {
  final List<int> _buffer = [];

  void _writeByte(int b) => _buffer.add(b & 0xFF);

  void _writeUint16(int v) {
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

  void _writeBytes(List<int> bytes) => _buffer.addAll(bytes);

  // ── Java modified UTF-8 编码 ──

  /// 编码为 Java modified UTF-8 并写入（2字节BE长度 + 数据）。
  void _writeJavaUTF(String s) {
    final bytes = _encodeJavaModifiedUtf8(s);
    if (bytes.length > 65535) {
      throw ArgumentError(
        'SettingsBin: string too long (${bytes.length} bytes for Java UTF)',
      );
    }
    _writeUint16(bytes.length);
    _writeBytes(bytes);
  }

  /// 将 Dart 字符串编码为 Java modified UTF-8 字节。
  static List<int> _encodeJavaModifiedUtf8(String s) {
    final buf = <int>[];

    for (int i = 0; i < s.length; i++) {
      final cp = s.codeUnitAt(i);

      if (cp == 0) {
        // U+0000 → 0xC0 0x80
        buf.add(0xC0);
        buf.add(0x80);
      } else if (cp <= 0x7F) {
        // 1字节 ASCII
        buf.add(cp);
      } else if (cp <= 0x7FF) {
        // 2字节
        buf.add(0xC0 | (cp >> 6));
        buf.add(0x80 | (cp & 0x3F));
      } else if (cp <= 0xFFFF) {
        // 不再使用代理对（Mindustry 键均为 ASCII），但保留标准 3 字节编码
        buf.add(0xE0 | (cp >> 12));
        buf.add(0x80 | ((cp >> 6) & 0x3F));
        buf.add(0x80 | (cp & 0x3F));
      }
      // Dart 的 codeUnitAt 不会返回 surrogate，characters > U+FFFF 应使用 runes
    }

    return buf;
  }

  // ── 主写入逻辑 ──

  void _writeAll(Map<String, dynamic> data) {
    _writeInt32(data.length);

    for (final entry in data.entries) {
      _writeEntry(entry.key, entry.value);
    }
  }

  void _writeEntry(String key, dynamic value) {
    // 写入 key
    _writeJavaUTF(key);

    // 写入 value
    if (value == null) {
      _writeByte(SettingsBinCodec._typeBool);
      _writeByte(0);
    } else if (value is bool) {
      _writeByte(SettingsBinCodec._typeBool);
      _writeByte(value ? 1 : 0);
    } else if (value is int) {
      _writeByte(SettingsBinCodec._typeInt);
      _writeInt32(value);
    } else if (value is double) {
      _writeByte(SettingsBinCodec._typeFloat);
      _writeFloat32(value);
    } else if (value is String) {
      _writeByte(SettingsBinCodec._typeString);
      _writeJavaUTF(value);
    } else if (value is Uint8List) {
      _writeByte(SettingsBinCodec._typeBinary);
      _writeInt32(value.length);
      _writeBytes(value);
    } else if (value is Map || value is List) {
      // 嵌套 Map/List → UBJson 编码 → 存入 binary
      final ubjsonBytes = UbjsonCodec.encode(value);
      _writeByte(SettingsBinCodec._typeBinary);
      _writeInt32(ubjsonBytes.length);
      _writeBytes(ubjsonBytes);
    } else {
      throw ArgumentError(
        'SettingsBin: unsupported value type ${value.runtimeType} for key "$key"',
      );
    }
  }
}
