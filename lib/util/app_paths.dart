import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class AppPaths {
  /// win => C:\Users\ASUS\AppData\Roaming\com.example\Copper\CopperLauncher
  static Future<Directory> get rootLocal async {
    return Directory(
      p.join((await getApplicationSupportDirectory()).path, 'CopperLauncher'),
    );
  }

  /// win => C:\Users\ASUS\Desktop\copperlauncher_main
  static String get copperLauncherDir => p.current;

  static String get versionsDir => p.join(copperLauncherDir, 'versions');

  static String get logsDir => p.join(copperLauncherDir, 'logs');

  static String get configJson => p.join(copperLauncherDir, 'config.json');

  static String get configBin => p.join(copperLauncherDir, 'config.bin');
}
