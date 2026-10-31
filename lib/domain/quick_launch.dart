import 'dart:async';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/game_instance.dart';
import 'package:copper_launcher/domain/launch_request.dart';
import 'package:copper_launcher/domain/shortcut_session.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/launcher_tray.dart';
import 'package:flutter/material.dart' show Icons;

/// 桌面端快捷启动：等界面就绪后按版本 id 交给现有启动任务
///
/// 冷启动（进程带 `--launch-version`）与转发（单实例 metadata）都走这里；
/// 窗口是否可见由启动参数决定，这里只负责启动，不碰窗口。
class QuickLaunch {
  QuickLaunch._();

  static final List<String> _pendingVersionIds = [];
  static Future<bool> Function()? _waitForShell;
  static bool _started = false;
  static bool _handling = false;

  /// 启动时调一次；[request] 是本次进程自带的启动请求（可能为空）
  ///
  /// 必须在 `runCopperLauncher()` 之前调用（内部会等 shell），但调用方不该 await 它——
  /// 界面要靠后面的 `runCopperLauncher()` 才会建出来
  static Future<void> start({
    LaunchRequest? request,
    Future<bool> Function()? waitForShell,
  }) async {
    if (_started) return;
    _started = true;
    _waitForShell = waitForShell;
    if (request != null) _pendingVersionIds.add(request.versionId);
    await _drain();
  }

  /// 已运行实例收到快捷启动通知时入队
  static void enqueue(LaunchRequest request) {
    _pendingVersionIds.add(request.versionId);
    if (_started) unawaited(_drain());
  }

  static Future<void> _drain() async {
    if (_handling) return;
    _handling = true;
    try {
      while (_pendingVersionIds.isNotEmpty) {
        final versionId = _pendingVersionIds.removeAt(0);
        await _launch(versionId);
      }
    } finally {
      _handling = false;
    }
  }

  static Future<void> _launch(String versionId) async {
    final shellReady = await _waitForShell?.call() ?? true;
    if (!shellReady) {
      addLog(.warning, '快捷启动：界面没起来，忽略这次请求 [$versionId]', tag: 'QuickLaunch');
      return;
    }

    final version = config.versionOptions.findVersionById(versionId);
    if (version == null) {
      addLog(.warning, '快捷启动：找不到版本 $versionId', tag: 'QuickLaunch');
      await LauncherTray.instance.showMainWindow();
      addNotice(
        icon: Icons.error_outline,
        title: '快捷启动失败',
        content: '启动器里已经找不到这个版本；可能已经被删除，重新创建一个快捷方式',
      );
      return;
    }

    addLog(.info, '快捷启动：${version.tag}', tag: 'QuickLaunch');
    // 被游戏单实例 / 同数据目录规则拦住时，先让界面可见，GameInstance 的通知才有人看；
    // 这种没真正启动的请求不能打「快捷方式启动」标记，否则会影响之后正常退出的行为
    if (GameInstance.blockReason(version) != GameLaunchBlock.none) {
      await LauncherTray.instance.showMainWindow();
      await GameInstance.launch(version);
      return;
    }
    ShortcutSession.markLaunchedFromShortcut();
    await GameInstance.launch(version);
  }
}
