import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/domain/mindustry_launcher.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/util/widget/feature_button.dart';
import 'package:flutter/material.dart';

import '../../data/mindustry_settings.dart';
import '../../ui/util/info/log_list.dart';
import '../../ui/util/info/notification.dart';

class LaunchMindustryTask extends Task {
  final Mindustry mindustry;

  final launcher = MindustryLauncher();

  LaunchMindustryTask(this.mindustry) {
    type = TaskType.launch;
  }

  @override
  Widget buildDisplayWidget(BuildContext context) {
    return Row(
      children: [
        Text('游戏运行中'),
        ReboundIconButton(icon: Icons.close, content: '关闭', onTap: cancel),
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

  void _launch() async {
    NotificationManager.addNotice(
      icon: Icons.rocket_launch_outlined,
      title: '启动',
      content: '正在启动\r\n[${mindustry.name}]',
    );
    LogManager.addLog(LogEntry(LogType.info, '正在启动游戏'));

    final launchOption = config.setting.launchOptions;

    final settingPath = mindustry.settingPath;
    final setting = MindustrySettings.fromFile(settingPath);

    //窗口大小和最大化在jvm的启动参数
    WindowSize? winSize;
    bool? maximize;
    switch (launchOption.gameWindowSizeSet) {
      case GameWindowSizeSet.fullScreen:
        setting.fullscreen = true;
        break;
      case GameWindowSizeSet.gameDefault:
        break;
      case GameWindowSizeSet.maximize:
        maximize = true;
        setting.fullscreen = false;
        break;
      case GameWindowSizeSet.custom:
        winSize = launchOption.customWindowSize;
        setting.fullscreen = false;
        break;
    }

    final Memory? maxMemory;
    final versionAuto = mindustry.autoMemory;

    if (versionAuto != null) {
      maxMemory = versionAuto ? null : mindustry.memory;
    } else {
      maxMemory = launchOption.autoMemory ? null : launchOption.memory;
    }

    if (maxMemory == null) {
      //todo 自动分配内存，需要配合模组遍历来估算合适的内存
    }

    String? javaPath = mindustry.java ?? launchOption.javaOptions.selectedJava;

    if (javaPath == 'auto') {
      javaPath = null;
      final javas = launchOption.javaOptions.javas;
      for (var it in javas) {
        if ((it.version ?? 0) < 17) continue;
        javaPath = it.path;
        break;
      }
    }

    final List<String> args =
        (mindustry.jvmParameter ?? launchOption.javaOptions.jvmParameter).split(
          ' ',
        );

    if (config.setting.mindustrySettingsOverride) {
      setting.applyPatch(config.setting.mindustrySettings);
    }

    if (setting.data.isNotEmpty) {
      await setting.saveAsync();
    }
    await launcher.start(
      mindustry,
      maximize: maximize,
      windowSize: winSize,
      maxMemory: maxMemory,
      javaExecutable: javaPath,
      extraArgs: args,
    );

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
        LogManager.addLog(LogEntry(LogType.success, '游戏启动成功，耗时$time'));
      }
      if (log.contains('exit')) {
        if (log.contains('0')) {
          NotificationManager.addNotice(
            icon: Icons.info_outline,
            title: '退出',
            content: '正常游戏退出',
          );
          LogManager.addLog(LogEntry(LogType.info, '正常游戏退出'));
        } else if (log.contains('-1')) {
          NotificationManager.addNotice(
            icon: Icons.info_outline,
            title: '退出',
            content: '已停止游戏',
          );
          LogManager.addLog(LogEntry(LogType.info, '已停止游戏'));
        } else {
          NotificationManager.addNotice(
            icon: Icons.error_outline,
            title: '退出',
            content: '游戏异常退出 ($log)',
          );
          LogManager.addLog(LogEntry(LogType.error, '游戏异常退出，退出码 ($log)'));
        }
        progress = 1.0;
        status = TaskStatus.completed;
        updateDisplay();
      }
    });
  }

  @override
  Future<void> runTask() async => _launch();
}
