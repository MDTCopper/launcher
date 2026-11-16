import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 崩溃报告的有效时间窗往前留的余量
///
/// 文件 mtime 与启动时刻可能有秒级偏差，留几分钟免得把本局刚写的报告漏掉
const Duration kCrashReportWindowMargin = Duration(minutes: 2);

/// 一次启动能拿到的全部事实
///
/// 只放数据；读盘由本文件的辅助函数做，诊断器只读这份对象
class CrashEvidence {
  const CrashEvidence({
    this.exitCode,
    this.canceledByUser = false,
    this.reachedMainMenu = false,
    this.logTail = '',
    this.lastLog,
    this.crashReport,
    this.crashReportPath,
    this.crashReportModifiedAt,
    this.launchStartedAt,
    this.viaLoader = false,
    this.loaderReady = true,
    this.loaderVersion,
    this.bridgeReady = true,
    this.bridgeAbi,
    this.javaReady = true,
    this.javaPath,
    this.memoryMb,
    this.versionTag = '',
    this.versionRelease = '',
    this.isBleedingEdge = false,
    this.steam = false,
    this.fromShortcut = false,
    this.launchSentinelLeft = false,
  });

  /// 桌面是真实退出码；桥那条路拿不到，留空
  final int? exitCode;

  /// 用户自己点了结束
  final bool canceledByUser;

  /// 日志里出现过 `Total time to load`
  final bool reachedMainMenu;

  /// 本次进程 stdout / stderr 的尾部
  final String logTail;

  /// `<数据目录>/last_log.txt` 全文，只留尾部
  final String? lastLog;

  /// 最新一份 `crash-report-*.txt` 的头部与首个异常块
  final String? crashReport;

  /// 那份崩溃报告的路径，给「查看全部」用
  final String? crashReportPath;

  /// 那份崩溃报告的修改时刻，用来判断是不是本局写下的
  final DateTime? crashReportModifiedAt;

  /// 本局启动时刻，用来把历史崩溃报告排除在外
  final DateTime? launchStartedAt;

  /// 走 Copper 加载器
  final bool viaLoader;

  /// 加载器本体是否可用
  final bool loaderReady;

  /// 加载器版本，读不出来时为空
  final String? loaderVersion;

  /// Android 桥的 JRE / so / ABI 是否可用
  final bool bridgeReady;

  /// Android 设备 ABI
  final String? bridgeAbi;

  /// 启动时选的 Java 是否可用
  final bool javaReady;

  /// 启动时选的 Java 路径
  final String? javaPath;

  /// 本次 `-Xmx`，兆字节
  final int? memoryMb;

  /// 版本标签
  final String versionTag;

  /// 版本号，如 `v160.3`
  final String versionRelease;

  /// 是不是 BE 版
  final bool isBleedingEdge;

  /// 是不是 Steam 版
  final bool steam;

  /// 是不是快捷方式拉起来的
  final bool fromShortcut;

  /// `launchid.dat` 残留，等于上次没正常退出
  final bool launchSentinelLeft;

  /// 本局时间窗内的崩溃报告
  ///
  /// 早于启动时刻写下的属于历史报告，不能算到这一局头上；缺时刻时按缺省处理
  String? get crashReportOfThisLaunch {
    final report = crashReport;
    if (report == null) return null;
    final startedAt = launchStartedAt;
    final modifiedAt = crashReportModifiedAt;
    if (startedAt == null || modifiedAt == null) return report;
    final earliest = startedAt.subtract(kCrashReportWindowMargin);
    return modifiedAt.isBefore(earliest) ? null : report;
  }

  /// 三份证据文本，按可信度排序：崩溃报告 → last_log → stdout 尾部
  List<String> get evidenceTexts {
    final texts = <String>[];
    for (final text in [crashReportOfThisLaunch, lastLog, logTail]) {
      if (text == null) continue;
      final trimmed = text.trim();
      if (trimmed.isEmpty) continue;
      texts.add(trimmed);
    }
    return texts;
  }

  /// 规则扫描用的合并文本
  String get diagnosticText => evidenceTexts.join('\n');

  /// 换掉三份从磁盘读出来的文本，其余字段照抄
  CrashEvidence copyWithCrashFiles({
    String? lastLog,
    String? crashReport,
    String? crashReportPath,
    DateTime? crashReportModifiedAt,
  }) {
    return CrashEvidence(
      exitCode: exitCode,
      canceledByUser: canceledByUser,
      reachedMainMenu: reachedMainMenu,
      logTail: logTail,
      lastLog: lastLog ?? this.lastLog,
      crashReport: crashReport ?? this.crashReport,
      crashReportPath: crashReportPath ?? this.crashReportPath,
      crashReportModifiedAt:
          crashReportModifiedAt ?? this.crashReportModifiedAt,
      launchStartedAt: launchStartedAt,
      viaLoader: viaLoader,
      loaderReady: loaderReady,
      loaderVersion: loaderVersion,
      bridgeReady: bridgeReady,
      bridgeAbi: bridgeAbi,
      javaReady: javaReady,
      javaPath: javaPath,
      memoryMb: memoryMb,
      versionTag: versionTag,
      versionRelease: versionRelease,
      isBleedingEdge: isBleedingEdge,
      steam: steam,
      fromShortcut: fromShortcut,
      launchSentinelLeft: launchSentinelLeft,
    );
  }
}

/// 崩溃报告的候选目录
///
/// 隔离开的版本会写进自己的数据目录，默认目录里还留着一份老的；三处都要探，
/// 版本数据目录优先。老版本的数据目录本身已经带一层 `Mindustry`，所以两种形态都列上
List<String> crashReportDirPaths({
  required String dataDirPath,
  required String defaultCrashesPath,
}) {
  final paths = <String>{
    p.join(dataDirPath, 'crashes'),
    p.join(dataDirPath, 'Mindustry', 'crashes'),
    defaultCrashesPath,
  };
  return paths.toList(growable: false);
}

/// 最新一份崩溃报告的路径；两个目录都找，按修改时间取
///
/// [notBefore] 给了就只算这个时刻之后写下的报告，历史报告一律跳过
String? latestCrashReportPath(
  List<String> crashesDirPaths, {
  DateTime? notBefore,
}) {
  String? newestPath;
  DateTime? newestTime;
  for (final dirPath in crashesDirPaths) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    try {
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('crash-report-')) continue;
        if (!name.endsWith('.txt')) continue;
        final modified = entity.lastModifiedSync();
        if (notBefore != null && modified.isBefore(notBefore)) continue;
        if (newestTime != null && !modified.isAfter(newestTime)) continue;
        newestTime = modified;
        newestPath = entity.path;
      }
    } on Object {
      continue;
    }
  }
  return newestPath;
}

/// 文件修改时刻；读不出来返回空
DateTime? lastModifiedOf(String? filePath) {
  if (filePath == null) return null;
  try {
    return File(filePath).lastModifiedSync();
  } on Object {
    return null;
  }
}

/// 游戏自己的 `last_log.txt` 路径
String gameLastLogPathIn(String dataDirPath) =>
    p.join(dataDirPath, 'last_log.txt');

/// 读 `last_log.txt` 的尾部；崩溃后它就是「崩溃前最后几行」
String? readGameLastLog(String dataDirPath, {int maxLines = 200}) =>
    readTextTail(gameLastLogPathIn(dataDirPath), maxLines: maxLines);

/// 读文本文件的头部若干行；文件不存在或读不出来返回空
///
/// 只读，读失败不抛
String? readTextHead(
  String filePath, {
  int maxLines = 120,
  int maxBytes = 256 * 1024,
}) {
  final text = _readPrefix(filePath, maxBytes: maxBytes, fromHead: true);
  if (text == null) return null;
  return _takeLines(text, maxLines: maxLines, fromHead: true);
}

/// 读文本文件的尾部若干行
String? readTextTail(
  String filePath, {
  int maxLines = 200,
  int maxBytes = 256 * 1024,
}) {
  final text = _readPrefix(filePath, maxBytes: maxBytes, fromHead: false);
  if (text == null) return null;
  return _takeLines(text, maxLines: maxLines, fromHead: false);
}

/// 把磁盘上的崩溃报告与 `last_log.txt` 补进证据
///
/// 只读；读不到就保持原样，让诊断按「没拿到」处理
/// [launchStartedAt] 是本局启动时刻，早于它的报告不读，免得历史报告被判成本局崩溃
CrashEvidence readEvidenceFiles({
  required CrashEvidence evidence,
  required String dataDirPath,
  required String defaultCrashesPath,
  DateTime? launchStartedAt,
}) {
  final earliestReport = launchStartedAt?.subtract(kCrashReportWindowMargin);
  final reportPath = latestCrashReportPath(
    crashReportDirPaths(
      dataDirPath: dataDirPath,
      defaultCrashesPath: defaultCrashesPath,
    ),
    notBefore: earliestReport,
  );
  return evidence.copyWithCrashFiles(
    crashReportPath: reportPath,
    crashReport: reportPath == null ? null : readTextHead(reportPath),
    crashReportModifiedAt: lastModifiedOf(reportPath),
    lastLog: readGameLastLog(dataDirPath),
  );
}

/// 按需要读文件头或文件尾；整份文件超过 [maxBytes] 时只读那一段
String? _readPrefix(
  String filePath, {
  required int maxBytes,
  required bool fromHead,
}) {
  try {
    final file = File(filePath);
    if (!file.existsSync()) return null;
    final length = file.lengthSync();
    final raf = file.openSync();
    try {
      if (!fromHead && length > maxBytes) {
        raf.setPositionSync(length - maxBytes);
      }
      final bytes = raf.readSync(maxBytes);
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      raf.closeSync();
    }
  } on Object {
    return null;
  }
}

String _takeLines(
  String text, {
  required int maxLines,
  required bool fromHead,
}) {
  final lines = text.split('\n');
  if (lines.length <= maxLines) return text;
  final kept = fromHead
      ? lines.take(maxLines)
      : lines.skip(lines.length - maxLines);
  return kept.join('\n');
}
