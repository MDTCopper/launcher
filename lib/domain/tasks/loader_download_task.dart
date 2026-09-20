import 'dart:async';

import 'package:copper_launcher/domain/loader_library.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/shell/drawer/log_list.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

/// 只下加载器（不碰游戏本体）的任务
///
/// 用在两处：① 用户只是往加载器库里加一个版本（选好远程版本之后）
/// ② 建 loader 变体时 loader 还没下 —— 变体弹窗**先开**，用户在填名字与继承的时候
/// 它在后台下；点「创建」时若还没下完，`createVersionVariant` 会等 [done]
///
/// 「下载游戏时顺带下 loader」不走它：那条路把 loader 并进本体下载任务
/// （见 `MindustryDownloadTask._resolveLoader`），进度与失败都在同一个任务里
class LoaderDownloadTask extends Task {
  LoaderDownloadTask({
    required this.tag,
    required this.url,
    this.afterDownload,
    @visibleForTesting this.downloader,
  }) {
    type = TaskType.download;
    // 没人 await done 时（比如用户把变体弹窗取消了），别让失败冒成未捕获异常
    _done.future.ignore();
  }

  final Completer<String> _done = Completer<String>();

  /// 任务**结束**才完成的 future：成功给库内路径，失败 / 取消抛异常
  ///
  /// 「换启动器新建」用它：弹窗先开，点「创建」时若还没下完就 await 它
  Future<String> get done => _done.future;

  /// 要下的 loader 版本号（`desktop-<tag>.jar`）
  final String tag;

  final String url;

  /// 下完之后的收尾（把 loader 指给版本 / 建变体）；它抛异常算任务失败
  final Future<void> Function(String loaderPath)? afterDownload;

  /// 用例注入假的下载实现；正常走 [LoaderLibrary.downloadDesktop]
  final Future<String> Function(
    CancelToken cancelToken,
    HttpStatusCallback onStatus,
  )?
  downloader;

  final CancelToken cancelToken = CancelToken();

  /// 当前状态文案（只有失败时用；下载中的信息看 [lastState]）
  String? statusText;

  /// 最近一次下载状态：总大小 / 已下载 / 速度都从它取（显示具体进度用）
  HttpDownloadState? lastState;

  /// 下完的 loader 路径
  String? loaderPath;

  @override
  void cancel() {
    super.cancel();
    cancelToken.cancel('cancel');
  }

  @override
  void pause() => cancel();

  @override
  Future<void> runTask() async {
    addTaskLog(LogEntry(LogType.info, '开始下载加载器 $tag'));
    addLog(.info, '下载加载器 [$tag]：$url', tag: 'Loader');

    try {
      final download = downloader;
      final path = download == null
          ? await LoaderLibrary.downloadDesktop(
              tag: tag,
              url: url,
              cancelToken: cancelToken,
              onStatus: _onDownloadStatus,
            )
          : await download(cancelToken, _onDownloadStatus);

      if (cancelToken.isCancelled) {
        status = TaskStatus.cancel;
        _finishDoneError(StateError('已取消下载加载器 $tag'));
        updateDisplay();
        return;
      }

      loaderPath = path;
      // 收尾（建变体之类）失败也算这个任务失败：loader 下好了但没落地，
      // 用户看到的应当是"这事没成"
      await afterDownload?.call(path);

      progress = 1.0;
      status = TaskStatus.completed;
      _finishDone(path);
      addTaskLog(LogEntry(LogType.success, '加载器 $tag 已就位：$path'));
      addLog(.info, '加载器已就位：$path', tag: 'Loader');
      addNotice(
        icon: Icons.check_box_outlined,
        title: '加载器已下载',
        content: 'Copper Loader $tag',
      );
    } catch (e) {
      status = TaskStatus.failed;
      statusText = '下载失败';
      _finishDoneError(e);
      addTaskLog(LogEntry(LogType.error, '加载器 $tag 下载失败：$e'));
      addLog(.error, '加载器下载失败：$e', tag: 'Loader');
      addNotice(
        icon: Icons.close,
        title: '加载器下载失败',
        content: 'Copper Loader $tag 没下下来，稍后再试或选本地 jar',
      );
    } finally {
      updateDisplay();
    }
  }

  /// 下载状态回填：进度条与「已下载/总大小 + 速度」都从它来
  void _onDownloadStatus(HttpDownloadState state) {
    lastState = state;
    progress = state.progress;
    updateDisplay();
  }

  void _finishDone(String path) {
    if (!_done.isCompleted) _done.complete(path);
  }

  void _finishDoneError(Object error) {
    if (!_done.isCompleted) _done.completeError(error);
  }

  /// 进度行：拿到总大小时给 `12.3MB/15.0MB  1.2MB/s`，还没拿到就给百分比
  String _progressText() {
    final state = lastState;
    if (state == null) return formatProgress();
    if (state.total <= 0) return state.progressText;
    return '${formatBytes(state.downloaded)}/${formatBytes(state.total)}'
        '  ${state.speedText}';
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
            Icon(getIcon(type), size: 32),
            const SizedBox(width: 4),
            Text(
              '下载加载器 $tag',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.secondary,
              ),
            ),
            const Expanded(child: SizedBox()),
            if (statusLabel != null)
              Text(statusLabel!, style: theme.textTheme.bodySmall),
            if (canCancel)
              ReboundButton(onTap: cancel, child: const Icon(Icons.close)),
          ],
        ),
        LinearProgressIndicator(value: progress),
        if (statusText != null)
          Text(statusText!, style: theme.textTheme.bodySmall)
        else if (progress != null)
          Text(_progressText(), style: theme.textTheme.bodySmall),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
