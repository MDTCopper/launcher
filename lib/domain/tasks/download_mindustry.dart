import 'dart:io';

import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../data/local_asset.dart';
import '../../data/net_asset.dart';
import '../../ui/shell/drawer/log_list.dart';
import '../../ui/util/notification.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import '../../util/app_paths.dart';
import '../../util/format/byte_unit.dart';
import '../../util/io/file_reader.dart';
import '../mindustry_body.dart';
import '../task.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';

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

  ///本次是否真下了新文件：出错只清自己下的那份，本体库里复用来的绝不删
  bool isFreshDownload = false;
  int totalSize = 0;
  int downloadedSize = 0;
  double speed = 0.0;

  List<HttpChunkInfo> chunks = [];

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
    await _download();
  }

  Future<void> _download() async {
    NotificationManager.addNotice(
      icon: Icons.download,
      title: '下载',
      content: '正在下载游戏[$tag]',
    );
    TaskLogManager.addLog(LogEntry(LogType.info, '正在下载游戏[$tag]'));

    try {
      //本体库里已有这个版本的可用本体就直接复用，不再下一次（重复下载同一个版本、或变体共用本体都走这里）
      final reusableVersion = MindustryBody.findUsableLibraryBody(
        isBe: mindustryMeta.isBe,
        release: mindustryMeta.tag,
      );
      if (reusableVersion != null) {
        file = File(reusableVersion.jarPath);
        addLog(
          .info,
          '本体库中已有 [$tag] 的本体，直接复用 ${file.path}',
          tag: 'GameDownload',
        );
        await _addIntoConfig(jarPath: reusableVersion.jarPath);
        progress = 1.0;
        status = TaskStatus.completed;

        NotificationManager.addNotice(
          icon: Icons.check_box_outlined,
          title: '复用已有本体',
          content: '本体库中已有 [$tag] 的游戏本体，未重复下载',
        );
        TaskLogManager.addLog(LogEntry(LogType.info, '复用本体库中已有的[$tag]本体'));
        return;
      }

      final jarAsset = mindustryMeta.desktopJarAsset;
      if (jarAsset == null) {
        throw Exception('该版本 release 中没有游戏本体 jar，无法下载');
      }
      final String url = jarAsset.url;

      //本体进本体库集中存放（与导入共用一份，变体直接引用）；文件名带来源 hash，
      //同一 URL 永远落到同一路径，断点续传不受影响
      file = File(
        await MindustryBody.downloadPath(
          identity: mindustryMeta.tag,
          sourceUrl: url,
        ),
      );
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      isFreshDownload = true;

      addLog(.info, '下载游戏[$tag],$url', tag: 'GameDownload');

      await cio.download(
        url: url,
        savePath: file.path,
        cancelToken: cancelToken,
        deleteOnError: false,
        onStatus: (s) {
          totalSize = s.total;
          downloadedSize = s.downloaded;
          speed = s.speed;
          progress = s.total > 0 ? s.downloaded / s.total : 0;
          chunks = s.chunks;
          updateDisplay();
        },
      );
      //检查文件完整性
      if (totalSize > 0 && await file.length() != totalSize) {
        throw Exception('文件可能在合并过程中损坏');
      }
      await _addIntoConfig();
      status = TaskStatus.completed;

      NotificationManager.addNotice(
        icon: Icons.check_box_outlined,
        title: '下载完成',
        content: '[$tag]下载完成，本体 ${file.path}',
      );
      TaskLogManager.addLog(LogEntry(LogType.info, '[$tag]下载完成，本体${file.path}'));
      addLog(.info, '[$tag]下载完成，本体${file.path}，版本目录$path', tag: 'GameDownload');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        if (e.toString().contains('paused')) {
          status = TaskStatus.paused;
        } else if (e.toString().contains('cancel')) {
          status = TaskStatus.cancel;
          Future.delayed(Duration(milliseconds: 300), () async {
            if (isFreshDownload) await file.delete();
          });
          debugPrint('取消下载:$e');

          addTaskLog(LogEntry(LogType.info, '已取消下载'));
          addNotice(icon: Icons.info_outline, title: '取消', content: '已取消下载');
          addLog(.info, '已取消下载[$tag]', tag: 'GameDownload');
        }
      } else {
        status = TaskStatus.failed;
        debugPrint('网络错误：$e');
        addTaskLog(LogEntry(LogType.error, '网络错误:$e'));
        addNotice(icon: Icons.error_outline, title: '错误', content: '网络错误:$e');
        addLog(.warning, '网络错误:${removeNewlines('$e')}', tag: 'GameDownload');
        if (isFreshDownload) await file.delete();
      }
    } catch (e) {
      status = TaskStatus.failed;
      debugPrint('未知错误$e');
      addTaskLog(LogEntry(LogType.error, '未知错误:$e'));
      addNotice(icon: Icons.error_outline, title: '致命错误！', content: '$e');
      addLog(.error, '未知错误:${removeNewlines('$e')}', tag: 'GameDownload');
      if (isFreshDownload) await file.delete();
    } finally {
      updateDisplay();
    }
  }

  Future<void> _addIntoConfig({String? jarPath}) async {
    // 复用本体库里已有本体时，jar 路径由调用方给进来（此时 file 不由本次下载产生）
    final bodyPath = jarPath ?? file.path;

    // 大版本号从 jar 的 version.properties 读（FileReader 已实现），github tag 只有 build 号
    int? versionNumber;
    try {
      final reader = await FileReader.fromPath(bodyPath);
      final meta = reader.mindustry;
      versionNumber = int.tryParse(meta?.version ?? '');
    } catch (e) {
      addLogAndPrint(.warning, '读取游戏版本元数据失败：${removeNewlines('$e')}', tag: 'GameDownload');
    }

    // 隔离与否取设置页的「游戏默认隔离设置」，不再写死
    final isolation = config.setting.launchOptions.isIsolatedByDefault(
      isBe: mindustryMeta.isBe,
      launcher: LauncherType.mindustry,
    );

    final mindustry = Mindustry(
      id: id,
      launcher: LauncherType.mindustry,
      tag: tag,
      jarPath: bodyPath,
      isBe: mindustryMeta.isBe,
      path: path,
      release: mindustryMeta.tag,
      addTime: DateTime.now(),
      isolation: isolation,
      versionNumber: versionNumber,
    );
    final foldIndex = config.versionOptions.versionFolds.indexWhere(
      (fold) => fold.path == mindustry.path,
    );
    if (foldIndex != -1) {
      config.versionOptions.versionFolds[foldIndex].versions.add(mindustry);
      config.saveAsJson();
      //版本建在哪、隔离开没开——后续「导入/存档跑到别处去了」都要靠这条对账
      addLog(
        .info,
        '创建版本 [${mindustry.tag}]（下载），存档隔离${isolation ? '开启' : '关闭'}，数据目录：${mindustry.dataPath}',
        tag: 'GameDownload',
      );
    } else {
      //todo 新的路径可以询问玩家是否创建，不创建就移入默认文件夹
      addLogAndPrint(.error, '无法同步配置文件', tag: 'GameDownload');
    }
  }

  String _formatDownloadProgress() {
    if ([downloadedSize, totalSize].contains(0)) return '等待连接...';

    String progress;
    String downloadSpeed;

    if (totalSize < KB) {
      progress =
          '${downloadedSize.toStringAsFixed(1)}/${totalSize.toStringAsFixed(1)}B';
    } else if (totalSize < MB) {
      progress =
          '${(downloadedSize / KB).toStringAsFixed(1)}/${(totalSize / KB).toStringAsFixed(1)}KB';
    } else if (totalSize < GB) {
      progress =
          '${(downloadedSize / MB).toStringAsFixed(1)}/${(totalSize / MB).toStringAsFixed(1)}MB';
    } else {
      progress =
          '${(downloadedSize / GB).toStringAsFixed(1)}/${(totalSize / GB).toStringAsFixed(1)}GB';
    }

    if (speed < KB) {
      downloadSpeed = '${(speed).toStringAsFixed(1)}B/S';
    } else if (speed < MB) {
      downloadSpeed = '${(speed / KB).toStringAsFixed(1)}KB/S';
    } else {
      downloadSpeed = '${(speed / MB).toStringAsFixed(1)}MB/S';
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

    final connectedCount = chunks
        .where(
          (it) =>
              it.status == HttpChunkStatus.downloading ||
              it.status == HttpChunkStatus.complete,
        )
        .length;

    if (connectedCount == chunks.length) {
      String str = '共${chunks.length}个分块：\n';

      for (var o in chunks) {
        final progress = o.received / o.size * 100;
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
            if (statusLabel != null)
              Text(statusLabel!, style: theme.textTheme.bodySmall),
            if (canCancel) ReboundButton(onTap: cancel, child: Icon(Icons.close)),
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
