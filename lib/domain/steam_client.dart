import 'dart:io';

import 'package:copper_launcher/domain/steam_library.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

/// 唤醒 Steam 客户端的结果
enum SteamWakeOutcome {
  /// 本来就在跑，我们没动手
  alreadyRunning,

  /// 我们唤醒了它，并确认已经登录
  wokeReady,

  /// 我们唤醒了它，但等不到确认（玩家可能还没选账号）——
  /// 这一局很可能显示 Steam 版本却用不了 Steam 功能，要提醒玩家
  wokeUnconfirmed,

  /// 唤不起来（找不到客户端 / 启动失败）
  failed,

  /// 玩家点了通知，主动选择不等了
  skipped;

  /// 值不值得给玩家一句提醒
  ///
  /// [skipped] 不算：那是玩家自己点的，别再念叨他
  bool get shouldWarn => this == wokeUnconfirmed || this == failed;
}

/// Steam 客户端的「在不在跑」「登没登录」与「把它唤醒」
///
/// Steam 版靠 `SteamAppId` 旁路独立启动（见 `SteamLibrary.launchEnvironment`），
/// 但那只在客户端**已经登录**时成立；进程起来但没选账号时游戏拿不到 Steam API，
/// 表现为「显示 Steam 版本但没有功能」
///
/// 唤醒与等待都不阻断游戏启动：拿不到确认就交给调用方提醒玩家
class SteamClient {
  SteamClient._();

  /// 唤醒后最多等多久（玩家要选账号，给宽一点）
  static const readyTimeout = Duration(seconds: 90);

  /// 轮询就绪的间隔
  static const pollInterval = Duration(milliseconds: 500);

  /// 客户端主进程名
  static String get processName {
    if (Platform.isWindows) return 'steam.exe';
    if (Platform.isMacOS) return 'steam_osx';
    return 'steam';
  }

  /// 客户端是否在跑
  static Future<bool> isRunning() async {
    try {
      if (Platform.isWindows) {
        // `/NH` 去表头；只认输出里有没有进程名 —— 「没匹配」的提示文案
        // 随系统语言变，不能拿它当判据
        final result = await Process.run('tasklist', [
          '/FI',
          'IMAGENAME eq $processName',
          '/NH',
        ]);
        return result.stdout.toString().toLowerCase().contains(
          processName.toLowerCase(),
        );
      }
      final result = await Process.run('pgrep', ['-x', processName]);
      return result.exitCode == 0;
    } catch (error) {
      addLog(.warning, '查 Steam 客户端是否在运行失败：$error', tag: 'Steam');
      return false;
    }
  }

  /// 从 `loginusers.vdf` 里取最新的一次登录时刻（纯函数，方便用例喂字符串）
  ///
  /// 取所有账号里的最大值：登进去的那个 `Timestamp` 会刷新成当下时间，所以它变了
  /// 就说明刚登录过；不用注册表的 `ActiveProcess\ActiveUser` —— 那是「当前登着谁」，
  /// 客户端退出后可能残留，分不出「刚登进去」和「上次会话留下的」
  static int? parseLastLoginTimestamp(String content) {
    var newest = 0;
    for (final match in RegExp(
      r'"Timestamp"\s*"(\d+)"',
      caseSensitive: false,
    ).allMatches(content)) {
      final value = int.tryParse(match.group(1)!);
      if (value != null && value > newest) newest = value;
    }
    return newest == 0 ? null : newest;
  }

  /// `<Steam根>/config/loginusers.vdf` 里最新的登录时刻；读不到返回 null
  static int? lastLoginTimestamp() {
    final root = SteamLibrary.steamRoot();
    if (root == null) return null;
    final file = File(p.join(root, 'config', 'loginusers.vdf'));
    if (!file.existsSync()) return null;
    try {
      return parseLastLoginTimestamp(file.readAsStringSync());
    } catch (error) {
      addLog(.warning, '读 Steam 登录记录失败：$error', tag: 'Steam');
      return null;
    }
  }

  /// 确保客户端可用：没跑就唤醒，然后等它真的登录进去
  ///
  /// [onWaking]：确实要唤醒、且已把它拉起来时回调一次，调用方拿它给玩家提示
  /// [shouldSkip]：每轮询问一次，返回 true 就不再等（玩家点了提示）
  ///
  /// 不抛异常、也不阻断游戏启动
  static Future<SteamWakeOutcome> ensureRunning({
    Duration? timeout,
    void Function()? onWaking,
    bool Function()? shouldSkip,
  }) async {
    if (await isRunning()) return SteamWakeOutcome.alreadyRunning;

    // 记下唤醒前的登录时刻：登录成功后 Steam 会刷新它 ⇒ 变了才算真的就绪
    final before = lastLoginTimestamp();

    if (!await _spawnClient()) {
      addLog(.warning, '找不到 Steam 客户端，跳过唤醒', tag: 'Steam');
      return SteamWakeOutcome.failed;
    }
    addLog(.info, '正在唤醒 Steam 客户端', tag: 'Steam');
    onWaking?.call();

    final deadline = DateTime.now().add(timeout ?? readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (shouldSkip?.call() ?? false) {
        addLog(.info, '玩家选择跳过等待 Steam 登录', tag: 'Steam');
        return SteamWakeOutcome.skipped;
      }
      await Future.delayed(pollInterval);
      if (!await isRunning()) continue;

      final now = lastLoginTimestamp();
      // 读不到登录记录就没法判断，只能接着等（超时按「不确定」返回）
      if (now != null && now != before) {
        addLog(.info, 'Steam 客户端已登录，可以启动', tag: 'Steam');
        return SteamWakeOutcome.wokeReady;
      }
    }

    addLog(.warning, '等 Steam 登录超时（可能还没选账号），照常启动游戏', tag: 'Steam');
    return SteamWakeOutcome.wokeUnconfirmed;
  }

  /// 拉起客户端；找不到可执行文件返回 false
  static Future<bool> _spawnClient() async {
    try {
      // macOS 的 Steam 是 app bundle，得走 open
      if (Platform.isMacOS) {
        await Process.run('open', ['-a', 'Steam']);
        return true;
      }

      final root = SteamLibrary.steamRoot();
      final name = Platform.isWindows ? 'steam.exe' : 'steam.sh';
      final candidate = root == null ? null : File(p.join(root, name));
      if (candidate != null && candidate.existsSync()) {
        await _startDetached(candidate.path);
        return true;
      }

      // 发行版包管理器装的 Steam 在 PATH 里，交给 shell 找
      if (Platform.isLinux) {
        await _startDetached('steam');
        return true;
      }
      return false;
    } catch (error) {
      addLog(.warning, '启动 Steam 客户端失败：$error', tag: 'Steam');
      return false;
    }
  }

  /// `-silent`：静默进托盘，不抢正在起的游戏焦点
  ///
  /// detached：不持有句柄，客户端不会因为启动器退出而被带走
  static Future<void> _startDetached(String executable) =>
      Process.start(executable, ['-silent'], mode: ProcessStartMode.detached);
}
