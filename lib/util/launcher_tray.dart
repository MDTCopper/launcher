import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

///Launcher 托盘管理，仅桌面端
///
///按 config 的游戏启动后行为决定：
///- none：无行为，游戏照常，关闭窗口即退出
///- tray：启动游戏成功后把 Launcher 收进系统托盘（进程存活以监听游戏退出），
///  托盘菜单可恢复窗口 / 快速启动最近游玩 / 停止当前游戏（两步确认）/ 退出
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

  bool get trayMode => _trayMode;

  /// 窗口是否收起了（托盘 / 最小化）：shell 据此停掉动画，别在后台白耗 GPU
  final ValueNotifier<bool> isWindowHidden = ValueNotifier(false);

  ///关窗行为：收进托盘
  bool _closeToTray = false;

  ///托盘图标资源：Windows 的 `LoadImage` 只认 .ico，macOS/Linux 用 png
  String get _iconAsset => Platform.isWindows
      ? 'assets/images/app_icon.ico'
      : 'assets/images/logo.png';

  ///Linux 状态栏宿主的探测结果（null = 还没探过）
  static bool? _linuxTrayHost;

  ///托盘是否可用（给 UI 读的同步版本，用的是 [resolveTraySupport] 缓存下来的结果）。
  ///启动时 [applyMode] 会先探一次；在那之前 Linux 一律按不支持算
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
  ///老式 XEmbed 托盘（二进制里没有 `_NET_SYSTEM_TRAY`），所以问它就是这个库的完整判据。
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

  ///按 config 应用托盘模式
  Future<void> applyMode() async {
    final personalization = config.setting.personalizationOptions;
    final traySupported = await resolveTraySupport();
    //托盘不可用时两个托盘行为都按未开启算，否则关窗会把窗口藏进一个点不到的地方
    _closeToTray =
        traySupported &&
        personalization.windowCloseAction == WindowCloseAction.minimizeToTray;
    _trayMode =
        traySupported &&
        (_closeToTray ||
            personalization.launcherPostLaunchBehavior ==
                LauncherPostLaunchBehavior.tray);
    if (!isDesktop) return;

    addLog(
      .info,
      '托盘：图标${_trayMode ? '常驻' : '不常驻'}（关窗行为：${_closeToTray ? '收进托盘' : '退出程序'}）',
      tag: 'Tray',
    );

    await windowManager.setPreventClose(_closeToTray);

    if (_trayMode) {
      await trayManager.setIcon(_iconAsset);
      //Linux 的插件只实现了 setIcon / setTitle / setContextMenu / destroy，
      //没有 setToolTip，直接调会 MissingPluginException
      if (!Platform.isLinux) {
        await trayManager.setToolTip('Copper Launcher');
      }
      await _refreshMenu();
    } else {
      await trayManager.destroy();
    }
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
        MenuItem.checkbox(
          key: 'restore',
          label: '游戏退出后恢复窗口',
          checked:
              config.setting.personalizationOptions.restoreWindowOnGameExit,
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出'),
      ],
    );
  }

  ///是否有游戏正在运行
  bool _isGameRunning() => taskManager.currentTasks.any(
    (task) => task.type == TaskType.launch && task.status == TaskStatus.process,
  );

  ///最近游玩版本：取 lastLaunchTime 最新者；没有则回落当前选中版本。
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

  ///启动游戏成功后调用：托盘模式下收进托盘，其它模式无操作
  Future<void> hideIfTrayMode() async {
    if (!_trayMode) return;
    addLog(.info, '游戏已启动，启动器收进托盘', tag: 'Tray');
    isWindowHidden.value = true;
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
    await _refreshMenu(); //游戏运行中，菜单切到「停止当前游戏」
  }

  ///游戏退出后调用：托盘模式下若开启「恢复窗口」且窗口确已被收纳，则弹出主窗口
  Future<void> showIfRestoreOnExit() async {
    if (!_trayMode) return;
    final restore =
        config.setting.personalizationOptions.restoreWindowOnGameExit;
    if (!restore) return;
    //窗口仍可见则不再弹出，避免重复
    if (await windowManager.isVisible()) return;
    addLog(.info, '游戏已退出，恢复启动器窗口', tag: 'Tray');
    await _showFromTray();
  }

  Future<void> _showFromTray() async {
    isWindowHidden.value = false;
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setSkipTaskbar(false);
    await _refreshMenu();
  }

  ///把主窗口叫回来：托盘隐藏 / 最小化状态都能拉回前台
  ///
  ///单实例守护收到第二个实例的通知时调它
  Future<void> showMainWindow() async {
    if (!isDesktop) return;
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await _showFromTray();
  }

  ///从托盘快速启动最近游玩版本
  Future<void> _quickLaunchRecent() async {
    final version = _recentVersion();
    if (version == null || _isGameRunning()) return;
    addLog(.info, '托盘：启动最近游玩 [${version.tag}]', tag: 'Tray');
    addTask(LaunchMindustryTask(version));
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
    addLog(.info, '托盘：退出启动器', tag: 'Tray');
    await trayManager.destroy();
    await windowManager.destroy();
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
      case 'restore':
        final personalization = config.setting.personalizationOptions;
        personalization.restoreWindowOnGameExit =
            !personalization.restoreWindowOnGameExit;
        config.save();
        addLog(
          .info,
          '托盘：游戏退出后恢复窗口 → ${personalization.restoreWindowOnGameExit ? '开' : '关'}',
          tag: 'Tray',
        );
        _refreshMenu();
      case 'quit':
        quitApp();
    }
  }

  // WindowListener
  @override
  void onWindowClose() {
    if (_closeToTray) {
      addLog(.info, '关闭窗口：收进托盘（进程保留，继续监听游戏退出）', tag: 'Tray');
      isWindowHidden.value = true;
      windowManager.hide();
      windowManager.setSkipTaskbar(true);
    } else {
      addLog(.info, '关闭窗口：退出启动器', tag: 'Tray');
      trayManager.destroy();
    }
  }

  @override
  void onWindowMinimize() => isWindowHidden.value = true;

  @override
  void onWindowRestore() => isWindowHidden.value = false;
}
