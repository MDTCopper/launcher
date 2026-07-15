import 'dart:io';
import 'dart:typed_data';

import 'package:copper_launcher/util/io/mindustry_save_file/settings_bin_codec.dart';

void main() {
  final path = r'C:\Users\ASUS\AppData\Roaming\Mindustry\settings.bin';
  final original = File(path).readAsBytesSync();
  print('Original: ${original.length} bytes');

  try {
    // 解码
    final decoded = SettingsBinCodec.decode(original);
    print('Decoded: ${decoded.length} entries');

    // 立即编码回去（不做任何修改）
    final reEncoded = SettingsBinCodec.encode(decoded);
    print('Re-encoded: ${reEncoded.length} bytes');

    // 逐字节对比
    if (original.length != reEncoded.length) {
      print('FAIL: size mismatch ${original.length} vs ${reEncoded.length}');
    } else {
      final diffs = <int>[];
      for (int i = 0; i < original.length; i++) {
        if (original[i] != reEncoded[i]) {
          diffs.add(i);
          if (diffs.length >= 20) break;
        }
      }
      if (diffs.isEmpty) {
        print('PASS: byte-for-byte identical!');
      } else {
        print('FAIL: ${diffs.length}+ bytes differ');
        for (final i in diffs.take(10)) {
          print(
            '  offset $i: original=0x${original[i].toRadixString(16).padLeft(2, '0')} '
            're-encoded=0x${reEncoded[i].toRadixString(16).padLeft(2, '0')}',
          );
        }
      }
    }
  } catch (e, stack) {
    print('Error: $e');
    print('Stack: $stack');
  }
}
