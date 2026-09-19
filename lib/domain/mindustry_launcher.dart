import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/domain/loader_library.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:path/path.dart' as p;

import '../core/app_config.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';

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

      // 隔离时补环境变量：官方 ClientLauncher 先读 -Dmindustry.data.dir、读不到退回
      // MINDUSTRY_DATA_DIR；更低版本则直接读 MINDUSTRY 环境变量
      final environment = mindustry.isolation && !mindustry.isViaLoader
          ? {
              ...Platform.environment,
              'MINDUSTRY_DATA_DIR': mindustry.dataPath,
              'MINDUSTRY': mindustry.dataPath,
              if (Platform.isWindows) 'APPDATA': mindustry.dataPath,
            }
          : null;

      _jarProcess = await Process.start(
        javaCmd,
        args,
        runInShell: false,
        workingDirectory: jarFile.parent.path,
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
      if (!mindustry.isViaLoader && mindustry.isolation)
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
    // args.add('-testMobile');
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
