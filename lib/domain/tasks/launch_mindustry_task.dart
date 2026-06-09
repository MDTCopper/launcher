import 'package:copperlauncher_main/core/app_config.dart';
import 'package:copperlauncher_main/data/local_asset.dart';
import 'package:copperlauncher_main/domain/mindustry_launcher.dart';
import 'package:copperlauncher_main/domain/task.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
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

  Future<void> _overrideSettings() async {
    final settingPath = mindustry.settingPath;
    final setting = MindustrySettings.fromFile(settingPath);
    setting.applyPatch(config.setting.mindustrySettings);
    await setting.saveAsync();
  }

  void _launch() async {
    NotificationManager.addNotice(
      icon: Icons.rocket_launch_outlined,
      title: '启动',
      content: '正在启动\r\n[${mindustry.name}]',
    );
    LogManager.addLog(LogEntry(LogType.info, '正在启动游戏'));

    final launchOption = config.setting.launchOptions;
    WindowSize? winSize;

    //todo 全屏参数
    bool? full;
    bool? maximize;
    switch (launchOption.gameWindowSizeSet) {
      case GameWindowSizeSet.gameDefault:
        break;
      case GameWindowSizeSet.maximize:
        maximize = true;
        break;
      case GameWindowSizeSet.custom:
        winSize = launchOption.customWindowSize;
        break;
      case GameWindowSizeSet.fullScreen:
        full = true;
        break;
    }

    final Memory? maxMemory;
    final gameAuto = mindustry.autoMemory;
    if (gameAuto != null) {
      maxMemory = gameAuto ? null : mindustry.memory;
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

    final List<String> args = (mindustry.jvmParameter ??
            launchOption.javaOptions.jvmParameter)
        .split(' ');

    if (config.setting.mindustrySettingsOverride) {
      await _overrideSettings();
    }
    await launcher.start(
      mindustry,
      fullScreen: full,
      maximize: maximize,
      windowSize: winSize,
      maxMemory: maxMemory,
      javaExecutable: javaPath,
      extraArgs: args,
    );

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
