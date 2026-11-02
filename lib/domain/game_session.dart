import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/util/game_process_watch.dart';
import 'package:path/path.dart' as p;

/// 一局由快捷启动拉起的游戏：UI 不在时由服务进程写，UI 再启动时读到它
class GameSession {
  GameSession({
    required this.id,
    required this.versionId,
    required this.tag,
    required this.phase,
    required this.startedAt,
    required this.servicePid,
    this.owner = 'service',
    this.gamePid,
    this.completedAt,
    this.playSeconds,
    this.error,
    this.cloudEnabled = false,
  });

  final String id;
  final String versionId;
  final String tag;

  /// launching / running / uploading / done / failed / delegated
  String phase;

  /// 谁负责这一局的退出上传与收尾：`service` = 无界面服务，`ui` = 启动器 UI
  String owner;

  final DateTime startedAt;
  final int servicePid;
  int? gamePid;
  DateTime? completedAt;
  int? playSeconds;
  String? error;
  final bool cloudEnabled;

  bool get isActive =>
      phase == 'launching' || phase == 'running' || phase == 'uploading';

  Map<String, dynamic> toJson() => {
    'id': id,
    'versionId': versionId,
    'tag': tag,
    'phase': phase,
    'startedAt': startedAt.toIso8601String(),
    'servicePid': servicePid,
    'owner': owner,
    'gamePid': gamePid,
    'completedAt': completedAt?.toIso8601String(),
    'playSeconds': playSeconds,
    'error': error,
    'cloudEnabled': cloudEnabled,
  };

  factory GameSession.fromJson(Map<String, dynamic> json) => GameSession(
    id: json['id'] as String,
    versionId: json['versionId'] as String,
    tag: json['tag'] as String? ?? '',
    phase: json['phase'] as String? ?? 'launching',
    startedAt:
        DateTime.tryParse(json['startedAt'] as String? ?? '') ?? DateTime.now(),
    servicePid: json['servicePid'] as int? ?? 0,
    owner: json['owner'] as String? ?? 'service',
    gamePid: json['gamePid'] as int?,
    completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
    playSeconds: json['playSeconds'] as int?,
    error: json['error'] as String?,
    cloudEnabled: json['cloudEnabled'] as bool? ?? false,
  );

  GameSession copyWith({
    String? phase,
    String? owner,
    int? gamePid,
    DateTime? completedAt,
    int? playSeconds,
    String? error,
  }) => GameSession(
    id: id,
    versionId: versionId,
    tag: tag,
    phase: phase ?? this.phase,
    owner: owner ?? this.owner,
    startedAt: startedAt,
    servicePid: servicePid,
    gamePid: gamePid ?? this.gamePid,
    completedAt: completedAt ?? this.completedAt,
    playSeconds: playSeconds ?? this.playSeconds,
    error: error ?? this.error,
    cloudEnabled: cloudEnabled,
  );
}

/// 一个待处理的启动请求（UI 在线时给 UI / 服务在线时给服务）
class LaunchTicket {
  LaunchTicket({
    required this.file,
    required this.versionId,
    required this.reason,
    required this.createdAt,
  });

  final File file;
  final String versionId;
  final String reason;
  final DateTime createdAt;

  static LaunchTicket? fromJson(File file, Map<String, dynamic> json) {
    final versionId = json['versionId'] as String?;
    if (versionId == null) return null;
    return LaunchTicket(
      file: file,
      versionId: versionId,
      reason: json['reason'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// 云存档服务的文件协议：`service.json` / `ui.json` / `sessions/*.json` / `pending/` / `requests/`
///
/// 用文件而不是平台单实例：UI 与无界面云服务是两个进程，需要跨进程的会话/presence/票据；
/// 文件 pid 探测在 Debug/Release 下行为一致
class GameSessionStore {
  GameSessionStore._();

  static Directory get _root => Directory(AppPaths.cloudService);
  static Directory get sessionsDir => Directory(AppPaths.cloudServiceSessions);
  static Directory get pendingDir => Directory(AppPaths.cloudServicePending);
  static Directory get requestsDir => Directory(AppPaths.cloudServiceRequests);
  static File get _serviceFile => File(p.join(_root.path, 'service.json'));
  static File get _uiFile => File(p.join(_root.path, 'ui.json'));
  static File get _lockFile => File(p.join(_root.path, 'store.lock'));

  static Future<void> ensureDirs() async {
    await _root.create(recursive: true);
    await sessionsDir.create(recursive: true);
    await pendingDir.create(recursive: true);
    await requestsDir.create(recursive: true);
  }

  /// 会话读改写串行：服务与 UI 可能同时读写
  static Future<T> withLock<T>(Future<T> Function() body) async {
    await ensureDirs();
    final raf = await _lockFile.open(mode: FileMode.append);
    try {
      await raf.lock(FileLock.exclusive);
      return await body();
    } finally {
      try {
        await raf.unlock();
      } catch (_) {}
      await raf.close();
    }
  }

  static Future<void> _atomicWrite(File file, Map<String, dynamic> json) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  static Future<void> save(GameSession session) =>
      withLock(() => _atomicWrite(_sessionFile(session.id), session.toJson()));

  /// 退出前的同步写：窗口关闭回调没时间等 async，先落盘再拉服务接管
  static void saveSync(GameSession session) {
    final file = _sessionFile(session.id);
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(session.toJson()), flush: true);
    if (file.existsSync()) file.deleteSync();
    tmp.renameSync(file.path);
  }

  static File _sessionFile(String id) =>
      File(p.join(sessionsDir.path, '$id.json'));

  static Future<GameSession?> find(String id) async {
    final file = _sessionFile(id);
    if (!await file.exists()) return null;
    return _readSession(file);
  }

  static Future<List<GameSession>> list() async {
    await ensureDirs();
    final result = <GameSession>[];
    await for (final entity in sessionsDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final session = await _readSession(entity);
      if (session != null) result.add(session);
    }
    result.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return result;
  }

  static Future<List<GameSession>> active() async =>
      (await list()).where((session) => session.isActive).toList();

  static Future<GameSession?> _readSession(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) return GameSession.fromJson(json);
    } catch (_) {}
    return null;
  }

  static Future<void> remove(String id) async {
    final file = _sessionFile(id);
    if (await file.exists()) await file.delete();
  }

  // ---------- 进程 pid 探测 ----------

  static Future<void> writeServicePid() async {
    await ensureDirs();
    await _atomicWrite(_serviceFile, {
      'pid': pid,
      'startedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<int?> servicePid() => _readPid(_serviceFile);

  static Future<bool> isServiceRunning() async {
    final value = await servicePid();
    return value != null && GameProcessWatch.isAlive(value);
  }

  static Future<void> clearServicePid() async {
    try {
      if (await _serviceFile.exists()) await _serviceFile.delete();
    } catch (_) {}
  }

  static Future<void> writeUiPid() async {
    await ensureDirs();
    await _atomicWrite(_uiFile, {
      'pid': pid,
      'startedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> clearUiPid() async {
    try {
      if (await _uiFile.exists()) await _uiFile.delete();
    } catch (_) {}
  }

  static Future<int?> uiPid() => _readPid(_uiFile);

  static Future<bool> isUiRunning() async {
    final value = await uiPid();
    return value != null && GameProcessWatch.isAlive(value);
  }

  static Future<int?> _readPid(File file) async {
    try {
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is Map && json['pid'] is int) return json['pid'] as int;
    } catch (_) {}
    return null;
  }

  // ---------- 会话所有权移交（UI 完全接管） ----------

  static Directory get takeoverDir =>
      Directory(p.join(AppPaths.cloudService, 'takeover'));

  /// UI 请求把某一局的所有权从服务移交给 UI
  static Future<void> requestTakeover(String sessionId) async {
    await ensureDirs();
    await takeoverDir.create(recursive: true);
    await _atomicWrite(File(p.join(takeoverDir.path, '$sessionId.json')), {
      'sessionId': sessionId,
      'requestedAt': DateTime.now().toIso8601String(),
    });
  }

  /// 服务取走移交请求（读完即删）
  static Future<List<String>> takeTakeoverRequests() async {
    await ensureDirs();
    await takeoverDir.create(recursive: true);
    final ids = <String>[];
    for (final entity in await takeoverDir.list().toList()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString());
        final id = (json is Map ? json['sessionId'] : null) as String?;
        if (id != null && id.isNotEmpty) ids.add(id);
        await entity.delete();
      } catch (_) {
        // 坏文件留着不处理
      }
    }
    return ids;
  }

  static Future<void> clearTakeover(String sessionId) async {
    try {
      final file = File(p.join(takeoverDir.path, '$sessionId.json'));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ---------- 待处理启动请求 ----------

  static Future<void> writePending({
    required String versionId,
    required String reason,
  }) => _writeTicket(pendingDir, versionId: versionId, reason: reason);

  static Future<void> writeRequest({
    required String versionId,
    required String reason,
  }) => _writeTicket(requestsDir, versionId: versionId, reason: reason);

  static Future<void> _writeTicket(
    Directory dir, {
    required String versionId,
    required String reason,
  }) async {
    await ensureDirs();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final file = File(p.join(dir.path, '$id.json'));
    await _atomicWrite(file, {
      'versionId': versionId,
      'reason': reason,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// 取走全部请求（读完即删；拿不到的文件跳过）
  static Future<List<LaunchTicket>> takePending() => _take(pendingDir);
  static Future<List<LaunchTicket>> takeRequests() => _take(requestsDir);

  static Future<List<LaunchTicket>> _take(Directory dir) async {
    await ensureDirs();
    final tickets = <LaunchTicket>[];
    final files = await dir.list().toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final entity in files) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString());
        if (json is Map<String, dynamic>) {
          final ticket = LaunchTicket.fromJson(entity, json);
          if (ticket != null) tickets.add(ticket);
        }
        await entity.delete();
      } catch (_) {
        // 坏文件留着不处理，避免和别的写入方抢
      }
    }
    return tickets;
  }

  /// 给测试 / 诊断用：生成一个不会撞的会话 id
  static String newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
