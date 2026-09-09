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
import 'package:window_manager/window_manager.dart';

void main() async {
  await _initialize();
  runCopperLauncher();
}

///必要的基础初始化完成后即进入 app
Future<void> _initialize() async {
  _checkPlatform();
  WidgetsFlutterBinding.ensureInitialized();
  await AppPaths.init();
  await Log.init();
  await TokenEncryptor.init();
  await initAppConfig();
  //config 就绪后同步网络设置（代理/token/限速/线程/镜像），此后新建请求即生效
  cio.applySettings();
  await _initPlatformView();
  //窗口就绪后应用托盘模式（依赖 config + windowManager）
  await LauncherTray.instance.applyMode();
  //后台初始化任务：不阻塞，进任务抽屉自跑
  addTask(StartupBackgroundTask());
}

void _checkPlatform() {
  if (kIsWeb) throw Exception('Web不支持');
  if (Platform.isIOS) throw Exception('IOS平台不支持');
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
    // 移动端尺寸 Size(760, 360),
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
