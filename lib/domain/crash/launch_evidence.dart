import 'dart:collection';

import 'package:copper_launcher/domain/crash/crash_evidence.dart';
import 'package:copper_launcher/domain/launch_exit.dart';

/// 一次启动结束时能拿到的事实
///
/// 由启动任务采集后交进来；本文件只做组装，不碰进程与配置
class LaunchEvidenceInput {
  const LaunchEvidenceInput({
    this.exitLog = '',
    this.exitCodeUnavailable = false,
    this.canceledByUser = false,
    this.reachedMainMenu = false,
    this.logTail = '',
    required this.dataDirPath,
    required this.defaultCrashesPath,
    this.versionTag = '',
    this.versionRelease = '',
    this.isBleedingEdge = false,
    this.steam = false,
    this.fromShortcut = false,
    this.viaLoader = false,
    this.loaderReady = true,
    this.loaderVersion,
    this.bridgeReady = true,
    this.bridgeAbi,
    this.javaReady = true,
    this.javaPath,
    this.memoryMb,
    this.launchSentinelLeft = false,
    this.launchStartedAt,
  });

  /// 退出事件行，形如 `exit 0`；退出码从它解析
  final String exitLog;

  /// 桥那条路拿不到真实退出码，为 true 时证据里的退出码留空
  final bool exitCodeUnavailable;

  /// 用户自己点了结束
  final bool canceledByUser;

  /// 日志里出现过 `Total time to load`
  final bool reachedMainMenu;

  /// 本次进程 stdout 的尾部
  final String logTail;

  /// 版本的数据目录
  final String dataDirPath;

  /// 游戏默认数据目录下的 crashes
  final String defaultCrashesPath;

  /// 版本标签
  final String versionTag;

  /// 版本号
  final String versionRelease;

  /// 是不是 BE 版
  final bool isBleedingEdge;

  /// 是不是 Steam 版
  final bool steam;

  /// 是不是快捷方式拉起来的
  final bool fromShortcut;

  /// 走 Copper 加载器
  final bool viaLoader;

  /// 加载器本体是否可用
  final bool loaderReady;

  /// 加载器版本
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

  /// `launchid.dat` 残留，等于上次没正常退出
  final bool launchSentinelLeft;

  /// 本局启动时刻；崩溃报告只认这个时刻之后写下的
  final DateTime? launchStartedAt;
}

/// 组装诊断用的证据，再把崩溃报告与 `last_log` 读进来
///
/// 只读；用例里不用起游戏进程
CrashEvidence assembleCrashEvidence(LaunchEvidenceInput input) {
  final evidence = CrashEvidence(
    exitCode: input.exitCodeUnavailable
        ? null
        : parseExitCodeLine(input.exitLog),
    canceledByUser: input.canceledByUser,
    reachedMainMenu: input.reachedMainMenu,
    logTail: input.logTail,
    viaLoader: input.viaLoader,
    loaderReady: input.loaderReady,
    loaderVersion: input.loaderVersion,
    bridgeReady: input.bridgeReady,
    bridgeAbi: input.bridgeAbi,
    javaReady: input.javaReady,
    javaPath: input.javaPath,
    memoryMb: input.memoryMb,
    versionTag: input.versionTag,
    versionRelease: input.versionRelease,
    isBleedingEdge: input.isBleedingEdge,
    steam: input.steam,
    fromShortcut: input.fromShortcut,
    launchSentinelLeft: input.launchSentinelLeft,
    launchStartedAt: input.launchStartedAt,
  );
  return readEvidenceFiles(
    evidence: evidence,
    dataDirPath: input.dataDirPath,
    defaultCrashesPath: input.defaultCrashesPath,
    launchStartedAt: input.launchStartedAt,
  );
}

/// 游戏 stdout 的尾部环形缓冲
///
/// 只留最近若干行且不超过字数上限；诊断只看这截尾部，不能一直攒
class StdoutTailBuffer {
  StdoutTailBuffer({this.maxLines = 300, this.maxChars = 64 * 1024});

  /// 最多留几行
  final int maxLines;

  /// 最多留几个字符
  final int maxChars;

  final Queue<String> _lines = Queue<String>();
  int _chars = 0;

  /// 收一行；超出行数或字数上限时从最早的一行开始丢
  void add(String line) {
    _lines.addLast(line);
    _chars += line.length + 1;
    while (_lines.isNotEmpty &&
        (_lines.length > maxLines || _chars > maxChars)) {
      _chars -= _lines.removeFirst().length + 1;
    }
  }

  /// 当前尾部，按行拼回去
  String get text => _lines.join('\n');
}
