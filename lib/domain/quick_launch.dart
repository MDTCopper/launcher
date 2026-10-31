import 'dart:async';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/game_instance.dart';
import 'package:copper_launcher/domain/launch_request.dart';
import 'package:copper_launcher/domain/shortcut_session.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/launcher_tray.dart';
import 'package:flutter/material.dart' show Icons;

/// 一条待启动的请求
class QuickLaunchItem {
  QuickLaunchItem(this.versionId, {required this.markShortcut});

  final String versionId;

  /// true = 真正的快捷启动（退出时按「直接退出 / 唤起启动器」处理）
  ///
  /// 服务被阻塞后拉起的 UI 不算：这局结束后 UI 留在界面上
  final bool markShortcut;
}

/// 桌面端快捷启动：等界面就绪后按版本 id 交给现有启动任务
///
/// 冷启动（进程带 `--resume-launch`）、UI 在线转发、服务委托的请求都走这里；
/// 窗口是否可见由启动参数决定，这里只负责启动，不碰窗口。
class QuickLaunch {
  QuickLaunch._();

  static final List<QuickLaunchItem> _pending = [];
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
    bool markShortcut = true,
  }) async {
    if (_started) return;
    _started = true;
    _waitForShell = waitForShell;
    if (request != null) {
      _pending.add(
        QuickLaunchItem(request.versionId, markShortcut: markShortcut),
      );
    }
    await _drain();
  }

  /// 已运行实例收到快捷启动通知 / UI 读到 pending 文件时入队
  static void enqueue(LaunchRequest request, {bool markShortcut = true}) {
    _pending.add(QuickLaunchItem(request.versionId, markShortcut: markShortcut));
    if (_started) unawaited(_drain());
  }

  static void enqueueVersion(String versionId, {bool markShortcut = true}) {
    _pending.add(QuickLaunchItem(versionId, markShortcut: markShortcut));
    if (_started) unawaited(_drain());
  }

  static Future<void> _drain() async {
    if (_handling) return;
    _handling = true;
    try {
      while (_pending.isNotEmpty) {
        final item = _pending.removeAt(0);
        await _launch(item);
      }
    } finally {
      _handling = false;
    }
  }

  static Future<void> _launch(QuickLaunchItem item) async {
    final shellReady = await _waitForShell?.call() ?? true;
    if (!shellReady) {
      addLog(
        .warning,
        '快捷启动：界面没起来，忽略这次请求 [${item.versionId}]',
        tag: 'QuickLaunch',
      );
      return;
    }

    final version = config.versionOptions.findVersionById(item.versionId);
    if (version == null) {
      addLog(.warning, '快捷启动：找不到版本 ${item.versionId}', tag: 'QuickLaunch');
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
    if (item.markShortcut) ShortcutSession.markLaunchedFromShortcut();
    await GameInstance.launch(version);
  }
}
