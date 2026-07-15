import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/data/local_asset.dart';

import '../core/app_config.dart';

class MindustryLauncher {
  Process? _jarProcess;
  StreamController<String>? _logController;
  Stream<String>? get logStream => _logController?.stream;

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
      print('Java 环境校验失败：$e');
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
    // 先校验 Java 环境
    final isJavaAvailable = await _checkJavaEnv(javaExecutable: javaExecutable);
    if (!isJavaAvailable) {
      print('错误：未检测到 Java 环境，请先安装并配置 Java');
      return false;
    }

    // 校验 Jar 文件是否存在
    final jarFile = File(mindustry.jarPath);
    if (!await jarFile.exists()) {
      print('错误：mindustry.jar 不存在，路径：${mindustry.jarPath}');
      return false;
    }

    try {
      // 初始化日志控制器
      if (_logController == null || _logController!.isClosed) {
        _logController = StreamController<String>.broadcast();
      }

      final args = <String>[];

      if (maxMemory != null && maxMemory.inGB > 0.1) {
        args.add('-Xmx${maxMemory.mb}m');
      } else {
        args.add('-Xmx512m');
      }

      if (mindustry.isolation) {
        args.add('-Dmindustry.data.dir=${mindustry.dataPath}');
      }

      // TODO: 安卓相关参数待处理
      // 可能需要添加安卓相关的JVM参数或环境变量

      // 添加额外的自定义参数

      if (extraArgs != null) {
        for (var arg in extraArgs) {
          if (arg.isNotEmpty) args.add(arg);
        }
      }

      args.add('-jar');
      args.add(mindustry.jarPath);

      args.addAll(
        _buildMindustryArgs(windowSize: windowSize, maximize: maximize),
      );

      final javaCmd = javaExecutable ?? 'java';

      _jarProcess = await Process.start(
        javaCmd,
        args,
        runInShell: false,
        workingDirectory: jarFile.parent.path,
      );

      print('进程 ID：${_jarProcess?.pid}，命令：java ${args.join(' ')}');

      // 监听进程日志（stdout + stderr）
      _listenToJarLogs();

      // 监听进程退出（释放资源）
      _jarProcess?.exitCode.then((code) {
        _logController?.add('exit $code');
        _logController?.close();
        _jarProcess = null;
      });
      return true;
    } catch (e) {
      _logController?.close();
      return false;
    }
  }

  // 3. 监听 Jar 进程输出日志
  void _listenToJarLogs() {
    if (_jarProcess == null || _logController == null) return;

    // 监听标准输出（游戏正常日志）
    _jarProcess!.stdout.transform(systemEncoding.decoder).listen((log) {
      if (log.isNotEmpty) {
        _logController?.add('[游戏日志] ${log.trim()}');
        print('[游戏日志] ${log.trim()}');
      }
    });

    // 监听错误输出（异常/报错日志）
    _jarProcess!.stderr.transform(systemEncoding.decoder).listen((error) {
      if (error.isNotEmpty) {
        _logController?.add('[错误] ${error.trim()}');
        print('[错误] ${error.trim()}');
      }
    });
  }

  // 4. 关闭 Jar 进程（可选）
  Future<bool> stopMindustryJar() async {
    if (_jarProcess == null) return true;

    try {
      _jarProcess!.kill(ProcessSignal.sigterm); // 发送终止信号
      await _jarProcess!.exitCode; // 等待进程退出
      print('Mindustry Jar 进程已关闭');
      _logController?.close();
      _jarProcess = null;
      return true;
    } catch (e) {
      print('关闭 Jar 进程失败：$e');
      return false;
    }
  }

  List<String> _buildMindustryArgs({WindowSize? windowSize, bool? maximize}) {
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

    ///Mindustry在桌面端测试移动端界面参数
    // args.add('-testMobile');
    return args;
  }

  void dispose() {
    _logController?.close();
    _logController = null;
    _jarProcess?.kill();
  }
}
