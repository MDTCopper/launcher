import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/mindustry/mindustry.dart';
import 'package:copper_launcher/domain/bridge_installer.dart';
import 'package:copper_launcher/domain/game_instance.dart';
import 'package:copper_launcher/domain/shortcut_session.dart';
import 'package:copper_launcher/generated/android_call.g.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/host_annotations.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart' show Icons;

/// 桌面快捷方式「直接启动游戏」的 Dart 侧入口
///
/// 快捷方式带 `version_id` 回到宿主（`IncomingIntake` 先攒着），这里在启动器起来后
/// 取一次并直接拉起对应版本；取走即清空，连点不会重复建启动任务。
/// 宿主的新请求通过生成的 [AndroidEvent] 直接调 [onShortcutLaunch] 推过来；
/// 冷启动时引擎会把平台消息排到 Dart 起来之后再送，所以事件和 `takeLaunchRequest`
/// 可能各触发一次同一份请求，由 [_launch] 按版本 id 去重。
class ShortcutLaunch {
  ShortcutLaunch._();

  static bool _started = false;
  static bool _handling = false;

  /// 正在处理的版本 id：同一次快捷方式的事件 + 冷启动 take 只处理一份
  static String? _lastVersionId;
  static DateTime? _lastLaunchedAt;
  static Future<bool> Function()? _waitForShell;

  /// 启动时调一次：把冷启动那次请求取回来
  ///
  /// 通道接线（`AndroidEvent.start()`）由启动流程统一做，这里只管取数据；
  /// [waitForShell] 给界面就绪信号：启动前可能还有冲突弹窗之类的界面动作，
  /// 拿不到界面时这次请求只记日志、不启动
  static Future<void> start({Future<bool> Function()? waitForShell}) async {
    if (!Platform.isAndroid || _started) return;
    _started = true;
    _waitForShell = waitForShell;
    await _consume();
  }

  /// 宿主推来的新请求：热启动事件自带版本 id，不用再取一次
  ///
  /// 冷启动时宿主那次事件不会被丢（引擎会把平台消息排到 Dart 起来之后再送），
  /// 会和 [start] 里的 `takeLaunchRequest` 各触发一次同一份请求，所以 [_launch] 里要去重。
  @KotlinEvent()
  static void onShortcutLaunch(String versionId, bool silent) {
    unawaited(_launch(versionId));
  }

  static Future<void> _consume() async {
    if (_handling) return;
    final versionId = await _takeLaunchRequest();
    if (versionId == null) return;
    _handling = true;
    try {
      final ready = await _waitForShell?.call() ?? true;
      if (!ready) {
        addLog(.warning, '快捷方式启动：界面没起来，忽略这次请求', tag: 'Shortcut');
        return;
      }
      await _launch(versionId);
    } finally {
      _handling = false;
    }
  }

  static Future<String?> _takeLaunchRequest() async {
    try {
      final value = await AndroidCall.takeLaunchRequest();
      if (value == null) return null;
      addLog(
        .info,
        '快捷方式启动请求：${value.isEmpty ? '默认版本' : value}',
        tag: 'Shortcut',
      );
      return value;
    } on Object catch (error) {
      addLog(
        .warning,
        '取快捷方式启动请求失败：${removeNewlines('$error')}',
        tag: 'Shortcut',
      );
      return null;
    }
  }

  /// 同一次快捷方式会从「事件」和「冷启动 take」前后脚各来一次
  ///
  /// 只按「并发」去重不够：先到的那次很快就把请求交给启动任务（事件回调先跑），
  /// 后到的 take 已经在另一个回合，会再走一遍并撞上 GameInstance 的「已有游戏在运行」，
  /// 给玩家弹一条无意义的提示。这里按版本 id + 短时间窗去重。
  static Future<void> _launch(String versionId) async {
    final now = DateTime.now();
    final lastAt = _lastLaunchedAt;
    final duplicate = _lastVersionId == versionId &&
        lastAt != null &&
        now.difference(lastAt) < const Duration(seconds: 5);
    if (duplicate) return;
    _lastVersionId = versionId;
    _lastLaunchedAt = now;
    await _launchOnce(versionId);
  }

  static Future<void> _launchOnce(String versionId) async {
    if (!BridgeInstaller.isRuntimeReady()) {
      addLog(.warning, '快捷方式启动：桥运行环境还没装好，忽略', tag: 'Shortcut');
      await _showLauncher();
      return;
    }
    if (await _isGameActivityVisible()) {
      addLog(.info, '快捷方式启动：游戏界面还在，回到游戏', tag: 'Shortcut');
      // 快捷方式是显式拉起 MainActivity，会在游戏上再压一个启动器实例；
      // 结束自己就把下面的游戏露出来，别让人看到启动器
      await _finishLauncher();
      return;
    }

    // 空 version id 是「默认入口」（比如从小组件面板直接加的小组件），用当前选中版本
    final version = versionId.isEmpty
        ? config.versionOptions.selectedVersion
        : _findVersion(versionId);
    if (version == null) {
      addLog(.warning, '快捷方式启动：找不到版本 $versionId', tag: 'Shortcut');
      await _showLauncher();
      addNotice(
        icon: Icons.error_outline,
        title: '快捷方式失效',
        content: '启动器里已经找不到这个版本，重新添加一个桌面快捷方式',
      );
      return;
    }

    addLog(.info, '快捷方式启动：${version.tag}', tag: 'Shortcut');
    // 打个标记：这一局是快捷方式启动的，退出后按设置决定回桌面还是回启动器
    ShortcutSession.markLaunchedFromShortcut();
    await GameInstance.launch(version);
    // 静默启动：黑幕先留着，等游戏盖上来；兜底 20 秒后撤掉（万一没起来也别一直黑）
    unawaited(_restoreLauncherAfterLaunch());
  }

  /// 兜底：20 秒后把黑幕撤掉。游戏正常起来时它早就盖在上面了，撤不撤都看不见；
  /// 万一启动失败又没走到失败分支，也不至于一直黑屏
  static Future<void> _restoreLauncherAfterLaunch() async {
    await Future<void>.delayed(const Duration(seconds: 20));
    await _showLauncher();
  }

  /// 游戏退出 / 启动失败时撤掉静默启动的黑幕，把启动器界面还回来
  static Future<void> showLauncher() => _showLauncher();

  static Future<bool> _isGameActivityVisible() async {
    try {
      return await AndroidCall.isGameActivityVisible();
    } on Object catch (error) {
      addLog(.warning, '查询游戏界面失败：${removeNewlines('$error')}', tag: 'Shortcut');
      return false;
    }
  }

  /// 把启动器窗口恢复可见（静默启动的收尾 / 启动失败时让玩家看到提示）
  static Future<void> _showLauncher() async {
    try {
      await AndroidCall.hide();
    } on Object catch (error) {
      addLog(
        .warning,
        '恢复启动器窗口失败：${removeNewlines('$error')}',
        tag: 'Shortcut',
      );
    }
  }

  /// 结束当前启动器实例（游戏在跑时用），把下面的游戏露出来
  static Future<void> _finishLauncher() async {
    try {
      await AndroidCall.finishLauncher();
    } on Object catch (error) {
      addLog(
        .warning,
        '结束启动器实例失败：${removeNewlines('$error')}',
        tag: 'Shortcut',
      );
    }
  }

  /// 请求给版本建一个桌面快捷方式（版本设置页「创建桌面快捷方式」用）
  ///
  /// 图标优先用玩家给版本换的那张，没换过用 jar 里的 logo；返回 false 表示桌面不支持固定快捷方式
  static Future<bool> requestPinShortcut(Mindustry version) async {
    try {
      final result = await AndroidCall.requestPinShortcut(
        version.id,
        version.tag,
        version.resolvedJarPath,
        version.resolvedIconPath ?? '',
      );
      addLog(
        .info,
        '请求桌面快捷方式 [${version.tag}]：${result ? '已提交' : '桌面不支持'}',
        tag: 'Shortcut',
      );
      return result;
    } on Object catch (error) {
      addLog(
        .warning,
        '请求桌面快捷方式失败：${removeNewlines('$error')}',
        tag: 'Shortcut',
      );
      return false;
    }
  }

  /// 请求给版本建一个桌面小组件（目前保留备用，版本设置页走快捷方式）
  ///
  /// 返回 false 表示这台设备的桌面不支持一键添加，需要引导用户去小组件面板
  static Future<bool> requestPinWidget(Mindustry version) async {
    try {
      final result = await AndroidCall.requestPinWidget(
        version.id,
        version.tag,
        version.resolvedJarPath,
        version.resolvedIconPath ?? '',
      );
      addLog(
        .info,
        '请求桌面小组件 [${version.tag}]：${result ? '已提交' : '桌面不支持'}',
        tag: 'Shortcut',
      );
      return result;
    } on Object catch (error) {
      addLog(
        .warning,
        '请求桌面小组件失败：${removeNewlines('$error')}',
        tag: 'Shortcut',
      );
      return false;
    }
  }

  /// 按 id 找版本；找不到就是快捷方式失效（不回落选中版本，免得启动错版本）
  static Mindustry? _findVersion(String versionId) {
    for (final fold in config.versionOptions.versionFolds) {
      for (final version in fold.versions) {
        if (version.id == versionId) return version;
      }
    }
    return null;
  }
}
