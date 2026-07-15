import 'dart:io';
import 'dart:typed_data';

import 'package:copper_launcher/util/io/mindustry_save_file/settings_bin_codec.dart';

void main() {
  final path = r'C:\Users\ASUS\AppData\Roaming\Mindustry\settings.bin';
  final file = File(path);

  if (!file.existsSync()) {
    print('File not found: $path');
    return;
  }

  final bytes = file.readAsBytesSync();
  print('File size: ${bytes.length} bytes');

  // 检查前几个字节
  print(
    'First 10 bytes: ${bytes.sublist(0, 10).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}',
  );

  try {
    final stopwatch = Stopwatch()..start();
    final decoded = SettingsBinCodec.decode(bytes);
    stopwatch.stop();

    print('\n=== Decode successful! ===');
    print('Time: ${stopwatch.elapsedMilliseconds}ms');
    print('Entries: ${decoded.length}');

    // 打印前20个键值对
    final keys = decoded.keys.toList();
    print('\nFirst 20 entries:');
    for (int i = 0; i < 20 && i < keys.length; i++) {
      final key = keys[i];
      final value = decoded[key];
      final valueStr = value is Uint8List
          ? '<binary: ${value.length} bytes>'
          : value.toString();
      final shortKey = key.length > 60 ? '${key.substring(0, 57)}...' : key;
      print('  [$i] $shortKey = $valueStr');
    }

    // 查找已知的Mindustry设置项
    final knownKeys = [
      'uiscale',
      'screenshake',
      'vsync',
      'fullscreen',
      'fpscap',
      'musicvol',
      'sfxvol',
      'saveinterval',
      'locale',
      'lastBuild',
    ];
    print('\nKnown Mindustry settings:');
    for (final k in knownKeys) {
      if (decoded.containsKey(k)) {
        print('  $k = ${decoded[k]}');
      } else {
        print('  $k = <not found>');
      }
    }

    // 统计类型
    int boolCount = 0, intCount = 0, strCount = 0, binCount = 0, otherCount = 0;
    for (final v in decoded.values) {
      if (v is bool)
        boolCount++;
      else if (v is int)
        intCount++;
      else if (v is String)
        strCount++;
      else if (v is Uint8List || v is Map || v is List)
        binCount++;
      else
        otherCount++;
    }
    print(
      '\nTypes: bool=$boolCount, int=$intCount, string=$strCount, binary=${binCount}, other=$otherCount',
    );
  } catch (e, stack) {
    print('\n=== Decode FAILED ===');
    print('Error: $e');
    print('Stack: $stack');
  }
}
