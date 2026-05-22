import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/app_config.dart';
import '../../data/local_asset.dart';
import '../../data/net_asset.dart';
import '../../ui/util/info/log_list.dart';
import '../../ui/util/info/notification.dart';
import '../../ui/util/widget/feature_button.dart';
import '../../util/app_paths.dart';
import '../../util/format/byte_unit.dart';
import '../../util/io/downloader.dart';
import '../task.dart';

///官方渠道下载，path路径默认为 [项目//version]
class DownloadMindustryTask extends Task {
  final MindustryGithubMeta mindustryMeta;

  ///自定义存储路径
  late final String path;

  ///需要标签
  final String tag;

  // final String copper;//todo CopperLoader下载
  final CancelToken cancelToken = CancelToken();
  late File file;
  int totalSize = 0;
  int downloadedSize = 0;
  double speed = 0.0;

  List<DownloadChunk> chunks = [];

  DownloadMindustryTask({
    required this.mindustryMeta,
    required this.tag,
    String? path,
    // CancelToken? cancelToken//外部取消token
  }) {
    super.type = TaskType.download;
    this.path = path ?? AppPaths.versions;
  }

  @override
  void cancel() {
    super.cancel();
    cancelToken.cancel('cancel');
  }

  @override
  void pause() {
    super.pause();
    cancelToken.cancel('pause');
  }

  @override
  Future<void> runTask() async {
    // progress = 0.0;
    // totalSize = 80 * mb;
    // await Future.delayed(const Duration(seconds: 2));
    // for (int i = 0; i < 1000; i++) {
    //   if (status != TaskStatus.process) return;
    //   final i = Random().nextInt(300) + 20;
    //   await Future.delayed(Duration(milliseconds: i));
    //   progress = progress! + 0.1 * 0.01;
    //   downloadedSize = (totalSize * progress!).toInt();
    //   updateDisplay();
    // }
    // _status = TaskStatus.completed;
    // updateDisplay();
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
      final jarName = 'mindustry-${mindustryMeta.releaseNum}.jar';
      final jarPath = p.join(path, tag, jarName);

      file = File(jarPath);
      var previousDownloaded = 0;
      if (!await file.exists()) {
        await file.create(recursive: true);
        downloadedSize = await file.length();
      }

      final String url =
          mindustryMeta.assets
              .firstWhere(
                (it) => it.name.toLowerCase().contains('mindustry.jar'),
              )
              .url;
      print(url);

      await dr.download(
        url,
        file.path,
        cancelToken: cancelToken,
        deleteOnError: false,
        fileAccessMode: FileAccessMode.append,
        onProgress: (receive, total) {
          totalSize = previousDownloaded + total;
          downloadedSize = previousDownloaded + receive;
          progress = downloadedSize / totalSize;
          updateDisplay();
        },
        onSpeedUpdate: (s) {
          speed = s;
          updateDisplay();
        },
        chunksStatus: (it) => chunks = it,
      );
      //检查文件完整性
      if (await file.length() != totalSize) Exception('文件可能在合并过程中损坏');
      await _addIntoConfig();
      status = TaskStatus.completed;

      NotificationManager.addNotice(
        icon: Icons.check_box_outlined,
        title: '下载完成',
        content: '[$tag]下载完成，存储路径[$path]',
      );
      LogManager.addLog(LogEntry(LogType.info, '[$tag]下载完成，存储路径[$path]'));
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        if (e.toString().contains('paused')) {
          status = TaskStatus.paused;
        } else if (e.toString().contains('cancel')) {
          status = TaskStatus.cancel;
          Future.delayed(Duration(milliseconds: 300), () async {
            await file.delete();
          });
          debugPrint('取消下载:$e');

          addLog(LogEntry(LogType.info, '已取消下载'));
          addNotice(icon: Icons.info_outline, title: '取消', content: '已取消下载');
        }
      } else {
        status = TaskStatus.failed;
        debugPrint('网络错误：$e');
        addLog(LogEntry(LogType.error, '网络错误:$e'));
        addNotice(icon: Icons.error_outline, title: '错误', content: '网络错误:$e');

        await file.delete();
      }
    } catch (e) {
      status = TaskStatus.failed;
      debugPrint('未知错误$e');
      addLog(LogEntry(LogType.error, '未知错误:$e'));
      addNotice(icon: Icons.error_outline, title: '致命错误！', content: '$e');

      await file.delete();
    } finally {
      updateDisplay();
    }
  }

  Future<void> _addIntoConfig() async {
    final mindustry = Mindustry(
      id: id,
      launcher: LauncherType.mindustry,
      tag: tag,
      jarPath: file.path,
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
      config.saveAsJson();
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

  Widget _chunkStatus() {
    if (chunks.isEmpty) {
      return Text('链接中...');
    }

    final connectedCount =
        chunks
            .where(
              (it) =>
                  it.status == DownloadChunkStatus.download ||
                  it.status == DownloadChunkStatus.complete,
            )
            .length;

    if (connectedCount == chunks.length) {
      String str = '共${chunks.length}个分块：\n';

      for (var o in chunks) {
        final progress = o.receive / o.size * 100;
        str += '分块${o.index + 1} (${progress.toStringAsFixed(1)}%)   ';
        if (o.index + 1 != chunks.length && (o.index + 1) % 3 == 0) str += '\n';
      }
      return Text(str);
    }
    return Text('分块连接中 $connectedCount / ${chunks.length}');
  }

  //todo 分块处理可以弄一下链接状态，下载状态
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
            Text(
              getTitle(type),
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
        if (progress != null)
          Row(
            children: [
              Text(formatProgress()),
              Expanded(child: SizedBox()),
              Text(_formatDownloadProgress()),
            ],
          ),
        Text('正在下载[$tag]'),
        _chunkStatus(),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
