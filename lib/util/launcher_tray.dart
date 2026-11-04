import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_runtime.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/cloud/cloud_auto_sync.dart';
import 'package:copper_launcher/domain/game_instance.dart';
import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/session_ownership.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/cloud_sync_task.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

///Launcher 托盘管理，仅桌面端
///
///按 config 的启动器行为决定：
///- 关闭窗口：没有游戏运行时按 [WindowCloseAction]，有游戏运行时按
///  [GameRunningCloseAction]；要退出的那档先把运行中的游戏交接给云服务
///- 游戏启动后：none 无行为、closeKeepService 退出并保留云服务、
///  minimizeToTray 收进系统托盘（游戏退出后恢复窗口）
///
///托盘是原生系统元素，只能自定义图标、tooltip 与原生菜单
class LauncherTray extends TrayListener with WindowListener {
  LauncherTray._() {
    trayManager.addListener(this);
    windowManager.addListener(this);
  }

  static final LauncherTray instance = LauncherTray._();

  bool _trayMode = false;

  ///停止当前游戏是否已点过一次
  bool _confirmStopArmed = false;

  /// 云存档在传时用的菜单刷新节拍：托盘菜单是**静态**的（原生菜单），
  /// 不主动重建就看不到进度变化
  Timer? _cloudSyncMenuTimer;
  StreamSubscription<List<Task>>? _taskSubscription;

  bool get trayMode => _trayMode;

  /// 窗口是否收起了（托盘 / 最小化）：shell 据此停掉动画，别在后台白耗 GPU
  final ValueNotifier<bool> isWindowHidden = ValueNotifier(false);

  ///关窗行为：没有游戏运行时收进托盘
  bool _closeToTray = false;

  ///关窗行为：游戏运行时收进托盘
  bool _gameRunningCloseToTray = false;

  ///游戏启动后收进托盘（游戏退出后恢复窗口）
  bool _postLaunchToTray = false;

  ///托盘图标资源：Windows 的 `LoadImage` 只认 .ico，macOS/Linux 用 png
  String get _iconAsset => Platform.isWindows
      ? 'assets/images/app_icon.ico'
      : 'assets/images/app_icon.png';

  ///Linux 状态栏宿主的探测结果（null = 还没探过）
  static bool? _linuxTrayHost;

  ///托盘是否可用（给 UI 读的同步版本，用的是 [resolveTraySupport] 缓存下来的结果）；
  ///启动时 [applyMode] 会先探一次，在那之前 Linux 一律按不支持算
  static bool get traySupported {
    if (!isDesktop) return false;
    if (!Platform.isLinux) return true;
    return _linuxTrayHost ?? false;
  }

  ///托盘是否可用。Windows / macOS 的插件实现是完整的；Linux 要问会话总线上有没有
  ///状态栏宿主 —— 没有宿主时 `setIcon` 不报错、图标只是不出现，窗口收进去就叫不回来
  static Future<bool> resolveTraySupport() async {
    if (!isDesktop || !Platform.isLinux) return traySupported;
    return _linuxTrayHost ??= await _probeLinuxTrayHost();
  }

  ///问 D-Bus 有没有状态栏宿主。`libayatana-appindicator` 走 StatusNotifierItem 协议，
  ///宿主（面板）会在 watcher 上把 [IsStatusNotifierHostRegistered] 置真；这个库不支持
  ///老式 XEmbed 托盘（二进制里没有 `_NET_SYSTEM_TRAY`），所以问它就是这个库的完整判据；
  ///命令行客户端依次试 glib / dbus / systemd 三家的，都没有就当不支持
  static Future<bool> _probeLinuxTrayHost() async {
    const probes = <(String, List<String>)>[
      (
        'gdbus',
        [
          'call',
          '--session',
          '--dest',
          'org.kde.StatusNotifierWatcher',
          '--object-path',
          '/StatusNotifierWatcher',
          '--method',
          'org.freedesktop.DBus.Properties.Get',
          'org.kde.StatusNotifierWatcher',
          'IsStatusNotifierHostRegistered',
        ],
      ),
      (
        'dbus-send',
        [
          '--session',
          '--print-reply',
          '--dest=org.kde.StatusNotifierWatcher',
          '/StatusNotifierWatcher',
          'org.freedesktop.DBus.Properties.Get',
          'string:org.kde.StatusNotifierWatcher',
          'string:IsStatusNotifierHostRegistered',
        ],
      ),
      (
        'busctl',
        [
          '--user',
          'get-property',
          'org.kde.StatusNotifierWatcher',
          '/StatusNotifierWatcher',
          'org.kde.StatusNotifierWatcher',
          'IsStatusNotifierHostRegistered',
        ],
      ),
    ];

    for (final (executable, arguments) in probes) {
      final ProcessResult result;
      try {
        result = await Process.run(
          executable,
          arguments,
        ).timeout(const Duration(seconds: 2));
      } on ProcessException {
        continue; //这台机器没装这个命令，换下一个
      } catch (_) {
        return false; //超时等：问不出来就按不支持
      }
      //能跑起来的客户端就是权威答案：名字不存在时 gdbus 只把错误写 stderr、
      //stdout 为空，读不出结论即「没有宿主」
      return parseTrayProbeOutput('${result.stdout}') ?? false;
    }
    return false;
  }

  ///从探测命令的输出里读结论：`gdbus` 给 `<true>`、`dbus-send` 给 `boolean true`、
  ///`busctl` 给 `b true`，读不出结论返回 null
  @visibleForTesting
  static bool? parseTrayProbeOutput(String stdout) {
    if (stdout.contains('true')) return true;
    if (stdout.contains('false')) return false;
    return null;
  }

  /// 快捷启动的隐藏窗口会话：托盘先不常驻，需要露面时再恢复用户设置
  bool _quietMode = false;

  /// 关窗 / 退出流程只走一次：先交接给云服务再真正退出
  bool _closing = false;

  ///按 config 应用托盘模式
  ///
  ///[quiet] 给快捷启动用：不建托盘图标、不接管关窗行为，窗口由 runner 侧保持隐藏；
  ///之后 [showMainWindow] 会把用户设置恢复回来
  Future<void> applyMode({bool quiet = false}) async {
    _quietMode = quiet;
    if (quiet) {
      _trayMode = false;
      _closeToTray = false;
      _gameRunningCloseToTray = false;
      _postLaunchToTray = false;
      _cloudSyncMenuTimer?.cancel();
      _cloudSyncMenuTimer = null;
      await _taskSubscription?.cancel();
      _taskSubscription = null;
      await windowManager.setPreventClose(false);
      await trayManager.destroy();
      addLog(.info, '快捷启动：托盘暂不常驻', tag: 'Tray');
      return;
    }

    final personalization = config.setting.personalizationOptions;
    final traySupported = await resolveTraySupport();
    //托盘不可用时所有托盘行为都按未开启算，否则关窗会把窗口藏进一个点不到的地方
    _closeToTray =
        traySupported &&
        personalization.windowCloseAction == WindowCloseAction.minimizeToTray;
    _gameRunningCloseToTray =
        traySupported &&
        personalization.gameRunningCloseAction ==
            GameRunningCloseAction.minimizeToTray;
    _postLaunchToTray =
        traySupported &&
        personalization.launcherPostLaunchBehavior ==
            LauncherPostLaunchBehavior.minimizeToTray;
    _trayMode =
        traySupported &&
        (_closeToTray || _gameRunningCloseToTray || _postLaunchToTray);
    if (!isDesktop) return;

    addLog(
      .info,
      '托盘：图标${_trayMode ? '常驻' : '不常驻'}'
      '（关窗：${_closeToTray ? '收进托盘' : '退出程序'}，'
      '游戏运行中关窗：${_gameRunningCloseToTray ? '收进托盘' : '退出并保留云服务'}）',
      tag: 'Tray',
    );

    // 关窗由 onWindowClose 接管：先交接正在跑的游戏给云服务，再决定隐藏还是退出。
    // 不能只按 _closeToTray 设 preventClose —— 否则关窗时进程会在交接完成前退出
    await windowManager.setPreventClose(true);

    if (_trayMode) {
      await trayManager.setIcon(_iconAsset);
      //Linux 的插件只实现了 setIcon / setTitle / setContextMenu / destroy，
      //没有 setToolTip，直接调会 MissingPluginException
      if (!Platform.isLinux) {
        await trayManager.setToolTip('Copper Launcher');
      }
      await _refreshMenu();
      _watchCloudSyncTasks();
    } else {
      _cloudSyncMenuTimer?.cancel();
      _cloudSyncMenuTimer = null;
      await _taskSubscription?.cancel();
      _taskSubscription = null;
      await trayManager.destroy();
    }
  }

  /// 盯着任务：有云存档在传时每秒重建一次托盘菜单
  ///
  /// 抽屉那边是实时刷新的，托盘只能这样（菜单一旦设好就不会再变）
  void _watchCloudSyncTasks() {
    _taskSubscription ??= taskManager.stream.listen((tasks) {
      final running = tasks.any(
        (task) => task is CloudSyncTask && task.status == TaskStatus.process,
      );
      if (!running) return;
      _cloudSyncMenuTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        final stillRunning = taskManager.currentTasks.any(
          (task) => task is CloudSyncTask && task.status == TaskStatus.process,
        );
        if (!stillRunning) {
          _cloudSyncMenuTimer?.cancel();
          _cloudSyncMenuTimer = null;
        }
        unawaited(_refreshMenu());
      });
    });
  }

  /// 正在跑的云存档同步压成一行（没有就 null）
  String? _cloudSyncLabel() {
    for (final task in taskManager.currentTasks) {
      if (task is! CloudSyncTask || task.status != TaskStatus.process) continue;
      final percent = task.progress == null
          ? ''
          : ' ${(task.progress! * 100).toStringAsFixed(0)}%';
      return task.direction == CloudSyncDirection.upload
          ? '云存档上传中$percent'
          : '云存档恢复中$percent';
    }
    return null;
  }

  ///重建托盘菜单
  Future<void> _refreshMenu() async {
    await trayManager.setContextMenu(_buildMenu());
  }

  Menu _buildMenu() {
    final gameRunning = _isGameRunning();
    if (!gameRunning) _confirmStopArmed = false;
    final hasRecent = _recentVersion() != null;

    return Menu(
      items: [
        MenuItem(key: 'show', label: '显示主窗口'),
        MenuItem.separator(),
        MenuItem(
          key: 'quickLaunch',
          label: '启动最近游玩',
          disabled: gameRunning || !hasRecent,
        ),
        if (gameRunning)
          MenuItem(
            key: 'stop',
            label: _confirmStopArmed ? '再次点击确认停止游戏' : '停止当前游戏',
          ),
        MenuItem.separator(),
        // 云存档在传时给一行进度（只读）—— 托盘里以前什么都看不到
        if (_cloudSyncLabel() case final cloudSync?) ...[
          MenuItem(key: 'cloudSync', label: cloudSync, disabled: true),
          MenuItem.separator(),
        ],
        MenuItem(key: 'quit', label: '退出'),
      ],
    );
  }

  ///是否有游戏正在运行
  bool _isGameRunning() => taskManager.currentTasks.any(
    (task) =>
        task is LaunchMindustryTask && task.status == TaskStatus.process,
  );

  ///最近游玩版本：取 lastLaunchTime 最新者；没有则回落当前选中版本
  Mindustry? _recentVersion() {
    final all = config.versionOptions.versionFolds.expand(
      (fold) => fold.versions,
    );
    Mindustry? recent;
    for (final version in all) {
      final time = version.lastLaunchTime;
      if (time != null &&
          (recent?.lastLaunchTime == null ||
              time.isAfter(recent!.lastLaunchTime!))) {
        recent = version;
      }
    }
    return recent ?? config.versionOptions.selectedVersion;
  }

  ///游戏启动成功后调用：按「游戏启动后」的行为处理启动器
  Future<void> hideIfTrayMode() async {
    //无界面服务与移动端没有窗口 / 托盘；快捷启动的隐藏会话由 ShortcutExitAction 收尾
    if (!isDesktop || AppRuntime.headless || _quietMode) return;
    switch (config.setting.personalizationOptions.launcherPostLaunchBehavior) {
      case LauncherPostLaunchBehavior.none:
        return;
      case LauncherPostLaunchBehavior.closeKeepService:
        addLog(.info, '游戏已启动，启动器退出并保留云服务', tag: 'Tray');
        await _closeAfterHandoff();
      case LauncherPostLaunchBehavior.minimizeToTray:
        if (!_postLaunchToTray) return;
        addLog(.info, '游戏已启动，启动器收进托盘', tag: 'Tray');
        await _hideToTray();
    }
  }

  ///游戏退出后调用：游戏启动后收进托盘的那档把主窗口恢复回来
  Future<void> showIfRestoreOnExit() async {
    if (!_postLaunchToTray) return;
    //窗口仍可见则不再弹出，避免重复
    if (await windowManager.isVisible()) return;
    addLog(.info, '游戏已退出，恢复启动器窗口', tag: 'Tray');
    await _showFromTray();
  }

  ///收进系统托盘，菜单切到「游戏运行中」状态
  Future<void> _hideToTray() async {
    isWindowHidden.value = true;
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
    await _refreshMenu();
  }

  Future<void> _showFromTray() async {
    isWindowHidden.value = false;
    // 先补任务栏按钮再显示，ShowWindowAsync 是异步的，显示完再补一次；
    // 只补一次时偶发「窗口出来了但任务栏没图标」
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await windowManager.setSkipTaskbar(false);
    await _refreshMenu();
  }

  ///把主窗口叫回来：托盘隐藏 / 最小化状态都能拉回前台
  ///
  ///单实例守护收到第二个实例的通知时调它；快捷启动的隐藏会话也靠它露出界面
  Future<void> showMainWindow() async {
    if (!isDesktop) return;
    if (_quietMode) {
      // 快捷启动期间没建托盘；现在要显示界面了，按用户设置恢复
      await applyMode();
    }
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await _showFromTray();
  }

  /// 需要弹窗 / 出错时保证主窗口可见（快捷启动的隐藏会话专用）
  ///
  /// 已经可见时不打扰；隐藏时走 [showMainWindow]（会恢复托盘设置）
  Future<void> ensureVisibleForPrompt() async {
    if (!isDesktop) return;
    // 无界面服务：窗口不存在，交给 CloudServiceProcess 拉起 UI
    if (AppRuntime.headless) return;
    if (await windowManager.isVisible()) return;
    await showMainWindow();
  }

  ///从托盘快速启动最近游玩版本
  Future<void> _quickLaunchRecent() async {
    final version = _recentVersion();
    if (version == null || _isGameRunning()) return;
    addLog(.info, '托盘：启动最近游玩 [${version.tag}]', tag: 'Tray');
    await GameInstance.launch(version);
    //窗口本就在托盘隐藏状态，无需再收进；刷新菜单反映运行状态
    await _refreshMenu();
  }

  ///停止当前游戏：两步确认
  void _stopCurrentGame() {
    final running = taskManager.currentTasks
        .whereType<LaunchMindustryTask>()
        .where((task) => task.status == TaskStatus.process)
        .toList();
    if (running.isEmpty) return;

    if (!_confirmStopArmed) {
      _confirmStopArmed = true;
      addLog(.info, '托盘：请求停止当前游戏，等待二次确认', tag: 'Tray');
      _refreshMenu();
      return;
    }
    _confirmStopArmed = false;
    addLog(.info, '托盘：确认停止当前游戏', tag: 'Tray');
    running.first.cancel();
    _refreshMenu();
  }

  /// 退出启动器
  Future<void> quitApp() async {
    if (_closing) return;
    _closing = true;
    _armCloseWatchdog(const Duration(seconds: 2));
    addLog(.info, '托盘：退出启动器', tag: 'Tray');
    await _handoffBounded();
    await _waitPendingBounded();
    await _destroyWindow();
  }

  /// 关窗回调里可能卡在某个 await 上；这个看门狗保证进程一定退出
  void _armCloseWatchdog(Duration delay) {
    Timer(delay, () {
      if (Process.killPid(pid)) {
        addLog(.warning, '退出看门狗：${delay.inMilliseconds}ms 后强制结束进程', tag: 'Tray');
      }
    });
  }

  /// 关窗 / 游戏启动后关闭启动器：交接游戏 → 等上传 → 真正销毁窗口
  Future<void> _closeAfterHandoff() async {
    if (_closing) return;
    _closing = true;
    addLog(.info, '退出启动器：先交接运行中的游戏', tag: 'Tray');
    try {
      await _handoffBounded();
      await _waitPendingBounded();
    } finally {
      await _destroyWindow();
    }
  }

  /// 交接必须有上限：服务/文件 IO 卡住时不能让 UI 一直无响应
  Future<void> _handoffBounded() async {
    try {
      await SessionOwnership.handoffToService().timeout(
        const Duration(seconds: 4),
      );
      addLog(.info, '退出：游戏交接完成', tag: 'Tray');
    } catch (error) {
      addLog(.warning, '退出：游戏交接超时/失败（继续关窗）：$error', tag: 'Tray');
    }
  }

  /// 等云存档自动上传完成，但最多等 4 秒；超时先关窗，服务侧继续收尾
  Future<void> _waitPendingBounded() async {
    try {
      await CloudAutoSync.waitForPending().timeout(
        const Duration(seconds: 4),
      );
      addLog(.info, '退出：存档上传等待完成', tag: 'Tray');
    } catch (error) {
      addLog(.warning, '退出：等存档上传超时（继续关窗）：$error', tag: 'Tray');
    }
  }

  Future<void> _destroyWindow() async {
    addLog(.info, '退出：销毁窗口（直接结束进程）', tag: 'Tray');
    // 先清掉 UI 在线标记，避免 pid 复用让下一次快捷启动误判 UI 还在
    try {
      await GameSessionStore.clearUiPid();
    } catch (_) {}
    // windowManager.destroy() 在 Windows 上会卡在引擎 teardown（实测 10s+），
    // 交接与上传已经做完，这里直接结束进程，窗口随进程一起消失
    if (Process.killPid(pid)) return;

    try {
      await windowManager.setPreventClose(false).timeout(
        const Duration(seconds: 1),
      );
    } catch (_) {}
    try {
      await trayManager.destroy().timeout(const Duration(seconds: 1));
    } catch (_) {}
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        Process.killPid(pid);
      }),
    );
    try {
      await windowManager.destroy().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  // TrayListener
  @override
  void onTrayIconMouseDown() {
    //Windows 左键单击恢复窗口
    _showFromTray();
  }

  @override
  void onTrayIconRightMouseDown() {
    //Linux 的插件也没有 popUpContextMenu，菜单由状态栏宿主自己弹
    if (Platform.isLinux) return;
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showFromTray();
      case 'quickLaunch':
        _quickLaunchRecent();
      case 'stop':
        _stopCurrentGame();
      case 'quit':
        quitApp();
    }
  }

  // WindowListener
  @override
  void onWindowClose() {
    if (_closing) return;
    //有游戏在跑时按「游戏运行时关闭窗口」的行为，否则按普通关窗行为
    final toTray = _isGameRunning() ? _gameRunningCloseToTray : _closeToTray;
    if (toTray) {
      addLog(.info, '关闭窗口：收进托盘（进程保留，继续监听游戏退出）', tag: 'Tray');
      unawaited(_hideToTray());
    } else {
      // 游戏还在跑：先写会话 + 拉起云服务接管，交接完再销毁窗口
      // 看门狗要晚于交接（4s）+ 等上传（4s）完成；正常路径几百毫秒就退了
      _armCloseWatchdog(const Duration(seconds: 10));
      unawaited(_closeAfterHandoff());
    }
  }

  @override
  void onWindowMinimize() => isWindowHidden.value = true;

  @override
  void onWindowRestore() => isWindowHidden.value = false;
}
