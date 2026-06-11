import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Mindustry 地图存档 (.msav) 和蓝图 (.msch) 的元数据解码器。
///
/// 两者统一返回 `Map<String, dynamic>`。
/// **先展开原始 tags，再覆盖已解析字段**，确保转换后的值不被原始 String 覆盖。
class SaveFileCodec {
  static const _mschHeader = [0x6D, 0x73, 0x63, 0x68];
  static const _msavHeader = [0x4D, 0x53, 0x41, 0x56];

  // ── .msch ──

  static Map<String, dynamic> decodeSchematic(Uint8List bytes) {
    for (int i = 0; i < _mschHeader.length; i++) {
      if (bytes[i] != _mschHeader[i]) {
        throw FormatException('不是有效的 .msch 文件（头部不匹配）');
      }
    }
    if (bytes[_mschHeader.length] > 1) {
      throw FormatException('不支持的 .msch 版本');
    }

    final data = _inflateRest(bytes, _mschHeader.length + 1);
    final r = _Reader(data);

    final width = r.u16();
    final height = r.u16();

    final tagCount = r.u8();
    final tags = <String, dynamic>{};
    for (int i = 0; i < tagCount; i++) {
      tags[r.utf()] = r.utf();
    }

    // 跳过 block 字典
    final blockCount = r.u8();
    for (int i = 0; i < blockCount; i++) {
      r.utf();
    }

    final tileCount = r.i32();

    // 解析 labels
    List<String> labels = [];
    final labelsRaw = tags['labels'] as String?;
    if (labelsRaw != null && labelsRaw != '[]') {
      try {
        labels = (jsonDecode(labelsRaw) as List).cast<String>();
      } catch (_) {}
    }

    // 先展开原始 tags，再覆盖已解析字段
    return {
      ...tags,
      'name': tags['name'] ?? '',
      'description': tags['description'] ?? '',
      'labels': labels,
      'width': width,
      'height': height,
      'tileCount': tileCount,
    };
  }

  // ── .msav ──

  static Map<String, dynamic> decodeMapMeta(Uint8List bytes) {
    final data = _decompress(bytes);
    final reader = _Reader(data);

    for (int i = 0; i < _msavHeader.length; i++) {
      if (reader.b() != _msavHeader[i]) {
        throw FormatException('不是有效的 .msav 文件（头部不匹配）');
      }
    }

    reader.i32(); // version

    final chunkLength = reader.i32();
    if (chunkLength <= 0) {
      throw FormatException('无效的 meta 区域长度: $chunkLength');
    }

    final entryCount = reader.u16();
    final tags = <String, dynamic>{};
    for (int i = 0; i < entryCount; i++) {
      tags[reader.utf()] = reader.utf();
    }

    // 解析 mods
    List<String> mods = [];
    final modsRaw = tags['mods'] as String?;
    if (modsRaw != null && modsRaw != '[]') {
      try {
        mods = (jsonDecode(modsRaw) as List).cast<String>();
      } catch (_) {}
    }

    // 先展开原始 tags，再覆盖已解析字段
    return {
      ...tags,
      'wave': int.tryParse(tags['wave'] as String? ?? '') ?? 0,
      'playtime': int.tryParse(tags['playtime'] as String? ?? '') ?? 0,
      'saved': int.tryParse(tags['saved'] as String? ?? '') ?? 0,
      'build': int.tryParse(tags['build'] as String? ?? '') ?? 0,
      'mods': mods,
    };
  }

  // ── 解压 ──

  static Uint8List _decompress(Uint8List bytes) {
    try {
      return Uint8List.fromList(ZLibDecoder().convert(bytes));
    } catch (_) {
      return Uint8List.fromList(ZLibDecoder(raw: true).convert(bytes));
    }
  }

  static Uint8List _inflateRest(Uint8List bytes, int skip) {
    final deflateData = bytes.sublist(skip);
    try {
      return Uint8List.fromList(ZLibDecoder(raw: true).convert(deflateData));
    } catch (_) {
      return Uint8List.fromList(ZLibDecoder().convert(deflateData));
    }
  }
}

// ═══════════════════════════════
// Java DataInput 读取器
// ═══════════════════════════════

class _Reader {
  final Uint8List _d;
  int _p = 0;

  _Reader(this._d);

  int b() => _d[_p++];

  int u8() => _d[_p++] & 0xFF;

  int u16() => (b() & 0xFF) << 8 | (b() & 0xFF);

  int i32() =>
      (b() & 0xFF) << 24 |
      (b() & 0xFF) << 16 |
      (b() & 0xFF) << 8 |
      (b() & 0xFF);

  String utf() {
    final len = u16();
    if (len == 0) return '';
    final s = _decodeUtf(_d, _p, len);
    _p += len;
    return s;
  }

  static String _decodeUtf(Uint8List d, int start, int len) {
    final buf = StringBuffer();
    int i = 0;
    while (start + i < start + len) {
      final b0 = d[start + i++] & 0xFF;
      if ((b0 & 0x80) == 0) {
        buf.writeCharCode(b0);
      } else if ((b0 & 0xE0) == 0xC0) {
        final b1 = d[start + i++] & 0xFF;
        buf.writeCharCode(
          b0 == 0xC0 && b1 == 0x80 ? 0 : ((b0 & 0x1F) << 6) | (b1 & 0x3F),
        );
      } else if ((b0 & 0xF0) == 0xE0) {
        final b1 = d[start + i++] & 0xFF;
        final b2 = d[start + i++] & 0xFF;
        buf.writeCharCode(
          ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F),
        );
      }
    }
    return buf.toString();
  }
}
