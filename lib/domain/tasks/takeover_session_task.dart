import 'dart:async';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/mindustry/mindustry.dart';
import 'package:copper_launcher/domain/cloud/cloud_auto_sync.dart';
import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/game_process_watch.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/launcher_tray.dart';
import 'package:flutter/material.dart';

/// UI 完全接管的一局：服务把所有权交出来后，退出上传 / 游玩时长 / 退出行为都在 UI 做
///
/// 与 [RemoteSessionTask] 的区别：这是**真任务**，拥有一条完整的收尾链；
/// 服务已经退位，不会再重复上传。
class TakeoverSessionTask extends Task {
  TakeoverSessionTask(this.session, this.version)
    : super(id: 'takeover-${session.id}');

  GameSession session;
  final Mindustry version;

  bool _cancelled = false;
  bool _finishing = false;
  bool _finished = false;

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
                version.tag,
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
    final gamePid = session.gamePid;
    if (gamePid == null) {
      await _finishRun(0);
      return;
    }
    while (true) {
      if (!GameProcessWatch.isAlive(gamePid)) break;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    await _finishRun(DateTime.now().difference(session.startedAt).inSeconds);
  }

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final gamePid = session.gamePid;
    if (gamePid != null) {
      final killed = GameProcessWatch.kill(gamePid);
      addLog(
        killed ? .info : .warning,
        '接管任务：结束游戏进程 $gamePid（${killed ? '已发出结束' : '失败'}）',
        tag: 'CloudService',
      );
    }
    updateDisplay();
  }

  /// 游戏结束：上传 → 写游玩时长 → 按快捷启动退出设置收尾
  Future<void> _finishRun(int playSeconds) async {
    if (_finishing || _finished) return;
    _finishing = true;

    session
      ..phase = 'uploading'
      ..playSeconds = playSeconds;
    await GameSessionStore.save(session);

    await CloudAutoSync.afterGameExit(version);
    await CloudAutoSync.waitForPending();

    final now = DateTime.now();
    version.lastLaunchTime = now;
    version.playTime = (version.playTime ?? Duration.zero) +
        Duration(seconds: playSeconds);
    await config.save();

    session
      ..phase = 'done'
      ..completedAt = now;
    await GameSessionStore.save(session);
    await GameSessionStore.remove(session.id);

    addLog(.info, '接管任务：游戏退出，已上传并记录 [${version.tag}]', tag: 'CloudService');
    NotificationManager.addNotice(
      icon: Icons.check,
      title: '已接管并收尾',
      content: '${version.tag} 已退出，云存档已上传',
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
