import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

///Launcher 托盘管理（仅桌面端）。
///
///按 config 的「游戏启动后行为」决定：
///- none：无行为，游戏照常，关闭窗口即退出
///- tray：启动游戏成功后把 Launcher 收进系统托盘（进程存活以监听游戏退出），
///  托盘图标可恢复窗口 / 退出
class LauncherTray extends TrayListener with WindowListener {
  LauncherTray._() {
    trayManager.addListener(this);
    windowManager.addListener(this);
  }

  static final LauncherTray instance = LauncherTray._();

  bool _trayMode = false;

  bool get trayMode => _trayMode;

  ///托盘图标资源：Windows 的 `LoadImage` 只认 .ico，macOS/Linux 用 png
  String get _iconAsset => Platform.isWindows
      ? 'assets/images/app_icon.ico'
      : 'assets/images/logo.png';

  ///按 config 应用托盘模式（启动时与设置页改动时调用）。
  Future<void> applyMode() async {
    _trayMode = isDesktop &&
        config.setting.personalizationOptions.launcherPostLaunchBehavior ==
            LauncherPostLaunchBehavior.tray;
    if (!isDesktop) return;

    //托盘模式下关闭窗口不退出（收进托盘），否则正常退出
    await windowManager.setPreventClose(_trayMode);

    if (_trayMode) {
      await trayManager.setIcon(_iconAsset);
      await trayManager.setToolTip('Copper Launcher');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: '显示主窗口'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出'),
      ]));
    } else {
      await trayManager.destroy();
    }
  }

  ///启动游戏成功后调用：托盘模式下收进托盘，其它模式无操作。
  Future<void> hideIfTrayMode() async {
    if (!_trayMode) return;
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  ///游戏退出后调用：托盘模式下若开启「恢复窗口」则弹出主窗口。
  Future<void> showIfRestoreOnExit() async {
    if (!_trayMode) return;
    final restore = config
        .setting
        .personalizationOptions
        .restoreWindowOnGameExit;
    if (restore) await _showFromTray();
  }

  Future<void> _showFromTray() async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setSkipTaskbar(false);
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
