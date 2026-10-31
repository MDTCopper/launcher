import 'dart:io';

import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/util/io/log.dart';

/// UI 退出 / 关窗时，把「启动器自己拉起的游戏」交接给云服务
///
/// 不交接的话 UI 进程一没，游戏退出后的上传就丢了。做法：把当前在跑的任务写成
/// `sessions/` 记录（带 gamePid），再拉起 `--cloud-service --adopt-all` 接管。
Future<bool> handoffRunningGamesToService() async {
  final running = taskManager.currentTasks
      .whereType<LaunchMindustryTask>()
      .where((task) => task.status == TaskStatus.process)
      .where((task) => task.gamePid != null)
      .toList();
  if (running.isEmpty) return false;

  for (final task in running) {
    final version = task.mindustry;
    final session = GameSession(
      id: GameSessionStore.newId(),
      versionId: version.id,
      tag: version.tag,
      phase: 'running',
      startedAt: task.createTime,
      servicePid: 0,
      gamePid: task.gamePid,
      cloudEnabled: CloudSaveService.isEnabled(version),
    );
    GameSessionStore.saveSync(session);
    addLog(
      .info,
      '交接：把运行中的游戏交给云服务 [${version.tag}] pid=${task.gamePid}',
      tag: 'CloudService',
    );
  }

  try {
    await Process.start(
      Platform.resolvedExecutable,
      ['--cloud-service', '--adopt-all'],
      mode: ProcessStartMode.detached,
      workingDirectory: File(Platform.resolvedExecutable).parent.path,
    );
    return true;
  } catch (error) {
    addLog(.warning, '交接：拉起云服务失败 $error', tag: 'CloudService');
    return false;
  }
}
