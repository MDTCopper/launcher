import 'dart:io';

import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/windows_registry.dart';
import 'package:path/path.dart' as p;

/// 一份检测到的 **Steam 版** Mindustry 安装
///
/// 形态与「下载一份 jar」不同：本体在 `jre/desktop.jar`、自带一份 JRE、
/// 数据目录是安装目录下的 `saves/`（不是 `%APPDATA%\Mindustry`）
class SteamInstall {
  const SteamInstall({
    required this.installPath,
    required this.jarPath,
    required this.dataPath,
    this.libraryPath,
    this.javaPath,
    this.versionNumber,
    this.build,
    this.isBe = false,
  });

  /// Steam 库根（`.../steamapps` 的父目录）；手工指定目录时为 null
  final String? libraryPath;

  /// 安装目录（`.../steamapps/common/Mindustry`）
  final String installPath;

  /// 本体 jar：`<安装目录>/jre/desktop.jar`
  final String jarPath;

  /// Steam 版的数据目录：`<安装目录>/saves`（**注意不是** `%APPDATA%\Mindustry`）
  final String dataPath;

  /// Steam 自带的 JRE（`<安装目录>/jre/bin/java[.exe]`），没有则为 null
  final String? javaPath;

  /// 大版本号（`version.properties` 的 `number`，如 `8`）
  final int? versionNumber;

  /// 构建号（如 `157.4`）
  final String? build;

  final bool isBe;

  /// 版本显示形态：`v157.4` / `Build 26398`
  String get release => isBe ? 'Build ${build ?? '?'}' : 'v${build ?? '?'}';
}

/// Steam 版 Mindustry 的探测（桌面端）
///
/// 路径来源都是官方的：Windows 读注册表 `HKCU\Software\Valve\Steam` 的 `SteamPath`，
/// 各库根从 `<Steam>/steamapps/libraryfolders.vdf` 里解析（新老两种写法都认）；
/// Linux 试几个常见位置。找到库根后再看 `appmanifest_1127400.acf` 记的 `installdir`
/// （Steam 允许改名），最后 [inspect] 认一认是不是真的 Steam 版（`modifier=steam`）。
class SteamLibrary {
  SteamLibrary._();

  /// Steam 上的 Mindustry appid
  static const appId = '1127400';

  /// appmanifest 读不出时的兜底目录名
  static const defaultInstallFolder = 'Mindustry';

  /// Steam 版数据目录在安装目录里的名字
  static const dataFolderName = 'saves';

  /// 本体 jar 的候选位置（Steam 版是 `jre/desktop.jar`，别的形态也认一认）
  static const jarCandidates = [
    'jre/desktop.jar',
    'desktop.jar',
    'Mindustry.jar',
  ];

  /// 起 Steam 版本体时要给子进程带的环境变量
  ///
  /// 不带的话，只要 Steam 客户端在跑，`SteamAPI_RestartAppIfNecessary` 就返回 true、
  /// 游戏会请 Steam 重新拉起自己然后立刻退出（详见 `pitfalls.md`）
  static Map<String, String> launchEnvironment() => const {
    'SteamAppId': appId,
    'SteamGameId': appId,
  };

  static const _steamSubKey = r'Software\Valve\Steam';
  static const _steamInstallSubKey = r'SOFTWARE\Valve\Steam';

  /// Steam 根目录；找不到返回 null
  static String? steamRoot() {
    if (Platform.isWindows) {
      final path = WindowsRegistry.readCurrentUser(
        subKey: _steamSubKey,
        valueName: 'SteamPath',
      );
      if (path != null && path.trim().isNotEmpty) {
        return p.normalize(path.trim());
      }
      final install = WindowsRegistry.readLocalMachine(
        subKey: _steamInstallSubKey,
        valueName: 'InstallPath',
        wow64: true,
      );
      if (install != null && install.trim().isNotEmpty) {
        return p.normalize(install.trim());
      }
      return null;
    }

    final home = Platform.environment['HOME'];
    if (home == null) return null;
    for (final relative in const [
      '.steam/steam',
      '.steam/root',
      '.local/share/Steam',
      'Library/Application Support/Steam',
    ]) {
      final candidate = p.joinAll([home, ...relative.split('/')]);
      if (Directory(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// 所有 Steam 库根（Steam 自己那份 + `libraryfolders.vdf` 里记的其它盘）
  static List<String> libraryRoots({String? root}) {
    final steam = root ?? steamRoot();
    final roots = <String>[];
    void add(String? path) {
      if (path == null || path.trim().isEmpty) return;
      final normalized = p.normalize(path.trim());
      if (!roots.any(
        (existing) => existing.toLowerCase() == normalized.toLowerCase(),
      )) {
        roots.add(normalized);
      }
    }

    add(steam);
    if (steam == null) return roots;

    final vdf = File(p.join(steam, 'steamapps', 'libraryfolders.vdf'));
    if (!vdf.existsSync()) return roots;
    try {
      add(steam);
      for (final path in parseLibraryFolders(vdf.readAsStringSync())) {
        add(path);
      }
    } catch (error) {
      addLog(.warning, '读 Steam 库列表失败：$error', tag: 'Steam');
    }
    return roots;
  }

  /// 解析 `libraryfolders.vdf` 里的库路径（纯函数，方便用例直接喂字符串）
  ///
  /// 两种写法都要认：
  /// - 新：`"0" { "path" "E:\\SteamLibrary" ... }`
  /// - 老：`"1" "E:\\SteamLibrary"`
  static List<String> parseLibraryFolders(String content) {
    final paths = <String>[];

    void add(String raw) {
      final path = unescapeVdf(raw);
      if (path.isEmpty) return;
      // 老的写法里数字键的值也是路径，用「像不像路径」兜一道
      if (!path.contains(':') && !path.contains('/') && !path.contains('\\')) {
        return;
      }
      if (!paths.contains(path)) paths.add(path);
    }

    for (final match in RegExp(
      r'"path"\s*"((?:[^"\\]|\\.)*)"',
      caseSensitive: false,
    ).allMatches(content)) {
      add(match.group(1)!);
    }
    for (final match in RegExp(
      r'"\d+"\s*"((?:[^"\\]|\\.)*)"',
    ).allMatches(content)) {
      add(match.group(1)!);
    }
    return paths;
  }

  /// VDF 里的转义：`\\` → `\`、`\"` → `"`
  static String unescapeVdf(String value) =>
      value.replaceAll(r'\\', r'\').replaceAll(r'\"', '"').trim();

  /// 扫一遍所有 Steam 库，列出装着的 Steam 版 Mindustry
  static Future<List<SteamInstall>> detect({String? root}) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return const [];
    }

    final installs = <SteamInstall>[];
    final seen = <String>{};
    for (final library in libraryRoots(root: root)) {
      final steamApps = Directory(p.join(library, 'steamapps'));
      if (!steamApps.existsSync()) continue;

      final folder =
          _installFolderFromManifest(steamApps.path) ?? defaultInstallFolder;
      final installPath = p.join(steamApps.path, 'common', folder);
      if (!Directory(installPath).existsSync()) continue;
      if (!seen.add(p.normalize(installPath).toLowerCase())) continue;

      final install = await inspect(installPath, libraryPath: library);
      if (install != null) installs.add(install);
    }
    return installs;
  }

  /// 认一个目录是不是 Steam 版 Mindustry：是就返回信息，不是返回 null
  ///
  /// 判据是本体 jar 里 `version.properties` 的 `modifier=steam` —— 下载来的官方 jar
  /// 是 `official`、BE 是 `bleeding-edge`，所以不会把普通版本误判成 Steam 版
  static Future<SteamInstall?> inspect(
    String installPath, {
    String? libraryPath,
  }) async {
    for (final relative in jarCandidates) {
      final jar = File(p.joinAll([installPath, ...relative.split('/')]));
      if (!jar.existsSync()) continue;

      try {
        final reader = await FileReader.fromPath(jar.path);
        if (reader.type != ResourceType.mindustry) continue;
        final meta = reader.mindustry;
        if (meta == null || meta.type != 'steam') continue;

        return SteamInstall(
          libraryPath: libraryPath,
          installPath: p.normalize(installPath),
          jarPath: jar.path,
          dataPath: p.join(p.normalize(installPath), dataFolderName),
          javaPath: _steamJava(installPath),
          versionNumber: int.tryParse(meta.version.trim()),
          build: meta.build.trim(),
          isBe: false,
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// `<安装目录>/jre/bin/java[.exe]`，没有返回 null
  static String? _steamJava(String installPath) {
    final name = Platform.isWindows ? 'java.exe' : 'java';
    final java = p.join(installPath, 'jre', 'bin', name);
    return File(java).existsSync() ? java : null;
  }

  /// 从 `appmanifest_1127400.acf` 里读 `installdir`
  static String? _installFolderFromManifest(String steamAppsPath) {
    final manifest = File(p.join(steamAppsPath, 'appmanifest_$appId.acf'));
    if (!manifest.existsSync()) return null;
    try {
      final match = RegExp(
        r'"installdir"\s*"((?:[^"\\]|\\.)*)"',
        caseSensitive: false,
      ).firstMatch(manifest.readAsStringSync());
      final folder = match == null ? null : unescapeVdf(match.group(1)!);
      return (folder == null || folder.isEmpty) ? null : folder;
    } catch (error) {
      addLog(.warning, '读 Steam appmanifest 失败：$error', tag: 'Steam');
      return null;
    }
  }
}
