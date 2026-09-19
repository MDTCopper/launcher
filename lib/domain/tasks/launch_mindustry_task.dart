import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/domain/mindustry_launcher.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/dialog/java_missing_prompt.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/auto_memory.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/java/java_compat.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/launcher_tray.dart';

import 'package:copper_launcher/util/system_info.dart';
import 'package:flutter/material.dart';

import '../../data/mindustry_settings.dart';
import '../../ui/shell/drawer/log_list.dart';
import '../../ui/util/notification.dart';

class LaunchMindustryTask extends Task {
  final Mindustry mindustry;

  final launcher = MindustryLauncher();

  /// 本次启动时刻；游戏退出成功时用于计算本次游玩时长
  DateTime? _launchStartTime;

  LaunchMindustryTask(this.mindustry) {
    type = TaskType.launch;
  }

  @override
  Widget buildDisplayWidget(BuildContext context) {
    //文案跟着状态走：抽屉只列进行中的任务，失败/结束的那一刻这一格会播 800ms 移出动画，
    //期间仍按旧文案渲染——写死「游戏运行中」就会在启动失败时骗人
    final statusText = switch (status) {
      TaskStatus.pending => '准备启动',
      TaskStatus.process => '游戏运行中',
      TaskStatus.completed => '游戏已退出',
      TaskStatus.failed => '启动失败',
      TaskStatus.paused => '已暂停',
      TaskStatus.cancel => '已停止',
    };

    return Row(
      children: [
        Text(statusText),
        //只有进程还在时「关闭」才有意义
        if (status == TaskStatus.process)
          IconTextButton(icon: Icons.close, content: '关闭', onTap: cancel),
      ],
    );
  }

  @override
  void cancel() async {
    super.cancel();
    await launcher.stopMindustryJar();
    status = TaskStatus.cancel;
    launcher.dispose();
  }

  @override
  void pause() => cancel();

  ///意外异常（读配置 / 读本体 / 建进程）也要收尾：任务卡在 process 就会一直
  ///挂在抽屉里显示「游戏运行中」，而游戏根本没起来
  Future<void> _launch() async {
    try {
      await _launchGame();
    } catch (e) {
      addTaskLog(LogEntry(LogType.error, '启动失败：${removeNewlines('$e')}'));
      addLog(.error, '启动失败：${removeNewlines('$e')}', tag: 'Launch');
      NotificationManager.addNotice(
        icon: Icons.error_outline,
        title: '启动失败',
        content: '详见运行日志',
      );
      status = TaskStatus.failed;
      updateDisplay();
    }
  }

  Future<void> _launchGame() async {
    NotificationManager.addNotice(
      icon: Icons.rocket_launch_outlined,
      title: '启动',
      content: '正在启动\r\n[${mindustry.tag}]',
    );
    TaskLogManager.addLog(LogEntry(LogType.info, '正在启动游戏'));

    final launchOption = config.setting.launchOptions;

    // 老配置可能没存大版本号（下载前），启动时从 jar 的 version.properties 补读一次并回写；
    // 新下载的版本已有 versionNumber，跳过此 IO
    if (mindustry.versionNumber == null) {
      try {
        final major = int.tryParse(
          (await FileReader.fromPath(mindustry.resolvedJarPath)).mindustry?.version ??
              '',
        );
        if (major != null) {
          mindustry.versionNumber = major;
          config.save();
        }
      } catch (_) {
        // 读取失败仅影响后续降级判定，不阻塞启动
      }
    }

    // settings.bin 覆写支持：仅 v7+（build ≥ 136，大版本 ≥ 7；数据目录才在版本内）
    // 低版本（io.anuke 时代）数据固定在 %APPDATA%，写入无效且无意义，整体跳过覆写
    final supportsSettingsOverride =
        (mindustry.versionNumber ?? mindustry.releaseInt) >= 7;

    final settingPath = mindustry.settingPath;
    final setting = MindustrySettings.fromFile(settingPath);

    //窗口大小和最大化在jvm的启动参数（fullscreen 写 settings.bin 需版本支持，老版本无相关参数，无法支持）
    WindowSize? winSize;
    bool? maximize;
    var fullscreen = false;
    switch (launchOption.gameWindowSizeSet) {
      case GameWindowSizeSet.fullScreen:
        fullscreen = true;
        break;
      case GameWindowSizeSet.gameDefault:
        break;
      case GameWindowSizeSet.maximize:
        maximize = true;
        break;
      case GameWindowSizeSet.custom:
        winSize = launchOption.customWindowSize;
        break;
    }
    if (supportsSettingsOverride) {
      setting.fullscreen = fullscreen;
    }

    Memory? maxMemory;
    final versionAuto = mindustry.autoMemory;

    if (versionAuto != null) {
      maxMemory = versionAuto ? null : mindustry.memory;
    } else {
      maxMemory = launchOption.autoMemory ? null : launchOption.memory;
    }

    // 自动分配内存：可用内存 + 启用 mod 体积估算合适的最大堆
    maxMemory ??= await _autoAllocateMemory(mindustry);

    // 大版本来自 jar 的 version.properties（已在启动开头补读/下载时存好）；
    // 走模组加载器时要抬到加载器要求的 Java 下限（Mixin 引擎要 17+）
    final releaseInt = mindustry.versionNumber ?? mindustry.releaseInt;
    final targetJavaMajor = mindustry.isViaLoader
        ? JavaCompat.recommendedForLoader(releaseInt)
        : JavaCompat.recommendedFor(releaseInt);

    String? javaPath = mindustry.java ?? launchOption.javaOptions.selectedJava;

    if (javaPath == 'auto') {
      javaPath = _autoPickJava(launchOption.javaOptions.javas, targetJavaMajor);
    } else {
      //记录形态（数据根内的相对路径）要还原成可用路径才能起进程
      javaPath = AppPaths.resolveStoredPath(javaPath);
    }

    // 启动前兜底：选中路径已失效（被删/移动）则回退自动选择；仍无则中止并提示
    if (javaPath != null && !File(javaPath).existsSync()) {
      addTaskLog(LogEntry(LogType.warning, 'Java 路径失效：$javaPath，回退自动选择'));
      javaPath = _autoPickJava(launchOption.javaOptions.javas, targetJavaMajor);
    }
    if (javaPath == null) {
      addTaskLog(LogEntry(LogType.error, '未找到可用 Java：无法启动'));
      addLog(.error, '未找到可用 Java：无法启动', tag: 'Launch');
      showJavaMissingPrompt(releaseInt: releaseInt);
      status = TaskStatus.failed;
      updateDisplay();
      return;
    }

    final List<String> args =
        (mindustry.jvmParameter ?? launchOption.javaOptions.jvmParameter).split(
          ' ',
        );

    if (supportsSettingsOverride && config.setting.mindustrySettingsOverride) {
      setting.applyPatch(config.setting.mindustrySettings);
    }

    //应用当前选中的游戏内用户：覆盖玩家的 name / color-0
    //（放在通用设置之后，用户信息优先）
    final user = config.setting.currentGameUser;
    if (supportsSettingsOverride && user != null) {
      setting.name = user.name;
      // 禁止：UUID 是联机身份，不随用户覆写
      // setting.uuid = user.uuid;
      setting.color0 = user.color;
    }

    if (supportsSettingsOverride && setting.data.isNotEmpty) {
      await setting.saveAsync();
    }
    //启动前的决策（Java / 内存 / 数据目录 / 覆写）是"改了没生效"的第一现场，记一条
    addLog(
      .info,
      '启动决策 [${mindustry.tag}]：Java：$javaPath；内存：$maxMemory；'
      '数据目录：${mindustry.dataPath}；隔离：${mindustry.isolation ? '开' : '关'}；'
      'settings 覆写：${supportsSettingsOverride && config.setting.mindustrySettingsOverride ? '是' : '否'}',
      tag: 'Launch',
    );

    // 记录本次启动时刻，游戏退出时回写 lastLaunchTime 与 playTime
    _launchStartTime = DateTime.now();
    //start() 失败只返回 false、不抛异常（Java 校验不过、本体不存在、进程起不来），
    //没收尾的话任务会一直停在 process：抽屉里挂着「游戏运行中」，而且接着读 logStream
    //还会踩空指针（失败路径上 _logController 根本没建）
    final isLaunchStarted = await launcher.start(
      mindustry,
      maximize: maximize,
      windowSize: winSize,
      maxMemory: maxMemory,
      javaExecutable: javaPath,
      extraArgs: args,
    );

    if (!isLaunchStarted) {
      //走加载器时常见原因是 loader jar 不在了（数据根搬过 / 手删过库里的文件），
      //这种情况说成「Java 或本体不可用」会把人带偏
      final isLoaderMissing =
          mindustry.isViaLoader &&
          MindustryLauncher.usableLoaderPath(mindustry) == null;
      final reason = isLoaderMissing ? '缺少 Copper 加载器' : 'Java 环境或游戏本体不可用';
      final suggestion = isLoaderMissing ? '到版本设置的模组加载器处补齐' : '详见运行日志';
      addTaskLog(LogEntry(LogType.error, '启动失败：$reason'));
      addLog(.error, '启动失败：$reason', tag: 'Launch');
      NotificationManager.addNotice(
        icon: Icons.error_outline,
        title: '启动失败',
        content: '$reason：$suggestion',
      );
      status = TaskStatus.failed;
      updateDisplay();
      return;
    }

    //todo 后续可以尝试做一个脱离
    //监听游戏状态
    launcher.logStream!.listen((log) {
      if (log.contains('Total time to load')) {
        final index = log.indexOf(':');
        final time = log.substring(index);
        NotificationManager.addNotice(
          icon: Icons.check,
          title: '启动成功',
          content: '启动成功，耗时${time.trim()}',
        );
        TaskLogManager.addLog(LogEntry(LogType.success, '游戏启动成功，耗时$time'));
        //托盘模式下收进系统托盘（进程保留监听游戏退出）
        LauncherTray.instance.hideIfTrayMode();
      }
      if (log.contains('exit')) {
        // 回写最近启动时间与累计游玩时长（含正常退出 / 停止 / 异常退出）
        final launchStart = _launchStartTime;
        if (launchStart != null) {
          final now = DateTime.now();
          mindustry.lastLaunchTime = now;
          final duration = now.difference(launchStart);
          mindustry.playTime = (mindustry.playTime ?? Duration.zero) + duration;
          _launchStartTime = null;
          // 退出回调非异步上下文，fire-and-forget 保存（后续任务流程会再 save）
          config.save();
        }
        //托盘模式下按「恢复窗口」选项决定是否弹出主窗口
        LauncherTray.instance.showIfRestoreOnExit();
        if (log.contains('0')) {
          NotificationManager.addNotice(
            icon: Icons.info_outline,
            title: '退出',
            content: '正常游戏退出',
          );
          TaskLogManager.addLog(LogEntry(LogType.info, '正常游戏退出'));
        } else if (log.contains('-1')) {
          NotificationManager.addNotice(
            icon: Icons.info_outline,
            title: '退出',
            content: '已停止游戏',
          );
          TaskLogManager.addLog(LogEntry(LogType.info, '已停止游戏'));
        } else {
          NotificationManager.addNotice(
            icon: Icons.error_outline,
            title: '退出',
            content: '游戏异常退出 ($log)',
          );
          TaskLogManager.addLog(LogEntry(LogType.error, '游戏异常退出，退出码 ($log)'));
        }
        progress = 1.0;
        status = TaskStatus.completed;
        updateDisplay();
      }
    });
  }

  /// 自动选择 Java：按 [target]（游戏版本推荐值，走加载器时会抬到 17+）
  /// 优先主版本精确匹配，没有则取「高于目标的最低可用」，再兜底任意已发现 JVM。
  ///
  ///返回的是**可用路径**（把记录形态解析过），直接可以起进程
  String? _autoPickJava(List<JavaInfo> javas, int target) {
    JavaInfo? exact;
    var bestHigherVersion = -1;
    JavaInfo? higherPick;
    JavaInfo? anyPick;

    for (final it in javas) {
      if (!it.isValid) continue; //失效项不参与选择
      final version = it.version ?? 0;
      if (version == target && exact == null) exact = it;
      if (version > target &&
          (bestHigherVersion == -1 || version < bestHigherVersion)) {
        bestHigherVersion = version;
        higherPick = it;
      }
      if (anyPick == null && it.version != null) anyPick = it;
    }

    return (exact ?? higherPick ?? anyPick)?.resolvedPath;
  }

  /// 自动分配内存：可用内存 + 启用 mod 体积估算合适的最大堆。
  Future<Memory> _autoAllocateMemory(Mindustry mindustry) async {
    final available = await SysInfo.getUsablePhysicalMemory();
    final modTotal = await sumEnabledModSizesIn(
      mindustry.modsPaths,
      settingsPath: mindustry.settingPath,
    );
    return AutoMemory.estimate(
      availableBytes: available,
      enabledModTotalBytes: modTotal,
    );
  }

  @override
  Future<void> runTask() async => _launch();
}
