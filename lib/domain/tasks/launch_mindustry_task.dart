import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/be_version.dart';
import 'package:copper_launcher/domain/bridge_launcher.dart';
import 'package:copper_launcher/domain/cloud/cloud_auto_sync.dart';
import 'package:copper_launcher/domain/mindustry_launcher.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_multiplayer_service.dart';
import 'package:copper_launcher/domain/steam_version.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/dialog/java_missing_prompt.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/auto_memory.dart';
import 'package:copper_launcher/util/format/date_time_format.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/game_process_watch.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/java/java_compat.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/launcher_tray.dart';

import 'package:copper_launcher/util/system_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../ui/dialog/game_log_dialog.dart';
import '../../ui/shell/drawer/log_list.dart';
import '../../ui/util/notification.dart';

class LaunchMindustryTask extends Task {
  @override
  IconData get displayIcon => Icons.rocket_launch;

  @override
  String get displayTitle => '启动';

  final Mindustry mindustry;

  final launcher = MindustryLauncher();

  /// 本次启动时刻；游戏退出成功时用于计算本次游玩时长
  DateTime? _launchStartTime;

  /// `exit` 只收尾一次：自更新接管与手动结束都可能走到这里
  bool _exitHandled = false;
  bool _finished = false;
  bool _cancelled = false;

  /// 自更新重启后接管的新进程 PID（null 表示没接管）
  int? _adoptedPid;
  String? _adoptedBuild;

  LaunchMindustryTask(this.mindustry);

  @override
  Widget buildDisplayWidget(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    final statusText = switch (status) {
      TaskStatus.pending => '准备启动',
      TaskStatus.process => '运行中...',
      TaskStatus.completed => '已退出',
      TaskStatus.failed => '启动失败',
      TaskStatus.paused => '已暂停',
      TaskStatus.cancel => '已停止',
    };

    return Column(
      crossAxisAlignment: .start,
      children: [
        Row(
          children: [
            Icon(Icons.rocket_launch, size: 24, color: colors.interactive),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Mindustry',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.interactive,
                ),
              ),
            ),
            Text(createTime.toTimeString(), style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _adoptedBuild == null
              ? 'Mindustry ${mindustry.tag}  $statusText'
              : 'Mindustry ${mindustry.tag}  Build $_adoptedBuild（自更新后运行中）',
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(),
        const SizedBox(height: 8),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: ActionButton(
                alignment: .center,
                backgroundColor: colors.highBackgroundOnCard,
                icon: Icon(Icons.pause),
                content: Text('结束进程'),
                onTap: cancel,
              ),
            ),
            if (kDebugMode)
              Expanded(
                child: ActionButton(
                  alignment: .center,
                  backgroundColor: colors.highBackgroundOnCard,
                  icon: Icon(Icons.terminal),
                  content: Text('进程日志'),
                  onTap: () => _showGameLog(context),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// 游戏自己的日志文件（`last_log.txt`）
  ///
  /// v126 之前游戏把数据落在 `<数据目录>/Mindustry/` 下，所以两个位置都找一遍
  File? _gameLogFile() {
    for (final path in [
      p.join(mindustry.dataPath, 'last_log.txt'),
      p.join(mindustry.dataPath, 'Mindustry', 'last_log.txt'),
    ]) {
      final file = File(path);
      if (file.existsSync()) return file;
    }
    return null;
  }

  /// 进程日志：游戏写在自己数据目录里的 `last_log.txt`
  ///
  /// 桥那条路（Android）拿不到进程的 stdout，这份文件是唯一能看的
  void _showGameLog(BuildContext context) {
    final file = _gameLogFile();
    if (file == null) {
      addNotice(
        icon: Icons.info_outline,
        title: '没有日志',
        content: '这个版本的数据目录下没有 last_log.txt',
      );
      return;
    }
    showLogFileDialog(context, path: file.path, text: file.readAsStringSync());
  }

  @override
  void cancel() async {
    _cancelled = true;
    final adopted = _adoptedPid;
    _adoptedPid = null;
    _adoptedBuild = null;
    if (adopted != null) {
      GameProcessWatch.kill(adopted);
      _removeLaunchSentinel();
      addLog(.info, '结束自更新后重启的游戏进程 $adopted', tag: 'BE');
    }
    super.cancel();
    await launcher.stopMindustryJar();
    status = TaskStatus.cancel;
    launcher.dispose();
  }

  @override
  void pause() => cancel();

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
    // 上次桥侧取消可能留下标记；新一局先清掉，避免误判
    _clearLaunchCanceledMarker();

    NotificationManager.addNotice(
      icon: Icons.rocket_launch_outlined,
      title: '启动',
      content: '正在启动\r\n[${mindustry.tag}]',
    );
    TaskLogManager.addLog(LogEntry(LogType.info, '正在启动游戏'));

    final launchOption = config.setting.launchOptions;

    // Steam 版特化：Steam 更新会把本体 jar 就地换掉（还是同一个路径），
    // 启动前核一次版本，变了就更新记录 + 通知（数据目录绑定也顺手补齐）
    if (mindustry.steam) {
      try {
        final change = await SteamVersion.refresh(mindustry);
        if (change != null) {
          NotificationManager.addNotice(
            icon: Icons.sync,
            title: 'Steam 版已更新',
            content: '${mindustry.tag}\r\n${change.description}',
          );
        }
      } catch (e) {
        addLog(.warning, 'Steam 版本检查失败：${removeNewlines('$e')}', tag: 'Steam');
      }
    }

    // BE 版同理：游戏自更新会先下载到 be_builds 再原地覆盖本体，
    // 启动前核一次，记录里的 release 才跟得上
    if (mindustry.isBe && !mindustry.steam) {
      try {
        final change = await BeVersion.refresh(mindustry);
        if (change != null) {
          NotificationManager.addNotice(
            icon: Icons.sync,
            title: '游戏本体已更新',
            content: '${mindustry.tag}\r\n${change.description}',
          );
        }
      } catch (e) {
        addLog(.warning, 'BE 版本检查失败：${removeNewlines('$e')}', tag: 'BE');
      }
    }

    // 老配置可能没存大版本号（下载前），启动时从 jar 的 version.properties 补读一次并回写；
    // 新下载的版本已有 versionNumber，跳过此 IO
    if (mindustry.versionNumber == null) {
      try {
        final major = int.tryParse(
          (await FileReader.fromPath(
                mindustry.resolvedJarPath,
              )).mindustry?.version ??
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

    // 文件在但解不开时整段覆写都要跳过：空实例写回去会清掉玩家的键位与存档标题
    // （游戏把标题记在 settings 的 `save-<文件名>-name` 里）
    final settingsReadable =
        !File(settingPath).existsSync() || setting.readable;
    if (!settingsReadable) {
      addLog(
        .warning,
        'settings.bin 读不出来，跳过这次设置覆写 [${mindustry.tag}]',
        tag: 'Launch',
      );
    }

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
    if (supportsSettingsOverride && settingsReadable) {
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

    // Android 上没有「桌面 JDK」这回事：Java 用桥载荷里的 JRE，这整段选择与校验
    // 都不该走 —— 否则设备上一份 Java 都没有，任务会先在这里收尾成「未找到可用 Java」
    if (!Platform.isAndroid) {
      // Steam 版原版启动固定用 Steam 自带的 JRE；走加载器时要换完整 JDK
      // （那份 JRE 只含 java.base + jdk.unsupported，带不了 Guava/Mixin）
      final steamJava = mindustry.steam && !mindustry.isViaLoader
          ? SteamVersion.javaFor(mindustry)
          : null;

      if (steamJava != null) {
        javaPath = steamJava;
        addTaskLog(LogEntry(LogType.info, 'Steam 版：固定用 Steam 自带的 JRE'));
      } else if (javaPath == 'auto') {
        javaPath = _autoPickJava(
          launchOption.javaOptions.javas,
          targetJavaMajor,
        );
      } else {
        //记录形态（数据根内的相对路径）要还原成可用路径才能起进程
        javaPath = AppPaths.resolveStoredPath(javaPath);
      }

      // 启动前兜底：选中路径已失效（被删/移动）则回退自动选择；仍无则中止并提示
      if (javaPath != null && !File(javaPath).existsSync()) {
        addTaskLog(LogEntry(LogType.warning, 'Java 路径失效：$javaPath，回退自动选择'));
        javaPath = _autoPickJava(
          launchOption.javaOptions.javas,
          targetJavaMajor,
        );
      }
      if (javaPath == null) {
        addTaskLog(LogEntry(LogType.error, '未找到可用 Java：无法启动'));
        addLog(.error, '未找到可用 Java：无法启动', tag: 'Launch');
        showJavaMissingPrompt(releaseInt: releaseInt);
        status = TaskStatus.failed;
        updateDisplay();
        return;
      }
    }

    final List<String> args =
        (mindustry.jvmParameter ?? launchOption.javaOptions.jvmParameter).split(
          ' ',
        );

    // 云存档：启动前按需把云端那份拉下来；**冲突要玩家选，没选就不启动**
    if (!await CloudAutoSync.beforeLaunch(mindustry)) {
      addTaskLog(LogEntry(LogType.info, '云存档冲突没处理，已停止启动'));
      addLog(.info, '云存档冲突没处理，停止启动 [${mindustry.tag}]', tag: 'Cloud');
      status = TaskStatus.cancel;
      updateDisplay();
      return;
    }

    if (supportsSettingsOverride &&
        settingsReadable &&
        config.setting.mindustrySettingsOverride) {
      setting.applyPatch(config.setting.mindustrySettings);
    }

    //应用当前选中的游戏内用户：覆盖玩家的 name / color-0
    //（放在通用设置之后，用户信息优先；「账户」页可以把这个覆写关掉）
    final user = config.setting.currentGameUser;
    final overrideIdentity =
        config.setting.getCustomSetting('game_user_override', true) == true;
    if (supportsSettingsOverride &&
        settingsReadable &&
        overrideIdentity &&
        user != null) {
      setting.name = user.name;
      // 禁止：UUID 是联机身份，不随用户覆写
      // setting.uuid = user.uuid;
      setting.color0 = user.color;
    }

    // 官方联机（房主/房客都一样）：失焦/切后台暂停会让另一端约 6 秒断线
    final multiplayer = MdtbbsMultiplayerService.instance.state.value;
    if (supportsSettingsOverride && settingsReadable && multiplayer.inSession) {
      setting.backgroundPause = false;
      addLog(
        .info,
        '联机：关闭游戏失焦暂停（backgroundpause=false）',
        tag: 'Multiplayer',
      );
    }

    if (supportsSettingsOverride &&
        settingsReadable &&
        setting.data.isNotEmpty) {
      await setting.saveAsync();
    }
    //启动前的决策（Java / 内存 / 数据目录 / 覆写）是"改了没生效"的第一现场，记一条
    addLog(
      .info,
      '启动决策 [${mindustry.tag}]：Java：$javaPath；内存：$maxMemory；'
      '数据目录：${mindustry.dataPath}；隔离：${mindustry.isolation ? '开' : '关'}；'
      'settings 覆写：${supportsSettingsOverride && config.setting.mindustrySettingsOverride ? '是' : '否'}；'
      '身份覆写：${overrideIdentity && user != null ? '是' : '否'}；'
      'settings 可读：${settingsReadable ? '是' : '否'}',
      tag: 'Launch',
    );

    // 记录本次启动时刻，游戏退出时回写 lastLaunchTime 与 playTime
    _launchStartTime = DateTime.now();

    final isLaunchStarted = await launcher.start(
      mindustry,
      maximize: maximize,
      windowSize: winSize,
      maxMemory: maxMemory,
      javaExecutable: javaPath,
      extraArgs: args,
    );

    if (!isLaunchStarted) {
      //走加载器时常见原因是 loader jar 不在了
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
        //托盘模式下收进系统托盘
        LauncherTray.instance.hideIfTrayMode();
      }
      if (log.contains('exit')) {
        unawaited(_handleExit(log));
      }
    });
  }

  /// 游戏退出：BE 自更新重启的话把新进程接回来，否则按正常结束收尾
  File _launchCanceledMarkerFile() =>
      File('${BridgeLauncher.cacheDirFor(mindustry)}/launch-canceled');

  /// 桥侧「取消启动」的标记；读到就删掉，按取消收尾
  bool _takeLaunchCanceledMarker() {
    try {
      final file = _launchCanceledMarkerFile();
      if (!file.existsSync()) return false;
      file.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _clearLaunchCanceledMarker() {
    try {
      final file = _launchCanceledMarkerFile();
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // 没有就算了
    }
  }

  Future<void> _handleExit(String exitLog) async {
    if (_exitHandled) return;
    _exitHandled = true;

    // 桥侧点「取消启动」会留这个标记：按取消收尾，不报正常退出
    if (_takeLaunchCanceledMarker()) {
      NotificationManager.addNotice(
        icon: Icons.cancel,
        title: '已取消',
        content: '启动已取消',
      );
      TaskLogManager.addLog(LogEntry(LogType.info, '已取消启动'));
      progress = 1.0;
      status = TaskStatus.cancel;
      updateDisplay();
      return;
    }

    if (!_cancelled &&
        mindustry.isBe &&
        !mindustry.steam &&
        !Platform.isAndroid) {
      if (await _tryAdoptRestartedGame()) return;
    }
    _finishRun(exitLog);
  }

  /// 返回 false 表示不是自更新重启、或者没接上新进程
  Future<bool> _tryAdoptRestartedGame() async {
    final pending = BeVersion.pendingBuild(mindustry, since: _launchStartTime);
    if (pending == null || _cancelled) return false;

    final pid = await GameProcessWatch.findRestartedGame(
      mindustry.resolvedJarPath,
    );
    if (pid == null) {
      if (!_cancelled) {
        addLog(.warning, '游戏自更新后没找到新进程，按退出收尾', tag: 'BE');
      }
      return false;
    }
    if (_cancelled) {
      GameProcessWatch.kill(pid);
      _removeLaunchSentinel();
      return false;
    }

    _adoptedPid = pid;
    _adoptedBuild = pending;
    status = TaskStatus.process;
    updateDisplay();
    addLog(.info, '自更新重启：接管新进程 $pid（Build $pending）', tag: 'BE');
    NotificationManager.addNotice(
      icon: Icons.system_update_alt,
      title: '游戏自更新后仍在运行',
      content: '${mindustry.tag}\r\n已更新到 Build $pending，继续运行',
    );
    // 本体复制可能还没完成，记录交给后台对账
    unawaited(BeVersion.watchAfterExit(mindustry, since: _launchStartTime));
    unawaited(_watchAdopted(pid));
    return true;
  }

  /// 等接管的那个进程结束；它结束才算这一局真的退出
  Future<void> _watchAdopted(int pid) async {
    while (!_cancelled && GameProcessWatch.isAlive(pid)) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    final stopped = _cancelled;
    _adoptedPid = null;
    _adoptedBuild = null;
    // 被启动器停掉时不会再有 exit 事件，收尾只能在这儿做
    _finishRun(stopped ? 'exit -1' : 'exit 0');
  }

  /// 接管的进程不归 [MindustryLauncher] 管，强杀后要自己清启动哨兵
  ///
  /// 哨兵留着，下次启动会被游戏当成「mod 加载崩溃」，把启用中的 mod 全禁掉
  void _removeLaunchSentinel() {
    try {
      final sentinel = File(p.join(mindustry.dataPath, 'launchid.dat'));
      if (sentinel.existsSync()) sentinel.deleteSync();
    } catch (_) {
      // 删不掉只影响下一次启动的 mod 判定，不挡收尾
    }
  }

  /// 一局真正结束：结算时长、恢复托盘、云存档上传、报退出
  void _finishRun(String exitLog) {
    if (_finished) return;
    _finished = true;

    // 回写最近启动时间与累计游玩时长
    final launchStart = _launchStartTime;
    if (launchStart != null) {
      final now = DateTime.now();
      mindustry.lastLaunchTime = now;
      final duration = now.difference(launchStart);
      mindustry.playTime = (mindustry.playTime ?? Duration.zero) + duration;
      _launchStartTime = null;
      // 退出回调非异步上下文，fire-and-forget 保存
      config.save();
    }
    //托盘模式下按恢复窗口选项决定是否弹出主窗口
    LauncherTray.instance.showIfRestoreOnExit();
    // 云存档：游戏退出后自动上传（只对启用了云存档的目录；失败只提示）
    unawaited(CloudAutoSync.afterGameExit(mindustry));
    if (exitLog.contains('0')) {
      NotificationManager.addNotice(
        icon: Icons.info_outline,
        title: '退出',
        content: '正常游戏退出',
      );
      TaskLogManager.addLog(LogEntry(LogType.info, '正常游戏退出'));
    } else if (exitLog.contains('-1')) {
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
        content: '游戏异常退出 ($exitLog)',
      );
      TaskLogManager.addLog(LogEntry(LogType.error, '游戏异常退出，退出码 ($exitLog)'));
    }
    progress = 1.0;
    status = TaskStatus.completed;
    updateDisplay();
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
