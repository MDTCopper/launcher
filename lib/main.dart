import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/startup_background_task.dart';
import 'package:copper_launcher/ui/copper_launcher.dart';
import 'package:copper_launcher/ui/dialog/resource_importer.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/data_root_migration.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/token_encryptor.dart';
import 'package:copper_launcher/util/launcher_tray.dart';
import 'package:copper_launcher/util/share_in.dart';
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
      Platform.isAndroid
          ? '拿不到外部应用目录，数据根留在应用内部：${AppPaths.copperLauncher}'
          : 'exe 目录不能放数据（系统目录或不可写），数据目录改用 ${AppPaths.copperLauncher}',
      tag: 'Startup',
    );
  }
  //数据目录是排查「东西写到哪去了」的第一现场，每次启动都记下来
  addLog(.info, '数据根目录：${AppPaths.copperLauncher}', tag: 'Startup');
  addLog(.info, '游戏默认数据目录：${AppPaths.defaultGameData}', tag: 'Startup');

  final multipleStartup = !await _initSingleInctance();
  if (multipleStartup) return;

  // 数据根从应用内部搬进外部专属目录（Android）：搬完才读配置，否则会读到空根上的默认值
  final migration = await DataRootMigration.runIfNeeded();
  final migrationSummary = migration?.describe();
  if (migrationSummary != null) {
    addLogAndPrint(.info, '数据根迁移：$migrationSummary', tag: 'Startup');
    if (migration!.failed.isNotEmpty) {
      addNotice(
        icon: Icons.warning_amber_outlined,
        title: '旧数据没搬完',
        content: '有 ${migration.failed.length} 项没搬过去，日志里记了原因；'
            '它们还在应用内部目录，没丢',
      );
    }
  }

  await TokenEncryptor.init();
  await initAppConfig();
  //config 就绪后同步网络设置（代理/token/限速/线程/镜像），此后新建请求即生效
  cio.applySettings(config.setting);
  addLog(
    .info,
    '网络设置：代理：${cio.proxyInfo}；'
    '镜像：${config.setting.mirrorOptions.enabled ? config.setting.mirrorOptions.strategy.name : '关闭'}；'
    'GitHub token：${config.setting.githubToken.isEmpty ? '未设置' : '已设置'}',
    tag: 'Startup',
  );
  await _initPlatformView();
  //窗口就绪后应用托盘模式（依赖 config + windowManager）
  await LauncherTray.instance.applyMode();
  //后台初始化任务，不阻塞，进任务抽屉自跑
  addTask(StartupBackgroundTask());

  //系统分享进来的文件（安卓）：宿主已经把它们复制到缓存目录，
  //接线后与桌面拖入走同一条导入路；冷启动那次分享也在这里被取回来
  ShareIn.onFiles((files) => unawaited(_importSharedFiles(files)));
  await ShareIn.start();
}

///导入一份系统分享进来的文件
///
///导入弹窗挂在 shell 上（`showDefaultDialogPopup` 拿不到全局 Context 会直接抛），
///而冷启动那次分享远早于界面、安卓上还可能先停在环境配置页，所以等 shell 建出来再走
Future<void> _importSharedFiles(List<String> files) async {
  if (!await _waitForShell()) {
    addNotice(
      icon: Icons.info_outline,
      title: '有文件等着导入',
      content: '界面还没准备好，稍后重新分享一次即可',
    );
    return;
  }
  await showResourceImporter(
    files,
    mindustry: config.versionOptions.selectedVersion,
  );
}

///等 shell 挂上 Context；最多 30 秒，等不到返回 false
Future<bool> _waitForShell() async {
  for (var attempt = 0; attempt < 300; attempt++) {
    if (PageKeyProvider.shellKey.currentContext != null) return true;
    await Future.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

void _checkPlatform() {
  if (kIsWeb) throw Exception('Web 不支持');
  if (Platform.isIOS) throw Exception('iOS 平台不支持');
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
    // 用结束进程而不是 exit(0)：Flutter 引擎里 exit(0) 之后进程会挂着不退
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
  //不锁方向：启动器跟随设备方向，游戏自己的 Activity 仍是 sensorLandscape
  //隐藏状态栏和导航栏
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}
