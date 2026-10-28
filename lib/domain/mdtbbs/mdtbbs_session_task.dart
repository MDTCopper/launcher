import 'dart:async';

import 'package:copper_launcher/domain/mdtbbs/mdtbbs_multiplayer_service.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_multiplayer_state.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/pages/online/online_page.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/util/format/date_time_format.dart';
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
    } else {
      // 会话没了：卡片收尾，别停在「进行中」
      _summary = '已退出房间';
      finish();
      return;
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
    final colors = AppColors.of(context);
    final state = MdtbbsMultiplayerService.instance.state.value;
    final session = state.session;
    final roomName = session?.activityName?.trim();
    final title = roomName == null || roomName.isEmpty ? '联机房间' : roomName;
    final code = state.joinCode;
    final busy = state.leaving || state.stoppingProxy;
    final statusText = switch (status) {
      TaskStatus.pending => '准备中',
      TaskStatus.process => '会话中',
      TaskStatus.completed => '已结束',
      TaskStatus.failed => '失败',
      TaskStatus.paused => '已暂停',
      TaskStatus.cancel => '已退出',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(displayIcon, size: 24, color: colors.interactive),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.interactive,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(createTime.toTimeString(), style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 8),
        Text('${code == null || code.isEmpty ? '' : '房间码 $code  '}$statusText'),
        const SizedBox(height: 4),
        Text(
          _summary,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.itemSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: ActionButton(
                alignment: MainAxisAlignment.center,
                backgroundColor: colors.highBackgroundOnCard,
                icon: const Icon(Icons.meeting_room_outlined),
                content: const Text('查看房间'),
                enable: session != null,
                onTap: () => _openRoom(context),
              ),
            ),
            Expanded(
              child: ActionButton(
                alignment: MainAxisAlignment.center,
                backgroundColor: colors.highBackgroundOnCard,
                icon: const Icon(Icons.logout),
                content: Text(busy ? '正在退出…' : '退出房间'),
                enable: session != null && !busy,
                onTap: () => _confirmLeave(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 抽屉里点「查看房间」：收起抽屉，再切到联机页（与左侧导航同一套切根路由）
  void _openRoom(BuildContext context) {
    Scaffold.maybeOf(context)?.closeEndDrawer();
    final navigator = PageKeyProvider.navigatorKey.currentState;
    if (navigator == null) return;
    unawaited(navigator.pushNamedAndRemoveUntil(onlinePageRouteKey, (_) => false));
  }

  void _confirmLeave(BuildContext context) {
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '退出房间？',
      content: '会离开当前房间，房间里的其他人会看到你离开；房间码不再有效',
      action: () => unawaited(onCancel()),
    );
  }
}
