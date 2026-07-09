import 'dart:io';

import 'package:copperlauncher_main/core/app_config.dart';
import 'package:copperlauncher_main/ui/copper_launcher.dart';
import 'package:copperlauncher_main/util/app_paths.dart';
import 'package:copperlauncher_main/util/io/run_time_log.dart';
import 'package:copperlauncher_main/util/io/token_encryptor.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  await _initialize();
  runCopperLauncher();
}

Future<void> _initialize() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TokenEncryptor.init();
  await initAppConfig();
  await RunTimeLog.init();
  await AppPaths.initDefaultDataPath();
  if (Platform.isWindows) {
    await _initWindow();
  }
}

Future _initWindow() async {
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
