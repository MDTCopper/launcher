import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/util/io/os.dart';
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

  ///停止当前游戏是否已点过一次（第二步才真正停止，防误触）
  bool _confirmStopArmed = false;

  bool get trayMode => _trayMode;

  ///托盘图标资源：Windows 的 `LoadImage` 只认 .ico，macOS/Linux 用 png
  String get _iconAsset => Platform.isWindows
      ? 'assets/images/app_icon.ico'
      : 'assets/images/logo.png';

  ///按 config 应用托盘模式
  Future<void> applyMode() async {
    _trayMode =
        isDesktop &&
        config.setting.personalizationOptions.launcherPostLaunchBehavior ==
            LauncherPostLaunchBehavior.tray;
    if (!isDesktop) return;

    //托盘模式下关闭窗口不退出（收进托盘），否则正常退出
    await windowManager.setPreventClose(_trayMode);

    if (_trayMode) {
      await trayManager.setIcon(_iconAsset);
      await trayManager.setToolTip('Copper Launcher');
      await _refreshMenu();
    } else {
      await trayManager.destroy();
    }
  }

  ///重建托盘菜单（反映游戏运行状态 / 两步确认 / 勾选项）
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

  ///是否有游戏正在运行（启动任务处于 process 状态）。
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
    await _showFromTray();
  }

  Future<void> _showFromTray() async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setSkipTaskbar(false);
    await _refreshMenu();
  }

  ///把主窗口叫回来：托盘隐藏 / 最小化状态都能拉回前台
  ///
  ///单实例守护收到第二个实例的通知时调它（用户又点了图标）
  Future<void> showMainWindow() async {
    if (!isDesktop) return;
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await _showFromTray();
  }

  ///从托盘快速启动最近游玩版本（游戏已在跑则不动作）
  Future<void> _quickLaunchRecent() async {
    final version = _recentVersion();
    if (version == null || _isGameRunning()) return;
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
      _refreshMenu();
      return;
    }
    _confirmStopArmed = false;
    running.first.cancel();
    _refreshMenu();
  }

  Future<void> _quit() async {
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
        _refreshMenu();
      case 'quit':
        _quit();
    }
  }

  // WindowListener
  @override
  void onWindowClose() {
    //托盘模式下点关闭 → 收进托盘（进程保留监听游戏退出）
    if (_trayMode) {
      windowManager.hide();
      windowManager.setSkipTaskbar(true);
    } else {
      trayManager.destroy();
    }
  }
}
