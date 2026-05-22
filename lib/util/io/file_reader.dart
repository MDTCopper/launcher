import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:open_filex/open_filex.dart';

import '../app_paths.dart';

class FileReader {
  // Cache to track recently opened folder paths with timestamps
  static final Map<String, DateTime> _recentlyOpenedPaths = <String, DateTime>{
  };
  static const Duration _cacheDuration = Duration(
      seconds: 3); // Clear cache after 3 seconds

  ///检查指定路径的文件夹是否已经在资源管理器中打开
  static bool _isFolderRecentlyOpened(String path) {
    final normalizedPath = path.toLowerCase();
    final currentTime = DateTime.now();

    if (_recentlyOpenedPaths.containsKey(normalizedPath)) {
      final lastOpened = _recentlyOpenedPaths[normalizedPath]!;
      if (currentTime.difference(lastOpened) < _cacheDuration) {
        return true; // Folder was opened recently
      } else {
        // Remove expired entry
        _recentlyOpenedPaths.remove(normalizedPath);
      }
    }
    return false;
  }

  ///打开对应路径文件夹
  static Future<void> openFolder(String path) async {
    //todo win32接口防止重复打开文件夹
    final dir = Directory(path);

    if (!(await dir.exists())) {
      throw Exception("路径不存在：\\$path");
    }

    try {
      if (Platform.isWindows) {
        if (_isFolderRecentlyOpened(path)) {
          print("文件夹最近已打开：\\$path");
          return;
        }
        
        await _runWinExplorer(["/open,", dir.path]);

        _recentlyOpenedPaths[path.toLowerCase()] = DateTime.now();
      }
    } catch (e) {
      rethrow;
    }
  }

  ///定位对应路径文件夹
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