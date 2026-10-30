import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/mindustry/mindustry.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show Icons;
import 'package:path/path.dart' as p;

/// 这次启动被什么挡住了
enum GameLaunchBlock { none, anotherGameRunning, sameDataPath }

/// 游戏单实例
///
/// 只管启动器自己拉起、还在管的游戏；启动器管不到的进程不判定，玩家自己负责。
/// 设置里打开「多游戏运行」后可以同时开多个，但只能开**数据目录不同**的版本
class GameInstance {
  GameInstance._();

  /// 本会话里启动器正在管的游戏
  static List<Mindustry> get managedVersions =>
      (debugManagedOverride ?? _managedVersions)();

  static List<Mindustry> _managedVersions() => taskManager.currentTasks
      .whereType<LaunchMindustryTask>()
      .where((task) => task.status == TaskStatus.process)
      .map((task) => task.mindustry)
      .toList();

  /// 「多游戏运行」实际生效没有：安卓的游戏跑在桥的同一个进程里，
  /// 开第二个会把前一个顶掉，所以安卓一律不放行
  static bool get _multiGameEnabled =>
      config.setting.launchOptions.multiGame && !Platform.isAndroid;

  /// 两个游戏能不能同时跑：开了多游戏，且不吃同一份数据目录（会互相写存档）
  static bool canRunTogether(Mindustry running, Mindustry next) =>
      _multiGameEnabled && !sameDataPath(running, next);

  static bool sameDataPath(Mindustry a, Mindustry b) =>
      _normalizedDataPath(a) == _normalizedDataPath(b);

  static String _normalizedDataPath(Mindustry version) =>
      p.normalize(version.dataPath).toLowerCase();

  /// 启动前判定：没有冲突返回 [GameLaunchBlock.none]
  static GameLaunchBlock blockReason(Mindustry version) {
    final running = managedVersions;
    if (running.isEmpty) return GameLaunchBlock.none;
    if (!_multiGameEnabled) return GameLaunchBlock.anotherGameRunning;

    for (final other in running) {
      if (sameDataPath(other, version)) return GameLaunchBlock.sameDataPath;
    }
    return GameLaunchBlock.none;
  }

  /// 启动游戏：与启动器正在管的游戏冲突时只提示，不会起第二个
  static Future<void> launch(Mindustry version) async {
    final reason = blockReason(version);
    if (reason != GameLaunchBlock.none) {
      _notifyBlocked(reason);
      return;
    }
    (debugLaunchOverride ?? _addLaunchTask)(version);
  }

  static void _addLaunchTask(Mindustry version) =>
      addTask(LaunchMindustryTask(version));

  static void _notifyBlocked(GameLaunchBlock reason) {
    switch (reason) {
      case GameLaunchBlock.none:
        return;
      case GameLaunchBlock.anotherGameRunning:
        addLog(.info, '已有游戏在运行，不再启动新实例', tag: 'Launch');
        NotificationManager.addNotice(
          icon: Icons.info_outline,
          title: '游戏已在运行',
          content: '同一时间只能开一个游戏；想同时开多个，可在设置的高级选项里打开「多游戏运行」',
          duration: const Duration(seconds: 8),
        );
      case GameLaunchBlock.sameDataPath:
        addLog(.info, '这个版本与正在跑的游戏共用数据目录，不再启动', tag: 'Launch');
        NotificationManager.addNotice(
          icon: Icons.info_outline,
          title: '两个游戏不能共用一份存档',
          content: '这个版本与正在运行的版本用的是同一个数据目录；先退出那个游戏，或给这个版本打开隔离数据目录',
          duration: const Duration(seconds: 8),
        );
    }
  }

  @visibleForTesting
  static List<Mindustry> Function()? debugManagedOverride;

  @visibleForTesting
  static void Function(Mindustry version)? debugLaunchOverride;
}
