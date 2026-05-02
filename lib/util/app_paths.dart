import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class AppPaths {
  /// win => C:\Users\ASUS\AppData\Roaming\com.example\Copper\MindustryLauncher
  static Future<Directory> get rootLocal async {
    return Directory(//路径返回
      p.join(//路径拼凑，适用于不同的系统
        (await getApplicationSupportDirectory()).path,
        'MindustryLauncher',
      ),
    );
  }

  /// win => C:\Users\ASUS\Desktop\copperlauncher_main\versions
  static String get versions {
    return p.join(p.current, 'versions');
  }

}
