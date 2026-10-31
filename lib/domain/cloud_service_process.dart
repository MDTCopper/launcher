import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_runtime.dart';
import 'package:copper_launcher/domain/cloud/cloud_auto_sync.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/domain/game_instance.dart';
import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/game_process_watch.dart';
import 'package:copper_launcher/util/io/log.dart';

/// 无界面云存档服务：拉起游戏、等它退出、上传完再退
///
/// 与 UI 进程分开：UI 关了也不影响这一局的退出上传。会话写
/// `cloud-service/sessions/*.json`，被阻塞时把请求写进 `pending/` 并拉起 UI。
class CloudServiceProcess {
  CloudServiceProcess._();

  /// 服务空闲多久后自己退
  static const idleExit = Duration(seconds: 30);

  final Map<String, LaunchMindustryTask> _tasks = {};
  final Map<String, GameSession> _sessions = {};

  Timer? _timer;
  bool _exiting = false;
  DateTime _lastActive = DateTime.now();

  static Future<void> start({
    String? launchVersionId,
    bool adoptAll = false,
    bool recover = false,
  }) async {
    await GameSessionStore.ensureDirs();
    await GameSessionStore.writeServicePid();
    addLog(
      .info,
      '云服务：启动（pid=$pid，数据根 ${AppPaths.copperLauncher}）',
      tag: 'CloudService',
    );
    final service = CloudServiceProcess._();
    if (launchVersionId != null) {
      await service._launch(launchVersionId, 'service_launch');
    }
    if (adoptAll) await service._adoptAll();
    if (recover) await service._recover();
    service._timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(service._tick()),
    );
  }

  Future<void> _tick() async {
    if (_exiting) return;
    try {
      for (final ticket in await GameSessionStore.takeRequests()) {
        await _launch(ticket.versionId, ticket.reason);
      }
      await _syncRunningSessions();
      await _finishAdopted();
      if (_tasks.isEmpty && _sessions.values.every((s) => !s.isActive)) {
        if (DateTime.now().difference(_lastActive) > idleExit) {
          await _exit();
        }
      } else {
        _lastActive = DateTime.now();
      }
    } catch (error) {
      addLog(.warning, '云服务：轮询失败 ${error.toString()}', tag: 'CloudService');
    }
  }

  Future<void> _launch(String versionId, String reason) async {
    if (_tasks.containsKey(versionId)) {
      addLog(.info, '云服务：这个版本已经在启动/运行 [$versionId]', tag: 'CloudService');
      return;
    }
    final version = config.versionOptions.findVersionById(versionId);
    if (version == null) {
      addLog(.warning, '云服务：找不到版本 $versionId，交回界面', tag: 'CloudService');
      await _delegate(versionId, 'version_not_found');
      return;
    }
    if (GameInstance.blockReason(version) != GameLaunchBlock.none) {
      addLog(.info, '云服务：启动被单实例规则拦住，交回界面 [${version.tag}]', tag: 'CloudService');
      await _delegate(versionId, 'blocked');
      return;
    }
    // 文件里的活跃会话可能来自「服务死了但游戏还在跑」：别起第二局
    for (final active in await GameSessionStore.active()) {
      final other = config.versionOptions.findVersionById(active.versionId);
      if (active.versionId == version.id) {
        addLog(.info, '云服务：这个版本已有一局在跑，交回界面 [${version.tag}]', tag: 'CloudService');
        await _delegate(versionId, 'already_running');
        return;
      }
      if (other != null && GameInstance.sameDataPath(other, version)) {
        addLog(.info, '云服务：数据目录已被另一局占用，交回界面 [${version.tag}]', tag: 'CloudService');
        await _delegate(versionId, 'same_data');
        return;
      }
    }

    AppRuntime.clearNeedsUi();
    final session = GameSession(
      id: GameSessionStore.newId(),
      versionId: version.id,
      tag: version.tag,
      phase: 'launching',
      startedAt: DateTime.now(),
      servicePid: pid,
      cloudEnabled: CloudSaveService.isEnabled(version),
    );
    await GameSessionStore.save(session);
    _sessions[version.id] = session;

    addLog(.info, '云服务：启动 [${version.tag}]（$reason）', tag: 'CloudService');
    await GameInstance.launch(version);

    final task = _findTask(version.id);
    if (task == null) {
      addLog(.warning, '云服务：启动任务没建起来，交回界面 [${version.tag}]', tag: 'CloudService');
      session.phase = 'delegated';
      session.error = 'no_task';
      await GameSessionStore.save(session);
      await _delegate(version.id, 'no_task');
      return;
    }
    _tasks[version.id] = task;
    _watch(task, session);
  }

  LaunchMindustryTask? _findTask(String versionId) {
    for (final task in taskManager.currentTasks.whereType<LaunchMindustryTask>()) {
      if (task.mindustry.id == versionId) return task;
    }
    return null;
  }

  void _watch(LaunchMindustryTask task, GameSession session) {
    void listener() {
      final status = task.status;
      if (status == TaskStatus.pending || status == TaskStatus.process) return;
      task.removeListener(listener);
      unawaited(_onTaskEnd(task, session));
    }

    task.addListener(listener);
  }

  Future<void> _onTaskEnd(LaunchMindustryTask task, GameSession session) async {
    final version = task.mindustry;
    _tasks.remove(version.id);
    _sessions.remove(version.id);

    if (AppRuntime.needsUi) {
      final reason = AppRuntime.needsUiReason.isEmpty
          ? 'needs_ui'
          : AppRuntime.needsUiReason;
      AppRuntime.clearNeedsUi();
      addLog(.info, '云服务：这局需要界面处理（$reason），拉起 UI', tag: 'CloudService');
      session.phase = 'delegated';
      session.error = reason;
      await GameSessionStore.save(session);
      await _delegate(version.id, reason);
      return;
    }

    if (task.status == TaskStatus.completed) {
      session.phase = 'uploading';
      final played = task.playedDuration;
      if (played != null) session.playSeconds = played.inSeconds;
      await GameSessionStore.save(session);
      // 任务收尾里已经 fire-and-forget 了 afterGameExit；这里等它传完
      await CloudAutoSync.waitForPending();
      session.phase = 'done';
      session.completedAt = DateTime.now();
      await GameSessionStore.save(session);
      addLog(.info, '云服务：这一局结束，已上传并记录 [${version.tag}]', tag: 'CloudService');
      _lastActive = DateTime.now();
      return;
    }

    session.phase = 'failed';
    session.error = 'launch_${task.status.name}';
    session.completedAt = DateTime.now();
    await GameSessionStore.save(session);
    addLog(.warning, '云服务：启动任务结束（${task.status.name}）[${version.tag}]', tag: 'CloudService');
    _lastActive = DateTime.now();
  }

  Future<void> _syncRunningSessions() async {
    for (final entry in _sessions.entries.toList()) {
      final session = entry.value;
      final task = _tasks[entry.key];
      if (task == null) continue;
      final gamePid = task.gamePid;
      var changed = false;
      if (gamePid != null && gamePid != session.gamePid) {
        session.gamePid = gamePid;
        changed = true;
      }
      if (task.status == TaskStatus.process && session.phase == 'launching') {
        session.phase = 'running';
        changed = true;
      }
      if (changed) await GameSessionStore.save(session);
    }
  }

  /// 服务被重启：接管还活着的游戏会话
  Future<void> _adoptAll() async {
    for (final session in await GameSessionStore.active()) {
      if (session.phase == 'running' &&
          session.gamePid != null &&
          GameProcessWatch.isAlive(session.gamePid!)) {
        _sessions[session.versionId] = session;
        addLog(.info, '云服务：接管运行中的游戏 [${session.tag}] pid=${session.gamePid}', tag: 'CloudService');
      } else {
        await _recoverSession(session);
      }
    }
  }

  /// 补做服务死后没上传的退出同步
  Future<void> _recover() async {
    for (final session in await GameSessionStore.active()) {
      await _recoverSession(session);
    }
  }

  Future<void> _recoverSession(GameSession session) async {
    final version = config.versionOptions.findVersionById(session.versionId);
    if (version == null) {
      session.phase = 'failed';
      session.error = 'version_missing';
      await GameSessionStore.save(session);
      return;
    }
    addLog(.info, '云服务：补做退出上传 [${session.tag}]', tag: 'CloudService');
    await CloudAutoSync.afterGameExit(version);
    await CloudAutoSync.waitForPending();
    session.phase = 'done';
    session.completedAt = DateTime.now();
    // 接管的会话没有任务对象，用开始时间补一个游玩时长给 UI 导入
    session.playSeconds ??= session.completedAt!
        .difference(session.startedAt)
        .inSeconds;
    await GameSessionStore.save(session);
  }

  Future<void> _finishAdopted() async {
    for (final entry in _sessions.entries.toList()) {
      final session = entry.value;
      if (session.phase != 'running') continue;
      if (_tasks.containsKey(entry.key)) continue;
      final gamePid = session.gamePid;
      if (gamePid == null) continue;
      if (GameProcessWatch.isAlive(gamePid)) continue;
      _sessions.remove(entry.key);
      await _recoverSession(session);
    }
  }

  /// 交回界面：写 pending；UI 没在跑就拉起一个
  Future<void> _delegate(String versionId, String reason) async {
    await GameSessionStore.writePending(versionId: versionId, reason: reason);
    if (!await GameSessionStore.isUiRunning()) {
      try {
        await Process.start(
          Platform.resolvedExecutable,
          ['--resume-launch', versionId],
          mode: ProcessStartMode.detached,
          workingDirectory: File(Platform.resolvedExecutable).parent.path,
        );
        addLog(.info, '云服务：已拉起启动器处理 [$versionId]（$reason）', tag: 'CloudService');
      } catch (error) {
        addLog(.warning, '云服务：拉起启动器失败 ${error.toString()}', tag: 'CloudService');
      }
    }
    _lastActive = DateTime.now();
    if (_tasks.isEmpty && _sessions.values.every((s) => !s.isActive)) {
      // 已经没有在管的一局：交出去就退，UI 会接着处理
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await _exit();
    }
  }

  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    _timer?.cancel();
    addLog(.info, '云服务：空闲退出', tag: 'CloudService');
    await GameSessionStore.clearServicePid();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // Flutter 引擎里 exit(0) 不会退，直接结束进程
    if (!Process.killPid(pid)) exit(0);
  }
}
