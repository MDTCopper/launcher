import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/mindustry/mindustry.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/game_process_watch.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show Icons;

/// 游戏单实例：同一时间只允许一个游戏在跑
///
/// 两条判据：本会话里还没收尾的启动任务，以及系统里已经在跑的游戏进程
/// （启动脚本启动的、启动器重启前启动的都算）。命中时只提示，不动正在玩的游戏
class GameInstance {
  GameInstance._();

  /// 上一次点击还在判定中：连点不重复起任务
  static bool _starting = false;

  /// 本会话里有没有还没收尾的游戏
  static bool get sessionGameRunning =>
      (debugSessionProbe ?? _sessionGameRunning)();

  static bool _sessionGameRunning() => taskManager.currentTasks.any(
    (task) => task is LaunchMindustryTask && task.status == TaskStatus.process,
  );

  /// 系统里有没有游戏进程在跑；查不出来按没有处理
  static Future<bool> systemGameRunning() async {
    // 安卓的游戏由桥跑在本应用的 :mdt_process 里，正常退出后那个进程会留在原地
    // （下次启动才清），光看进程会误判 ⇒ 只认本会话的启动任务
    if (Platform.isAndroid) return false;

    final probe = debugSystemProbe;
    if (probe != null) return probe();

    final running = await GameProcessWatch.findRunningGame(installedJarPaths());
    if (running == null) {
      addLog(.warning, '查不了系统里的游戏进程，这次不做单实例拦截', tag: 'Launch');
      return false;
    }
    return running;
  }

  /// 启动器记录里的全部游戏本体路径：游戏进程按它认人
  static Set<String> installedJarPaths() {
    final paths = <String>{};
    for (final fold in config.versionOptions.versionFolds) {
      for (final version in fold.versions) {
        final path = version.resolvedJarPath;
        if (path.isNotEmpty) paths.add(path);
      }
    }
    return paths;
  }

  /// 启动游戏：已有游戏在跑就只提示，不会起第二个
  static Future<void> launch(Mindustry version) async {
    if (_starting) return;
    _starting = true;
    try {
      if (sessionGameRunning || await systemGameRunning()) {
        _notifyAlreadyRunning();
        return;
      }
      (debugLaunchOverride ?? _addLaunchTask)(version);
    } finally {
      _starting = false;
    }
  }

  static void _addLaunchTask(Mindustry version) =>
      addTask(LaunchMindustryTask(version));

  static void _notifyAlreadyRunning() {
    addLog(.info, '游戏已在运行，不再启动新实例', tag: 'Launch');
    NotificationManager.addNotice(
      icon: Icons.info_outline,
      title: '游戏已在运行',
      content: '同一时间只能启动一个游戏；先退出当前游戏再启动',
      duration: const Duration(seconds: 8),
    );
  }

  @visibleForTesting
  static bool Function()? debugSessionProbe;

  @visibleForTesting
  static Future<bool> Function()? debugSystemProbe;

  @visibleForTesting
  static void Function(Mindustry version)? debugLaunchOverride;
}
