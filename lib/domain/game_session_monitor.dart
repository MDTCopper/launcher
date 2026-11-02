import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_runtime.dart';
import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/session_ownership.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/session_task.dart';
import 'package:copper_launcher/domain/tasks/takeover_session_task.dart';
import 'package:copper_launcher/util/game_process_watch.dart';
import 'package:copper_launcher/util/io/log.dart';

/// UI 侧会话发现与接管
///
/// - 服务拥有且游戏还在：向服务请求**完全接管**；服务把 owner 改成 ui 后，建
///   [TakeoverSessionTask]（退出上传 / 游玩时长 / 退出行为都在 UI 做）；
/// - 服务已经没了：UI 直接把 owner 改成 ui 接管；
/// - 服务拥有但游戏已结束：仍由服务补上传，UI 只显示只读卡 / 等 done；
/// - `done` 会话：把游玩时长写回 config 并删文件（服务模式不写 config）。
class GameSessionMonitor {
  GameSessionMonitor._();

  static final GameSessionMonitor instance = GameSessionMonitor._();

  static const _pollInterval = Duration(seconds: 2);
  static const _takeoverRequestInterval = Duration(seconds: 5);

  final Map<String, RemoteSessionTask> _remote = {};
  final Map<String, TakeoverSessionTask> _takeover = {};
  final Map<String, DateTime> _lastTakeoverRequest = {};

  bool _started = false;
  bool _ticking = false;

  Future<void> start() async {
    if (_started) return;
    // 会话/服务进程是桌面形态；Android 的游戏在同进程内，没有 session 可发现
    if (Platform.isAndroid) return;
    _started = true;
    await _tick();
    Timer.periodic(_pollInterval, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (_ticking || AppRuntime.headless) return;
    _ticking = true;
    try {
      final sessions = await GameSessionStore.list();
      final active = <String>{};
      final serviceRunning = await GameSessionStore.isServiceRunning();

      for (final session in sessions) {
        if (session.isActive) {
          active.add(session.id);
          await _handleActive(session, serviceRunning: serviceRunning);
        } else if (session.phase == 'done') {
          await _importDone(session);
        }
      }

      for (final entry in _remote.entries.toList()) {
        if (active.contains(entry.value.session.id)) continue;
        _remote.remove(entry.key)?.finish();
      }
      for (final entry in _takeover.entries.toList()) {
        if (active.contains(entry.value.session.id)) continue;
        _takeover.remove(entry.key);
        if (entry.value.status == TaskStatus.process) {
          entry.value.status = TaskStatus.completed;
          entry.value.updateDisplay();
        }
      }
    } catch (error) {
      addLog(.warning, '会话发现失败：$error', tag: 'CloudService');
    } finally {
      _ticking = false;
    }
  }

  Future<void> _handleActive(
    GameSession session, {
    required bool serviceRunning,
  }) async {
    final gameAlive =
        session.gamePid != null && GameProcessWatch.isAlive(session.gamePid!);

    // 服务已退位：UI 直接接管
    if (session.owner == 'ui') {
      await _ensureTakeover(session);
      return;
    }

    if (!serviceRunning) {
      if (gameAlive) {
        // 服务没了但游戏还活着：UI 直接变成 owner（不用再起服务）
        await GameSessionStore.clearTakeover(session.id);
        session.owner = 'ui';
        await GameSessionStore.save(session);
        addLog(.info, '会话接管：服务不在，UI 直接接管 [${session.tag}]', tag: 'CloudService');
      } else {
        // 服务没了、游戏也结束了：让服务补上传（现有恢复路径）
        _ensureRemote(session);
        await _ensureServiceFor(session);
      }
      return;
    }

    // 服务还在：请求完全接管；等 owner 变成 ui 后下一轮建接管任务
    if (gameAlive) {
      _ensureRemote(session);
      final last = _lastTakeoverRequest[session.id];
      if (last == null ||
          DateTime.now().difference(last) > _takeoverRequestInterval) {
        _lastTakeoverRequest[session.id] = DateTime.now();
        await SessionOwnership.requestTakeover(session.id);
        addLog(.info, '会话接管：请求服务移交 [${session.tag}]', tag: 'CloudService');
      }
      return;
    }

    // 服务还在、游戏已结束：等它上传，UI 只读显示
    _ensureRemote(session);
  }

  void _ensureRemote(GameSession session) {
    if (_takeover.containsKey(session.id)) return;
    final existing = _remote[session.id];
    if (existing != null) {
      existing.session = session;
      existing.refresh();
      return;
    }
    final task = RemoteSessionTask(session);
    _remote[session.id] = task;
    addTask(task);
    addLog(.info, '会话发现：接回运行中的游戏 [${session.tag}]', tag: 'CloudService');
  }

  Future<void> _ensureTakeover(GameSession session) async {
    _lastTakeoverRequest.remove(session.id);
    await GameSessionStore.clearTakeover(session.id);

    final existing = _takeover[session.id];
    if (existing != null) {
      existing.session = session;
      existing.updateDisplay();
      return;
    }
    final remote = _remote.remove(session.id);
    if (remote != null) remote.finish();

    final version = config.versionOptions.findVersionById(session.versionId);
    if (version == null) {
      addLog(.warning, '会话接管：找不到版本 ${session.versionId}，只保留只读卡', tag: 'CloudService');
      _ensureRemote(session);
      return;
    }
    final task = TakeoverSessionTask(session, version);
    _takeover[session.id] = task;
    addTask(task);
    addLog(.info, '会话接管：UI 已完全接管 [${session.tag}] pid=${session.gamePid}', tag: 'CloudService');
  }

  Future<void> _ensureServiceFor(GameSession session) async {
    // 游戏已结束但服务不在：让服务补一次退出上传
    addLog(.info, '会话发现：拉起云服务补上传 [${session.tag}]', tag: 'CloudService');
    await SessionOwnership.ensureService(recover: true);
  }

  /// done 会话：服务模式不写 config，这里补写最近启动时间与累计时长
  Future<void> _importDone(GameSession session) async {
    try {
      final version = config.versionOptions.findVersionById(session.versionId);
      if (version != null) {
        final completedAt = session.completedAt ?? DateTime.now();
        version.lastLaunchTime = completedAt;
        final played = Duration(seconds: session.playSeconds ?? 0);
        version.playTime = (version.playTime ?? Duration.zero) + played;
        await config.save();
        addLog(
          .info,
          '会话发现：导入游玩记录 [${session.tag}] ${played.inMinutes} 分钟',
          tag: 'CloudService',
        );
      } else {
        addLog(.warning, '会话发现：版本已不存在，丢弃会话 ${session.versionId}', tag: 'CloudService');
      }
      await GameSessionStore.remove(session.id);
    } catch (error) {
      addLog(.warning, '会话发现：导入会话失败 $error', tag: 'CloudService');
    }
  }
}
