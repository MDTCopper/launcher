import 'dart:io';

import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/domain/tasks/takeover_session_task.dart';
import 'package:copper_launcher/util/game_process_watch.dart';
import 'package:copper_launcher/util/io/log.dart';

/// UI 与服务之间**唯一**的会话交接入口
///
/// 所有权只有两种迁移，其它路径都不该直接改 `GameSession.owner`：
/// - `service → ui`：UI 后开时请求接管；服务消费请求并退出，游戏进程不动
/// - `ui → service`：UI 退出/关窗时交接；写 session 后拉起 `--cloud-service --adopt-all`
///
/// 服务进程内部的 `_transferToUi` 是第一条迁移的另一半；`_adoptAll` 是服务启动时
/// 把已写好的 owner=service 会话接回内存，不改变 owner。UI 的 monitor 只在
/// 「服务已死」时直接把 owner 改成 ui，这个兜底不在正常交接路径上。
class SessionOwnership {
  SessionOwnership._();

  /// 两个实例同时拉起服务没有意义；5 秒内只尝试一次
  static const _spawnCooldown = Duration(seconds: 5);
  static DateTime? _lastSpawn;

  /// UI 退出/关窗：把当前 UI 正在管的游戏交给云服务
  ///
  /// 包括启动器自己拉起的 [LaunchMindustryTask] 和已接管过来的
  /// [TakeoverSessionTask]；没有运行中的游戏时直接返回 false，不拉服务。
  static Future<bool> handoffToService() async {
    addLog(.info, '交接：开始检查运行中的游戏', tag: 'CloudService');
    final launches = taskManager.currentTasks
        .whereType<LaunchMindustryTask>()
        .where((task) => task.status == TaskStatus.process)
        .where((task) => task.gamePid != null)
        .where((task) => !task.isExiting)
        .where((task) => GameProcessWatch.isAlive(task.gamePid!))
        .toList();
    final takeovers = taskManager.currentTasks
        .whereType<TakeoverSessionTask>()
        .where((task) => task.status == TaskStatus.process)
        .where((task) => task.session.gamePid != null)
        .where((task) => !task.isExiting)
        .where((task) => GameProcessWatch.isAlive(task.session.gamePid!))
        .toList();
    final skippedExiting = taskManager.currentTasks
            .whereType<LaunchMindustryTask>()
            .where((task) => task.isExiting)
            .length +
        taskManager.currentTasks
            .whereType<TakeoverSessionTask>()
            .where((task) => task.isExiting)
            .length;
    // UI 后开接管但还没建出任务时，只有 owner=ui 的 session；这类也要交接
    final knownVersions = <String>{
      ...launches.map((task) => task.mindustry.id),
      ...takeovers.map((task) => task.session.versionId),
    };
    final orphanSessions = <GameSession>[];
    for (final session in await GameSessionStore.active()) {
      if (session.owner != 'ui' ||
          knownVersions.contains(session.versionId) ||
          session.gamePid == null ||
          !GameProcessWatch.isAlive(session.gamePid!)) {
        continue;
      }
      session
        ..owner = 'service'
        ..phase = 'running';
      GameSessionStore.saveSync(session);
      orphanSessions.add(session);
      addLog(
        .info,
        '交接：把 owner=ui 的会话交还云服务 [${session.tag}] pid=${session.gamePid}',
        tag: 'CloudService',
      );
    }
    addLog(
      .info,
      '交接：可交 LaunchTask=${launches.length} TakeoverTask=${takeovers.length} '
          'OrphanSession=${orphanSessions.length} 正在退出/已结束=$skippedExiting',
      tag: 'CloudService',
    );
    if (launches.isEmpty && takeovers.isEmpty && orphanSessions.isEmpty) {
      return false;
    }

    // 先挂起 UI 任务的退出收尾：服务拉起期间游戏退出也不能两边同时处理
    for (final task in launches) {
      task.prepareHandoff();
    }
    for (final task in takeovers) {
      task.prepareHandoff();
    }

    final handoffSessions = <GameSession>[];
    for (final task in launches) {
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
      handoffSessions.add(session);
      addLog(
        .info,
        '交接：把运行中的游戏交给云服务 [${version.tag}] pid=${task.gamePid}',
        tag: 'CloudService',
      );
    }

    for (final task in takeovers) {
      final session = task.session
        ..owner = 'service'
        ..phase = 'running';
      GameSessionStore.saveSync(session);
      addLog(
        .info,
        '交接：把已接管的游戏交还云服务 [${session.tag}] pid=${session.gamePid}',
        tag: 'CloudService',
      );
    }

    final started = await ensureService(adoptAll: true, force: true);
    if (!started) {
      // 服务没起来：撤掉刚写的 session，让 UI 任务自己按正常退出收尾
      for (final task in launches) {
        task.completeHandoff(transferred: false);
      }
      for (final task in takeovers) {
        task.completeHandoff(transferred: false);
      }
      for (final session in handoffSessions) {
        await GameSessionStore.remove(session.id);
      }
      for (final session in orphanSessions) {
        session
          ..owner = 'ui'
          ..phase = 'running';
        GameSessionStore.saveSync(session);
      }
      addLog(.warning, '交接：服务没起来，保留 UI 任务收尾', tag: 'CloudService');
      return false;
    }
    // 服务已经接手：UI 侧任务退出时不要再上传/写 config，否则两套收尾会重复
    for (final task in launches) {
      task.completeHandoff(transferred: true);
    }
    for (final task in takeovers) {
      task.completeHandoff(transferred: true);
    }
    return true;
  }

  /// 需要云服务时统一从这里拉起，带冷却避免重复进程
  static Future<bool> ensureService({
    bool adoptAll = false,
    bool recover = false,
    bool force = false,
  }) async {
    if (!force && await GameSessionStore.isServiceRunning()) return false;
    final last = _lastSpawn;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _spawnCooldown) {
      return false;
    }
    _lastSpawn = DateTime.now();
    final args = <String>[
      '--cloud-service',
      if (adoptAll) '--adopt-all',
      if (recover) '--recover',
    ];
    try {
      await Process.start(
        Platform.resolvedExecutable,
        args,
        mode: ProcessStartMode.detached,
        workingDirectory: File(Platform.resolvedExecutable).parent.path,
      );
      addLog(.info, '会话：拉起云服务 ${args.skip(1).join(' ')}', tag: 'CloudService');
      return true;
    } catch (error) {
      addLog(.warning, '会话：拉起云服务失败 $error', tag: 'CloudService');
      return false;
    }
  }

  /// UI 后开：请求服务把某一局的所有权交给 UI
  static Future<void> requestTakeover(String sessionId) =>
      GameSessionStore.requestTakeover(sessionId);
}
