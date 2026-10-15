import 'dart:async';

import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// 同步方向（决定卡片标题与图标）
enum CloudSyncDirection { upload, download }

/// 一次云存档自动同步（退出后上传 / 启动前恢复）的任务卡片
///
/// **为什么要有它**：这两条路以前只有日志与最后那一条通知 —— 退出后上传时启动器
/// 可能已经在收尾、托盘与任务抽屉里什么都看不到，玩家只能猜「传完了没有」。
/// 挂成任务之后：抽屉里看得见进度、托盘与任务栏有进度、还能当场取消。
///
/// 类型借用 [TaskType.download]（**新增 TaskType 要动 `domain/task.dart`，那是用户的文件**）——
/// 它只影响图标 / 标题的兜底，而本卡片自己画标题与图标
class CloudSyncTask extends Task {
  CloudSyncTask({
    required this.direction,
    required this.versionTag,
    required this.onRun,
  }) {
    type = TaskType.download;
  }

  final CloudSyncDirection direction;
  final String versionTag;

  /// 真正跑那件事；返回一句给人看的结果（如「已上传 2.3 MB」）
  final Future<String> Function(CloudSyncTask task) onRun;

  /// 由任务自己持有：调用方把它传给云存档接口，卡片上的 ✕ 就能中途取消
  final CancelToken cancelToken = CancelToken();

  final Completer<void> _done = Completer<void>();

  String _phase = '准备中…';
  int _doneBytes = 0;
  int _totalBytes = 0;
  String? _result;

  /// 失败时的原始异常：调用方据此**保留原来的分类处理**（比如冲突要单独弹一条）
  Object? error;

  /// 跑完（成功 / 失败 / 取消都会完成）——`await` 它就能拿到「同步到底结束了」
  Future<void> get done => _done.future;

  String? get result => _result;

  bool get succeeded => status == TaskStatus.completed;

  /// 同一个版本同一个方向只留一张卡（重复触发时复用，不叠一堆）
  @override
  String get id => 'cloud_sync_${direction.name}_$versionTag';

  /// 阶段文字：服务端那份 `onStatus` 直接接到这里
  void setPhase(String text) {
    _phase = text;
    updateDisplay();
  }

  /// 传输进度：下载那条路把 `onProgress` 直接接到这里
  void acceptProgress(HttpDownloadState state) {
    if (state.progress > 0) {
      _doneBytes = state.downloaded;
      _totalBytes = state.total;
      progress = state.progress.clamp(0.0, 1.0);
      updateDisplay();
      return;
    }
    acceptBytes(state.downloaded, state.total);
  }

  /// 传输字节：上传那条路用的是 dio 的 `onSendProgress`
  void acceptBytes(int done, int total) {
    _doneBytes = done;
    _totalBytes = total;
    if (total > 0) progress = (done / total).clamp(0.0, 1.0);
    updateDisplay();
  }

  @override
  Future<void> runTask() async {
    try {
      _result = await onRun(this);
      progress = 1.0;
      status = TaskStatus.completed;
    } catch (captured) {
      error = captured;
      // 用户自己按的取消：状态保持「已取消」，别改写成失败
      if (status != TaskStatus.cancel) {
        status = TaskStatus.failed;
        _result = removeNewlines('$captured');
      }
    } finally {
      if (!_done.isCompleted) _done.complete();
      updateDisplay();
    }
  }

  @override
  void cancel() {
    super.cancel();
    if (!cancelToken.isCancelled) cancelToken.cancel('用户在任务抽屉里取消了云存档同步');
    if (!_done.isCompleted) _done.complete();
    updateDisplay();
  }

  String get _title => direction == CloudSyncDirection.upload ? '云端上传' : '云端恢复';

  IconData get _icon => direction == CloudSyncDirection.upload
      ? Icons.cloud_upload_outlined
      : Icons.cloud_download_outlined;

  @override
  Widget buildDisplayWidget(BuildContext context) {
    final theme = Theme.of(context);
    final hasBytes = _doneBytes > 0 || _totalBytes > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, size: 32),
            const SizedBox(width: 4),
            Text(
              _title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              versionTag,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            if (statusLabel != null)
              Text(statusLabel!, style: theme.textTheme.bodySmall),
            if (canCancel)
              ReboundButton(onTap: cancel, child: const Icon(Icons.close)),
          ],
        ),
        LinearProgressIndicator(value: progress),
        Text(_phase, style: theme.textTheme.bodyMedium),
        if (hasBytes)
          Text(
            _totalBytes > 0
                ? '${formatBytes(_doneBytes)} / ${formatBytes(_totalBytes)}'
                : formatBytes(_doneBytes),
            style: theme.textTheme.bodySmall,
          ),
        if (_result != null) Text(_result!, style: theme.textTheme.bodySmall),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
