import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/core/app_paths.dart';
import 'package:path/path.dart' as p;

/// 一局游戏从启动到退出的记录
///
/// 通知几秒就没了，退出码这类东西要落盘才能在事后诊断
class LaunchRecord {
  LaunchRecord({
    required this.versionId,
    required this.tag,
    required this.startedAt,
    this.completedAt,
    this.gamePid,
    this.exitCode,
    this.fromShortcut = false,
    this.viaLoader = false,
    this.diagnosis,
  });

  /// 版本记录的 id
  final String versionId;

  /// 版本标签
  final String tag;

  /// 游戏进程起来的时刻
  final DateTime startedAt;

  /// 游戏退出的时刻；还在跑时为空
  DateTime? completedAt;

  /// 游戏进程 pid；桥那条路拿不到句柄时为空
  int? gamePid;

  /// 退出码；没退出时为空
  int? exitCode;

  /// 是不是快捷启动进来的
  final bool fromShortcut;

  /// 是不是走 Copper 加载器
  final bool viaLoader;

  /// 崩溃诊断结果；诊断还没做时为空
  String? diagnosis;

  /// 这一局跑了多久；还没退出时为空
  Duration? get duration {
    final end = completedAt;
    if (end == null) return null;
    return end.difference(startedAt);
  }

  Map<String, dynamic> toJson() => {
    'versionId': versionId,
    'tag': tag,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'gamePid': gamePid,
    'exitCode': exitCode,
    'fromShortcut': fromShortcut,
    'viaLoader': viaLoader,
    'diagnosis': diagnosis,
  };

  /// 字段不对（老文件 / 手改坏了）返回 null，调用方按「没有记录」处理
  static LaunchRecord? fromJson(Map<String, dynamic> json) {
    final versionId = json['versionId'];
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    if (versionId is! String || startedAt == null) return null;
    return LaunchRecord(
      versionId: versionId,
      tag: json['tag'] as String? ?? '',
      startedAt: startedAt,
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      gamePid: json['gamePid'] is int ? json['gamePid'] as int : null,
      exitCode: json['exitCode'] is int ? json['exitCode'] as int : null,
      fromShortcut: json['fromShortcut'] == true,
      viaLoader: json['viaLoader'] == true,
      diagnosis: json['diagnosis'] as String?,
    );
  }
}

/// `last-launch.json` 与历史记录的读写
///
/// 都落在数据根下：`last-launch.json` 只留最近一份，`launch-history/` 留最近几份
class LaunchRecordStore {
  LaunchRecordStore._();

  /// 历史记录保留份数：够定位刚跑完的那几局，又不至于把数据根堆满
  static const int historyLimit = 5;

  /// 最近一局的记录
  static File get lastFile =>
      File(p.join(AppPaths.copperLauncher, 'last-launch.json'));

  /// 历史记录目录，文件名是启动时刻的毫秒时间戳
  static Directory get historyDir =>
      Directory(p.join(AppPaths.copperLauncher, 'launch-history'));

  /// 启动成功时落一份还没结束的记录
  ///
  /// 写失败只影响诊断，不挡启动
  static Future<void> recordLaunchStart({
    required String versionId,
    required String tag,
    required DateTime startedAt,
    int? gamePid,
    bool fromShortcut = false,
    bool viaLoader = false,
  }) {
    return _write(
      lastFile,
      LaunchRecord(
        versionId: versionId,
        tag: tag,
        startedAt: startedAt,
        gamePid: gamePid,
        fromShortcut: fromShortcut,
        viaLoader: viaLoader,
      ),
    );
  }

  /// 退出时补上退出码与结束时刻，并留一份历史
  ///
  /// 找不到开始记录（比如上一份写失败）就不写：没有版本信息的退出码没法定位；
  /// 已经收过尾的记录也不覆盖，免得旧记录被这一局的退出码盖掉
  static Future<void> recordLaunchEnd({
    required int? exitCode,
    DateTime? completedAt,
    String? diagnosis,
  }) async {
    final previous = await readLast();
    if (previous == null || previous.completedAt != null) return;
    previous
      ..completedAt = completedAt ?? DateTime.now()
      ..exitCode = exitCode
      ..diagnosis = diagnosis ?? previous.diagnosis;
    await _write(lastFile, previous);
    await _appendHistory(previous);
  }

  /// 读最近一份记录；没有或读不出来时为空
  static Future<LaunchRecord?> readLast() => _read(lastFile);

  static Future<LaunchRecord?> _read(File file) async {
    try {
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return LaunchRecord.fromJson(json);
    } on Object {
      return null;
    }
  }

  /// 先写临时文件再改名：读的一侧随时可能来取，不能让它读到半截 JSON
  ///
  /// 临时文件名带 pid：UI 与无界面服务会同时写这份记录
  static Future<void> _write(File file, LaunchRecord record) async {
    try {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.$pid.tmp');
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(record.toJson()),
        flush: true,
      );
      // Dart 在 Windows 上的 rename 是替换语义，不用先删旧文件
      await temp.rename(file.path);
    } on Object {
      // 记录只是诊断辅助，写不进去不影响启动
    }
  }

  static Future<void> _appendHistory(LaunchRecord record) async {
    try {
      await historyDir.create(recursive: true);
      final stamp = record.startedAt.millisecondsSinceEpoch;
      await _write(File(p.join(historyDir.path, '$stamp.json')), record);
      await _pruneHistory();
    } on Object {
      // 历史是可选的追溯，删不掉就留着
    }
  }

  /// 只留最近 [historyLimit] 份，按文件名里的启动时刻排
  static Future<void> _pruneHistory() async {
    final entries = <({int stamp, File file})>[];
    await for (final entity in historyDir.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.json')) continue;
      final stamp = int.tryParse(p.basenameWithoutExtension(entity.path));
      if (stamp == null) continue;
      entries.add((stamp: stamp, file: entity));
    }
    if (entries.length <= historyLimit) return;
    entries.sort((a, b) => b.stamp.compareTo(a.stamp));
    for (final entry in entries.skip(historyLimit)) {
      try {
        await entry.file.delete();
      } on Object {
        // 删不掉下次再删
      }
    }
  }
}
