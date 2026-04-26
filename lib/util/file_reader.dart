import 'dart:io';

import 'package:open_filex/open_filex.dart';

class FileReader {
  static Future<void> openFolder(String path) async {
    //todo 用win32接口调用，防止反复打开文件夹
    final dir = Directory(path);

    if (!(await dir.exists())) {
      throw Exception("路径不存在：$path");
    }

    try {
      if (Platform.isWindows) {
        await _runWinExplorer(["/open,", dir.path]);
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> locatedPath(String path) async {
    final dir = Directory(path);
    if (!(await dir.exists())) {
      throw Exception("路径不存在：$path");
    }

    try {
      if (Platform.isWindows) {
        await _runWinExplorer(["/select,", dir.path]);
      } else if (Platform.isAndroid) {
        _locateFileOnAndroid(path);
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> _runWinExplorer(List<String> arguments) async {
    await Process.run("explorer.exe", arguments, runInShell: true);
  }

  //todo 安卓端文件定位
  static Future<void> _locateFileOnAndroid(String path) async {
    // 步骤1：申请存储权限（Android 13+需读取权限）
    final bool hasPermission = await _requestAndroidFilePermission();
    if (!hasPermission) {
      throw Exception('安卓端暂时不支持文件定位');
    }

    final File file = File(path);
    final String folderPath = file.parent.path;

    try {
      // 方式1：优先使用open_filex尝试直接定位（部分文件管理器支持）
      final result = await OpenFilex.open(path, type: "file");

      if (result.type != ResultType.done) {
        // 方式2：兜底方案：打开文件所在文件夹，提示用户查找
        await OpenFilex.open(folderPath, type: "folder");
        print("Android文件管理器不支持直接定位，已打开所在文件夹：$folderPath");
      } else {
        print("Android文件定位成功：$path");
      }
    } catch (e) {
      // 最终兜底：打开文件夹
      await OpenFilex.open(folderPath, type: "folder");
      print("Android文件定位异常，已打开所在文件夹：$e");
    }
  }

  static Future<bool> _requestAndroidFilePermission() async {
    //todo 存储权限申请

    return false;
  }
}
