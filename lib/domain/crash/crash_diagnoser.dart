import 'dart:math';

import 'package:copper_launcher/domain/crash/crash_diagnosis.dart';
import 'package:copper_launcher/domain/crash/crash_evidence.dart';
import 'package:copper_launcher/domain/crash/crash_rules.dart';

/// 诊断一次启动
///
/// 判定顺序：用户主动停止 → 空；没崩 → 空；有致命命中 → 取分最高的那条；
/// 只有非致命命中 → 给一条 info，只进日志不弹窗
CrashDiagnosis? diagnose(CrashEvidence evidence) {
  if (evidence.canceledByUser) return null;
  if (!_looksCrashed(evidence)) return null;

  final hits = <_RuleHit>[];
  for (var index = 0; index < kCrashRules.length; index++) {
    final rule = kCrashRules[index];
    final line = rule.matcher(evidence);
    if (line == null) continue;
    hits.add(_RuleHit(rule, index, line, _scoreOf(rule, evidence, line)));
  }
  if (hits.isEmpty) return _unknownDiagnosis(evidence);

  // 同分时按规则表顺序，保证同样的证据每次给同样的结论
  hits.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  return _toDiagnosis(hits.first, evidence);
}

/// 有没有「真的崩了」的证据
///
/// 退出码 0 且没报告、没残留哨兵、Java 与桥都正常 ⇒ 不算崩
/// 崩溃报告只认本局时间窗内的那份，历史报告不算信号
bool _looksCrashed(CrashEvidence evidence) {
  if (evidence.launchSentinelLeft) return true;
  final report = evidence.crashReportOfThisLaunch;
  if (report != null && report.trim().isNotEmpty) {
    return true;
  }
  // Java 或缺桥时游戏进程压根没起来，这也是一次失败的启动
  if (!evidence.javaReady) return true;
  if (!evidence.bridgeReady) return true;
  final code = evidence.exitCode;
  // 桥那条路不给退出码；-1 是启动器主动停止
  if (code == null || code == -1) return false;
  return code != 0;
}

/// 基础分 + 多信号加分
///
/// 同一个命中行在崩溃报告与 last_log 里同时出现，说明两份证据互相印证
int _scoreOf(CrashRule rule, CrashEvidence evidence, String hitLine) {
  var score = rule.weight;
  if (_textsContaining(evidence, hitLine) > 1) score += 10;
  if (evidence.launchSentinelLeft) score += 5;
  return score;
}

int _textsContaining(CrashEvidence evidence, String hitLine) {
  if (hitLine.isEmpty) return 0;
  var count = 0;
  for (final text in evidence.evidenceTexts) {
    if (text.contains(hitLine)) count++;
  }
  return count;
}

CrashDiagnosis _toDiagnosis(_RuleHit hit, CrashEvidence evidence) {
  final rule = hit.rule;
  return CrashDiagnosis(
    code: rule.id,
    severity: rule.severity,
    fatal: rule.fatal,
    title: rule.title,
    detail: _detailOf(rule, evidence),
    suggestions: rule.suggestions,
    evidenceExcerpt: _excerptOf(evidence, hit.line),
    matchedRuleId: rule.id,
    action: rule.action,
  );
}

String _detailOf(CrashRule rule, CrashEvidence evidence) {
  final parts = <String>[rule.reason];
  final facts = <String>[
    if (evidence.versionTag.isNotEmpty) '版本 ${evidence.versionTag}',
    if (evidence.versionRelease.isNotEmpty) evidence.versionRelease,
    if (evidence.exitCode != null) '退出码 ${evidence.exitCode}',
    if (evidence.crashReportOfThisLaunch != null) '有新崩溃报告',
    if (evidence.viaLoader) '走了加载器',
    if (evidence.viaLoader && !evidence.loaderReady) '加载器不可用',
    if (evidence.memoryMb != null) '堆 ${evidence.memoryMb} MB',
  ];
  if (facts.isNotEmpty) parts.add('依据：${facts.join('；')}');

  final modName = _namedModOf(rule, evidence);
  if (modName != null) parts.add('被点名的模组：$modName');
  return parts.join('\n');
}

String? _namedModOf(CrashRule rule, CrashEvidence evidence) {
  if (rule.id != 'MOD_GAME_VERSION_MISMATCH' &&
      rule.id != 'MOD_RUNTIME_ERROR') {
    return null;
  }
  return namedModIn(evidence.diagnosticText);
}

/// 命中行前后两行，最多 12 行
String? _excerptOf(CrashEvidence evidence, String hitLine) {
  if (hitLine.isEmpty) return null;
  final text = evidence.diagnosticText;
  final index = text.indexOf(hitLine);
  if (index < 0) return null;

  final lines = text.split('\n');
  final lineIndex = '\n'.allMatches(text.substring(0, index)).length;
  final start = max(0, lineIndex - 2);
  final end = min(lines.length, start + 12);
  return lines.sublist(start, end).join('\n');
}

CrashDiagnosis _unknownDiagnosis(CrashEvidence evidence) {
  final facts = <String>[
    if (evidence.exitCode != null) '退出码 ${evidence.exitCode}',
    if (evidence.crashReport != null) '有崩溃报告',
    if (evidence.launchSentinelLeft) '游戏没删掉启动哨兵',
  ];
  return CrashDiagnosis(
    code: 'UNKNOWN',
    severity: CrashSeverity.degraded,
    fatal: true,
    title: '游戏异常退出，没认出具体原因',
    detail: facts.isEmpty
        ? '没拿到可判定的证据'
        : '看到的线索：${facts.join('；')}；日志里没有能归因的写法',
    suggestions: const ['到运行日志里看最后 200 行', '把 crashes 里最新一份报告留好', '导出诊断包再对照着看'],
    matchedRuleId: '',
    evidenceExcerpt: _tailOf(evidence.diagnosticText, 12),
    action: CrashAction.exportBundle,
  );
}

String? _tailOf(String text, int maxLines) {
  if (text.isEmpty) return null;
  final lines = text.split('\n');
  if (lines.length <= maxLines) return text;
  return lines.sublist(lines.length - maxLines).join('\n');
}

/// 一条命中：规则、规则表里的位置、命中行、得分
class _RuleHit {
  const _RuleHit(this.rule, this.index, this.line, this.score);

  final CrashRule rule;
  final int index;
  final String line;
  final int score;
}
