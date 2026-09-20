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
import '../loader_library.dart';
import '../mindustry_body.dart';
import '../task.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';

/// 加载器没配好（下载失败 / 收进库失败）
///
/// 单独一个类型是为了让任务收尾时分辨：本体已经下好了，**别把它一起删掉**
/// （下次重试能直接复用本体库那份）
class LoaderSetupException implements Exception {
  LoaderSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 下载完成后要建的版本记录
///
/// 启动方式由 [loaderPath] 决定：选了 loader 就建 Copper 版本（loader 按记录形态存），
/// 没选就是原版启动；抽出来是为了让用例直接验这条规则
@visibleForTesting
Mindustry buildDownloadedVersion({
  required String id,
  required String tag,
  required String bodyPath,
  required String path,
  required bool isBe,
  required String release,
  required bool isolation,
  int? versionNumber,
  String? loaderPath,
}) => Mindustry(
  id: id,
  launcher: loaderPath == null ? LauncherType.mindustry : LauncherType.copper,
  launcherPath: loaderPath == null ? null : AppPaths.toStoredPath(loaderPath),
  tag: tag,
  jarPath: AppPaths.toStoredPath(bodyPath),
  isBe: isBe,
  path: AppPaths.toStoredPath(path),
  release: release,
  addTime: DateTime.now(),
  isolation: isolation,
  versionNumber: versionNumber,
);

///官方渠道下载，path路径默认为 [项目//version]
class DownloadMindustryTask extends Task {
  final MindustryGithubMeta mindustryMeta;

  ///自定义存储路径
  late final String path;

  ///需要标签
  final String tag;

  ///下载时选的加载器（**选择结果**，还没落地）；null = 原版启动。
  ///
  /// 下载（或收进库）在本任务里做 —— 与本体一起下、进度与失败都看得见；
  /// 选了就建 Copper 版本，省得下完再「换启动器新建」
  final LoaderChoice? loader;

  final CancelToken cancelToken = CancelToken();
  late File file;

  ///本次是否真下了新文件：出错只清自己下的那份，本体库里复用来的绝不删
  bool isFreshDownload = false;
  int totalSize = 0;
  int downloadedSize = 0;
  double speed = 0.0;

  ///当前阶段的说明（如「正在下载加载器 0.1.2」）；null = 正在下本体
  String? phaseText;

  List<HttpChunkInfo> chunks = [];

  DownloadMindustryTask({
    required this.mindustryMeta,
    required this.tag,
    this.loader,
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
        file = File(reusableVersion.resolvedJarPath);
        addLog(
          .info,
          '本体库中已有 [$tag] 的游戏本体，复用 ${file.path}',
          tag: 'GameDownload',
        );
        await _addIntoConfig(bodyFilePath: reusableVersion.resolvedJarPath);
        progress = 1.0;
        status = TaskStatus.completed;

        NotificationManager.addNotice(
          icon: Icons.check_box_outlined,
          title: '复用已有游戏本体',
          content: '本体库中已有 [$tag] 的游戏本体，未重复下载',
        );
        TaskLogManager.addLog(LogEntry(LogType.info, '复用本体库中已有的 [$tag] 游戏本体'));
        return;
      }

      final jarAsset = mindustryMeta.desktopJarAsset;
      if (jarAsset == null) {
        throw Exception('该版本 release 里没有游戏本体，无法下载');
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

      addLog(.info, '下载游戏 [$tag]：$url', tag: 'GameDownload');

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
        content: '[$tag] 下载完成：游戏本体 ${file.path}',
      );
      TaskLogManager.addLog(
        LogEntry(LogType.info, '[$tag] 下载完成，游戏本体 ${file.path}'),
      );
      addLog(
        .info,
        '[$tag] 下载完成：游戏本体 ${file.path}，版本目录 $path',
        tag: 'GameDownload',
      );
    } on LoaderSetupException catch (e) {
      // 本体已经下好了：这条失败只说明加载器没配好，**别把本体一起删掉**
      // （本体库那份留着，下次重试直接复用）
      status = TaskStatus.failed;
      debugPrint('加载器没配好：$e');
      addTaskLog(LogEntry(LogType.error, '$e'));
      addNotice(icon: Icons.close, title: '加载器没配好', content: '$e');
      addLog(.error, '加载器没配好：${removeNewlines('$e')}', tag: 'Loader');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        if (e.toString().contains('paused')) {
          status = TaskStatus.paused;
        } else if (e.toString().contains('cancel')) {
          status = TaskStatus.cancel;
          Future.delayed(Duration(milliseconds: 300), () async {
            if (isFreshDownload) await file.delete();
          });
          debugPrint('取消下载：$e');

          addTaskLog(LogEntry(LogType.info, '已取消下载'));
          addNotice(icon: Icons.info_outline, title: '取消', content: '已取消下载');
          addLog(.info, '已取消下载 [$tag]', tag: 'GameDownload');
        }
      } else {
        status = TaskStatus.failed;
        debugPrint('网络错误：$e');
        addTaskLog(LogEntry(LogType.error, '网络错误：$e'));
        addNotice(icon: Icons.error_outline, title: '错误', content: '网络错误：$e');
        addLog(.warning, '网络错误：${removeNewlines('$e')}', tag: 'GameDownload');
        if (isFreshDownload) await file.delete();
      }
    } catch (e) {
      status = TaskStatus.failed;
      debugPrint('未知错误$e');
      addTaskLog(LogEntry(LogType.error, '未知错误：$e'));
      addNotice(icon: Icons.error_outline, title: '致命错误', content: '$e');
      addLog(.error, '未知错误：${removeNewlines('$e')}', tag: 'GameDownload');
      if (isFreshDownload) await file.delete();
    } finally {
      updateDisplay();
    }
  }

  Future<void> _addIntoConfig({String? bodyFilePath}) async {
    // 复用本体库里已有本体时，文件路径由调用方给进来（此时 file 不由本次下载产生）；
    // 读文件要绝对路径，写进配置走记录形态（数据根内记相对）
    final bodyPath = bodyFilePath ?? file.path;

    // 选了的加载器在这里落地（库内复用 / 本地收进库 / 远程下载）——
    // 失败会抛 LoaderSetupException，任务收尾成失败且**不建版本**
    final loaderPath = await _resolveLoader();

    // 大版本号从 jar 的 version.properties 读（FileReader 已实现），github tag 只有 build 号
    int? versionNumber;
    try {
      final reader = await FileReader.fromPath(bodyPath);
      final meta = reader.mindustry;
      versionNumber = int.tryParse(meta?.version ?? '');
    } catch (e) {
      addLogAndPrint(
        .warning,
        '读取游戏版本元数据失败：${removeNewlines('$e')}',
        tag: 'GameDownload',
      );
    }

    final launcher = loaderPath == null
        ? LauncherType.mindustry
        : LauncherType.copper;

    final mindustry = buildDownloadedVersion(
      id: id,
      tag: tag,
      bodyPath: bodyPath,
      path: path,
      isBe: mindustryMeta.isBe,
      release: mindustryMeta.tag,
      loaderPath: loaderPath,
      // 隔离与否取设置页的「游戏默认隔离设置」，不再写死
      isolation: config.setting.launchOptions.isIsolatedByDefault(
        isBe: mindustryMeta.isBe,
        launcher: launcher,
      ),
      versionNumber: versionNumber,
    );

    // 找 fold 用解析后的路径比：记录形态可能是相对、也可能还是老的绝对路径
    final foldIndex = config.versionOptions.versionFolds.indexWhere(
      (fold) =>
          AppPaths.resolveStoredPath(fold.path) ==
          AppPaths.resolveStoredPath(mindustry.path),
    );
    if (foldIndex != -1) {
      config.versionOptions.versionFolds[foldIndex].versions.add(mindustry);
      config.saveAsJson();
      //版本建在哪、用什么启动、隔离开没开——后续「导入/存档跑到别处去了」都要靠这条对账
      addLog(
        .info,
        '创建版本 [${mindustry.tag}]（下载）：启动方式 '
        '${mindustry.isViaLoader ? 'Copper 加载器' : '原版'}，'
        '存档隔离${mindustry.isolation ? '开启' : '关闭'}，数据目录：${mindustry.dataPath}',
        tag: 'GameDownload',
      );
    } else {
      //todo 新的路径可以询问玩家是否创建，不创建就移入默认文件夹
      addLogAndPrint(.error, '无法同步配置文件', tag: 'GameDownload');
    }
  }

  /// 把选好的加载器落到实处，返回可用的绝对路径（null = 原版启动）
  ///
  /// - 库内已有的：直接用（不重复下载）
  /// - 本地 jar：收进加载器库
  /// - 远程版本：下载（进度接到本任务的进度条上）
  ///
  /// 任何一步失败都抛 [LoaderSetupException]，由 [_download] 收尾成「任务失败」，
  /// 不建版本 —— 用户要的是 Copper 版本，别默默给一个原版
  Future<String?> _resolveLoader() async {
    final choice = loader;
    if (choice == null || choice.useNone) return null;
    if (choice.loaderPath case final path?) return path;

    final localPath = choice.localFile;
    if (localPath != null) {
      try {
        return await LoaderLibrary.importIntoLibrary(File(localPath));
      } catch (e) {
        throw LoaderSetupException('加载器没放进加载器库：${removeNewlines('$e')}');
      }
    }

    final remote = choice.remote;
    if (remote == null) return null;

    phaseText = '正在下载加载器 ${remote.tag}';
    downloadedSize = 0;
    totalSize = 0;
    chunks = [];
    progress = 0;
    updateDisplay();
    TaskLogManager.addLog(LogEntry(LogType.info, '正在下载加载器 ${remote.tag}'));
    addLog(.info, '下载加载器 [${remote.tag}]：${remote.url}', tag: 'Loader');

    try {
      final path = await LoaderLibrary.downloadDesktop(
        tag: remote.tag,
        url: remote.url,
        cancelToken: cancelToken,
        onProgress: (value) {
          progress = value;
          updateDisplay();
        },
      );
      addLog(.info, '加载器已就位：$path', tag: 'Loader');
      return path;
    } catch (e) {
      throw LoaderSetupException(
        '加载器 ${remote.tag} 没下下来：${removeNewlines('$e')}',
      );
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
            if (canCancel)
              ReboundButton(onTap: cancel, child: Icon(Icons.close)),
          ],
        ),
        LinearProgressIndicator(value: progress),
        if (progress != null)
          Row(
            children: [
              Text(formatProgress()),
              Expanded(child: SizedBox()),
              // 下载加载器那一段的字节数不是本体那份，别混着显示
              if (phaseText == null) Text(_formatDownloadProgress()),
            ],
          ),
        Text(phaseText ?? '正在下载[$tag]'),
        if (phaseText == null) _chunkStatus(),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
