import 'dart:io';

import 'package:copper_launcher/util/io/log.dart';
import 'package:file_selector/file_selector.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_paths.dart';
import 'explorer_helper.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';

class PathSelector {
  ///打开对应路径文件夹
  static Future<void> openFolder(String path) async {
    final dir = Directory(path);
    if (!(await dir.exists())) {
      throw Exception("路径不存在：\\$path");
    }

    try {
      if (Platform.isWindows) {
        ExplorerHelper.openExplorer(dir.path);
      } else if (Platform.isMacOS) {
        await Process.run('open', [dir.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir.path]);
      }
    } catch (e) {
      addLogAndPrint(
        .warning,
        '打开文件夹失败[$path]：${removeNewlines('$e')}',
        tag: 'Path',
      );
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
        ExplorerHelper.locateFile(dir.path);
      } else if (Platform.isMacOS) {
        // -R 在 Finder 中显示并选中
        await Process.run('open', ['-R', dir.path]);
      } else if (Platform.isLinux) {
        await _locateFileOnLinux(path);
      } else if (Platform.isAndroid) {
        _locateFileOnAndroid(path);
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Linux 下在文件管理器中定位文件
  ///
  /// 优先走 freedesktop 标准 DBus 接口 `org.freedesktop.FileManager1.ShowItems`
  /// （Nautilus / Dolphin / Thunar 等主流 FM 都注册了这个接口），
  /// 失败则退化为 `xdg-open` 打开父目录
  static Future<void> _locateFileOnLinux(String path) async {
    final absPath = Uri.file(path).toString();
    try {
      final result = await Process.run('dbus-send', [
        '--session',
        '--dest=org.freedesktop.FileManager1',
        '--type=method_call',
        '/org/freedesktop/FileManager1',
        'org.freedesktop.FileManager1.ShowItems',
        'array:string:$absPath',
        'string:',
      ]);
      if (result.exitCode == 0) return;
    } catch (_) {
      // dbus-send 不存在 / FM 未注册接口：退化为打开父目录
    }
    final parent = Directory(path).parent.path;
    await Process.run('xdg-open', [parent]);
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

  ///多选文件（批量导入等多种资源时使用）
  static Future<List<String>> selectFiles({
    String? initialDirectory,
    String? confirmButtonText,
    List<XTypeGroup> acceptedTypeGroups = const <XTypeGroup>[],
  }) async {
    initialDirectory ??= AppPaths.copperLauncher;
    final files = await openFiles(
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
      acceptedTypeGroups: acceptedTypeGroups,
    );
    return files.map((file) => file.path).toList();
  }

  static Future<void> _locateFileOnAndroid(String path) async {
    // 申请存储权限（公共存储路径需要；应用私有目录无需）
    final bool hasPermission = await _requestAndroidFilePermission(
      path,
    ); //私有目录直接通过
    if (!hasPermission) {
      throw Exception('暂时不支持文件定位');
    }

    final File file = File(path);
    final String folderPath = file.parent.path;

    try {
      final result = await OpenFilex.open(path, type: "file");

      if (result.type != ResultType.done) {
        //兜底
        await OpenFilex.open(folderPath, type: "folder");
        addLogAndPrint(.warning, "Android 文件管理器不支持定位，已打开所在文件夹：$folderPath", tag: 'Path');
      }
    } catch (e) {
      // 最终兜底：打开文件夹
      await OpenFilex.open(folderPath, type: "folder");
      addLogAndPrint(.warning, "Android 文件定位异常，已打开所在文件夹：${removeNewlines('$e')}", tag: 'Path');
    }
  }

  /// 申请安卓存储权限
  ///
  /// 应用私有目录（[AppPaths.applicationSupportPath]）内的路径经 OpenFilex /
  /// FileProvider 即可打开，无需任何存储权限，直接放行；
  /// 公共存储路径按版本申请：Android 11+ 用 所有文件访问
  /// （MANAGE_EXTERNAL_STORAGE，跳系统设置），更旧的版本降级用传统
  /// 存储权限（READ / WRITE_EXTERNAL_STORAGE，maxSdk 32）
  static Future<bool> _requestAndroidFilePermission(String path) async {
    // 私有目录无需权限（避免 Android 13+ 传统存储权限已失效却仍弹申请）
    final prefix = AppPaths.applicationSupportPath;
    if (path == prefix || path.startsWith('$prefix${Platform.pathSeparator}')) {
      return true;
    }

    var granted = await Permission.manageExternalStorage.isGranted;
    if (!granted) {
      granted =
          await Permission.manageExternalStorage.request() ==
          PermissionStatus.granted;
    }
    // 旧版本不支持 MANAGE_EXTERNAL_STORAGE（request 会直接 denied），降级传统权限
    if (!granted) {
      granted =
          await Permission.storage.isGranted ||
          await Permission.storage.request() == PermissionStatus.granted;
    }
    return granted;
  }
}
