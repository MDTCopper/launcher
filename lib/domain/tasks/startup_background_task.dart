import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/components/animation/eased_progress_bar.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/util/io/github_mirror.dart';
import 'package:copper_launcher/util/io/java/java_finder.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/remote_data.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

///启动后台初始化任务：刷新 remote 数据、加载镜像节点、校验 Java 配置、
///检查游戏文件完整性。由 main 在进入 app 前添加，进任务抽屉自跑，不阻塞首帧。
class StartupBackgroundTask extends Task {
  ///当前步骤描述
  String? describe;

  ///已完成步骤数，用于折算进度
  int _completedSteps = 0;

  ///总步骤数，每完成一步进度前进一步
  static const _totalSteps = 4;

  StartupBackgroundTask() {
    type = TaskType.check;
    progress = 0.0;
  }

  bool get _shouldStop => status == TaskStatus.cancel;

  @override
  Future<void> runTask() async {
    await _runStep('正在刷新远程数据', RemoteData.refresh);
    if (_shouldStop) return;
    await _runStep('正在加载镜像节点', GithubMirror.instance.load);
    if (_shouldStop) return;
    await _runStep('正在校验 Java 配置', _checkConfiguredJavas);
    if (_shouldStop) return;
    await _runStep('正在检查游戏文件', _checkAndPromptGameIssues);
    if (_shouldStop) return;

    describe = '后台校验完成';
    progress = 1.0;
    status = TaskStatus.completed;
    updateDisplay();
  }

  ///执行单个步骤：先更新描述，完成后折算进度
  Future<void> _runStep(String label, Future<void> Function() step) async {
    describe = '$label（${_completedSteps + 1}/$_totalSteps）';
    updateDisplay();
    await step();
    _completedSteps++;
    progress = _completedSteps / _totalSteps;
    updateDisplay();
  }

  ///校验配置里的 javas：失效项标记，选中失效则回退自动选择，有变更才保存
  Future<void> _checkConfiguredJavas() async {
    final invalid = await JavaFinder.validateConfiguredJavas();
    if (invalid > 0) {
      addLogAndPrint(.warning, '$invalid 个 Java 配置路径失效，已标记并在选中时回退自动');
      await config.save();
    }
  }

  ///检查缺失目录/版本，引用检测出孤儿本体，一并询问是否删除。
  ///
  ///空 fold（无版本记录）的目录未创建属正常（如首启默认文件夹），不误报。
  Future<void> _checkAndPromptGameIssues() async {
    final folds = config.versionOptions.versionFolds;

    final missingFolds = <VersionFold>[];
    final missingVersions = <Mindustry>[];
    for (final fold in folds) {
      if (!await Directory(fold.path).exists()) {
        //空 fold 目录未创建不算丢失（首启默认文件夹尚无版本），跳过不误报
        if (fold.versions.isEmpty) continue;
        missingFolds.add(fold);
        Log.add(.warning, '游戏目录不存在: [${fold.tag}] ${fold.path}');
        continue;
      }
      for (final version in fold.versions) {
        if (!await File(version.jarPath).exists()) {
          missingVersions.add(version);
          Log.add(.warning, '游戏版本缺少 jar: [${version.tag}] ${version.jarPath}');
        }
      }
    }

    // 引用检测
    final brokenLower = <String>{
      for (final fold in missingFolds)
        for (final version in fold.versions)
          p.normalize(version.jarPath).toLowerCase(),
      for (final version in missingVersions)
        p.normalize(version.jarPath).toLowerCase(),
    };
    final survivingLower = <String>{
      for (final fold in folds)
        for (final version in fold.versions)
          p.normalize(version.jarPath).toLowerCase(),
    }..removeAll(brokenLower);

    final orphanJars = <String>[];
    final seenOrphan = <String>{};
    void considerOrphan(String jarPath) {
      final norm = p.normalize(jarPath).toLowerCase();
      if (seenOrphan.add(norm) &&
          !survivingLower.contains(norm) &&
          File(jarPath).existsSync()) {
        orphanJars.add(jarPath);
      }
    }

    for (final fold in missingFolds) {
      for (final version in fold.versions) {
        considerOrphan(version.jarPath);
      }
    }
    for (final version in missingVersions) {
      considerOrphan(version.jarPath);
    }

    final count =
        missingFolds.length + missingVersions.length + orphanJars.length;
    if (count == 0) return;

    // 应用首帧后几秒：检查缺失目录 / 版本 + 引用检测，有缺失则询问是否删除
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), () {
        final navContext = PageKeyProvider.navigatorKey.currentContext;
        if (navContext == null || !navContext.mounted) return;
        final detail = [
          for (final fold in missingFolds) '目录 [${fold.tag}] 已不存在',
          for (final version in missingVersions) '版本 [${version.tag}] 缺少 jar',
          for (final jar in orphanJars) '无引用本体: $jar',
        ].join('\n');
        showConfirmationPopup(
          context: navContext,
          type: ConfirmationType.warning,
          title: '检测到缺失或被孤立的游戏文件',
          content:
              '以下记录或文件是否删除？\n$detail\n\n'
              '（缺失记录仅删记录；无引用本体将删除文件）',
          action: () async {
            for (final fold in missingFolds) {
              config.versionOptions.versionFolds.remove(fold);
              Log.add(.info, '已删除缺失目录记录: [${fold.tag}]');
            }
            for (final version in missingVersions) {
              for (final fold in config.versionOptions.versionFolds) {
                fold.versions.remove(version);
              }
              Log.add(.info, '已删除缺失版本记录: [${version.tag}]');
            }
            for (final jar in orphanJars) {
              try {
                await File(jar).delete();
                Log.add(.info, '已删除无引用本体: $jar');
              } catch (e) {
                Log.add(.warning, '删除无引用本体失败: $jar $e');
              }
            }
            await config.save();
          },
        );
      });
    });
  }

  @override
  Widget buildDisplayWidget(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(getIcon(type), size: 32),
            SizedBox(width: 4),
            Text(
              getTitle(type),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.secondary,
              ),
            ),
            Expanded(child: SizedBox()),
            ReboundButton(onTap: cancel, child: Icon(Icons.close)),
          ],
        ),
        EasedProgressBar(value: progress),
        if (describe != null) Text(describe!, style: theme.textTheme.bodySmall),
        Text(
          createTime.toString().split(' ').last.split('.').first,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
