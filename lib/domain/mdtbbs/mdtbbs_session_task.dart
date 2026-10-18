import 'dart:async';

import 'package:copper_launcher/domain/mdtbbs/mdtbbs_multiplayer_state.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:flutter/material.dart';

/// 联机会话的任务卡片：会话在，卡片就在（抽屉里可见、可取消）
///
/// 长寿命资源（会话 / 心跳 / 中继通道）的 owner 是任务管理器而不是页面，
/// 所以切页不会让它们失控 —— 页面只是它的一个入口
class MultiplayerSessionTask extends Task {
  MultiplayerSessionTask({required this.onCancel});

  /// 取消卡片时做什么（退出会话）
  final Future<void> Function() onCancel;

  Completer<void>? _done;
  String _summary = '正在建立会话…';

  /// 全程只有一个任务卡片，重复使用这个 id
  @override
  String get id => 'multiplayer_session';

  @override
  IconData get displayIcon => Icons.lan_outlined;

  @override
  String get displayTitle => '联机';

  /// 开一轮新的会话：重置完成信号与进度，由 [Task.start] 拉起
  void reset() {
    _done = Completer<void>();
    progress = null;
    status = TaskStatus.pending;
    _summary = '正在建立会话…';
    updateDisplay();
  }

  /// 会话结束：卡片收尾（已完成）
  void finish() {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
    if (status == TaskStatus.process) status = TaskStatus.completed;
    updateDisplay();
  }

  /// 跟着服务状态刷新卡片文字
  void updateFrom(MultiplayerState state) {
    final session = state.session;
    if (session != null) {
      final heartbeat = state.heartbeatFailures == 0
          ? '心跳正常'
          : '心跳异常 ${state.heartbeatFailures} 次';
      final proxy = state.proxyRunning
          ? '通道 ${state.localAddress ?? ''}'
          : '通道未启动';
      _summary =
          '${session.currentPlayers}/${session.maxPlayers} 人 · $heartbeat · $proxy';
    } else if (state.waitingForSession || state.resuming) {
      _summary = '正在恢复会话…';
    }
    updateDisplay();
  }

  @override
  Future<void> runTask() async {
    final done = _done;
    if (done == null) return;
    await done.future;
    if (status == TaskStatus.process) status = TaskStatus.completed;
    updateDisplay();
  }

  @override
  void cancel() {
    super.cancel();
    unawaited(onCancel());
    finish();
  }

  @override
  Widget buildDisplayWidget(BuildContext context) {
    final theme = Theme.of(context);
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
              '联机会话',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.secondary,
              ),
            ),
            const Spacer(),
            if (statusLabel != null)
              Text(statusLabel!, style: theme.textTheme.bodySmall),
            if (canCancel)
              ReboundButton(onTap: cancel, child: const Icon(Icons.close)),
          ],
        ),
        Text(_summary, style: theme.textTheme.bodyMedium),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
