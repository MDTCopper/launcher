import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/bridge_installer.dart';
import 'package:copper_launcher/domain/bridge_launcher.dart';
import 'package:copper_launcher/domain/bridge_payload.dart';
import 'package:copper_launcher/domain/loader_library.dart';
import 'package:copper_launcher/domain/steam_client.dart';
import 'package:copper_launcher/domain/steam_library.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/gpu_preference.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show Icons;

import 'package:path/path.dart' as p;

import '../core/app_config.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import '../ui/util/notification.dart';

class MindustryLauncher {
  Process? _jarProcess;
  StreamController<String>? _logController;
  Stream<String>? get logStream => _logController?.stream;

  /// 当前启动的游戏数据目录（用于定位 launchid.dat）。
  String? _dataPath;

  /// 是否为启动器主动停止游戏。
  ///
  /// 主动停止且游戏未完全启动时，需清理残留的 launchid.dat 哨兵文件，
  /// 避免下次启动被 Mindustry 误判为「mod 加载崩溃」而全部禁用 mod
  bool _stoppedByLauncher = false;

  // 校验 Java 环境是否可用
  Future<bool> _checkJavaEnv({String? javaExecutable}) async {
    try {
      final javaCmd = javaExecutable ?? 'java';

      // 执行 java -version 命令，验证 Java 是否可调用
      final process = await Process.start(javaCmd, ['-version']);

      // 捕获错误流（java -version 输出在 stderr，非 stdout）
      final errorOutput = await process.stderr
          .transform(systemEncoding.decoder)
          .join();
      await process.exitCode;

      // 若输出含 "java version" 或 "openjdk version"，说明 Java 可用
      return errorOutput.contains('java version') ||
          errorOutput.contains('openjdk version');
    } catch (e) {
      addLogAndPrint(
        .warning,
        'Java 环境校验失败：${removeNewlines('$e')}',
        tag: 'Launch',
      );
      return false;
    }
  }

  Future<bool> start(
    Mindustry mindustry, {
    WindowSize? windowSize,
    bool? maximize,
    Memory? maxMemory,
    String? javaExecutable,
    List<String>? extraArgs = const [],
  }) async {
    // Android 上没有「桌面 JDK」这回事：Java 是载荷里的 JRE，进程由桥在游戏进程里起
    if (Platform.isAndroid) {
      return _startWithBridge(
        mindustry,
        maxMemory: maxMemory,
        extraArgs: extraArgs ?? const [],
      );
    }

    // 校验 Java 环境
    final isJavaAvailable = await _checkJavaEnv(javaExecutable: javaExecutable);
    if (!isJavaAvailable) {
      addLogAndPrint(.warning, '未检测到 Java 环境，请先安装并配置 Java', tag: 'Launch');
      return false;
    }

    // 校验 Jar 文件是否存在
    final jarFile = File(mindustry.resolvedJarPath);
    if (!await jarFile.exists()) {
      addLogAndPrint(
        .warning,
        '游戏本体不存在：${mindustry.resolvedJarPath}',
        tag: 'Launch',
      );
      return false;
    }

    // 走加载器时先确认 loader jar 在：没有就别硬起（调用方会收尾成启动失败）
    final loaderPath = mindustry.isViaLoader
        ? usableLoaderPath(mindustry)
        : null;
    if (mindustry.isViaLoader && loaderPath == null) {
      addLogAndPrint(
        .warning,
        '没有可用的模组加载器：${mindustry.launcherPath ?? '（该版本未指定 loader）'}',
        tag: 'Launch',
      );
      return false;
    }

    try {
      // 初始化日志控制器
      if (_logController == null || _logController!.isClosed) {
        _logController = StreamController<String>.broadcast();
      }

      final args = buildLaunchArguments(
        mindustry: mindustry,
        loaderPath: loaderPath,
        maxMemory: maxMemory,
        windowSize: windowSize,
        maximize: maximize,
        extraArgs: extraArgs ?? const [],
      );

      final javaCmd = javaExecutable ?? 'java';

      // 「使用高性能显卡」：版本级三态覆盖全局开关（null = 跟随全局）
      final preferHighPerformance =
          mindustry.useBetterGPU ??
          config.setting.launchOptions.javaOptions.useBetterGPU;

      // Windows 的显卡首选项是系统级、按 exe 记的：启动前对齐一次（已一致就不写）
      GpuPreference.applyToExecutable(
        executablePath: javaCmd,
        preferHighPerformance: preferHighPerformance,
      );

      // 隔离时补环境变量：官方 ClientLauncher 先读 -Dmindustry.data.dir、读不到退回
      // MINDUSTRY_DATA_DIR；更低版本则直接读 MINDUSTRY 环境变量；
      // 高性能显卡在 Linux 上就是靠环境变量让游戏走独显。
      // **Steam 版不走这一支**：它的数据目录靠工作目录定，改 APPDATA 反而指歪
      final gpuEnvironment = GpuPreference.launchEnvironment(
        preferHighPerformance: preferHighPerformance,
      );

      // Steam 版必须带 SteamAppId / SteamGameId，否则 Steam 客户端在跑时游戏会秒退
      // 并交给 Steam（见 `SteamLibrary.launchEnvironment`）
      final extraEnvironment = {
        ...gpuEnvironment,
        if (mindustry.steam) ...SteamLibrary.launchEnvironment(),
      };
      final environment =
          mindustry.isolation && !mindustry.isViaLoader && !mindustry.steam
          ? {
              ...Platform.environment,
              'MINDUSTRY_DATA_DIR': mindustry.dataPath,
              'MINDUSTRY': mindustry.dataPath,
              if (Platform.isWindows) 'APPDATA': mindustry.dataPath,
              ...extraEnvironment,
            }
          : extraEnvironment.isEmpty
          ? null
          : {...Platform.environment, ...extraEnvironment};

      // 「自动唤醒 Steam」：客户端没跑就先唤醒，**并等它真的登录进去**。
      // Steam 版靠 `SteamAppId` 旁路独立启动，但那只在**已登录**时成立；
      // 只等进程起来就往下走会得到「显示 Steam 版本但没有功能」
      if (mindustry.steam && config.setting.launchOptions.autoWakeSteam) {
        final wake = await SteamClient.ensureRunning(
          // 等登录最长 90 秒，期间任务卡片只会停在「准备启动」——
          // 所以先告诉玩家该做什么，别让他对着没反应的界面等
          onWaking: () => addNotice(
            icon: Icons.hourglass_top,
            title: '正在启动 Steam',
            content: '请在 Steam 里选好账号，选好后会自动继续启动游戏',
            duration: const Duration(seconds: 20),
          ),
        );
        if (wake.shouldWarn) {
          addNotice(
            icon: Icons.info_outline,
            title: 'Steam 可能还没就绪',
            content: wake == SteamWakeOutcome.failed
                ? '没找到 Steam 客户端，这一局会用不了 Steam 功能'
                      '（云存档 / 游戏时长 / 联机）'
                : 'Steam 是刚唤醒的，可能还没选好账号。若弹出「谁在玩游戏？」'
                      '请先选好，否则这一局用不了 Steam 功能',
            duration: const Duration(seconds: 12),
          );
        }
      }

      _jarProcess = await Process.start(
        javaCmd,
        args,
        runInShell: false,
        // Steam 版的数据目录算在工作目录上，其余版本用本体所在目录
        workingDirectory: mindustry.launchWorkingDirectory,
        environment: environment,
      );

      // 记录游戏数据目录，用于退出时清理 launchid.dat
      _dataPath = mindustry.dataPath;

      addLogAndPrint(
        .info,
        '进程 ID：${_jarProcess?.pid}，命令：java ${args.join(' ')}',
        tag: 'Launch',
      );

      // 监听进程日志（stdout + stderr）
      _listenToJarLogs();

      // 监听进程退出（释放资源）
      _jarProcess?.exitCode.then((code) {
        _logController?.add('exit $code');
        _logController?.close();
        _jarProcess = null;
        // 启动器主动停止且游戏未完全启动（launchid.dat 残留）时删除哨兵，
        // 避免下次启动被误判为 mod 加载崩溃
        if (_stoppedByLauncher) {
          _stoppedByLauncher = false;
          _removeLaunchSentinelIfAny();
        }
      });
      return true;
    } catch (e) {
      _logController?.close();
      return false;
    }
  }

  /// Android：载荷齐了就把参数交给桥（这条路没有 `java -jar`，Java 是载荷里的 JRE）
  ///
  /// 与桌面那条路的区别：不校验桌面 JDK、不认窗口参数、不建 [Process]（游戏由桥在
  /// 自己起的进程里跑）；arc 原生库跟着**具体游戏版本**走，缺了就在这儿现下（同版本
  /// 只下一次）。`Bridge.launch` 只是把参数交出去，起没起来要看界面切没切到游戏
  /// 或 `<数据目录>/last_log.txt`
  Future<bool> _startWithBridge(
    Mindustry mindustry, {
    Memory? maxMemory,
    List<String> extraArgs = const [],
  }) async {
    if (_logController == null || _logController!.isClosed) {
      _logController = StreamController<String>.broadcast();
    }

    if (!BridgeInstaller.isRuntimeReady()) {
      addLogAndPrint(
        .warning,
        'Android 桥的载荷不齐（缺 JRE 或 bridge.jar）：先走安装页',
        tag: 'Launch',
      );
      return false;
    }
    final bridgeJar = BridgePayload.installedBridgeJar();
    if (bridgeJar == null) return false;

    final abi = await BridgeInstaller.detectDeviceAbi();
    if (abi == null) {
      addLogAndPrint(
        .warning,
        '问不出设备 ABI：载荷按 ABI 分包，起不来（设备信息请反馈）',
        tag: 'Launch',
      );
      return false;
    }

    // 走 Copper 加载器时注入 wrapper + loader 桌面 jar（文档 §7）：少了任何一份就按原版起，
    // 免得「点了没反应」——mod 不会加载，但游戏能起来
    var loaderJars = const <String>[];
    String? loaderMainClass;
    if (mindustry.isViaLoader) {
      final desktopLoader = usableLoaderPath(mindustry);
      final wrapper = await BridgeInstaller.ensureLoaderWrapper(
        desktopLoaderPath: desktopLoader,
        onStatus: (status) =>
            addLogAndPrint(.info, 'Android 桥：$status', tag: 'Bridge'),
      );
      if (wrapper != null && desktopLoader != null) {
        loaderJars = [wrapper, desktopLoader];
        loaderMainClass = BridgePayload.wrapperMainClass;
      } else {
        addLogAndPrint(
          .warning,
          'Android 桥：模组加载器不全（适配层 ${wrapper == null ? '不可用' : '就绪'}、'
          '桌面 jar ${desktopLoader ?? '缺失'}），这次按原版启动，mod 不会加载',
          tag: 'Launch',
        );
      }
    }

    final arcRef = await BridgeLauncher.arcRefOf(mindustry);
    String? arcDir;
    if (arcRef == null) {
      addLogAndPrint(
        .warning,
        '查不到这个版本用的 arc：先不带 arc 原生库启动（性能下降）',
        tag: 'Launch',
      );
    } else {
      arcDir = AppPaths.bridgeArcDir(arcRef, abi);
      final arcFolder = Directory(arcDir);
      if (!arcFolder.existsSync() || arcFolder.listSync().isEmpty) {
        try {
          await BridgeInstaller.installArcNatives(
            arcRef: arcRef,
            abi: abi,
            onStatus: (status) =>
                addLogAndPrint(.info, 'Android 桥：$status', tag: 'Bridge'),
          );
        } catch (error) {
          addLogAndPrint(
            .warning,
            'arc 原生库装不上：${removeNewlines('$error')}（先照起，性能下降）',
            tag: 'Launch',
          );
        }
      }
    }

    final jvmArgs = [
      ...BridgeLauncher.jvmArgsFrom(maxMemory: maxMemory),
      ...extraArgs.where(
        (arg) => arg.isNotEmpty && !BridgeLauncher.isDesktopOnlyJvmArg(arg),
      ),
      ...BridgeLauncher.gcSafetyArgsFor(abi),
    ];

    final args = BridgeLauncher.buildArguments(
      gameJar: mindustry.resolvedJarPath,
      dataPath: mindustry.dataPath,
      cacheDir: BridgeLauncher.cacheDirFor(mindustry),
      jreDir: AppPaths.bridgeJre,
      arcDir: arcDir,
      jvmArgs: jvmArgs,
      loaderJars: loaderJars,
      loaderMainClass: loaderMainClass,
      // Android 上的「使用高性能显卡」就是向桥要 OpenGL ES 3（关掉退 ES 2）
      gl3:
          mindustry.useBetterGPU ??
          config.setting.launchOptions.javaOptions.useBetterGPU,
    );

    try {
      BridgeLauncher.launchWithBridge(bridgeJar: bridgeJar.path, args: args);
    } catch (error) {
      addLogAndPrint(
        .error,
        '交给桥启动失败：${removeNewlines('$error')}',
        tag: 'Launch',
      );
      _logController?.close();
      return false;
    }

    _dataPath = mindustry.dataPath;
    addLogAndPrint(
      .info,
      'Android 桥：已交给桥启动（${mindustry.tag}）：${args.join(' ')}',
      tag: 'Launch',
    );
    return true;
  }

  void _listenToJarLogs() {
    if (_jarProcess == null || _logController == null) return;

    // 监听标准输出（游戏正常日志）
    _jarProcess!.stdout.transform(systemEncoding.decoder).listen((log) {
      if (log.isNotEmpty) {
        _logController?.add('[游戏日志] ${log.trim()}');
        addLogAndPrint(.info, '[游戏日志] ${log.trim()}', tag: 'Launch');
      }
    });

    // 监听错误输出（异常/报错日志）
    _jarProcess!.stderr.transform(systemEncoding.decoder).listen((error) {
      if (error.isNotEmpty) {
        _logController?.add('[错误] ${error.trim()}');
        addLogAndPrint(.warning, '[错误] ${error.trim()}', tag: 'Launch');
      }
    });
  }

  Future<bool> stopMindustryJar() async {
    if (_jarProcess == null) return true;

    try {
      _stoppedByLauncher = true; // 主动停止：退出后清理残留哨兵
      _jarProcess!.kill(ProcessSignal.sigterm);
      await _jarProcess!.exitCode;
      addLogAndPrint(.info, '游戏进程已关闭', tag: 'Launch');
      _logController?.close();
      _jarProcess = null;
      return true;
    } catch (e) {
      addLogAndPrint(
        .warning,
        '关闭游戏进程失败：${removeNewlines('$e')}',
        tag: 'Launch',
      );
      return false;
    }
  }

  /// 组装启动参数（纯函数，方便用例覆盖两种启动方式）
  ///
  /// 官方 Jar：`-jar <游戏本体> <游戏参数>`
  /// 走加载器：`-jar <loader> -G <游戏本体> -D <数据目录> -- <游戏参数>`，
  /// 数据目录交给加载器（它自己把目录注入游戏），所以不再塞 `-Dmindustry.data.dir`
  @visibleForTesting
  static List<String> buildLaunchArguments({
    required Mindustry mindustry,
    required String? loaderPath,
    Memory? maxMemory,
    WindowSize? windowSize,
    bool? maximize,
    List<String> extraArgs = const [],
  }) {
    return [
      if (maxMemory != null && maxMemory.inGB > 0.1)
        '-Xmx${maxMemory.mb}m'
      else
        '-Xmx512m',
      if (mindustry.needsDataDirArg)
        '-Dmindustry.data.dir=${mindustry.dataPath}',
      ...extraArgs.where((arg) => arg.isNotEmpty),
      '-jar',
      if (mindustry.isViaLoader) loaderPath! else mindustry.resolvedJarPath,
      if (mindustry.isViaLoader) ...[
        '-G',
        mindustry.resolvedJarPath,
        '-D',
        mindustry.dataPath,
        '--',
      ],
      ..._buildMindustryArgs(windowSize: windowSize, maximize: maximize),
    ];
  }

  /// 取这个版本可用的 loader：优先它自己指定的，其次库里第一个；都没有返回 null
  static String? usableLoaderPath(Mindustry mindustry) =>
      LoaderLibrary.usablePath(mindustry.resolvedLauncherPath);

  static List<String> _buildMindustryArgs({
    WindowSize? windowSize,
    bool? maximize,
  }) {
    final args = <String>[];

    if (windowSize != null) {
      args.add('-width');
      args.add('${windowSize.width}');
      args.add('-height');
      args.add('${windowSize.height}');
    }
    if (maximize != null) {
      args.add('-maximized');
      args.add(maximize.toString());
    } else {
      if (windowSize != null) {
        args.add('-maximized');
        args.add('false');
      }
    }

    //Mindustry在桌面端测试移动端界面参数
    return args;
  }

  void dispose() {
    _logController?.close();
    _logController = null;
    if (_jarProcess != null) {
      _stoppedByLauncher = true; // 应用关闭强制终止：退出后清理残留哨兵
      _jarProcess?.kill();
    }
  }

  /// 删除残留的 Mindustry 启动哨兵文件 launchid.dat
  /// 游戏自身崩溃退出时不清理，保留原生的崩溃保护机制
  Future<void> _removeLaunchSentinelIfAny() async {
    final dataPath = _dataPath;
    if (dataPath == null) return;
    final sentinel = File(p.join(dataPath, 'launchid.dat'));
    try {
      if (await sentinel.exists()) {
        await sentinel.delete();
        addLogAndPrint(.info, '启动被中断：已删除残留的 launchid.dat', tag: 'Launch');
      }
    } catch (e) {
      addLogAndPrint(
        .info,
        '删除 launchid.dat 失败：${removeNewlines('$e')}',
        tag: 'Launch',
      );
    }
  }
}
