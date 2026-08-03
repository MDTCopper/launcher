import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/copper_launcher.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/run_time_log.dart';
import 'package:copper_launcher/util/io/token_encryptor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  await _initialize();
  runCopperLauncher();
}

Future<void> _initialize() async {
  _checkPlatform();
  WidgetsFlutterBinding.ensureInitialized();
  await AppPaths.init();
  await TokenEncryptor.init();
  await initAppConfig();
  await RunTimeLog.init();
  await _initViewPool();
}

void _checkPlatform() {
  if (kIsWeb) throw Exception('Web不支持');
  if (Platform.isIOS) throw Exception('IOS平台不支持');
}

Future _initViewPool() async {
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
