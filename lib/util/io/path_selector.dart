import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:open_filex/open_filex.dart';

import '../app_paths.dart';
import 'process_controller.dart';

class PathSelector {
  ///打开对应路径文件夹（Win32 防重复打开：已有同路径窗口则激活，否则新建）
  static Future<void> openFolder(String path) async {
    final dir = Directory(path);
    if (!(await dir.exists())) {
      throw Exception("路径不存在：\\$path");
    }

    try {
      if (Platform.isWindows) {
        WindowProcessController.openExplorer(dir.path);
      }
    } catch (e) {
      rethrow;
    }
  }

  ///在资源管理器中定位选中文件/文件夹
  static Future<void> locatedPath(String path) async {
    final dir = Directory(path);
    if (!(await dir.exists())) {
      throw Exception("路径不存在：$path");
    }

    try {
      if (Platform.isWindows) {
        WindowProcessController.locateFile(dir.path);
      } else if (Platform.isAndroid) {
        _locateFileOnAndroid(path);
      }
    } catch (e) {
      rethrow;
    }
  }

  ///选择文件夹,默认初始目录为CopperLauncher目录
  static Future<String?> selectDirectory({
    String? initialDirectory,
    String? confirmButtonText,
    // bool? canCreateDirectories,
  }) async {
    initialDirectory ??= AppPaths.copperLauncher;
    return await getDirectoryPath(
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
      // canCreateDirectories: canCreateDirectories,
    );
  }

  static Future<String?> selectFile({
    String? initialDirectory,
    String? confirmButtonText,
    List<XTypeGroup> acceptedTypeGroups = const <XTypeGroup>[],
  }) async {
    initialDirectory ??= AppPaths.copperLauncher;
    final file = await openFile(
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
      acceptedTypeGroups: acceptedTypeGroups,
    );
    return file?.path;
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
