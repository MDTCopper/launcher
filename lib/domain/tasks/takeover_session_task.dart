import 'dart:async';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/cloud/cloud_auto_sync.dart';
import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/game_process_watch.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/launcher_tray.dart';
import 'package:flutter/material.dart';

/// UI 完全接管的一局：**继承 [LaunchMindustryTask]**，保证任务抽屉 / 托盘 / 单实例
/// 判断都把它当普通启动任务；只是 `runTask()` 不再去起游戏，而是监听已存在的游戏进程。
class TakeoverSessionTask extends LaunchMindustryTask {
  TakeoverSessionTask(this.session, super.mindustry);

  GameSession session;

  bool _cancelled = false;
  bool _finishing = false;
  bool _finished = false;
  bool _ownershipTransferred = false;

  @override
  bool get isExiting =>
      _finishing || _finished || _ownershipTransferred || super.isExiting;

  @override
  void transferOwnership() {
    _ownershipTransferred = true;
    super.transferOwnership();
  }

  @override
  int? get gamePid => session.gamePid;

  @override
  IconData get displayIcon => Icons.videogame_asset;

  @override
  String get displayTitle => '游戏运行中（已接管）';

  @override
  bool get canCancel => status == TaskStatus.process && !_cancelled;

  @override
  Widget buildDisplayWidget(BuildContext context) {
    final theme = Theme.of(context);
    final elapsed = DateTime.now().difference(session.startedAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(displayIcon, size: 32),
            const SizedBox(width: 4),
            Text(
              displayTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                mindustry.tag,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canCancel)
              ReboundButton(onTap: cancel, child: const Icon(Icons.close)),
          ],
        ),
        Text(
          _cancelled ? '正在结束游戏，结束后自动上传…' : '由启动器接管，退出后自动上传',
          style: theme.textTheme.bodyMedium,
        ),
        Text(
          '已运行 ${_formatElapsed(elapsed)}'
          '${session.gamePid == null ? '' : ' · 进程 ${session.gamePid}'}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  @override
  Future<void> runTask() async {
    final pid = session.gamePid;
    if (pid == null) {
      await _finishRun(0);
      return;
    }
    while (true) {
      if (!GameProcessWatch.isAlive(pid)) break;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    await _finishRun(DateTime.now().difference(session.startedAt).inSeconds);
  }

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final pid = session.gamePid;
    if (pid != null) {
      final killed = GameProcessWatch.kill(pid);
      addLog(
        killed ? .info : .warning,
        '接管任务：结束游戏进程 $pid（${killed ? '已发出结束' : '失败'}）',
        tag: 'CloudService',
      );
    }
    updateDisplay();
  }

  /// 游戏结束：上传 → 写游玩时长 → 按快捷启动退出设置收尾
  Future<void> _finishRun(int playSeconds) async {
    if (_finishing || _finished) return;
    if (_ownershipTransferred) {
      _finished = true;
      return;
    }
    _finishing = true;

    session
      ..phase = 'uploading'
      ..playSeconds = playSeconds;
    await GameSessionStore.save(session);

    await CloudAutoSync.afterGameExit(mindustry);
    await CloudAutoSync.waitForPending();

    final now = DateTime.now();
    mindustry.lastLaunchTime = now;
    mindustry.playTime =
        (mindustry.playTime ?? Duration.zero) + Duration(seconds: playSeconds);
    await config.save();

    session
      ..phase = 'done'
      ..completedAt = now;
    await GameSessionStore.save(session);
    await GameSessionStore.remove(session.id);

    addLog(
      .info,
      '接管任务：游戏退出，已上传并记录 [${mindustry.tag}]',
      tag: 'CloudService',
    );
    NotificationManager.addNotice(
      icon: Icons.check,
      title: '已接管并收尾',
      content: '${mindustry.tag} 已退出，云存档已上传',
    );

    // 快捷方式启动的局（无主 UI 时服务接的）退出后按设置去哪
    final action = config.setting.personalizationOptions.shortcutExitAction;
    if (action == ShortcutExitAction.backToHome) {
      await LauncherTray.instance.quitApp();
    } else {
      await LauncherTray.instance.showMainWindow();
    }

    _finished = true;
    _finishing = false;
    status = TaskStatus.completed;
    progress = 1;
    updateDisplay();
  }

  String _formatElapsed(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours} 小时 ${duration.inMinutes % 60} 分';
    }
    return '${duration.inMinutes} 分 ${duration.inSeconds % 60} 秒';
  }
}
