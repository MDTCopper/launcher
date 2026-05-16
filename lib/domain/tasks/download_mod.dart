import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:copperlauncher_main/core/app_constant.dart';
import 'package:copperlauncher_main/data/net_asset.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../ui/util/info/log_list.dart';
import '../../ui/util/info/notification.dart';
import '../../ui/util/widget/feature_button.dart';
import '../../util/downloader.dart';
import '../../util/format/byte_unit.dart';
import '../../util/math/speed_calculate.dart';
import '../task.dart';

class DownloadJavaModTask extends Task {
  final ModOfficialListMeta modListMeta;
  final ModGithubMeta modMeta;

  final String savePath;

  final CancelToken cancelToken = CancelToken();

  late File file;

  int totalSize = 0;
  int downloadedSize = 0;
  double speed = 0.0;

  List<DownloadChunk> chunks = [];

  DownloadJavaModTask({
    required this.modListMeta,
    required this.modMeta,
    required this.savePath,
  }) : assert(modListMeta.hasJava, '模组类型只能为Java') {
    type = TaskType.download;
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

  Future<void> _download() async {
    NotificationManager.addNotice(
      icon: Icons.download,
      title: '下载',
      content: '正在下载模组[${modListMeta.name}(${modMeta.releaseNum})]',
    );
    LogManager.addLog(
      LogEntry(
        LogType.info,
        '正在下载模组[${modListMeta.name}(${modMeta.releaseNum})]',
      ),
    );

    await Future.delayed(const Duration(milliseconds: 500));

    try {
      final fileName = '${modListMeta.name}-${modMeta.name}.jar';

      final path = p.join(savePath, fileName);
      file = File(path);
      var previousDownloaded = 0;
      if (!await file.exists()) await file.create(recursive: true);

      final jar = modMeta.assets.where((it) => it.name.contains('.jar'));

      final url = jar.firstOrNull?.url;
      if (url == null) throw Exception('模组元数据提供的url为空,元数据: ${modMeta.assets}');
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

      print(url);

      if (await file.length() != totalSize) Exception('文件可能在合并过程中损坏');
      status = TaskStatus.completed;

      NotificationManager.addNotice(
        icon: Icons.check_box_outlined,
        title: '下载完成',
        content: '[${modListMeta.name}(${modMeta.name})]下载完成，存储路径[$path]',
      );
      LogManager.addLog(
        LogEntry(
          LogType.info,
          '[${modListMeta.name}(${modMeta.name})]下载完成，存储路径[$path]',
        ),
      );
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

      addLog(LogEntry(LogType.error, '未知错误:$e'));
      addNotice(icon: Icons.error_outline, title: '致命错误！', content: '$e');

      await file.delete();
      rethrow;
    } finally {
      updateDisplay();
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
        Text('正在下载[${modListMeta.name}(${modMeta.name})]'),
        _chunkStatus(),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  @override
  Future<void> runTask() async {
    await _download();
  }
}

//非java模组 => 'https://github.com/<用户名>/<项目名>/archive/refs/tags/<版本号>.zip'
//下载源码.zip，github本身会分块下载且无法获取总大小，可以写一个伪进度
//   url =
//       'https://github.com/${modListMeta.repo}/archive/refs/tags/${modMeta.releaseNum}.zip';

class DownloadZipModTask extends Task {
  final ModOfficialListMeta modListMeta;
  final ModGithubMeta? modMeta;
  int downloadedSize = 0;
  double speed = 0.0;
  final String savePath;
  final CancelToken cancelToken = CancelToken();
  late File file;

  DownloadZipModTask(this.modListMeta, this.modMeta, this.savePath)
    : assert(!modListMeta.hasJava, '下载模组只能为非Java') {
    type = TaskType.download;
  }

  ///没有总大小，只能做一个伪进度，根据一些模组的大小
  void _updateProgress(int size) {
    final total = 2 * mb;
    progress = size / (total + size);
  }

  Future<void> _progressMoveTo100() async {
    final p = progress!;

    final times = (8 + 20 * (1 - p)).ceil();

    for (int i = 0; i < times; i++) {
      final c = CurveTween(
        curve: Curves.fastEaseInToSlowEaseOut,
      ).transform(i / times);
      progress = min(1.0, c * (1 - p) + p);
      updateDisplay();
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _download() async {
    var modTag = modListMeta.name;
    if (modMeta != null) {
      modTag += '(${modMeta!.releaseNum})';
    }

    NotificationManager.addNotice(
      icon: Icons.download,
      title: '下载',
      content: '正在下载模组[$modTag]',
    );
    LogManager.addLog(LogEntry(LogType.info, '正在下载模组[$modTag]'));

    var fileName = modListMeta.name;
    var url = '$githubCOM/${modListMeta.repo}/archive/refs/heads/';
    if (modMeta != null) {
      fileName += '-${modMeta!.releaseNum}';
      url += modMeta!.releaseNum;
    } else {
      if (modListMeta.mainBranchCache != null) {
        url += modListMeta.mainBranchCache!;
      } else {
        var res = await dio.head('${url}main.zip');
        if (res.statusCode == 206) {
          url += 'main';
        } else {
          res = await dio.head('${url}master.zip');
          if (res.statusCode != 206) throw Exception('找不到模组主仓库');
          url += 'master';
        }
      }
    }
    fileName += '.zip';
    url += '.zip';

    final path = p.join(savePath, fileName);
    print('$url => $path');
    file = File(path);
    if (await file.exists()) await file.delete();
    await file.create(recursive: true);

    final sizeNotifier = ValueNotifier<int>(0);
    final speedCalculator = SpeedCalculator(
      dataNotifier: sizeNotifier,
      updateCallback: (s) {
        speed = s;
        updateDisplay();
      },
    );
    try {
      await dio.download(
        url,
        path,
        cancelToken: cancelToken,
        onReceiveProgress: (receive, total) {
          downloadedSize = receive;
          sizeNotifier.value = receive;
          _updateProgress(receive);
          updateDisplay();
        },
      );

      await _progressMoveTo100();

      status = TaskStatus.completed;
      NotificationManager.addNotice(
        icon: Icons.check_box_outlined,
        title: '下载完成',
        content: '[$modTag]下载完成，存储路径[$path]',
      );
      LogManager.addLog(LogEntry(LogType.info, '[$modTag]下载完成，存储路径[$path]'));
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

      addLog(LogEntry(LogType.error, '未知错误:$e'));
      addNotice(icon: Icons.error_outline, title: '致命错误！', content: '$e');

      await file.delete();
      rethrow;
    } finally {
      speedCalculator.cancel();
      updateDisplay();
    }
  }

  @override
  void cancel() {
    super.cancel();
    cancelToken.cancel('cancel');
  }

  ///源码下载无法暂停 =>[cancel()]
  @override
  void pause() => cancel();

  String _formatDownloadProgress() {
    if (downloadedSize == 0) return '等待连接...';

    String progress;
    String downloadSpeed;

    if (downloadedSize < kb) {
      progress = '${downloadedSize.toStringAsFixed(1)}B/...';
    } else if (downloadedSize < mb) {
      progress = '${(downloadedSize / kb).toStringAsFixed(1)}KB/...';
    } else {
      progress = '${(downloadedSize / mb).toStringAsFixed(1)}MB/...';
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
    var modTag = modListMeta.name;
    if (modMeta != null) {
      modTag += '(${modMeta!.releaseNum})';
    }
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
        Text('正在下载[$modTag]'),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  @override
  Future<void> runTask() async {
    await _download();
  }
}
