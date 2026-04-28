import 'dart:io';

import 'package:copperlauncher_main/data/net_asset.dart';
import 'package:copperlauncher_main/util/format/byte_unit.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/app_config.dart';
import '../data/local_asset.dart';
import '../ui/util/info/log_list.dart';
import '../ui/util/info/notification.dart';
import '../ui/util/widget/feature_button.dart';
import '../util/app_paths.dart';
import '../util/downloader.dart';

///任务抽象类，需要长时间或异步运行的程序在task类中进行
///简单任务用SimpleTask快速进行
///复杂任务需要继承Task并实现runTask
abstract class Task implements Listenable {
  late final String id;
  final TaskType type;
  TaskStatus _status = TaskStatus.pending; //创建时为待定，需要外部启动
  double? progress;
  late final DateTime createTime;

  final Set<VoidCallback> listeners = {};

  Task({required this.type, DateTime? createTime, String? id}) {
    this.createTime = createTime ?? DateTime.now();
    this.id = id ?? createTime.hashCode.toString();
  }

  TaskStatus get status => _status;

  @override
  void addListener(VoidCallback listener) => listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);

  IconData _getIcon(TaskType type) {
    switch (type) {
      case TaskType.check:
        return Icons.search;
      case TaskType.launch:
        return Icons.rocket_launch;
      case TaskType.download:
        return Icons.download;
    }
  }

  String _getTitle(TaskType type) {
    switch (type) {
      case TaskType.check:
        return '校验';
      case TaskType.launch:
        return '启动';
      case TaskType.download:
        return '下载';
    }
  }

  String _formatProgress(double? progress) {
    if (progress == null) return '0.0%';
    return '${(progress * 100).toStringAsFixed(1)} %';
  }

  ///呈现在信息栏位的组件
  Widget buildDisplayWidget(BuildContext context);

  ///需更新任务呈现信息时调用
  void _updateDisplay() {
    for (var it in listeners) {
      it.call();
    }
  }

  void cancel() {
    _status = TaskStatus.cancel;
    _updateDisplay();
  }

  void pause() {
    _status = TaskStatus.paused;
    _updateDisplay();
  }

  void start() {
    _status = TaskStatus.process;
    _updateDisplay();
  }

  ///自定义任务内容
  Future<void> _runTask();
}

enum TaskType { check, launch, download }

enum TaskStatus { pending, process, completed, failed, paused, cancel }

class SimpleTask extends Task {
  final VoidCallback? task;
  final Future<void> Function()? futureTask;
  final String? describe;
  final String? details;

  SimpleTask({
    required super.id,
    required super.type,
    this.task,
    this.futureTask,
    this.describe,
    this.details,
  });

  @override
  Future<void> _runTask() async {
    task?.call();
    await futureTask?.call();
    _status = TaskStatus.completed;
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
            Icon(_getIcon(type), size: 32),
            SizedBox(width: 4),
            Text(
              _getTitle(type),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.secondary,
              ),
            ),
            Expanded(child: SizedBox()),
            ReboundButton(onTap: cancel, child: Icon(Icons.close)),
          ],
        ),
        LinearProgressIndicator(value: progress),
        if (progress != null) Text(_formatProgress(progress)),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

final dr = Downloader();

///官方渠道下载，path路径默认为 项目//version
class DownloadMindustryTask extends Task {
  final MindustryGithubMeta mindustryMeta;
  final String? path;

  ///需要标签
  final String tag;

  // final String copper;//todo CopperLoader下载
  final CancelToken cancelToken = CancelToken();
  late File file;
  int totalSize = 0;
  int downloadedSize = 0;
  double speed = 0.0;

  DownloadMindustryTask({
    required this.mindustryMeta,
    required this.tag,
    super.type = TaskType.download,
    this.path,

    // CancelToken? cancelToken//外部取消token
  });

  @override
  void cancel() {
    super.cancel();
    cancelToken.cancel('cancel');
  }

  @override
  void start() {
    super.start();
    _runTask();
  }

  @override
  void pause() {
    super.pause();
    cancelToken.cancel('pause');
  }

  @override
  Future<void> _runTask() async {
    // progress = 0.0;
    // await Future.delayed(const Duration(seconds: 3));
    // for (int i = 0; i < 1000; i++) {
    //   if (status != TaskStatus.process) return;
    //   final i = Random().nextInt(100)+20;
    //   await Future.delayed(Duration(milliseconds: i));
    //   progress = progress! + 0.1*0.01;
    //   _updateDisplay();
    // }
    // _status = TaskStatus.completed;
    // _updateDisplay();
    // return;
    await _download();
  }

  Future<void> _download() async {
    NotificationManager.addNotice(
      icon: Icons.download,
      title: '下载',
      content: '正在下载游戏[$tag]',
    );
    LogManager.addLog(LogEntry(LogType.info, '正在下载游戏[$tag]'));

    try {
      if (path == null) {
        file = File((await AppPaths.versions).toString());
        if (!await file.exists()) {
          await file.create(recursive: true);
        }
      } else {
        file = File(path!);
        if (!await file.exists()) {
          await file.create(recursive: true);
        }
        downloadedSize = await file.length();
      }

      final String url =
          mindustryMeta.assets
              .firstWhere((it) => it.name.contains('mindustry.jar'))
              .url;

      await dr.download(
        url,
        file.path,
        cancelToken: cancelToken,
        deleteOnError: false,
        fileAccessMode: FileAccessMode.append,
        onProgress: (receive, total) {
          totalSize = downloadedSize + total;
          downloadedSize = downloadedSize + receive;
          progress = downloadedSize / totalSize;
          _updateDisplay();
        },
        onSpeedUpdate: (s) {
          speed = s;
          _updateDisplay();
        },
      );
      //检查文件完整性
      if (await file.length() != totalSize) Exception('文件可能在合并过程中损坏');
      await _addIntoConfig();
      _status = TaskStatus.completed;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        if (e.toString().contains('paused')) {
          _status = TaskStatus.paused;
        } else if (e.toString().contains('cancel')) {
          _status = TaskStatus.cancel;
          Future.delayed(Duration(milliseconds: 300), () async {
            await file.delete();
          });
          debugPrint('取消下载:$e');

          addLog(LogEntry(LogType.info, '已取消下载'));
          addNotice(icon: Icons.info_outline, title: '取消', content: '已取消下载');
        }
      } else {
        _status = TaskStatus.failed;
        debugPrint('网络错误：$e');
        addLog(LogEntry(LogType.error, '网络错误:$e'));
        addNotice(icon: Icons.error_outline, title: '错误', content: '网络错误:$e');

        await file.delete();
      }
    } catch (e) {
      _status = TaskStatus.failed;
      debugPrint('未知错误$e');
      addLog(LogEntry(LogType.error, '未知错误:$e'));
      addNotice(icon: Icons.error_outline, title: '致命错误！', content: '$e');

      await file.delete();
    } finally {
      _updateDisplay();
    }
  }

  Future<void> _addIntoConfig() async {
    String jarName = 'mindustry-${mindustryMeta.releaseNum}.jar';
    String path = file.path;
    String jarPath = p.join(path, tag, jarName);

    final mindustry = Mindustry(
      id: id,
      launcher: LauncherType.mindustry,
      tag: tag,
      jarPath: jarPath,
      isBe: mindustryMeta.isBe,
      path: path,
      name: mindustryMeta.name,
      releaseNum: mindustryMeta.releaseNum,
      addTime: DateTime.now(),
      isolation: false,
    );
    final foldIndex = config.versionOptions.versionFolds.indexWhere(
      (fold) => fold.path == mindustry.path,
    );
    if (foldIndex != -1) {
      config.versionOptions.versionFolds[foldIndex].versions.add(mindustry);
      config.save();
    } else {
      //todo 新的路径可以询问玩家是否创建，不创建就移入默认文件夹
      debugPrint('无法同步配置文件');
    }
  }

  String _formatDownloadProgress() {
    if ([downloadedSize, totalSize].contains(0)) return '等待连接...';

    String progress;
    String downloadSpeed;

    if (totalSize < kb) {
      progress =
          '${downloadedSize.toStringAsFixed(1)}/${totalSize.toStringAsFixed(1)}B';
    } else if (totalSize < mb) {
      progress =
          '${(downloadedSize / kb).toStringAsFixed(1)}/${(totalSize / kb).toStringAsFixed(1)}KB';
    } else if (totalSize < gb) {
      progress =
          '${(downloadedSize / mb).toStringAsFixed(1)}/${(totalSize / mb).toStringAsFixed(1)}MB';
    } else {
      progress =
          '${(downloadedSize / gb).toStringAsFixed(1)}/${(totalSize / gb).toStringAsFixed(1)}GB';
    }

    if (speed < kb) {
      downloadSpeed = '${(speed).toStringAsFixed(1)}B/S';
    } else if (speed < mb) {
      downloadSpeed = '${(speed / kb).toStringAsFixed(1)}KB/S';
    } else {
      downloadSpeed = '${(speed / mb).toStringAsFixed(1)}MB/S';
    }
    if (speed <= 0) {
      downloadSpeed = '0B/S';
    }

    String status = '$progress($downloadSpeed)';

    return status;
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
            Icon(_getIcon(type), size: 32),
            SizedBox(width: 4),
            Text(
              _getTitle(type),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.secondary,
              ),
            ),
            Expanded(child: SizedBox()),
            ReboundButton(onTap: cancel, child: Icon(Icons.close)),
          ],
        ),
        LinearProgressIndicator(value: progress),
        if (progress != null) Text(_formatProgress(progress)),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
