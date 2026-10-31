import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/util/game_process_watch.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

/// UI 后开 / 服务还活着时，把「正在跑的那一局」显示成只读任务卡片
///
/// 这不是启动器自己拉起的任务，所以 [runTask] 是空的；状态跟着
/// `cloud-service/sessions/*.json` 走，✕ 只负责杀游戏进程，上传与收尾仍由服务做
class RemoteSessionTask extends Task {
  RemoteSessionTask(this.session) : super(id: 'remote-session-${session.id}');

  GameSession session;

  bool _stopping = false;

  @override
  IconData get displayIcon => Icons.videogame_asset_outlined;

  @override
  String get displayTitle => '游戏运行中';

  @override
  bool get canCancel =>
      status == TaskStatus.process && !_stopping && session.gamePid != null;

  @override
  String? get statusLabel => null;

  @override
  void cancel() {
    if (_stopping) return;
    final gamePid = session.gamePid;
    if (gamePid == null) return;
    _stopping = true;
    final killed = GameProcessWatch.kill(gamePid);
    addLog(
      killed ? .info : .warning,
      '会话卡：结束游戏进程 $gamePid（${killed ? '已发出结束' : '失败'}）',
      tag: 'CloudService',
    );
    updateDisplay();
  }

  @override
  Widget buildDisplayWidget(BuildContext context) {
    final theme = Theme.of(context);
    final started = session.startedAt;
    final elapsed = DateTime.now().difference(started);
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
                session.tag,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canCancel)
              ReboundButton(onTap: cancel, child: const Icon(Icons.close)),
          ],
        ),
        Text(
          _stopping ? '正在结束游戏，结束后由云服务上传…' : '由云服务托管，退出后自动上传',
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

  String _formatElapsed(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours} 小时 ${duration.inMinutes % 60} 分';
    }
    return '${duration.inMinutes} 分 ${duration.inSeconds % 60} 秒';
  }

  @override
  Future<void> runTask() async {
    // 只负责显示；生命周期由 GameSessionMonitor 轮询会话文件驱动
  }

  void finish() {
    status = TaskStatus.completed;
    updateDisplay();
  }

  void refresh() => updateDisplay();
}
