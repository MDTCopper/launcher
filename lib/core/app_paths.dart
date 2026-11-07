import 'dart:io';

import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 启动器的路径表
///
/// 所有路径都**只赋值一次**：[init] / [overrideForTesting] 走 [_applyDataRoot]，
/// 其余地方只读。未 [init] 就访问会在那处抛 `LateInitializationError`，
/// 用例记得先 `AppPaths.overrideForTesting(临时目录)`。
///
abstract class AppPaths {
  // ---------------------------------------------------------------------------
  // 路径
  // ---------------------------------------------------------------------------

  /// 数据根：桌面端跟着 exe（绿色版）、checkout 内是 `<仓库>/data`、受限环境回退应用支持目录；
  /// Android 是外部应用专属目录
  /// 例：`D:\Games\Copper`、`<仓库>\data`、`C:\Users\<用户>\AppData\Roaming\io.github.copper\Copper`
  static late String copperLauncher;

  /// 应用内部目录（path_provider 的应用支持目录）：Android 桥载荷住这儿、桌面端当回退位置
  /// 例：`C:\Users\<用户>\AppData\Roaming\io.github.copper\Copper`、`/data/user/0/io.github.copper/files`
  static String get applicationSupportPath => _applicationSupportPath!;

  /// 应用内部目录的别名：Android 上桥载荷住这儿，将来做旧数据迁移也靠它找
  /// 例：同 [applicationSupportPath]
  static String get internalRoot => applicationSupportPath;

  /// Android 的外部应用专属目录；桌面端、或拿不到外部目录时是 null
  /// 例：`/storage/emulated/0/Android/data/io.github.copper/files`
  static String? get androidExternalRoot => _androidExternalRoot;

  /// 默认版本文件夹：每个版本一个子目录，里面放该版本的数据
  /// 例：`<数据根>\versions\v160.7\data`
  static late String versions;

  /// 默认版本文件夹（移动端专用）：版本记录在这里另存一份，不和数据根下的 versions 混
  /// 例：`<数据根>\versionsFolds`
  static late String versionsFolds;

  /// 玩家给版本换的图标
  /// 例：`<数据根>\version_icons\f7078a96-d701-4593-a7b9-17d5946773ea.jpg`
  static late String versionIcons;

  /// 游戏本体库：下载 / 导入的 jar 集中放这里，变体共用同一份
  /// 例：`<数据根>\mindustrys\mindustry-v160.7-314baa30.jar`
  static late String mindustrys;

  /// 模组加载器库：loader jar 集中放这里，多版本复用同一份
  /// 例：`<数据根>\copper_loader\desktop-0.2.0.jar`
  static late String copperLoader;

  /// 日志目录：每次启动一个文件
  /// 例：`<数据根>\logs\11-01T10-44-36.919.log`
  static late String logs;

  /// 启动器管理的 JDK 安装目录
  /// 例：`<数据根>\java\jdk-17\jdk-17.0.20.1+1\bin\java.exe`
  static late String java;

  /// 远程数据源缓存（`remote/` 的本地副本：启动拉取覆盖，离线用缓存 / 内置 assets 兜底）
  /// 例：`<数据根>\remote_data\mindustry_versions.json`
  static late String remoteData;

  /// 公共数据索引缓存（模组索引 / 每个模组的版本 / 游戏版本列表，按远端相对路径存）
  /// 例：`<数据根>\remote_data\data_index\index.json`
  static late String dataIndexCache;

  /// 启动器配置（人可读的 JSON）
  /// 例：`<数据根>\config.json`
  static late String configJson;

  /// 启动器配置（二进制缓存）
  /// 例：`<数据根>\config.bin`
  static late String configBin;

  /// 云存档后台服务的数据：服务 pid、会话、待处理请求
  /// 例：`<数据根>\cloud-service\service.json`
  static late String cloudService;

  /// 云存档后台服务的会话目录
  /// 例：`<数据根>\cloud-service\sessions`
  static late String cloudServiceSessions;

  /// 云存档后台服务的待处理请求目录
  /// 例：`<数据根>\cloud-service\pending`
  static late String cloudServicePending;

  /// 云存档后台服务的请求目录
  /// 例：`<数据根>\cloud-service\requests`
  static late String cloudServiceRequests;

  /// 桥载荷的根：Android 固定在应用内部目录（exec / dlopen 只允许内部目录），桌面端跟着数据根
  /// 例：`/data/user/0/io.github.copper/files`
  static late String bridgeRoot;

  /// 桥的共享库（JRE / arc 原生库 / bridge.jar），多版本共用
  /// 例：`<桥载荷根>\bridge\bridge-snapshot.jar`
  static late String bridge;

  /// 桥用的 Android JRE 根：`--java` 传它下面的 `bin/java`
  /// 例：`<桥载荷根>\bridge\jre\bin\java`
  static late String bridgeJre;

  /// 桌面快捷方式用的 .ico 缓存
  ///
  /// 放应用支持目录而不是数据根：数据根在调试 / 便携 / 受限环境里可能带低完整性标签或受限 ACL，
  /// Explorer 会拒绝从那里加载 `.lnk` 图标（实测白纸图标）
  /// 例：`C:\Users\<用户>\AppData\Roaming\io.github.copper\Copper\shortcut_icons\f7078a96-….ico`
  static late String shortcutIcons;

  /// 游戏默认数据目录（Windows 是 `%APPDATA%\Mindustry`）
  /// 例：`C:\Users\<用户>\AppData\Roaming\Mindustry`
  static String? get defaultGameData => _defaultGameDataPath;

  /// 游戏默认模组目录
  /// 例：`C:\Users\<用户>\AppData\Roaming\Mindustry\mods`
  static String? get defaultMods =>
      defaultGameData == null ? null : p.join(defaultGameData!, 'mods');

  // ---------------------------------------------------------------------------
  // 解析与赋值
  // ---------------------------------------------------------------------------

  /// 应用支持目录的真实值：可空，供 [_applyDataRoot] 判断「有没有算过」
  static String? _applicationSupportPath;

  /// Android 的外部应用专属目录（`/sdcard/Android/data/<包名>/files`）；
  /// 拿不到时为 null，数据根退回 [applicationSupportPath]
  static String? _androidExternalRoot;

  static String? _defaultGameDataPath;

  /// [init] 跑过没有；[isUsingFallbackDataPath] 靠它区分「真的回退了」与「还没算」
  static bool _initialized = false;

  /// 在 checkout 里跑时的数据根子目录名：运行时数据集中放这儿，不散落在仓库根
  static const String _devDataDirName = 'data';

  /// 是否没有把数据放在 exe 旁边（系统目录 / exe 目录不可写，回退了应用支持目录）
  static bool get isUsingFallbackDataPath =>
      _initialized && copperLauncher == applicationSupportPath;

  static Future<void> init() async {
    _applicationSupportPath = (await getApplicationSupportDirectory()).path;
    _androidExternalRoot = await _resolveAndroidExternalRoot();
    _applyDataRoot(await _resolveCopperLauncherPath());
    _initialized = true;
    await initDefaultDataPath();
  }

  /// 用例把数据根指到临时目录；传 null 恢复默认（工作目录）
  ///
  /// `init()` 要平台插件（`flutter test` 里没有），而没 init 时数据根是工作目录
  /// （仓库根）—— 直接跑 `initAppConfig()` 之类会动到真实配置，所以留这个口子；
  /// 从数据根派生的那些路径也在这里一起重算
  @visibleForTesting
  static void overrideForTesting(String? rootPath) {
    _applyDataRoot(rootPath ?? p.current);
    _initialized = false;
  }

  /// 数据根定下来之后，把路径表一次填好：[init] 与 [overrideForTesting] 都只走这里
  static void _applyDataRoot(String rootPath) {
    copperLauncher = rootPath;
    final appSupportPath = _applicationSupportPath;
    if (appSupportPath != null) {
      shortcutIcons = p.join(appSupportPath, 'shortcut_icons');
    }
    versions = p.join(rootPath, 'versions');
    versionsFolds = isDesktop ? versions : p.join(rootPath, 'versionsFolds');
    versionIcons = p.join(rootPath, 'version_icons');
    mindustrys = p.join(rootPath, 'mindustrys');
    copperLoader = p.join(rootPath, 'copper_loader');
    logs = p.join(rootPath, 'logs');
    java = p.join(rootPath, 'java');
    remoteData = p.join(rootPath, 'remote_data');
    dataIndexCache = p.join(remoteData, 'data_index');
    configJson = p.join(rootPath, 'config.json');
    configBin = p.join(rootPath, 'config.bin');
    cloudService = p.join(rootPath, 'cloud-service');
    cloudServiceSessions = p.join(cloudService, 'sessions');
    cloudServicePending = p.join(cloudService, 'pending');
    cloudServiceRequests = p.join(cloudService, 'requests');
    // 桥载荷在 Android 上固定在应用内部目录，桌面端仍跟着数据根
    bridgeRoot = Platform.isAndroid ? internalRoot : rootPath;
    bridge = p.join(bridgeRoot, 'bridge');
    bridgeJre = p.join(bridge, 'jre');
  }

  /// 决定数据根目录
  ///
  /// 以 **exe 所在目录**为锚，而不是工作目录：`p.current` 是进程工作目录，
  /// UAC 提权会把它设成 System32，快捷方式"起始位置"不同也会让数据目录漂移；
  ///
  /// - exe 在系统目录（Program Files / Windows）下 → 用 [applicationSupportPath]，
  ///   那里的可写性随提权变化，不能当稳定依据
  /// - exe 是 Flutter 项目里的产物（向上能找到 pubspec.yaml）→ 用项目根下的
  ///   [_devDataDirName]，这样 flutter clean 删掉 build/ 也不影响数据，
  ///   仓库根也不会被版本 / 本体 / 日志这些运行时数据堆满
  /// - 其余（绿色版装在普通目录）→ 跟着 exe 走；目录不可写（只读盘等）时
  ///   仍退回 [applicationSupportPath]，避免双击后进程秒退
  static Future<String> _resolveCopperLauncherPath() async {
    if (Platform.isAndroid) {
      return _androidExternalRoot ?? applicationSupportPath;
    }
    if (!isDesktop) return applicationSupportPath;

    final exeDirPath = File(Platform.resolvedExecutable).parent.path;
    if (isProtectedDir(exeDirPath)) return applicationSupportPath;

    final projectRoot = await findProjectRoot(exeDirPath);
    if (projectRoot != null) {
      // 目录可能还不存在，先建出来；建不出来只记一行
      final dataRootPath = p.join(projectRoot, _devDataDirName);
      try {
        await Directory(dataRootPath).create(recursive: true);
      } on FileSystemException catch (error) {
        debugPrint('数据根目录建不出来[$dataRootPath]：$error');
      }
      return dataRootPath;
    }

    if (await _isWritable(exeDirPath)) return exeDirPath;

    debugPrint('数据目录不可写[$exeDirPath]，改用[$applicationSupportPath]');
    return applicationSupportPath;
  }

  /// Android 的外部应用专属目录 `/sdcard/Android/data/<包名>/files`
  ///
  /// 只放**要交给用户的东西**（配置 / 版本 / 存档 / 日志）—— 插上数据线或用文件管理器
  /// 就能取，且这个位置不需要任何存储权限；桥载荷不放这儿，见 [bridge]
  static Future<String?> _resolveAndroidExternalRoot() async {
    if (!Platform.isAndroid) return null;
    try {
      return (await getExternalStorageDirectory())?.path;
    } on Object catch (error) {
      debugPrint('拿不到 Android 外部应用目录，数据根留在应用内部：$error');
      return null;
    }
  }

  /// 判断 [dirPath] 是否在系统受保护目录（Program Files / Windows）之下
  ///
  /// 受保护目录的可写性随提权变化，不能作为数据目录的稳定依据
  @visibleForTesting
  static bool isProtectedDir(String dirPath) {
    final normalizedPath = _normalizeDirPath(dirPath);
    const protectedRootEnvNames = [
      'ProgramFiles',
      'ProgramFiles(x86)',
      'ProgramW6432',
      'WinDir',
    ];
    for (final name in protectedRootEnvNames) {
      final rootPath = Platform.environment[name];
      if (rootPath == null || rootPath.isEmpty) continue;
      if (normalizedPath.startsWith(_normalizeDirPath(rootPath))) return true;
    }
    return false;
  }

  /// 从 [startDirPath] 一路向上找含 pubspec.yaml 的目录（Flutter 项目根）
  @visibleForTesting
  static Future<String?> findProjectRoot(String startDirPath) async {
    var dirPath = p.normalize(startDirPath);
    while (true) {
      if (await File(p.join(dirPath, 'pubspec.yaml')).exists()) return dirPath;
      final parentPath = p.dirname(dirPath);
      if (parentPath == dirPath) return null;
      dirPath = parentPath;
    }
  }

  static String _normalizeDirPath(String dirPath) =>
      '${p.normalize(dirPath).toLowerCase()}\\';

  /// 目录可写性靠直接写一个探针文件再删掉来判，比看权限位可靠
  static Future<bool> _isWritable(String dirPath) async {
    final probeFile = File(p.join(dirPath, '.copper_write_probe'));
    try {
      await probeFile.writeAsString('probe', flush: true);
      await probeFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> initDefaultDataPath() async {
    if (Platform.isWindows) {
      final roamingPath = Platform.environment['APPDATA'];
      if (roamingPath != null) {
        _defaultGameDataPath = p.join(roamingPath, 'Mindustry');
      }
    } else if (Platform.isAndroid) {
      _defaultGameDataPath = p.join(copperLauncher, '.mindustry');
    } else if (Platform.isLinux) {
      final homePath = Platform.environment['HOME'];
      if (homePath != null) {
        _defaultGameDataPath = p.join(homePath, '.local', 'share', 'Mindustry');
      }
    }
    if (_defaultGameDataPath == null) throw ('无法获取默认游戏数据存储位置');
  }

  // ---------------------------------------------------------------------------
  // 桥载荷里的具体文件 / 目录
  // ---------------------------------------------------------------------------

  /// 桥自己的 jar [*\bridge\<文件名>\]：`bridge-<版本>.jar` / `bridge-snapshot.jar` 可共存
  /// 例：`<桥载荷根>\bridge\bridge-0.2.0.jar`
  static String bridgeJarFile(String fileName) => p.join(bridge, fileName);

  /// arc 原生库目录 [*\bridge\arc\<arcRef>\<abi>\]：必须按 arc ref 分（不同游戏版本
  /// 可能用不同 arc），按 ABI 分目录（平铺布局只能放一个 ABI 的库）
  /// 例：`<桥载荷根>\bridge\arc\93033a05\arm64-v8a`
  static String bridgeArcDirPath(String arcRef, String abi) =>
      p.join(bridge, 'arc', arcRef, abi);

  // ---------------------------------------------------------------------------
  // 记录形态 ↔ 绝对路径
  // ---------------------------------------------------------------------------

  /// 把绝对路径转成**记录形态**：落在数据根里的记相对路径（数据根搬家 / 换盘后
  /// 配置仍然可用），数据根之外的用户文件（「添加目录」扫来的本体）保持绝对路径
  static String toStoredPath(String path) {
    final rootPath = p.normalize(copperLauncher);
    final normalizedPath = p.normalize(path);
    if (!_isInside(rootPath, normalizedPath)) return normalizedPath;
    return p.relative(normalizedPath, from: rootPath);
  }

  /// 把记录形态还原成可用路径：绝对路径（含老配置）原样返回，相对路径按数据根拼回
  static String resolveStoredPath(String storedPath) {
    if (p.isAbsolute(storedPath)) return p.normalize(storedPath);
    return p.normalize(p.join(copperLauncher, storedPath));
  }

  /// [childPath] 是否落在 [rootPath] **里面**（Windows 路径大小写不敏感，统一小写后再比）；
  /// 根目录自身不算「根内文件」—— 那样会算出空字符串
  static bool _isInside(String rootPath, String childPath) {
    final rootLower = p.normalize(rootPath).toLowerCase();
    final childLower = p.normalize(childPath).toLowerCase();
    return p.isWithin(rootLower, childLower);
  }
}
