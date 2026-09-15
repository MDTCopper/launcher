import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/startup_background_task.dart';
import 'package:copper_launcher/ui/copper_launcher.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/token_encryptor.dart';
import 'package:copper_launcher/util/launcher_tray.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:window_manager/window_manager.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initialize();
  runCopperLauncher();
}

///必要的基础初始化完成后即进入 app
Future<void> _initialize() async {
  _checkPlatform();
  await AppPaths.init();
  await Log.init();
  if (AppPaths.isUsingFallbackDataPath) {
    addLogAndPrint(
      .warning,
      'exe 目录不能放数据（系统目录或不可写），数据目录改用 ${AppPaths.copperLauncher}',
      tag: 'Startup',
    );
  }
  //数据目录是排查「东西写到哪去了」的第一现场，每次启动都记下来
  addLog(.info, '数据根目录：${AppPaths.copperLauncher}', tag: 'Startup');
  addLog(.info, '游戏默认数据目录：${AppPaths.defaultGameData}', tag: 'Startup');

  final multipleStartup = !await _initSingleInctance();
  if (multipleStartup) return;

  await TokenEncryptor.init();
  await initAppConfig();
  //config 就绪后同步网络设置（代理/token/限速/线程/镜像），此后新建请求即生效
  cio.applySettings(config.setting);
  await _initPlatformView();
  //窗口就绪后应用托盘模式（依赖 config + windowManager）
  await LauncherTray.instance.applyMode();
  //后台初始化任务，不阻塞，进任务抽屉自跑
  addTask(StartupBackgroundTask());
}

void _checkPlatform() {
  if (kIsWeb) throw Exception('Web不支持');
  if (Platform.isIOS) throw Exception('IOS平台不支持');
}

Future<bool> _initSingleInctance() async {
  // 单实例：该包在 Windows / Linux / macOS 都能判定
  if (!await FlutterSingleInstance().isFirstInstance()) {
    addLogAndPrint(.info, '已有实例在运行，通知它显示窗口后退出', tag: 'Startup');
    final error = await FlutterSingleInstance().focus();
    if (error != null) {
      addLogAndPrint(
        .warning,
        '唤醒已有实例失败：${removeNewlines(error)}',
        tag: 'Startup',
      );
    }
    // 留一点时间让上面的日志落盘
    await Future.delayed(const Duration(milliseconds: 200));
    // 用结束进程而不是 exit(0)：实测 Flutter 引擎里 exit(0) 之后进程会挂着不退
    if (!Process.killPid(pid)) exit(0);
    return false;
  }
  // 第二个实例发来的唤醒请求：把窗口从托盘 / 最小化状态拉回来
  FlutterSingleInstance.onFocus = (metadata) {
    addLogAndPrint(.info, '收到第二次启动，显示主窗口（参数 $metadata）', tag: 'Startup');
    unawaited(LauncherTray.instance.showMainWindow());
  };
  return true;
}

///平台视图初始化：桌面端建窗口，移动端设置系统 UI
Future<void> _initPlatformView() async {
  if (Platform.isAndroid) {
    await _initAndroidView();
  } else {
    await _initWindows();
  }
}

Future<void> _initWindows() async {
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(880, 495),
    minimumSize: Size(760, 450),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

Future<void> _initAndroidView() async {
  // 设置屏幕方向为横屏
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  //隐藏状态栏和导航栏
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}
