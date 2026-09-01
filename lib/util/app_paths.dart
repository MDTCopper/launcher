import 'dart:io';

import 'package:copper_launcher/util/io/os.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class AppPaths {
  static late String applicationSupportPath;

  static String? _defaultGameDataPath;

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
      _defaultGameDataPath = p.join(applicationSupportPath, '.mindustry');
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
    if (_defaultGameDataPath == null) throw ('无法获取默认游戏数据存储位置');
  }

  /// 桌面端为根目录 [*\copper_launcher]
  ///
  /// android为工作目录
  static String get copperLauncher {
    if (Platform.isAndroid) return applicationSupportPath;
    return p.current;
  }

  /// 默认版本文件夹路径 [*\versions\]
  static String get versions => p.join(copperLauncher, 'versions');

  /// 默认移动端版本文件分类 [*\versionsFolds]，创建的文件分类只会存储在这里
  static String get versionsFolds {
    if (isDesktop) return versions;
    return p.join(copperLauncher, 'versionsFolds');
  }

  /// 存储游戏本体引用的路径
  static String get mindustrys => p.join(copperLauncher, 'mindustrys');

  /// [*\logs\]
  static String get logs => p.join(copperLauncher, 'logs');

  /// [*\config.json]
  static String get configJson => p.join(copperLauncher, 'config.json');

  /// [*\config.bin]
  static String get configBin => p.join(copperLauncher, 'config.bin');

  /// win => [C:\Users\{username}\AppData\Roaming\Mindustry\]
  static String? get defaultGameData => _defaultGameDataPath;

  /// win => [C:\Users\{username}\AppData\Roaming\Mindustry\mods\]
  static String? get defaultMods =>
      defaultGameData == null ? null : p.join(defaultGameData!, 'mods');
}
