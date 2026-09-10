import 'dart:io';

import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class AppPaths {
  static late String applicationSupportPath;

  /// 数据根目录：桌面端优先用可执行文件所在目录（绿色版，配置跟着 exe 走），
  /// 不可写时退回 [applicationSupportPath]；未 [init] 时为 null（测试环境按工作目录算）
  static String? _copperLauncher;

  static String? _defaultGameDataPath;

  /// 是否退回了应用支持目录（装到 Program Files 这类只读位置时为 true）
  static bool get isUsingFallbackDataPath =>
      _copperLauncher != null && _copperLauncher != p.current;

  static Future<void> init() async {
    final appSupportDir = await getApplicationSupportDirectory();
    applicationSupportPath = appSupportDir.path;
    _copperLauncher = await _resolveCopperLauncherPath();
    await initDefaultDataPath();
  }

  /// 决定数据根目录
  ///
  /// 装到 Program Files 且非管理员运行时，exe 目录写不进去，
  /// 日志 / 配置 / 远程数据缓存都会失败（表现为双击后进程秒退），
  /// 所以这里实测一次可写性，不可写就整体改用 %APPDATA%
  static Future<String> _resolveCopperLauncherPath() async {
    if (Platform.isAndroid || !isDesktop) return applicationSupportPath;

    final workingDir = p.current;
    if (await _isWritable(workingDir)) return workingDir;

    debugPrint('数据目录不可写[$workingDir]，改用[$applicationSupportPath]');
    return applicationSupportPath;
  }

  /// 实测目录可写性：直接写一个探针文件再删掉，比看权限位可靠
  static Future<bool> _isWritable(String dir) async {
    final probe = File(p.join(dir, '.copper_write_probe'));
    try {
      await probe.writeAsString('probe', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
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

  /// 桌面端为 exe 所在目录（可写时）或应用支持目录，见 [_resolveCopperLauncherPath]
  ///
  /// android为工作目录
  static String get copperLauncher {
    if (Platform.isAndroid) return applicationSupportPath;
    return _copperLauncher ?? p.current;
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

  /// [*\java\]，启动器管理的 JDK 安装目录
  static String get java => p.join(copperLauncher, 'java');

  /// 远程数据源缓存（remote/ 的本地副本：启动拉取覆盖，离线用缓存/内置 assets 兜底）
  static String get remoteData => p.join(copperLauncher, 'remote_data');

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
