import 'dart:async';
import 'dart:io';

import 'package:copperlauncher_main/data/local_asset.dart';
import 'package:flutter/material.dart' show Icons;

import '../core/app_config.dart';
import '../ui/util/info/log_list.dart';
import '../ui/util/info/notification.dart';





class MindustryLauncher {
  Process? _jarProcess; // 存储 Jar 进程
  StreamController<String>? _logController; // 日志流
  Stream<String>? get logStream => _logController?.stream;

  // 校验 Java 环境是否可用
  Future<bool> _checkJavaEnv({String? javaExecutable}) async {
    try {
      final javaCmd = javaExecutable ?? 'java';

      // 执行 java -version 命令，验证 Java 是否可调用
      final process = await Process.start(javaCmd, [
        '-version',
      ], runInShell: true);

      // 捕获错误流（java -version 输出在 stderr，非 stdout）
      final errorOutput =
          await process.stderr.transform(systemEncoding.decoder).join();
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
    int? maxMemory,
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

      // 构建 Java 启动命令，包含内存、窗口大小、隔离模式等参数
      final args = <String>[];

      // 添加内存设置 (如果提供了最大内存参数)
      if (maxMemory != null && maxMemory > 0) {
        args.add('-Xmx${maxMemory}m');
      } else {
        // 默认内存设置，可以根据需要调整
        args.add('-Xmx512m');
      }

      // 根据是否隔离添加数据目录参数
      if (mindustry.isolation) {
        // 隔离模式下，使用版本特定的数据目录
        args.add('-Dmindustry.data.dir=${mindustry.dataPath}');
      }

      // TODO: 安卓相关参数待处理
      // 可能需要添加安卓相关的JVM参数或环境变量

      // 添加额外的自定义参数
      if (extraArgs != null && extraArgs.isNotEmpty) {
        args.addAll(extraArgs);
      }

      // 添加核心启动参数
      args.add('-jar');
      args.add(mindustry.jarPath);

      args.addAll(
        _buildMindustryArgs(
          windowSize: windowSize,
          fullScreen: windowSize == null,
        ),
      );

      final javaCmd = javaExecutable ?? 'java';

      _jarProcess = await Process.start(
        javaCmd, // 使用指定的 Java 可执行文件
        args,
        runInShell: true, // 支持路径含空格
        workingDirectory: jarFile.parent.path, // 以 Jar 所在目录为工作目录（避免资源路径问题）
      );

      print(
        'Mindustry Jar 启动成功！进程 ID：${_jarProcess?.pid}，命令：java ${args.join(' ')}',
      );

      // 监听进程日志（stdout + stderr）
      _listenToJarLogs();

      // 监听进程退出（释放资源）
      _jarProcess?.exitCode.then((code) {
        if (code == 0) {
          print('Mindustry Jar 进程退出，退出码：$code');
          _logController?.close();
          _jarProcess = null;
          NotificationManager.addNotice(
            icon: Icons.info_outline,
            title: '退出',
            content: '正常游戏退出，退出码：$code',
          );
          LogManager.addLog(LogEntry(LogType.success, '正常游戏退出，退出码：$code'));
        } else if (code == 1) {
          print('游戏异常退出，退出码：$code');
          _logController?.close();
          _jarProcess = null;
          NotificationManager.addNotice(
            icon: Icons.error_outline,
            title: '退出',
            content: '游戏异常退出，退出码：$code',
          );
          LogManager.addLog(LogEntry(LogType.error, '游戏异常退出，退出码：$code'));
        }
      });

      return true;
    } catch (e) {
      print('启动 Jar 失败：$e');
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
        _logController?.add('[日志] ${log.trim()}');
        print('[日志] ${log.trim()}');
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

  List<String> _buildMindustryArgs({WindowSize? windowSize, bool? fullScreen}) {
    final args = <String>[];

    if (windowSize != null) {
      args.add('-width');
      args.add('${windowSize.width}');
      args.add('-height');
      args.add('${windowSize.height}');
    }
    if (fullScreen != null) {
      args.add('-maximized');
      args.add(fullScreen.toString().toLowerCase());
    }

    ///Mindustry在桌面端测试移动端界面参数
    // args.add('-testMobile');
    return args;
  }

  // 释放资源（页面销毁时调用）
  void dispose() {
    _logController?.close();
    _logController = null;
    _jarProcess?.kill();
  }
}
