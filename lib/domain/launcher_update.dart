import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/app_constant.dart';
import '../util/app_paths.dart';
import '../util/format/string_cleaner.dart';
import '../util/io/copper_io.dart';
import '../util/io/log.dart';
import '../util/version_filter.dart';

/// 发布通道：正式版没有尾缀，内测 / 公测接 build number（`tool/build_release.dart` 定的）
enum LauncherChannel {
  release('正式版', 2),
  beta('公测版', 1),
  alpha('内测版', 0);

  const LauncherChannel(this.label, this.rank);

  final String label;

  /// 同一个版本号下的比较优先级：正式 > 公测 > 内测
  final int rank;

  static LauncherChannel fromSuffix(String suffix) => switch (suffix) {
    'alpha' => LauncherChannel.alpha,
    'beta' => LauncherChannel.beta,
    _ => LauncherChannel.release,
  };
}

/// 启动器版本的可比较形态：release tag 与本地显示版本号都解析成它
class LauncherVersion implements Comparable<LauncherVersion> {
  const LauncherVersion({
    required this.number,
    required this.channel,
    this.build,
  });

  /// 形如 `0.0.1` 的版本号
  final SemVer number;

  final LauncherChannel channel;

  /// 内测 / 公测的 build number；正式版不带
  final int? build;

  @override
  int compareTo(LauncherVersion other) {
    final byNumber = number.compareTo(other.number);
    if (byNumber != 0) return byNumber;

    final byChannel = channel.rank.compareTo(other.channel.rank);
    if (byChannel != 0) return byChannel;

    // 正式版不带 build number：同版本号就是同一版
    if (channel == LauncherChannel.release) return 0;
    return (build ?? 0).compareTo(other.build ?? 0);
  }

  /// tag 形态（`v0.0.1-alpha5` / `v0.0.2`）：与 release tag、产物名同一套写法，
  /// 传给更新引导脚本的版本号也用这个形态
  String get tag => build == null ? 'v$number' : 'v$number-${channel.name}$build';

  @override
  String toString() =>
      build == null ? 'v$number' : 'v$number ${channel.name}$build';
}

/// 解析 release tag：`v0.0.1-alpha5`（内测 5）、`v0.0.2`（正式版）
LauncherVersion? parseLauncherTag(String tag) {
  final matched = RegExp(
    r'^v(\d+(?:\.\d+)*)(?:-(alpha|beta)(\d+))?$',
  ).firstMatch(tag.trim());
  if (matched == null) return null;

  final number = SemVer.tryParse(matched.group(1));
  if (number == null) return null;

  final suffix = matched.group(2);
  final buildText = matched.group(3);
  return LauncherVersion(
    number: number,
    channel: suffix == null
        ? LauncherChannel.release
        : LauncherChannel.fromSuffix(suffix),
    build: buildText == null ? null : int.tryParse(buildText),
  );
}

/// 解析本地版本：[displayVersion] 形如 `v0.0.1 alpha 5`，正式版就是 `v0.0.2`；
/// [buildNumber] 是同一份版本信息里的 build number（正式版用不上）
LauncherVersion? parseLocalVersion(String displayVersion, int? buildNumber) {
  final text = displayVersion.trim().replaceFirst(RegExp('^v'), '');
  if (text.isEmpty) return null;

  final parts = text.split(RegExp(r'\s+'));
  final number = SemVer.tryParse(parts.first);
  if (number == null) return null;

  if (parts.length == 1) {
    return LauncherVersion(number: number, channel: LauncherChannel.release);
  }
  return LauncherVersion(
    number: number,
    channel: LauncherChannel.fromSuffix(parts[1]),
    build: parts.length > 2 ? int.tryParse(parts[2]) : buildNumber,
  );
}

/// release 里的一个产物
class LauncherAsset {
  const LauncherAsset({required this.name, required this.url, this.size});

  final String name;

  final String url;

  /// 字节数（接口没给就是 null）
  final int? size;
}

/// 启动器的一次发布
class LauncherRelease {
  const LauncherRelease({
    required this.tag,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.prerelease,
    required this.assets,
  });

  final String tag;

  /// release 标题，为空时展示 [tag]
  final String name;

  /// 发布说明（markdown 原文，直接显示）
  final String body;

  final String htmlUrl;

  final bool prerelease;

  final List<LauncherAsset> assets;

  /// tag 解析出的版本；解析不出来时为 null（选最新一版时排最后）
  LauncherVersion? get version => parseLauncherTag(tag);

  /// 这一版属于哪个通道
  ///
  /// 优先信 tag 尾缀（`v0.1.0-alpha6` → 内测、`v0.1.0-beta1` → 公测）；
  /// tag 没写通道却勾了 pre-release 时按**内测**处理 —— 宁可把它当最不稳的那级，
  /// 也别让公测用户吃到来路不明的预发布。两条都不成立就是正式版
  LauncherChannel get channel {
    final parsed = version;
    if (parsed != null && parsed.channel != LauncherChannel.release) {
      return parsed.channel;
    }
    return prerelease ? LauncherChannel.alpha : LauncherChannel.release;
  }

  /// 这一版算不算预发布（内测 / 公测）
  bool get isPrerelease => channel != LauncherChannel.release;

  /// 展示用标题
  String get displayName => name.trim().isEmpty ? tag : name.trim();
}

/// 启动器自身更新：查仓库 release、挑产物、下载、拉起安装
///
/// 只做 Windows 的产物挑选与安装拉起；其余平台交给 release 页面手动下载
class LauncherUpdate {
  /// 启动器仓库（与 [launcherRepoUrl] 同一份）
  static const String repo = 'MDTCopper/launcher';

  /// 一次查多少个 release：挑最新一版够用
  ///
  /// 走列表而不是 `/releases/latest`：后者按定义排除预发布，而内测 / 公测版本
  /// 正是靠预发布标记发出去的；吃不吃预发布由 [newestFor] 按本地通道决定
  static const int fetchLimit = 10;

  /// 当前这份的版本（`app_constant.dart` 里由构建脚本写入的版本信息）
  static LauncherVersion? get currentVersion =>
      parseLocalVersion(appVersion, appBuildNumber);

  /// 查 release 列表（含预发布），按版本号自己排序、不吃接口返回顺序；
  /// **拉取失败返回 null**（与「没有候选」区分开：后者返回空列表）
  static Future<List<LauncherRelease>?> fetchReleases() async {
    try {
      final decoded = await fetchJsonBody(
        '$githubAPI/repos/$repo/releases?per_page=$fetchLimit',
      );
      return parseReleases(decoded);
    } catch (e) {
      addLogAndPrint(
        .warning,
        '查询启动器版本失败：${removeNewlines('$e')}',
        tag: 'Update',
      );
      return null;
    }
  }

  /// 本地这份能收到的最新一版
  ///
  /// 通道阶梯 **内测 < 公测 < 正式**，本地只吃「本级与更稳的」：
  /// 内测能吃到内测 / 公测 / 正式，公测能吃到公测 / 正式（**不吃内测** ——
  /// 那是更不稳的一级，哪怕版本号更高），正式版只吃正式版。
  /// 本地版本读不出来时按正式版处理（宁可少提示，也别把预发布推给正式版用户）
  static LauncherRelease? newestFor({
    required LauncherVersion? local,
    required List<LauncherRelease> releases,
  }) {
    final localChannel = local?.channel ?? LauncherChannel.release;
    return newestOf([
      for (final release in releases)
        if (release.channel.rank >= localChannel.rank) release,
    ]);
  }

  /// [release] 是否比当前这份新（[local] 不传就取 [currentVersion]）
  static bool isNewer(LauncherRelease release, {LauncherVersion? local}) {
    final base = local ?? currentVersion;
    final remote = release.version;
    if (base == null || remote == null) return false;
    return remote.compareTo(base) > 0;
  }

  /// 该不该直接拉起安装：Windows + 下的是 Setup + 当前这份就是 Setup 装出来的
  static bool shouldRunInstaller(LauncherAsset asset) =>
      Platform.isWindows &&
      asset.name.toLowerCase().endsWith('-setup.exe') &&
      isInstalledBuild;

  /// 该不该走「退出后脚本覆盖」：Windows + 下的是 zip + 当前是解压版，
  /// 且程序目录可写（不可写时数据根已经回退到应用支持目录，就地进行覆盖也写不进去）
  static bool shouldReplacePortable(LauncherAsset asset) =>
      Platform.isWindows &&
      asset.name.toLowerCase().endsWith('.zip') &&
      !isInstalledBuild &&
      !AppPaths.isUsingFallbackDataPath;

  /// 当前这份是不是 Setup 装出来的（解压版没有卸载器）
  static bool get isInstalledBuild =>
      isInstalledBuildIn(File(Platform.resolvedExecutable).parent.path);

  /// Inno Setup 会在程序目录里留 `unins000.exe`，用它区分「安装版」与「解压版」
  @visibleForTesting
  static bool isInstalledBuildIn(String exeDir) =>
      File(p.join(exeDir, 'unins000.exe')).existsSync();

  /// 更新包下载目录：临时目录（更新包是一次性文件，不往数据根里塞）
  static Directory get downloadDir =>
      Directory(p.join(Directory.systemTemp.path, 'copper_launcher_update'));

  /// 下载产物，返回落盘路径
  static Future<String> downloadAsset({
    required LauncherAsset asset,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
  }) async {
    final dir = downloadDir;
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, asset.name));
    // 每次重下：上一次中断留下的半截文件不能当成完整的更新包
    if (await target.exists()) await target.delete();

    await cio.download(
      url: asset.url,
      savePath: target.path,
      cancelToken: cancelToken,
      onStatus: (state) => onProgress?.call(state.progress),
    );
    return target.path;
  }

  /// 拉起 Setup：静默安装（不出向导、装完也不自动启动），并让安装器
  /// 关掉还占着文件的本进程 —— 调用方随后要退出启动器
  static Future<void> runInstaller(String setupPath) async {
    await Process.start(setupPath, const [
      '/SILENT',
      '/CLOSEAPPLICATIONS',
      '/NORESTART',
    ], mode: ProcessStartMode.detached);
  }

  /// 解压版的就地覆盖：写脚本 + VBS 再拉起，等本进程退出后覆盖、跑引导脚本、重启
  ///
  /// 必须等进程退出：运行中的 exe 与已加载的 dll（flutter_windows / 插件 / app.so）
  /// 在 Windows 上不允许被覆盖；调用方拉起后应退出启动器
  ///
  /// 用 VBS 包一层：detached 出来的 cmd 自己没有控制台，它拉起的
  /// `tasklist` / `find` / `tar` / `ping` 会各自新建控制台 → 屏幕上冒窗口；
  /// `WScript.Shell.Run(..., 0, ...)` 给 cmd 一个**隐藏**控制台，子进程共用它。
  /// 重启启动器交给 VBS（等 cmd 跑完再拉），这样引导脚本就算硬 `exit` 掉
  /// cmd，也不会把「重新打开启动器」这步一起吞掉
  static Future<void> runPortableReplace({
    required String zipPath,
    required String toVersion,
  }) async {
    final installDir = File(Platform.resolvedExecutable).parent.path;
    final command = File(p.join(downloadDir.path, 'apply_update.cmd'));
    final launcher = File(p.join(downloadDir.path, 'apply_update.vbs'));
    await command.writeAsString(
      buildPortableUpdateScript(
        zipPath: zipPath,
        installDir: installDir,
        toVersion: toVersion,
        fromVersion: currentVersion?.tag ?? '',
        processId: pid,
      ),
      flush: true,
    );
    await launcher.writeAsString(
      buildPortableUpdateLauncher(
        commandPath: command.path,
        exePath: Platform.resolvedExecutable,
        installDir: installDir,
      ),
      flush: true,
    );

    addLogAndPrint(.info, '解压版更新：退出后覆盖 $installDir', tag: 'Update');
    try {
      await Process.start(
        'wscript.exe',
        [launcher.path],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      // 极少数环境不让跑 wscript：退回直接拉 cmd（会闪一下窗口，但更新照做）
      addLogAndPrint(
        .warning,
        '隐藏拉起更新脚本失败，改用普通方式：${removeNewlines('$e')}',
        tag: 'Update',
      );
      await Process.start('cmd.exe', [
        '/c',
        command.path,
      ], mode: ProcessStartMode.detached);
    }
  }

  /// 引导脚本在程序目录里的名字：随每个版本一起下发，覆盖完由更新流程调用
  ///
  /// 它处理光靠覆盖不行的破坏性变更（数据布局 / 配置格式变了等），
  /// 契约见仓库里的模板 `tool/update_script.cmd`
  static const String bootstrapScriptName = 'update.cmd';

  /// 生成拉起更新用的 VBS（纯函数）
  ///
  /// 三步：**隐藏**跑覆盖脚本并等它结束（窗口样式 0）→ 重新启动启动器
  /// （样式 1，工作目录设为程序目录）→ 自删。cmd 脚本里不再负责重启，
  /// 这样引导脚本硬 `exit` 也不会把重启吞掉
  @visibleForTesting
  static String buildPortableUpdateLauncher({
    required String commandPath,
    required String exePath,
    required String installDir,
  }) {
    // VBS 里两个引号代表一个引号：下面拼出来的命令行是
    //   cmd.exe /c ""C:\...\apply_update.cmd""   —— 外层再包一层引号，
    //   路径带空格也不会被拆开
    final command = 'cmd.exe /c ""$commandPath""'.replaceAll('"', '""');
    final exe = '"$exePath"'.replaceAll('"', '""');
    final directory = installDir.replaceAll('"', '""');
    return [
      'Set sh = CreateObject("WScript.Shell")',
      'sh.CurrentDirectory = "$directory"',
      'sh.Run "$command", 0, True',
      'sh.Run "$exe", 1, False',
      'CreateObject("Scripting.FileSystemObject")'
          '.DeleteFile WScript.ScriptFullName',
      '',
    ].join('\r\n');
  }

  /// 生成解压版的覆盖脚本（纯函数，便于用例核对等待与引号处理）
  ///
  /// 流程：轮询 PID 等本进程退出（最多 60 秒）→ 用系统自带的 `tar.exe` 解压覆盖
  /// （失败就等一秒再试，最多 15 次）→ 跑新版带来的引导脚本 `update.cmd`
  /// → 由 VBS 重启启动器。`tar` 是 Win10 1803+ 内置的 bsdtar，能直接解 zip，
  /// 不引第三方依赖；解压只覆盖同名文件、不删任何东西，用户数据都留着
  @visibleForTesting
  static String buildPortableUpdateScript({
    required String zipPath,
    required String installDir,
    required String toVersion,
    required String fromVersion,
    required int processId,
  }) {
    // cmd 脚本用 CRLF；内容保持纯 ASCII，免得控制台代码页把中文编坏
    const newline = '\r\n';
    return [
      '@echo off',
      'rem Overwrite the portable copy after Copper Launcher (pid $processId) exits.',
      'set "ZIP=$zipPath"',
      'set "TARGET=$installDir"',
      'set "TO=$toVersion"',
      'set "FROM=$fromVersion"',
      'set "PIDFILE=%~dp0pid_check.txt"',
      'set /a TRIES=0',
      ':wait',
      // 不能写成 `tasklist ... | find ...`：detached（没有控制台）下这条管道会挂住，
      // 实测卡在这里再也不往下走 —— 先落成文件再 find 才对
      'tasklist /FI "PID eq $processId" /NH > "%PIDFILE%" 2>nul',
      'find "$processId" "%PIDFILE%" >nul',
      'if errorlevel 1 goto apply',
      'set /a TRIES+=1',
      'if %TRIES% geq 60 goto apply',
      // 也不用 timeout：它要求真实的控制台输入句柄，detached 下会直接报错
      'ping -n 2 127.0.0.1 >nul',
      'goto wait',
      ':apply',
      // 进程没了通常一次就成；万一还有文件被占着，等一秒重来
      'set /a TRIES=0',
      ':retry',
      'tar -xf "%ZIP%" -C "%TARGET%" 2>nul',
      'if not errorlevel 1 goto migrate',
      'set /a TRIES+=1',
      'if %TRIES% geq 15 goto migrate',
      'ping -n 2 127.0.0.1 >nul',
      'goto retry',
      ':migrate',
      'del "%PIDFILE%" 2>nul',
      'cd /d "%TARGET%"',
      // 覆盖完先跑新版带来的引导脚本（破坏性变更的迁移钩子）：传「目标版本 来源版本」，
      // 用 call 而不是直接执行，脚本里的 exit /b 才能正常返回
      'if exist "%TARGET%\\$bootstrapScriptName" call "%TARGET%\\$bootstrapScriptName" "%TO%" "%FROM%"',
      // 自删放最后一行：删除后 cmd 就不再往下读了，后面不能有别的东西；
      // 别用 `(goto) 2>nul & del` 那套写法 —— 在这台机器上实测会把脚本挂住
      'del "%~f0"',
    ].join(newline);
  }

  /// Windows 产物：安装版取 Setup（覆盖安装）、解压版取 zip；要的那种没有时退另一种
  static LauncherAsset? pickWindowsAsset(
    List<LauncherAsset> assets, {
    required bool preferSetup,
  }) {
    LauncherAsset? setup;
    LauncherAsset? zip;
    for (final asset in assets) {
      final name = asset.name.toLowerCase();
      if (!name.contains('windows')) continue;
      if (name.endsWith('-setup.exe')) {
        setup ??= asset;
      } else if (name.endsWith('.zip')) {
        zip ??= asset;
      }
    }
    return preferSetup ? (setup ?? zip) : (zip ?? setup);
  }

  /// 版本最高的一版：tag 解析不出来的排最后；列表为空返回 null
  @visibleForTesting
  static LauncherRelease? newestOf(List<LauncherRelease> releases) {
    if (releases.isEmpty) return null;
    final sorted = [...releases]
      ..sort((a, b) {
        final left = a.version;
        final right = b.version;
        if (left == null || right == null) {
          if (left == right) return 0;
          return left == null ? 1 : -1;
        }
        return right.compareTo(left);
      });
    return sorted.first;
  }

  /// 解析 release 列表 JSON（结构不对的条目跳过）
  @visibleForTesting
  static List<LauncherRelease> parseReleases(dynamic json) {
    if (json is! List) return const [];

    final releases = <LauncherRelease>[];
    for (final item in json) {
      if (item is! Map) continue;
      final tag = item['tag_name'];
      if (tag is! String) continue;

      releases.add(
        LauncherRelease(
          tag: tag,
          name: '${item['name'] ?? ''}',
          body: '${item['body'] ?? ''}',
          htmlUrl: '${item['html_url'] ?? ''}',
          prerelease: item['prerelease'] == true,
          assets: parseAssets(item['assets']),
        ),
      );
    }
    return releases;
  }

  /// 解析产物列表（缺名字 / 下载地址的项跳过）
  @visibleForTesting
  static List<LauncherAsset> parseAssets(dynamic assets) {
    if (assets is! List) return const [];

    return [
      for (final asset in assets)
        if (asset is Map &&
            asset['name'] is String &&
            asset['browser_download_url'] is String)
          LauncherAsset(
            name: asset['name'] as String,
            url: asset['browser_download_url'] as String,
            size: asset['size'] is int ? asset['size'] as int : null,
          ),
    ];
  }
}
