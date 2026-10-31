import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_runtime.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/cloud_service_process.dart';
import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/launch_args.dart';
import 'package:copper_launcher/domain/launch_request.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_notification_service.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_presence_service.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_realtime_service.dart';
import 'package:copper_launcher/domain/quick_launch.dart';
import 'package:copper_launcher/domain/shortcut_launch.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/startup_background_task.dart';
import 'package:copper_launcher/ui/copper_launcher.dart';
import 'package:copper_launcher/ui/dialog/resource_importer.dart';
import 'package:copper_launcher/ui/startup/startup_page.dart';
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

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final cli = LaunchArgs.parse(args);
  // 服务 / 快捷启动触发进程不建 UI：先置位，核心初始化里就不会去弹通知 / 碰窗口
  AppRuntime.headless = cli.service || cli.isQuickLaunch;

  // 基础层：路径 / 日志 / 配置 / 网络，服务与 UI 共用
  await _initializeCore();

  // 快捷启动触发：UI 在线就把请求交给 UI，否则本进程直接进无界面服务
  if (cli.isQuickLaunch) {
    if (await GameSessionStore.isUiRunning()) {
      addLogAndPrint(
        .info,
        '快捷启动：UI 在线，请求交给界面后退出（${cli.launchVersionId}）',
        tag: 'Startup',
      );
      await GameSessionStore.writePending(
        versionId: cli.launchVersionId!,
        reason: 'ui_online',
      );
      await _quitProcess();
      return;
    }
    // 服务已在跑（上一局游戏还没退 / 服务刚起来）：请求交给服务，别自己再起一局
    if (await GameSessionStore.isServiceRunning()) {
      addLogAndPrint(
        .info,
        '快捷启动：云服务在线，请求交给服务后退出（${cli.launchVersionId}）',
        tag: 'Startup',
      );
      await GameSessionStore.writeRequest(
        versionId: cli.launchVersionId!,
        reason: 'ui_offline',
      );
      await _quitProcess();
      return;
    }
    addLog(.info, '快捷启动：没有 UI / 服务，本进程进入云服务模式', tag: 'Startup');
    await CloudServiceProcess.start(launchVersionId: cli.launchVersionId);
    return;
  }

  // 显式服务模式（UI 二次启动发现 / 接管 / 补上传）
  if (cli.service) {
    addLog(.info, '云服务：命令行要求进入服务模式', tag: 'Startup');
    await CloudServiceProcess.start(
      launchVersionId: cli.launchVersionId,
      adoptAll: cli.adoptAll,
      recover: cli.recover,
    );
    return;
  }

  // 普通 UI 启动 / 服务委托的 --resume-launch
  AppRuntime.headless = false;
  final launchRequest = cli.uiVersionId == null
      ? null
      : LaunchRequest(cli.uiVersionId!);
  final fromService = cli.resumeVersionId != null;
  if (!await _initSingleInctance(launchRequest)) return;

  await _initializeUi(launchRequest, fromService: fromService);
  try {
    await precacheStartupItem(config.setting.personalizationOptions.themeColor);
  } catch (_) {
    // 预解码失败不影响启动
  }
  runCopperLauncher();
}

/// 路径 / 日志 / 配置 / 网络：所有角色都要，服务模式也走这里
Future<void> _initializeCore() async {
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

  // 数据根从应用内部搬进外部专属目录（Android）：搬完才读配置，否则会读到空根上的默认值
  final migration = await DataRootMigration.runIfNeeded();
  final migrationSummary = migration?.describe();
  if (migrationSummary != null) {
    addLogAndPrint(.info, '数据根迁移：$migrationSummary', tag: 'Startup');
    if (migration!.failed.isNotEmpty && !AppRuntime.headless) {
      addNotice(
        icon: Icons.warning_amber_outlined,
        title: '旧数据没搬完',
        content:
            '有 ${migration.failed.length} 项没搬过去，日志里记了原因；'
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
}

///必要的基础初始化完成后即进入 app
Future<void> _initializeUi(
  LaunchRequest? launchRequest, {
  required bool fromService,
}) async {
  await _initPlatformView(quiet: false);
  //窗口就绪后应用托盘模式（依赖 config + windowManager）
  await LauncherTray.instance.applyMode();
  //后台初始化任务，不阻塞，进任务抽屉自跑
  addTask(StartupBackgroundTask());
  //在线状态：已登录就建连接，好友列表靠它判断「在线」
  MdtbbsPresenceService.instance;
  //账户通知：实时事件流优先（/realtime/v1），轮询兜底
  MdtbbsNotificationService.instance;
  //实时通道：好友请求 / 联机邀请一到就推，失败自动退避重连
  MdtbbsRealtimeService.instance;
  //启动即登录：读盘 → 拉一次资料（头像 / 用户名给顶栏与好友用），失败不打扰
  unawaited(_warmUpAccount());

  //系统分享进来的文件（安卓）：宿主已经把它们复制到缓存目录，
  //接线后与桌面拖入走同一条导入路；冷启动那次分享也在这里被取回来
  ShareIn.onFiles((files) => unawaited(_importSharedFiles(files)));
  await ShareIn.start();
  //桌面快捷方式「直接启动」：把冷启动那次请求取回来，启动器起来后拉起对应版本
  //
  //安卓上不等界面就绪：静默启动本来就不该让人看到界面，等 shell 只会白白多等 1 秒左右
  unawaited(
    ShortcutLaunch.start(
      waitForShell: Platform.isAndroid ? null : _waitForShell,
    ),
  );

  // UI 在线标记：快捷启动触发进程靠它决定「交给 UI」还是「自己进服务」
  await GameSessionStore.writeUiPid();

  //桌面端快捷启动：服务委托 / 正常启动都走这一个队列
  unawaited(QuickLaunch.start(waitForShell: _waitForShell));
  if (fromService) {
    // 服务已经写过 pending：以文件为准，避免同一个请求启动两次
    final tickets = await GameSessionStore.takePending();
    for (final ticket in tickets) {
      addLog(.info, '收到界面委托的启动请求 [${ticket.versionId}]（${ticket.reason}）', tag: 'QuickLaunch');
      QuickLaunch.enqueueVersion(ticket.versionId, markShortcut: false);
    }
    if (tickets.isEmpty && launchRequest != null) {
      QuickLaunch.enqueueVersion(
        launchRequest.versionId,
        markShortcut: false,
      );
    }
  } else if (launchRequest != null) {
    QuickLaunch.enqueue(launchRequest);
  }

  // UI 一直在线时，服务 / 触发进程把请求写进 pending，这里轮询接
  if (!Platform.isAndroid) {
    Timer.periodic(const Duration(milliseconds: 700), (_) {
      unawaited(_pollPending());
    });
  }
}

/// 读取服务 / 触发进程留给 UI 的启动请求
Future<void> _pollPending() async {
  final tickets = await GameSessionStore.takePending();
  for (final ticket in tickets) {
    addLog(
      .info,
      '快捷启动：界面收到待启动请求 [${ticket.versionId}]（${ticket.reason}）',
      tag: 'QuickLaunch',
    );
    QuickLaunch.enqueueVersion(ticket.versionId, markShortcut: false);
  }
}

/// 启动即登录：有落盘的账号就把它恢复出来，再拉一次资料
///
/// 之前只在进账户 / 联机页时才拉 `/me`，于是顶栏没头像、好友页要等一会儿才有名字。
/// 刚开机时常常还没连上网（`Failed host lookup`），所以失败会退避重试两次；
/// 仍然失败就只记日志 —— 离线启动也该能用启动器
Future<void> _warmUpAccount() async {
  final accounts = AccountManager.instance;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      await accounts.ensureRestored();
      if (!accounts.isLoggedIn) return;
      await accounts.loadAccount();
      return;
    } on Object catch (error) {
      addLog(
        .warning,
        '启动时恢复账号失败（第 $attempt 次）：${removeNewlines('$error')}',
        tag: 'Account',
      );
      if (attempt == 3) return;
      await Future.delayed(Duration(seconds: attempt == 1 ? 5 : 15));
    }
  }
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

Future<bool> _initSingleInctance(LaunchRequest? launchRequest) async {
  if (AppRuntime.headless) return true;
  // 单实例：该包在 Windows / Linux / macOS 都能判定
  if (!await FlutterSingleInstance().isFirstInstance()) {
    addLogAndPrint(
      .info,
      launchRequest == null ? '已有实例在运行，通知它显示窗口后退出' : '已有实例在运行，把快捷启动请求转给它后退出',
      tag: 'Startup',
    );
    final error = launchRequest == null
        ? await FlutterSingleInstance().focus()
        // 快捷启动不抢焦点、不弹出启动器窗口
        : await FlutterSingleInstance().focus(
            launchRequest.toMetadata(),
            false,
          );
    if (error != null) {
      addLogAndPrint(
        .warning,
        '唤醒已有实例失败：${removeNewlines(error)}',
        tag: 'Startup',
      );
    }
    // 留一点时间让上面的日志落盘
    await Future.delayed(const Duration(milliseconds: 200));
    await _quitProcess();
    return false;
  }
  // 第二个实例发来的请求：快捷启动交给 QuickLaunch，普通第二次启动把窗口叫回来
  FlutterSingleInstance.onFocus = (metadata) {
    final request = LaunchRequest.fromMetadata(metadata);
    if (request != null) {
      addLogAndPrint(.info, '收到快捷启动请求：${request.versionId}', tag: 'Startup');
      QuickLaunch.enqueue(request);
      return;
    }
    addLogAndPrint(.info, '收到第二次启动，显示主窗口（参数 $metadata）', tag: 'Startup');
    unawaited(LauncherTray.instance.showMainWindow());
  };
  return true;
}

/// 结束当前进程：Flutter 引擎里 exit(0) 之后进程会挂着不退
Future<void> _quitProcess() async {
  await Future.delayed(const Duration(milliseconds: 200));
  if (!Process.killPid(pid)) exit(0);
}

///平台视图初始化：桌面端建窗口，移动端设置系统 UI
Future<void> _initPlatformView({required bool quiet}) async {
  if (Platform.isAndroid) {
    await _initAndroidView();
  } else {
    await _initWindows(quiet: quiet);
  }
}

Future<void> _initWindows({required bool quiet}) async {
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(880, 495),
    minimumSize: Size(760, 450),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
  );

  if (quiet) {
    // 只应用窗口参数，不显示；快捷启动的界面由 runner 按参数跳过首帧显示。
    // 不要在这里 setSkipTaskbar(true)：窗口从没显示过，任务栏本来就没有按钮，
    // 删一次反而会让后面 show() 补不回来（表现为回到启动器后任务栏没图标）
    await windowManager.waitUntilReadyToShow(windowOptions, null);
    addLog(.info, '快捷启动：主窗口保持隐藏', tag: 'Startup');
    return;
  }

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
