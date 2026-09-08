import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/shell/drawer/log_list.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/java/java_downloader.dart';
import 'package:flutter/material.dart';

import 'package:copper_launcher/ui/components/button/rebound_button.dart';

///Java 下载安装任务：从 Adoptium 拉 JDK，解压到 [AppPaths.java]，
///装完自动写入配置的 javas 列表。
class JavaDownloadTask extends Task {
  final int version;

  final CancelToken cancelToken = CancelToken();

  ///当前状态文案（下载中 / 解压中 / 已完成...）
  String? statusText;

  JavaDownloadTask({required this.version}) {
    type = TaskType.download;
  }

  @override
  void cancel() {
    super.cancel();
    cancelToken.cancel('cancel');
  }

  @override
  void pause() => cancel();

  @override
  Future<void> runTask() async {
    addTaskLog(LogEntry(LogType.info, '开始下载 Java $version'));

    final javaExe = await JavaDownloader.downloadAndInstall(
      version: version,
      installDir: AppPaths.java,
      cancelToken: cancelToken,
      onProgress: (p) {
        progress = p;
        updateDisplay();
      },
      onStatus: (s) {
        statusText = s;
        updateDisplay();
      },
    );

    if (cancelToken.isCancelled) {
      status = TaskStatus.cancel;
      updateDisplay();
      return;
    }

    if (javaExe == null) {
      status = TaskStatus.failed;
      addTaskLog(LogEntry(LogType.error, 'Java $version 安装失败'));
      addNotice(
        icon: Icons.error_outline,
        title: 'Java 下载失败',
        content: 'Java $version 安装失败，请检查网络后重试',
      );
      updateDisplay();
      return;
    }

    //写入配置的 javas 列表（路径重复则替换）
    final javas = config.setting.launchOptions.javaOptions.javas;
    javas.removeWhere((it) => it.path == javaExe);
    javas.add(JavaInfo(path: javaExe, version: version));
    await config.save();

    progress = 1.0;
    status = TaskStatus.completed;
    addTaskLog(LogEntry(LogType.success, 'Java $version 安装完成'));
    addNotice(
      icon: Icons.check_box_outlined,
      title: 'Java 安装完成',
      content: 'Java $version 已安装，可在设置中选择使用',
    );
    updateDisplay();
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
              '下载Java $version',
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
          Text(
            statusText ?? formatProgress(),
            style: theme.textTheme.bodySmall,
          ),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}