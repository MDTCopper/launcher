import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class AppPaths {
  static String? _defaultGameDataPath;
  static late String applicationSupportPath;

  static Future<void> init() async {
    final appSupportDir = await getApplicationSupportDirectory();
    applicationSupportPath = appSupportDir.path;
    await initDefaultDataPath();
  }

  static Future<void> initDefaultDataPath() async {
    if (Platform.isWindows) {
      final roaming = Platform.environment['APPDATA'];
      if (roaming != null) {
        _defaultGameDataPath = p.join(roaming, 'Mindustry');
      }
    } else if (Platform.isAndroid) {
      //安卓平台默认为/storage/emulated/0/Android/data/io.anuke.mindustry/files/，但安卓平台不能直接读取data
      _defaultGameDataPath =
          '/storage/emulated/0/Android/data/io.anuke.mindustry/files/';
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        _defaultGameDataPath = p.join(
          Platform.environment['HOME']!,
          '.local',
          'share',
          'Mindustry',
        );
      }
    }
    if (_defaultGameDataPath == null) {
      throw ('无法获取默认游戏数据存储位置');
    } else {
      print('默认数据存储路径:$_defaultGameDataPath');
    }
  }

  /// win => [C:\Users\ASUS\AppData\Roaming\com.example\Copper\CopperLauncher]
  static Future<Directory> get rootLocal async {
    return Directory(
      p.join((await getApplicationSupportDirectory()).path, 'CopperLauncher'),
    );
  }

  /// [*\copperlauncher_main]
  /// android => [/data/user/0/com.example.copperlauncher_main/files]
  static String get copperLauncher {
    if (Platform.isAndroid) return applicationSupportPath;
    return p.current;
  }

  /// 默认版本文件夹路径 [*\copperlauncher_main\versions\]
  static String get versions => p.join(copperLauncher, 'versions');

  /// [*\copperlauncher_main\logs\]
  static String get logs => p.join(copperLauncher, 'logs');

  /// [*\copperlauncher_main\config.json]
  static String get configJson => p.join(copperLauncher, 'config.json');

  /// [*\copperlauncher_main\config.bin]
  static String get configBin => p.join(copperLauncher, 'config.bin');

  /// win => [C:\Users\\{username}\AppData\Roaming\Mindustry\]
  static String? get defaultGameData => _defaultGameDataPath;

  /// win => [C:\Users\\{username}\AppData\Roaming\Mindustry\mods\]
  static String? get defaultMods =>
      defaultGameData == null ? null : p.join(defaultGameData!, 'mods');
}
