import 'dart:io';

import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class AppPaths {
  static late String applicationSupportPath;

  /// 数据根目录：桌面端优先用 exe 所在目录（绿色版，配置跟着 exe 走），
  /// debug 产物回项目根、系统目录或 exe 目录不可写时退回 [applicationSupportPath]；
  /// 未 [init] 时为 null（测试环境按工作目录算）
  static String? _copperLauncher;

  static String? _defaultGameDataPath;

  /// 是否没有把数据放在 exe 旁边（系统目录 / exe 目录不可写，回退了应用支持目录）
  static bool get isUsingFallbackDataPath =>
      _copperLauncher != null && _copperLauncher == applicationSupportPath;

  static Future<void> init() async {
    final appSupportDir = await getApplicationSupportDirectory();
    applicationSupportPath = appSupportDir.path;
    _copperLauncher = await _resolveCopperLauncherPath();
    await initDefaultDataPath();
  }

  /// 决定数据根目录
  ///
  /// 以 **exe 所在目录**为锚，而不是工作目录：`p.current` 是进程工作目录，
  /// 管理员启动时 UAC 会把它设成 C:\Windows\System32（对管理员可写），
  /// 数据就会写进系统目录；快捷方式"起始位置"不同也会让数据目录漂移。
  ///
  /// - exe 在系统目录（Program Files / Windows）下 → 用 [applicationSupportPath]，
  ///   那里的可写性随提权变化，不能当稳定依据
  /// - exe 是 Flutter 项目里的 debug 产物（向上能找到 pubspec.yaml）→ 用项目根，
  ///   这样 flutter clean 删掉 build/ 也不影响数据
  /// - 其余（绿色版装在普通目录）→ 跟着 exe 走；目录不可写（只读盘等）时
  ///   仍退回 [applicationSupportPath]，避免双击后进程秒退
  static Future<String> _resolveCopperLauncherPath() async {
    if (Platform.isAndroid || !isDesktop) return applicationSupportPath;

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (isProtectedDir(exeDir)) return applicationSupportPath;

    final projectRoot = await findProjectRoot(exeDir);
    if (projectRoot != null) return projectRoot;

    if (await _isWritable(exeDir)) return exeDir;

    debugPrint('数据目录不可写[$exeDir]，改用[$applicationSupportPath]');
    return applicationSupportPath;
  }

  /// 判断 [dir] 是否在系统受保护目录（Program Files / Windows）之下
  ///
  /// 受保护目录的可写性随提权变化，不能作为数据目录的稳定依据
  @visibleForTesting
  static bool isProtectedDir(String dir) {
    final normalized = _normalizeDir(dir);
    const protectedRootEnvNames = [
      'ProgramFiles',
      'ProgramFiles(x86)',
      'ProgramW6432',
      'WinDir',
    ];
    for (final name in protectedRootEnvNames) {
      final root = Platform.environment[name];
      if (root == null || root.isEmpty) continue;
      if (normalized.startsWith(_normalizeDir(root))) return true;
    }
    return false;
  }

  /// 从 [startDir] 一路向上找含 pubspec.yaml 的目录（Flutter 项目根）
  @visibleForTesting
  static Future<String?> findProjectRoot(String startDir) async {
    var dir = p.normalize(startDir);
    while (true) {
      if (await File(p.join(dir, 'pubspec.yaml')).exists()) return dir;
      final parent = p.dirname(dir);
      if (parent == dir) return null;
      dir = parent;
    }
  }

  static String _normalizeDir(String dir) =>
      '${p.normalize(dir).toLowerCase()}\\';

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
