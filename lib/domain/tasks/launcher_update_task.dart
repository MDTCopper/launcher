import 'package:copper_launcher/domain/launcher_update.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/shell/drawer/log_list.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/path_selector.dart';
import 'package:copper_launcher/util/launcher_tray.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// 下载启动器更新包
///
/// Windows 的安装版直接拉起 Setup 并退出启动器（安装器负责替换文件）；
/// 解压版与其它平台只下载，然后打开下载目录，由用户退出后自己覆盖
class LauncherUpdateTask extends Task {
  LauncherUpdateTask({required this.release, required this.asset}) {
    type = TaskType.download;
  }

  final LauncherRelease release;

  final LauncherAsset asset;

  final CancelToken cancelToken = CancelToken();

  /// 当前状态文案（下载中 / 正在安装...）
  String? statusText;

  /// 下载完的落盘路径
  String? downloadedPath;

  @override
  void cancel() {
    super.cancel();
    cancelToken.cancel('cancel');
  }

  @override
  void pause() => cancel();

  @override
  Future<void> runTask() async {
    addTaskLog(LogEntry(LogType.info, '开始下载启动器更新 ${release.tag}'));
    try {
      final path = await LauncherUpdate.downloadAsset(
        asset: asset,
        cancelToken: cancelToken,
        onProgress: (value) {
          progress = value;
          statusText = '下载 ${asset.name}';
          updateDisplay();
        },
      );

      if (cancelToken.isCancelled) {
        status = TaskStatus.cancel;
        updateDisplay();
        return;
      }

      downloadedPath = path;
      await _finishUpdate(path);
    } catch (e) {
      status = TaskStatus.failed;
      addTaskLog(LogEntry(LogType.error, '启动器更新下载失败：$e'));
      addNotice(
        icon: Icons.close,
        title: '更新下载失败',
        content: '稍后再试，或到 release 页手动下载',
      );
      updateDisplay();
    }
  }

  /// 收尾：安装版拉起 Setup、解压版写覆盖脚本，两者都要退出启动器
  /// （运行中的 exe / dll 不能覆盖，必须等进程退出）；其余平台打开下载目录
  Future<void> _finishUpdate(String path) async {
    progress = 1.0;

    if (LauncherUpdate.shouldRunInstaller(asset)) {
      statusText = '正在安装';
      status = TaskStatus.completed;
      addTaskLog(LogEntry(LogType.success, '更新包已下载，拉起安装程序：$path'));
      addNotice(
        icon: Icons.system_update_alt,
        title: '正在安装更新',
        content: '安装程序启动后启动器会退出，装完重新打开即可',
      );
      updateDisplay();

      await LauncherUpdate.runInstaller(path);
      // 留一点时间让日志与通知落地，再退出（安装器随后要替换本进程的文件）
      await Future.delayed(const Duration(seconds: 1));
      await LauncherTray.instance.quitApp();
      return;
    }

    if (LauncherUpdate.shouldReplacePortable(asset)) {
      statusText = '正在替换文件';
      status = TaskStatus.completed;
      addTaskLog(LogEntry(LogType.success, '更新包已下载，退出后由脚本覆盖：$path'));
      addNotice(
        icon: Icons.system_update_alt,
        title: '正在安装更新',
        content: '启动器会退出并重新打开，用户数据不受影响',
      );
      updateDisplay();

      await LauncherUpdate.runPortableReplace(zipPath: path);
      await Future.delayed(const Duration(seconds: 1));
      await LauncherTray.instance.quitApp();
      return;
    }

    status = TaskStatus.completed;
    addTaskLog(LogEntry(LogType.success, '更新包已下载：$path'));
    addNotice(
      icon: Icons.folder_open,
      title: '更新包已下载',
      content: '退出启动器后用它覆盖当前版本：${p.basename(path)}',
    );
    updateDisplay();
    await PathSelector.openFolder(LauncherUpdate.downloadDir.path);
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
              '更新启动器',
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
          Text(formatProgress(), style: theme.textTheme.bodySmall),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
