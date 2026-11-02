import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/cloud/cloud_restore_gap.dart';
import 'package:copper_launcher/domain/cloud/mod_fill_runner.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/tasks/cloud_sync_task.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

/// 补不回来的模组：名字 + 原因，界面拼一句话用
typedef CloudMissingMod = ({String name, String reason});

/// 排一个补全项；返回 false 表示没排上，按失败算
typedef CloudGapEnqueue = Future<bool> Function(ModFillOutcome outcome);

/// 按「本机还缺什么」把能补的模组补上
///
/// 拉取 / 历史恢复 / 一键补全共用这一份：读官方列表、逐个定计划、交给
/// [enqueue] 排下载，补不回来的收成一张表；不碰任务卡，怎么排由调用方定
///
/// [enqueue] 收到 `isQueued` 的结果，返回 false 或抛错都记成下载失败
/// [isCancelled] 返回 true 时收手，已排上的不动
Future<List<CloudMissingMod>> fillGapMods({
  required CloudRestoreGap gap,
  required Mindustry version,
  required CloudGapEnqueue enqueue,
  void Function(String status)? onStatus,
  bool Function()? isCancelled,
}) async {
  if (gap.downloadableMods.isEmpty) return const [];
  final missing = <CloudMissingMod>[];

  onStatus?.call('补全 ${version.tag} 的模组');
  final outcomes = await fillMissingMods(
    gap: gap,
    version: version,
    queueTasks: false,
    onStatus: onStatus,
  );
  for (final outcome in outcomes) {
    if (isCancelled?.call() ?? false) return missing;
    if (!outcome.isQueued) {
      missing.add((
        name: outcome.displayName,
        reason: outcome.detail ?? modFillReason(outcome.status),
      ));
      continue;
    }
    var ok = false;
    try {
      ok = await enqueue(outcome);
    } on Object catch (error) {
      addLog(
        .warning,
        '补全模组失败：${outcome.displayName} —— ${removeNewlines('$error')}',
        tag: 'Cloud',
      );
      ok = false;
    }
    if (!ok) missing.add((name: outcome.displayName, reason: '下载失败'));
  }
  return missing;
}

/// 「补全本机缺的模组」任务卡
///
/// 缺口算好传进来，按模组个数加权推进度；每个模组挂成子任务，
/// 不进任务抽屉、不单独发通知
class CloudGapFillTask extends CloudSyncTask {
  CloudGapFillTask({
    required this.version,
    required this.gap,
    this.idSuffix,
  }) : super(
         direction: CloudSyncDirection.download,
         versionTag: version.tag,
         idOverride: 'cloud_gap_fill_${idSuffix ?? version.tag}',
         onRun: _run,
       );

  final Mindustry version;
  final CloudRestoreGap gap;

  /// 同一个版本可能有多个入口，给不同 id 免得互相顶掉
  final String? idSuffix;

  /// 补不回来的模组
  final List<CloudMissingMod> missingMods = [];

  @override
  String get displayTitle => '补全模组';

  @override
  IconData get displayIcon => Icons.extension_outlined;

  static Future<String> _run(CloudSyncTask task) =>
      (task as CloudGapFillTask).run();

  Future<String> run() async {
    missingMods
      ..clear()
      ..addAll(
        await fillGapMods(
          gap: gap,
          version: version,
          isCancelled: () => cancelToken.isCancelled,
          onStatus: setPhase,
          enqueue: (outcome) async {
            final item = CloudTaskItem(title: outcome.displayName);
            addQueueItem(item);
            final subtask = buildFillTask(outcome.plan!, version);
            bindQueueSubTask(item, subtask);
            await subtask.startAsync();
            return subtask.status == TaskStatus.completed;
          },
        ),
      );
    if (cancelToken.isCancelled) return '已取消补全';
    final parts = <String>['补全 ${version.tag}'];
    if (missingMods.isNotEmpty) parts.add('${missingMods.length} 个没补回来');
    return parts.join('，');
  }
}
