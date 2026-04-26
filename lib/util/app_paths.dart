import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPaths {

  static Future<Directory> get rootLocal async {
    return Directory(//路径返回
      p.join(//路径拼凑，适用于不同的系统
        (await getApplicationSupportDirectory()).path,
        'MindustryLauncher',
      ),
    );
  }

  static Future<File> jarFile(String tag) async {
    return File(p.join((await rootLocal).path, 'mindustry-$tag.jar'));
  }

  static Future<Directory> get versions async{
    return Directory(p.join(p.current,'versions'));
  }

}
