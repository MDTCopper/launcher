import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/data/mindustry_top_map.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/shell/drawer/log_list.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/mindustry_top_map_api.dart';
import 'package:flutter/material.dart';

/// 从 mindustry.top 下载地图本体（`.msav`）到目标版本的数据目录
///
/// 落盘位置由 [savePath] 决定（调用方按目标版本的 `mapsPath` 拼好）；
/// [version] 只用于文案与日志——出问题时能看出"导到哪个版本去了"
class DownloadMapTask extends Task {
  DownloadMapTask({
    required this.map,
    required this.version,
    required this.savePath,
  }) {
    type = TaskType.download;
  }

  final MindustryTopMapMeta map;

  ///目标游戏版本
  final Mindustry version;

  ///地图落盘完整路径
  final String savePath;

  final CancelToken cancelToken = CancelToken();

  ///当前状态文案（下载中 / 合并分块 / 已完成…）
  String? statusText;

  @override
  void cancel() {
    super.cancel();
    cancelToken.cancel('cancel');
  }

  @override
  void pause() => cancel();

  @override
  Future<void> runTask() async {
    addTaskLog(LogEntry(LogType.info, '开始下载地图 [${map.name}]'));
    addLog(
      .info,
      '下载地图 [${map.name}]（id ${map.id}）到 [${version.tag}]：$savePath',
    );

    try {
      await MindustryTopMapApi.download(
        id: map.id,
        savePath: savePath,
        cancelToken: cancelToken,
        onStatus: (state) {
          progress = state.progress;
          statusText = _statusText(state);
          updateDisplay();
        },
      );
    } catch (error) {
      if (cancelToken.isCancelled) {
        status = TaskStatus.cancel;
        addTaskLog(LogEntry(LogType.info, '已取消下载地图 [${map.name}]'));
        updateDisplay();
        return;
      }
      MindustryTopMapApi.logFailure(error, context: '下载');
      status = TaskStatus.failed;
      addTaskLog(LogEntry(LogType.error, '地图 [${map.name}] 下载失败'));
      addNotice(
        icon: Icons.error_outline,
        title: '地图下载失败',
        content: '可能是网络或代理问题，稍后重试',
      );
      updateDisplay();
      return;
    }

    if (cancelToken.isCancelled) {
      status = TaskStatus.cancel;
      updateDisplay();
      return;
    }

    progress = 1;
    status = TaskStatus.completed;
    addTaskLog(LogEntry(LogType.success, '地图 [${map.name}] 已下载到 [${version.tag}]'));
    addNotice(
      icon: Icons.check_box_outlined,
      title: '地图下载完成',
      content: '[${map.name}] 已放进 [${version.tag}] 的地图目录',
    );
    updateDisplay();
  }

  /// 状态行文案：分块合并 / 连接 / 进度与速率各说一句
  String _statusText(HttpDownloadState state) {
    switch (state.status) {
      case HttpDownloadStatus.connecting:
        return '正在连接…';
      case HttpDownloadStatus.merging:
        return '正在合并分块…';
      case HttpDownloadStatus.completed:
        return '已完成';
      case HttpDownloadStatus.failed:
        return '下载失败';
      case HttpDownloadStatus.cancelled:
        return '已取消';
      case HttpDownloadStatus.idle:
      case HttpDownloadStatus.downloading:
        final speed = '${formatBytes(state.speed.round())}/s';
        //总长度还没探到时（分块前的 HEAD 阶段）只报已下载
        return state.total > 0
            ? '${formatBytes(state.downloaded)} / ${formatBytes(state.total)}（$speed）'
            : '${formatBytes(state.downloaded)}（$speed）';
    }
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
            SizedBox(width: 4),
            Expanded(
              child: Text(
                '下载地图 [${map.name}]',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ),
            ReboundButton(onTap: cancel, child: Icon(Icons.close)),
          ],
        ),
        LinearProgressIndicator(value: progress),
        if (progress != null)
          Text(statusText ?? formatProgress(), style: theme.textTheme.bodySmall),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
