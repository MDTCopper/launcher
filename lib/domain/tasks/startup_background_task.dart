import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/data/min_game_versions.dart';
import 'package:copper_launcher/domain/mindustry_body.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/components/animation/eased_progress_bar.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/github_mirror.dart';
import 'package:copper_launcher/util/io/java/java_finder.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/remote_data.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:copper_launcher/util/format/string_cleaner.dart';

///启动后台初始化任务：刷新 remote 数据、加载镜像节点、检查 Java 环境、
///检查游戏文件完整性。由 main 在进入 app 前添加，进任务抽屉自跑，不阻塞首帧。
class StartupBackgroundTask extends Task {
  ///当前步骤描述
  String? describe;

  ///已完成步骤数，用于折算进度
  int _completedSteps = 0;

  ///是否包含 Java 环境检查步骤：仅桌面端（移动端用自带 loader，无桌面 Java 路径）
  final bool _includeJavaCheck = isDesktop;

  ///总步骤数，每完成一步进度前进一步
  int get _totalSteps => _includeJavaCheck ? 5 : 4;

  StartupBackgroundTask() {
    type = TaskType.check;
    progress = 0.0;
  }

  bool get _shouldStop => status == TaskStatus.cancel;

  @override
  Future<void> runTask() async {
    //镜像节点必须先加载：后面几步要拉 github 文件，直连 raw 不通的网络只能靠镜像兜底
    await _runStep('正在加载镜像节点', GithubMirror.instance.load);
    if (_shouldStop) return;
    await _runStep('正在刷新远程数据', RemoteData.refresh);
    if (_shouldStop) return;
    await _runStep('正在同步模组版本门禁', MinGameVersions.instance.loadFromRemote);
    if (_shouldStop) return;
    if (_includeJavaCheck) {
      await _runStep('正在检查 Java 环境', _checkJavaEnvironment);
      if (_shouldStop) return;
    }
    await _runStep('正在检查游戏文件', _checkAndPromptGameIssues);
    if (_shouldStop) return;

    describe = '后台校验完成';
    progress = 1.0;
    status = TaskStatus.completed;
    updateDisplay();
  }

  ///执行单个步骤：先更新描述，完成后折算进度
  ///
  ///单步失败（远程拉取超时之类）只记一条继续下一步：这几步互相独立，
  ///一步失败不该连累后面的 Java / 文件检查；抛出去还会让任务卡在「进行中」
  Future<void> _runStep(String label, Future<void> Function() step) async {
    describe = '$label（${_completedSteps + 1}/$_totalSteps）';
    updateDisplay();
    try {
      await step();
    } catch (e) {
      addLogAndPrint(
        .warning,
        '$label失败：${removeNewlines('$e')}',
        tag: 'Startup',
      );
    }
    _completedSteps++;
    progress = _completedSteps / _totalSteps;
    updateDisplay();
  }

  ///检查 Java 环境：一处都没登记过就先浅扫一遍常见位置（首启即自动就绪，
  ///否则「自动选择」在空列表里挑不出东西，第一次点启动只会报缺 Java）；
  ///已登记的则校验失效项，选中失效时回退自动选择
  Future<void> _checkJavaEnvironment() async {
    final javaOptions = config.setting.launchOptions.javaOptions;

    if (javaOptions.javas.isEmpty) {
      //浅扫即可（环境变量 + 常见安装目录）；深扫是全盘递归，不能放启动路径上
      final found = await JavaFinder.getJavaInstallationsInfo();
      if (found.isEmpty) {
        addLogAndPrint(
          .warning,
          '常见位置未找到可用 Java：启动游戏前需手动添加或下载',
          tag: 'Startup',
        );
        return;
      }
      javaOptions.javas = found;
      await config.save();
      addLogAndPrint(.info, '自动登记可用 Java：${found.length} 个', tag: 'Startup');
      return;
    }

    final invalid = await JavaFinder.validateConfiguredJavas();
    if (invalid > 0) {
      addLogAndPrint(
        .warning,
        '$invalid 个 Java 配置路径失效：已标记，选中时回退自动选择',
        tag: 'Startup',
      );
      await config.save();
    }
  }

  ///检查缺失目录/版本，引用检测出孤儿本体，一并询问是否删除
  Future<void> _checkAndPromptGameIssues() async {
    final folds = config.versionOptions.versionFolds;

    final missingFolds = <VersionFold>[];
    final missingVersions = <Mindustry>[];
    for (final fold in folds) {
      if (!await Directory(fold.resolvedPath).exists()) {
        //空 fold 目录未创建不算丢失
        if (fold.versions.isEmpty) continue;
        missingFolds.add(fold);
        addLog(.warning, '游戏目录 [${fold.tag}] 不存在：${fold.resolvedPath}', tag: 'Startup');
        continue;
      }
      for (final version in fold.versions) {
        if (!await File(version.resolvedJarPath).exists()) {
          missingVersions.add(version);
          addLog(
            .warning,
            '版本 [${version.tag}] 缺少游戏本体：${version.resolvedJarPath}',
            tag: 'Startup',
          );
        }
      }
    }

    // 引用检测（比较与去重都按绝对路径，记录形态可能是相对）
    final brokenLower = <String>{
      for (final fold in missingFolds)
        for (final version in fold.versions)
          p.normalize(version.resolvedJarPath).toLowerCase(),
      for (final version in missingVersions)
        p.normalize(version.resolvedJarPath).toLowerCase(),
    };
    final survivingLower = <String>{
      for (final fold in folds)
        for (final version in fold.versions)
          p.normalize(version.resolvedJarPath).toLowerCase(),
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
        considerOrphan(version.resolvedJarPath);
      }
    }
    for (final version in missingVersions) {
      considerOrphan(version.resolvedJarPath);
    }

    // 本体库里的孤儿：库内文件必然是启动器放的，没被任何记录引用就能清
    //
    // 只认启动器自己的命名（`mindustry-<身份>-<hash8>.jar`）：下载的临时 / 分块文件
    // （`<目标>.temp.<i>`）也落在这个目录里，它们不是本体，也不该被列成「无引用」——
    // 删了等于丢掉续传缓存
    final libraryDir = Directory(AppPaths.mindustrys);
    if (await libraryDir.exists()) {
      await for (final entity in libraryDir.list()) {
        if (entity is! File) continue;
        if (!MindustryBody.isLibraryBodyName(p.basename(entity.path))) continue;
        considerOrphan(entity.path);
      }
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
          for (final version in missingVersions) '版本 [${version.tag}] 缺少游戏本体',
          for (final jar in orphanJars) '无引用游戏本体：$jar',
        ].join('\n');
        showConfirmationPopup(
          context: navContext,
          type: ConfirmationType.warning,
          title: '检测到缺失或被孤立的游戏文件',
          content:
              '以下记录或文件是否删除？\n$detail\n\n'
              '（缺失记录只删记录；无引用的游戏本体将删除文件）',
          action: () async {
            for (final fold in missingFolds) {
              config.versionOptions.versionFolds.remove(fold);
              addLog(.info, '已删除缺失目录记录 [${fold.tag}]', tag: 'Startup');
            }
            for (final version in missingVersions) {
              for (final fold in config.versionOptions.versionFolds) {
                fold.versions.remove(version);
              }
              addLog(.info, '已删除缺失版本记录 [${version.tag}]', tag: 'Startup');
            }
            for (final jar in orphanJars) {
              try {
                await File(jar).delete();
                addLog(.info, '已删除无引用游戏本体：$jar', tag: 'Startup');
              } catch (e) {
                addLog(
                  .warning,
                  '无引用游戏本体删除失败：$jar，${removeNewlines('$e')}',
                  tag: 'Startup',
                );
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
            if (statusLabel != null)
              Text(statusLabel!, style: theme.textTheme.bodySmall),
            if (canCancel)
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
