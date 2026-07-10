import 'dart:io';

import 'package:copperlauncher_main/core/app_config.dart';
import 'package:copperlauncher_main/ui/copper_launcher.dart';
import 'package:copperlauncher_main/util/app_paths.dart';
import 'package:copperlauncher_main/util/io/run_time_log.dart';
import 'package:copperlauncher_main/util/io/token_encryptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  await _initialize();
  runCopperLauncher();
}

Future<void> _initialize() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPaths.init();
  await TokenEncryptor.init();
  await initAppConfig();
  await RunTimeLog.init();
  await _initViewPool();
}

Future _initViewPool() async {
  if (Platform.isWindows) {
    await _initWindows();
  } else if (Platform.isAndroid) {
    await _initAndroidView();
  } else {
    // TODO: 其他平台的初始化逻辑
  }
}

Future<void> _initWindows() async {
  // 必须先初始化窗口管理器
  await windowManager.ensureInitialized();

  // 配置窗口初始属性
  const windowOptions = WindowOptions(
    size: Size(960, 544),
    minimumSize: Size(900, 450),
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
