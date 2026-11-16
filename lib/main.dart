import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_runtime.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/account/account_store.dart';
import 'package:copper_launcher/domain/bridge_installer.dart';
import 'package:copper_launcher/domain/cloud_service_process.dart';
import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/game_session_monitor.dart';
import 'package:copper_launcher/domain/launch_args.dart';
import 'package:copper_launcher/domain/launch_request.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_notification_service.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_presence_service.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_realtime_service.dart';
import 'package:copper_launcher/domain/quick_launch.dart';
import 'package:copper_launcher/domain/quick_launch_entry.dart';
import 'package:copper_launcher/domain/shortcut_launch.dart';
import 'package:copper_launcher/domain/sync_proxy.dart';
import 'package:copper_launcher/domain/sync_proxy_process.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/startup_background_task.dart';
import 'package:copper_launcher/ui/copper_launcher.dart';
import 'package:copper_launcher/ui/dialog/resource_importer.dart';
import 'package:copper_launcher/ui/sync_proxy/android_sync_proxy_page.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/generated/android_call.g.dart';
import 'package:copper_launcher/generated/android_event.g.dart';
import 'package:copper_launcher/util/data_root_migration.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/token_encryptor.dart';
import 'package:copper_launcher/util/launcher_icon.dart';
import 'package:copper_launcher/util/launcher_tray.dart';
import 'package:copper_launcher/util/share_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:window_manager/window_manager.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';

/// 初始化路径表；失败不静默崩：记日志，有界面时给一个可读的失败页
///
/// [withUi] 为 true 表示这是带界面的形态，失败后要把原因画出来
Future<bool> _initPaths({bool withUi = false}) async {
  try {
    await AppPaths.init();
    return true;
  } on Object catch (error) {
    final message = removeNewlines('$error');
    addLogAndPrint(.error, '数据目录初始化失败：$message', tag: 'Startup');
    stderr.writeln('数据目录初始化失败：$message');
    if (withUi) {
      runApp(_StartupFailureApp(message: message));
    }
    return false;
  }
}

/// 启动失败的兜底页：总比静默退出留一个黑窗口好
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.message});

  /// 失败原因
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  '启动失败：无法初始化数据目录',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SelectableText(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => exit(1),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main(List<String> args) async {
  AppRuntime.startedAt = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  final cli = LaunchArgs.parse(args);
  _checkPlatform();

  // 云同步代理：服务在启动前同步超过 3 秒才会拉起它；判在快捷启动之前，
  // 因为参数里也带 --launch-version，否则会被当成普通快捷启动
  if (args.contains('--sync-proxy')) {
    await SyncProxyProcess.start(versionId: cli.launchVersionId);
    return;
  }

  // 安卓桌面快捷方式：按出去方式决定要不要建 UI；不建 UI 时启动器只做宿主
  if (Platform.isAndroid && await AndroidCall.isSilentLaunch()) {
    await _runAndroidSilentShortcut(cli);
    return;
  }

  // 角色判定只做一次，具体执行分到三个 _run*，入口内不再混着读配置 / 建窗口
  if (cli.isQuickLaunch) {
    AppRuntime.form = AppForm.quickTrigger;
    AppRuntime.headless = true;
    await _runQuickLaunch(cli);
    return;
  }
  if (cli.service) {
    AppRuntime.form = AppForm.cloudService;
    AppRuntime.headless = true;
    await _runCloudService(cli);
    return;
  }
  AppRuntime.form = AppForm.launcherUi;
  AppRuntime.headless = false;
  await _runLauncherUi(cli);
}

/// 形态一：桌面快捷方式 / 启动脚本的触发进程
///
/// 只初始化路径 + 日志，判 UI / 服务是否在线；都不在才补完配置、本进程转为云服务。
Future<void> _runQuickLaunch(LaunchArgs cli) async {
  if (!await _initPaths()) return;
  await Log.init();
  addLog(
    .info,
    '时间线：快捷启动预检 +${AppRuntime.elapsedMs}ms（${AppRuntime.form.label}）',
    tag: 'Timeline',
  );
  final route = await QuickLaunchEntry.dispatch(
    LaunchRequest(cli.launchVersionId!),
  );
  switch (route) {
    case LaunchRoute.uiOnline:
      addLogAndPrint(
        .info,
        '快捷启动：UI 在线，请求交给界面后退出（${cli.launchVersionId}）',
        tag: 'Startup',
      );
      await _quitProcess();
      return;
    case LaunchRoute.serviceOnline:
      addLogAndPrint(
        .info,
        '快捷启动：云服务在线，请求交给服务后退出（${cli.launchVersionId}）',
        tag: 'Startup',
      );
      await _quitProcess();
      return;
    case LaunchRoute.android:
      // --launch-version 只在桌面出现；Android 走 ShortcutLaunch 宿主通道
      return;
    case LaunchRoute.startService:
      // 需要本进程接手：补完配置 / 网络初始化再进服务
      break;
  }
  if (!await _initializeCore(pathsReady: true, logReady: true)) return;
  AppRuntime.form = AppForm.cloudService;
  addLog(.info, '形态切换：触发进程转为无界面云服务', tag: 'Startup');
  await CloudServiceProcess.start(launchVersionId: cli.launchVersionId);
}

/// 安卓桌面快捷方式：桥已就绪且设置为「直接回桌面」时不建启动器 UI，
/// 只留宿主 Activity 把游戏拉起来；游戏退出后由 [ShortcutLaunch] 在后台传完再退出。
/// 需要回到启动器或还要装桥时仍走建 UI 的路径。
Future<void> _runAndroidSilentShortcut(LaunchArgs cli) async {
  AppRuntime.form = AppForm.quickTrigger;
  AppRuntime.headless = true;
  // 无界面形态也要画一帧：Flutter 不画首帧时 Android 的启动图会一直挂着
  runApp(const AndroidSyncProxyPage());
  await WidgetsBinding.instance.endOfFrame;
  if (!await _initPaths()) return;
  await Log.init();
  if (!await _initializeCore(pathsReady: true, logReady: true)) return;

  final online = await AndroidCall.isNetworkAvailable();
  final quickCloudSync =
      config.setting.personalizationOptions.quickLaunchCloudSync;
  // 上一次残留的代理状态会让本次页面误显示；先清掉
  await SyncProxyStore.clear();
  if (online && quickCloudSync) {
    // 先清掉上次残留的取消标记，再放「检查云端」占位状态
    final versionId = cli.launchVersionId ?? '';
    final startedAt = DateTime.now();
    try {
      await SyncProxyStore.writeStatus(
        SyncProxyStatus(
          versionId: versionId,
          phase: SyncProxyPhase.checking,
          startedAt: startedAt,
          updatedAt: startedAt,
          message: '检查云端存档',
        ),
      );
    } catch (_) {}
  }

  final action = config.setting.personalizationOptions.shortcutExitAction;
  if (action != ShortcutExitAction.backToHome ||
      !BridgeInstaller.isRuntimeReady()) {
    AppRuntime.form = AppForm.launcherUi;
    AppRuntime.headless = false;
    await _initializeUi(null, fromService: false);
    runCopperLauncher();
    return;
  }

  addLog(
    .info,
    '时间线：安卓静默快捷启动无界面模式 +${AppRuntime.elapsedMs}ms',
    tag: 'Timeline',
  );
  await AndroidCall.setHeadlessSilent();
  AndroidEvent.start();
  unawaited(ShortcutLaunch.start());
  unawaited(ShortcutLaunch.watchHeadless());
}

/// 形态二：无界面云存档服务（UI 二次启动 / 接管 / 补上传）
Future<void> _runCloudService(LaunchArgs cli) async {
  if (!await _initializeCore()) return;
  addLog(.info, '云服务：命令行要求进入服务模式', tag: 'Startup');
  await CloudServiceProcess.start(
    launchVersionId: cli.launchVersionId,
    adoptAll: cli.adoptAll,
    recover: cli.recover,
  );
}

/// 形态三：完整启动器 UI（含服务委托的 --resume-launch）
Future<void> _runLauncherUi(LaunchArgs cli) async {
  final launchRequest = cli.uiVersionId == null
      ? null
      : LaunchRequest(cli.uiVersionId!);
  final fromService = cli.resumeVersionId != null;

  // 先判单实例再读配置：第二个实例只写日志就退，不能并发改写 config
  if (!await _initPaths(withUi: true)) return;
  await Log.init();
  if (!await _initSingleInstance(launchRequest)) return;

  if (!await _initializeCore(pathsReady: true, logReady: true)) return;
  await _initializeUi(launchRequest, fromService: fromService);
  // 桌面图标跟配置里的主题对齐；headless 形态没有桌面入口，不调
  unawaited(applyLauncherIcon(config.setting.personalizationOptions.themeColor));
  runCopperLauncher();
}

/// 路径 / 日志 / 配置 / 网络：所有角色都要，服务模式也走这里
///
/// [pathsReady] / [logReady]：快捷启动预检已经初始化过路径与日志，别重复 init
/// 返回 false 表示路径初始化失败，调用方应直接收尾
Future<bool> _initializeCore({
  bool pathsReady = false,
  bool logReady = false,
}) async {
  if (!pathsReady) {
    _checkPlatform();
    if (!await _initPaths(withUi: !AppRuntime.headless)) return false;
  }
  if (!logReady) await Log.init();
  if (!logReady) {
    addLog(.info, '时间线：日志就绪 +${AppRuntime.elapsedMs}ms', tag: 'Timeline');
    addLog(.info, '启动器形态：${AppRuntime.form.label}', tag: 'Startup');
  }
  if (AppPaths.isUsingFallbackDataPath) {
    addLogAndPrint(
      .warning,
      Platform.isAndroid
          ? '拿不到外部应用目录，数据根留在应用内部：${AppPaths.copperLauncher}'
          : 'exe 目录不能放数据（系统目录或不可写），数据目录改用 ${AppPaths.copperLauncher}',
      tag: 'Startup',
    );
  }
  // 数据目录是排查「东西写到哪去了」的第一现场，每次启动都记下来
  addLog(.info, '数据根目录：${AppPaths.copperLauncher}', tag: 'Startup');
  addLog(.info, '游戏默认数据目录：${AppPaths.defaultGameData}', tag: 'Startup');
  addLog(.info, '时间线：基础路径就绪 +${AppRuntime.elapsedMs}ms', tag: 'Timeline');

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
  // 账号文件（refresh token）在 Android 上要从外部专属目录搬进 /data/data：
  // 先搬再读配置 / 账号，否则这一轮会按「未登录」处理
  await AccountStore.migrateLegacyLocation();
  await initAppConfig();
  addLog(.info, '时间线：配置就绪 +${AppRuntime.elapsedMs}ms', tag: 'Timeline');
  //config 就绪后同步网络设置（代理/token/限速/线程/镜像），此后新建请求即生效
  cio.applySettings(config.setting);
  addLog(
    .info,
    '网络设置：代理：${cio.proxyInfo}；'
    '镜像：${config.setting.mirrorOptions.enabled ? config.setting.mirrorOptions.strategy.name : '关闭'}；'
    'GitHub token：${config.setting.githubToken.isEmpty ? '未设置' : '已设置'}',
    tag: 'Startup',
  );
  return true;
}

/// 基础初始化完成后进入界面初始化
Future<void> _initializeUi(
  LaunchRequest? launchRequest, {
  required bool fromService,
}) async {
  await _initPlatformView();
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

  //宿主 → Dart 事件：先装通道 handler（非安卓平台它自己短路），之后各自取冷启动数据
  AndroidEvent.start();
  //系统分享进来的文件（安卓）：宿主已经把它们复制到缓存目录，
  //与桌面拖入走同一条导入路；冷启动那次分享也在这里被取回来
  ShareIn.onFiles((files) => unawaited(_importSharedFiles(files)));
  await ShareIn.start();
  //桌面快捷方式「直接启动」：把冷启动那次请求取回来，启动器起来后拉起对应版本
  unawaited(ShortcutLaunch.start());

  // UI 在线标记：快捷启动触发进程靠它决定「交给 UI」还是「自己进服务」
  await GameSessionStore.writeUiPid();
  // 心跳：崩溃/强杀后 pid 文件可能残留，时间戳用来判定 UI 是否真活着
  Timer.periodic(
    const Duration(seconds: 10),
    (_) => unawaited(GameSessionStore.writeUiPid()),
  );
  // 代理窗口可能正压在屏幕上：UI 已经起来就不需要它了
  await SyncProxyStore.closeIfRunning();
  // 发现服务进程正在管的局：接回任务抽屉；服务死了就补接管；done 记录导入游玩时长
  unawaited(GameSessionMonitor.instance.start());

  //桌面端快捷启动：服务委托 / 正常启动都走这一个队列
  unawaited(QuickLaunch.start(waitForShell: _waitForShell));
  if (fromService) {
    // 服务已经写过 pending：以文件为准，避免同一个请求启动两次
    final tickets = await GameSessionStore.takePending();
    for (final ticket in tickets) {
      addLog(
        .info,
        '收到界面委托的启动请求 [${ticket.versionId}]（${ticket.reason}）',
        tag: 'QuickLaunch',
      );
      QuickLaunch.enqueueVersion(ticket.versionId, markShortcut: false);
    }
    if (tickets.isEmpty && launchRequest != null) {
      QuickLaunch.enqueueVersion(launchRequest.versionId, markShortcut: false);
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

/// 启动即登录：有落盘的账号就恢复出来，再拉一次资料给顶栏与好友用
///
/// 刚开机时常常还没连上网（`Failed host lookup`），失败会退避重试两次；
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

/// 导入一份系统分享进来的文件
///
/// 导入弹窗挂在 shell 上（`showDefaultDialogPopup` 拿不到全局 Context 会直接抛），
/// 而冷启动那次分享远早于界面、安卓上还可能先停在环境配置页，所以等 shell 建出来再走
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

/// 等 shell 挂上 Context；最多 30 秒，等不到返回 false
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

Future<bool> _initSingleInstance(LaunchRequest? launchRequest) async {
  if (AppRuntime.headless) return true;
  // 插件默认 debugMode = kDebugMode，Debug 下会故意放行多实例；
  // 启动器必须单实例，否则两个 shell 会抢托盘/配置/会话
  FlutterSingleInstance.debugMode = false;
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

/// 平台视图初始化：桌面端建窗口，移动端设置系统 UI
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
    // 不要在这里 show：Windows runner 会在 Flutter 第一帧渲染完后才 Show；
    // 提前 show 会先露出窗口默认白底，Debug 下第一帧偏慢就会闪一道白光。
    // 这里只补一次焦点，窗口本身交给 runner 的首帧回调显示。
    await windowManager.focus();
  });
}

Future<void> _initAndroidView() async {
  //不锁方向：启动器跟随设备方向，游戏自己的 Activity 仍是 sensorLandscape
  //隐藏状态栏和导航栏
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}
