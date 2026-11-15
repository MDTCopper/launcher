import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_runtime.dart';
import 'package:copper_launcher/domain/cloud/cloud_auto_sync.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/domain/game_instance.dart';
import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/sync_proxy.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/core/app_paths.dart';
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

  /// 一局卡在 `launching` 多久算死：云同步 + 起进程的正常耗时远小于它
  static const staleLaunchTimeout = Duration(seconds: 120);

  /// 会话扫描间隔，每轮轮询都读一遍 sessions 目录没必要
  static const _sweepInterval = Duration(seconds: 5);

  final Map<String, LaunchMindustryTask> _tasks = {};
  final Map<String, GameSession> _sessions = {};

  Timer? _timer;
  bool _exiting = false;
  DateTime _lastActive = DateTime.now();
  DateTime _lastSweep = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> start({
    String? launchVersionId,
    bool adoptAll = false,
    bool recover = false,
  }) async {
    await GameSessionStore.ensureDirs();
    // 上一次进程崩溃可能留下同步状态 / 取消标记：先清掉，否则这次同步会被秒取消
    await SyncProxyGate.resetStale();
    await GameSessionStore.writeServicePid();
    addLog(
      .info,
      '云服务：启动（pid=$pid，数据根 ${AppPaths.copperLauncher}）',
      tag: 'CloudService',
    );
    final service = CloudServiceProcess._();
    addLog(.info, '时间线：云服务就绪 +${AppRuntime.elapsedMs}ms', tag: 'Timeline');
    // 先清掉上一次进程留下的卡死会话，否则下面这局会被它当成「已在运行」拦掉
    await service._sweepStaleLaunches();
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
      await _sweepStaleLaunches();
      _dropFinishedTasks();
      // UI 请求完全接管：把会话所有权交给 UI，本服务退位（游戏进程不动）
      for (final sessionId in await GameSessionStore.takeTakeoverRequests()) {
        await _transferToUi(sessionId);
      }
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
      addLog(
        .info,
        '云服务：启动被单实例规则拦住，交回界面 [${version.tag}]',
        tag: 'CloudService',
      );
      await _delegate(versionId, 'blocked');
      return;
    }
    // 文件里的活跃会话可能来自「服务死了但游戏还在跑」：别起第二局
    for (final active in await GameSessionStore.active()) {
      // 卡在 launching 的会话按死亡收尾，它不该挡住这次启动
      if (await _recoverStaleLaunch(active)) continue;
      final other = config.versionOptions.findVersionById(active.versionId);
      if (active.versionId == version.id) {
        addLog(
          .info,
          '云服务：这个版本已有一局在跑，交回界面 [${version.tag}]',
          tag: 'CloudService',
        );
        await _delegate(versionId, 'already_running');
        return;
      }
      if (other != null && GameInstance.sameDataPath(other, version)) {
        addLog(
          .info,
          '云服务：数据目录已被另一局占用，交回界面 [${version.tag}]',
          tag: 'CloudService',
        );
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
    await GameInstance.launch(version, serviceOwned: true);

    final task = _findTask(version.id);
    if (task == null) {
      addLog(
        .warning,
        '云服务：启动任务没建起来，交回界面 [${version.tag}]',
        tag: 'CloudService',
      );
      session.phase = 'delegated';
      session.error = 'no_task';
      await GameSessionStore.save(session);
      await _delegate(version.id, 'no_task');
      return;
    }
    _tasks[version.id] = task;
    _watch(task, session);
    // 进程可能已经起来了，先推进一次会话，别等下一轮轮询
    await _syncRunningSessions();
  }

  /// 取这次启动真正对应的任务
  ///
  /// 任务表不清理已结束的任务，按版本找第一个会拿到上一局那个已完结的任务，
  /// 监听它再也等不到通知，`_tasks` 会一直挡住这个版本
  LaunchMindustryTask? _findTask(String versionId) =>
      findRunningTask(taskManager.currentTasks, versionId);

  @visibleForTesting
  static LaunchMindustryTask? findRunningTask(
    Iterable<Task> tasks,
    String versionId,
  ) {
    for (final task in tasks.whereType<LaunchMindustryTask>()) {
      if (task.mindustry.id == versionId && isTaskRunning(task.status)) {
        return task;
      }
    }
    return null;
  }

  /// 任务还能不能代表「这一局在跑」：pending 还没起进程，process 已经起了
  @visibleForTesting
  static bool isTaskRunning(TaskStatus status) =>
      status == TaskStatus.pending || status == TaskStatus.process;

  void _watch(LaunchMindustryTask task, GameSession session) {
    void listener() {
      if (isTaskRunning(task.status)) return;
      task.removeListener(listener);
      unawaited(_onTaskEnd(task, session));
    }

    task.addListener(listener);
    // 拿到时已经结束的任务不会再发通知，直接按结束收尾
    if (!isTaskRunning(task.status)) {
      task.removeListener(listener);
      unawaited(_onTaskEnd(task, session));
    }
  }

  /// 兜底：任务已经结束却没收到通知时也要收尾，否则 `_tasks` 会一直挡住这个版本
  void _dropFinishedTasks() {
    for (final entry in _tasks.entries.toList()) {
      final task = entry.value;
      if (isTaskRunning(task.status)) continue;
      _tasks.remove(entry.key);
      final session = _sessions[entry.key];
      if (session == null) continue;
      unawaited(_onTaskEnd(task, session));
    }
  }

  Future<void> _onTaskEnd(LaunchMindustryTask task, GameSession session) async {
    final version = task.mindustry;
    // 同一版本后来可能又起了一局：只收尾自己这一局，别动新的
    if (!identical(_sessions[version.id], session)) return;
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
    addLog(
      .warning,
      '云服务：启动任务结束（${task.status.name}）[${version.tag}]',
      tag: 'CloudService',
    );
    _lastActive = DateTime.now();
  }

  /// UI 后开请求完全接管：把这一局交给 UI，服务不再监听 / 上传
  ///
  /// 游戏进程不动；UI 侧会建自己的接管任务，退出上传 / 游玩时长 / 退出行为都由 UI 负责。
  /// 交出去之后服务不再管这一局，若没有别的会话就直接退出，避免两个 owner 同时收尾。
  Future<void> _transferToUi(String sessionId) async {
    final session = await GameSessionStore.find(sessionId);
    if (session == null || !session.isActive) {
      addLog(.warning, '云服务：接管请求对应的会话不在了 [$sessionId]', tag: 'CloudService');
      return;
    }
    final gameAlive =
        session.gamePid != null && GameProcessWatch.isAlive(session.gamePid!);
    if (!gameAlive) {
      // 游戏已经结束：先摘掉服务侧任务/监听，避免它和补上传同时收尾
      final task = _tasks.remove(session.versionId);
      _sessions.remove(session.versionId);
      task?.transferOwnership();
      addLog(.info, '云服务：接管时游戏已结束，先补上传 [${session.tag}]', tag: 'CloudService');
      await _recoverSession(session);
      return;
    }

    final task = _tasks.remove(session.versionId);
    _sessions.remove(session.versionId);
    // 先摘掉服务任务的退出副作用：游戏真退出时 UI 才是 owner
    task?.transferOwnership();
    session
      ..owner = 'ui'
      ..phase = 'running';
    await GameSessionStore.save(session);
    addLog(
      .info,
      '云服务：已把游戏完全移交给 UI [${session.tag}] pid=${session.gamePid}',
      tag: 'CloudService',
    );

    if (_tasks.isEmpty && _sessions.values.every((s) => !s.isActive)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _exit();
    }
  }

  Future<void> _syncRunningSessions() async {
    for (final entry in _sessions.entries.toList()) {
      final session = entry.value;
      final task = _tasks[entry.key];
      if (task == null) continue;
      if (advanceSession(
        session,
        gamePid: task.gamePid,
        taskStatus: task.status,
      )) {
        await GameSessionStore.save(session);
      }
    }
  }

  /// 把任务侧看到的状态推进到会话；返回会话是否有变化
  @visibleForTesting
  static bool advanceSession(
    GameSession session, {
    required int? gamePid,
    required TaskStatus taskStatus,
  }) {
    var changed = false;
    if (gamePid != null && gamePid != session.gamePid) {
      session.gamePid = gamePid;
      changed = true;
    }
    if (taskStatus == TaskStatus.process && session.phase == 'launching') {
      session.phase = 'running';
      changed = true;
    }
    return changed;
  }

  /// 会话是否卡在 `launching`：进程没建起来就再也不会推进
  ///
  /// 口径同 [_adoptAll]：这类会话占着活跃会话会挡住这个版本之后的启动
  @visibleForTesting
  static bool isStaleLaunch(
    GameSession session, {
    required DateTime now,
    Duration timeout = staleLaunchTimeout,
  }) =>
      session.phase == 'launching' &&
      session.gamePid == null &&
      now.difference(session.startedAt) >= timeout;

  /// 自愈：卡在 `launching` 的会话按已结束收尾，别让它永久挡住后续启动
  ///
  /// 返回收尾了几个，调用方不看返回值
  Future<int> _sweepStaleLaunches() async {
    final now = DateTime.now();
    if (now.difference(_lastSweep) < _sweepInterval) return 0;
    _lastSweep = now;
    var recovered = 0;
    for (final session in await GameSessionStore.active()) {
      if (await _recoverStaleLaunch(session, now: now)) recovered++;
    }
    return recovered;
  }

  /// 单个会话的卡死判定与收尾；返回是否把它按已结束处理了
  Future<bool> _recoverStaleLaunch(GameSession session, {DateTime? now}) async {
    if (!isStaleLaunch(session, now: now ?? DateTime.now())) return false;
    _tasks.remove(session.versionId);
    _sessions.remove(session.versionId);
    addLog(
      .warning,
      '云服务：启动会话卡在 launching，按已结束收尾 [${session.tag}]',
      tag: 'CloudService',
    );
    try {
      await _recoverSession(session);
    } catch (error) {
      // 补上传失败也得收尾，否则这个版本还是被卡住
      session.phase = 'done';
      session.completedAt ??= DateTime.now();
      await GameSessionStore.save(session);
      addLog(
        .warning,
        '云服务：卡死会话补上传失败 ${error.toString()}',
        tag: 'CloudService',
      );
    }
    return true;
  }

  /// 测试用：跑一次卡死会话自愈，返回收尾的会话数
  @visibleForTesting
  Future<int> sweepStaleLaunchesForTest() async {
    _lastSweep = DateTime.fromMillisecondsSinceEpoch(0);
    return _sweepStaleLaunches();
  }

  /// 测试用：拿一个能调实例方法的服务对象，不走 start 的进程/定时器
  @visibleForTesting
  static CloudServiceProcess debugCreate() => CloudServiceProcess._();

  /// 服务启动：接管还活着的游戏会话，其余按已结束补做退出上传
  ///
  /// 只按 phase / gamePid 判活：`phase=launching` 的会话一律按已结束收尾——
  /// 留着它会一直占住活跃会话、挡住同一个版本之后的启动；这类会补做一次退出上传
  /// （多传一份没变的存档，代价小于卡住启动）
  Future<void> _adoptAll() async {
    for (final session in await GameSessionStore.active()) {
      if (session.phase == 'running' &&
          session.gamePid != null &&
          GameProcessWatch.isAlive(session.gamePid!)) {
        session.owner = 'service';
        await GameSessionStore.save(session);
        _sessions[session.versionId] = session;
        addLog(
          .info,
          '云服务：接管运行中的游戏 [${session.tag}] pid=${session.gamePid}',
          tag: 'CloudService',
        );
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
        addLog(
          .info,
          '云服务：已拉起启动器处理 [$versionId]（$reason）',
          tag: 'CloudService',
        );
      } catch (error) {
        addLog(
          .warning,
          '云服务：拉起启动器失败 ${error.toString()}',
          tag: 'CloudService',
        );
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
    await SyncProxyGate.resetStale();
    await GameSessionStore.clearServicePid();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // Flutter 引擎里 exit(0) 不会退，直接结束进程
    if (!Process.killPid(pid)) exit(0);
  }
}
