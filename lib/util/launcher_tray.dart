import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:copper_launcher/util/io/log.dart';
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

  ///关窗行为：收进托盘（否则直接退出）
  bool _closeToTray = false;

  ///托盘图标资源：Windows 的 `LoadImage` 只认 .ico，macOS/Linux 用 png
  String get _iconAsset => Platform.isWindows
      ? 'assets/images/app_icon.ico'
      : 'assets/images/logo.png';

  ///按 config 应用托盘模式
  Future<void> applyMode() async {
    final personalization = config.setting.personalizationOptions;
    _closeToTray =
        personalization.windowCloseAction == WindowCloseAction.minimizeToTray;
    _trayMode =
        isDesktop &&
        (_closeToTray ||
            personalization.launcherPostLaunchBehavior ==
                LauncherPostLaunchBehavior.tray);
    if (!isDesktop) return;
    //托盘行为都是"看不见的副作用"，生效条件与结果记一条，免得关窗没进托盘还得翻设置
    addLog(
      .info,
      '托盘模式：${_trayMode ? '常驻' : '关闭'}（关窗行为：${_closeToTray ? '收进托盘' : '退出程序'}）',
      tag: 'Tray',
    );

    //托盘常驻或关窗进托盘时，拦截关闭按钮（收进托盘），否则正常退出
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
    addLog(.info, '游戏已启动，启动器收进托盘', tag: 'Tray');
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

  /// 退出启动器（托盘菜单与「安装更新」共用：先销毁托盘再销毁窗口）
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
    //关窗进托盘 / 托盘模式下点关闭 → 收进托盘（进程保留监听游戏退出）
    if (_trayMode || _closeToTray) {
      addLog(.info, '关闭窗口：收进托盘（进程保留，继续监听游戏退出）', tag: 'Tray');
      windowManager.hide();
      windowManager.setSkipTaskbar(true);
    } else {
      addLog(.info, '关闭窗口：退出启动器', tag: 'Tray');
      trayManager.destroy();
    }
  }
}
