import 'package:copper_launcher/domain/bridge_installer.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/shell/drawer/log_list.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:flutter/material.dart';

/// 这次要装运行环境的哪一块
enum BridgeRuntimeTarget {
  /// 一键准备好：三件套缺什么装什么（给不懂的人用）
  all,

  /// Java 运行环境
  jre,

  /// Copper 桥
  bridge,

  /// 模组加载器适配层
  wrapper,
}

extension BridgeRuntimeTargetLabel on BridgeRuntimeTarget {
  String get label => switch (this) {
    .all => '运行环境',
    .jre => 'Java 运行环境',
    .bridge => 'Copper 桥',
    .wrapper => '模组加载器适配层',
  };
}

/// 装 / 重装 Android 桥的运行环境，走任务抽屉（进度、阶段文案、可取消）
///
/// [force] 为 true 时无条件重下（设置页各行的「重装」）；
/// 一键那档用 false —— 已经齐的就不再下，避免白白吃流量
class BridgeRuntimeTask extends Task {
  final BridgeRuntimeTarget target;
  final bool force;

  final CancelToken cancelToken = CancelToken();

  /// 当前阶段文案（下载中 / 解压中 / 已就绪…）
  String? statusText;

  BridgeRuntimeTask({required this.target, this.force = false}) {
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
    addTaskLog(
      LogEntry(LogType.info, '开始安装${target.label}${force ? '（重装）' : ''}'),
    );

    try {
      final abi = await BridgeInstaller.detectDeviceAbi();
      if (abi == null) {
        throw StateError('认不出这台设备的 ABI，选不了对应的 Java 运行环境');
      }

      switch (target) {
        case .all:
          await BridgeInstaller.installRuntime(
            abi: abi,
            force: force,
            cancelToken: cancelToken,
            onStatus: _setStatus,
            onProgress: _setProgress,
          );
          await BridgeInstaller.installLoaderWrapper(
            force: force,
            cancelToken: cancelToken,
            onStatus: _setStatus,
          );
        case .jre:
          await BridgeInstaller.installJre(
            abi: abi,
            force: force,
            cancelToken: cancelToken,
            onStatus: _setStatus,
            onProgress: _setProgress,
          );
        case .bridge:
          final tag = await BridgeInstaller.installBridgeJar(
            force: force,
            cancelToken: cancelToken,
            onStatus: _setStatus,
            onProgress: _setProgress,
          );
          addTaskLog(LogEntry(LogType.info, '桥版本：$tag'));
        case .wrapper:
          await BridgeInstaller.installLoaderWrapper(
            force: force,
            cancelToken: cancelToken,
            onStatus: _setStatus,
          );
      }
    } catch (error) {
      if (cancelToken.isCancelled) {
        status = TaskStatus.cancel;
        updateDisplay();
        return;
      }
      status = TaskStatus.failed;
      addTaskLog(LogEntry(LogType.error, '${target.label}安装失败：$error'));
      addNotice(
        icon: Icons.error_outline,
        title: '${target.label}安装失败',
        content: '检查网络后可在设置里重试',
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
    addTaskLog(LogEntry(LogType.success, '${target.label}已就绪'));
    addNotice(
      icon: Icons.check_box_outlined,
      title: '${target.label}已就绪',
      content: force ? '已重新装好' : '缺的与有更新的都装好了',
    );
    updateDisplay();
  }

  void _setStatus(String status) {
    statusText = status;
    updateDisplay();
  }

  void _setProgress(HttpDownloadState state) {
    progress = state.progress;
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
            const SizedBox(width: 4),
            Text(
              '安装${target.label}',
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
              TextButton(onPressed: cancel, child: const Text('取消')),
          ],
        ),
        LinearProgressIndicator(value: progress),
        if (progress != null)
          Text(
            statusText ?? formatProgress(),
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}
