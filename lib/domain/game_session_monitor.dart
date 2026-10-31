import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_runtime.dart';
import 'package:copper_launcher/domain/game_session.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/session_task.dart';
import 'package:copper_launcher/util/game_process_watch.dart';
import 'package:copper_launcher/util/io/log.dart';

/// UI 侧会话发现：UI 后开 / 服务重启后，把正在跑的局接回任务抽屉
///
/// 负责三件事：
/// 1. `sessions/` 里的活跃会话 → 只读任务卡片（✕ 只杀游戏，上传仍由服务做）；
/// 2. 服务死了但游戏还活着 → 拉起 `--cloud-service --adopt-all`；
/// 3. `done` 会话 → 把游玩时长写回 config 并删文件（服务模式不写 config）
class GameSessionMonitor {
  GameSessionMonitor._();

  static final GameSessionMonitor instance = GameSessionMonitor._();

  static const _pollInterval = Duration(seconds: 2);

  final Map<String, RemoteSessionTask> _tasks = {};

  bool _started = false;
  bool _ticking = false;
  DateTime? _lastServiceSpawn;

  Future<void> start() async {
    if (_started) return;
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
      for (final session in sessions) {
        if (session.isActive) {
          active.add(session.id);
          _syncTask(session);
          await _ensureServiceFor(session);
        } else if (session.phase == 'done') {
          await _importDone(session);
        }
      }
      for (final entry in _tasks.entries.toList()) {
        if (active.contains(entry.value.session.id)) continue;
        _tasks.remove(entry.key)?.finish();
      }
    } catch (error) {
      addLog(.warning, '会话发现失败：$error', tag: 'CloudService');
    } finally {
      _ticking = false;
    }
  }

  void _syncTask(GameSession session) {
    final existing = _tasks[session.id];
    if (existing != null) {
      existing.session = session;
      existing.refresh();
      return;
    }
    final task = RemoteSessionTask(session);
    _tasks[session.id] = task;
    addTask(task);
    addLog(.info, '会话发现：接回运行中的游戏 [${session.tag}]', tag: 'CloudService');
  }

  Future<void> _ensureServiceFor(GameSession session) async {
    if (await GameSessionStore.isServiceRunning()) return;
    // 服务没了：游戏还在就接管，游戏没了就补上传
    final gameAlive =
        session.gamePid != null && GameProcessWatch.isAlive(session.gamePid!);
    if (gameAlive) {
      await _spawnService(['--adopt-all']);
    } else {
      await _spawnService(['--recover']);
    }
  }

  Future<void> _spawnService(List<String> args) async {
    final last = _lastServiceSpawn;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _lastServiceSpawn = DateTime.now();
    try {
      await Process.start(
        Platform.resolvedExecutable,
        ['--cloud-service', ...args],
        mode: ProcessStartMode.detached,
        workingDirectory: File(Platform.resolvedExecutable).parent.path,
      );
      addLog(.info, '会话发现：拉起云服务 ${args.join(' ')}', tag: 'CloudService');
    } catch (error) {
      addLog(.warning, '会话发现：拉起云服务失败 $error', tag: 'CloudService');
    }
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
