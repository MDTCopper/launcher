import 'dart:io';

import 'package:copper_launcher/domain/steam_library.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

/// Steam 客户端的「在不在跑」与「把它唤醒」
///
/// Steam 版 Mindustry 靠 `SteamAppId` 旁路独立启动（见 `SteamLibrary.launchEnvironment`），
/// 但那只在 **Steam 客户端已经在跑** 时成立。客户端没跑时游戏拿不到 Steam API
/// （云存档 / 时长 / overlay / 联机全没有），所以起游戏前先把客户端唤醒
///
/// **唤醒失败不抛、也不阻断游戏启动**：这功能是锦上添花，不该把主流程卡死
class SteamClient {
  SteamClient._();

  /// 唤醒后最多等多久（Steam 自己常要几秒）
  static const readyTimeout = Duration(seconds: 30);

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
        // 用 `/NH` 去掉表头；**不能比对「没匹配」的提示文案**，那随系统语言变，
        // 只认输出里有没有进程名本身
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

  /// 确保客户端在跑：没跑就唤醒并等它就绪
  ///
  /// 返回是否（最终）确认在跑；**拿不到也照常继续**，由调用方决定要不要提示
  static Future<bool> ensureRunning({Duration? timeout}) async {
    if (await isRunning()) return true;

    if (!await _spawnClient()) {
      addLog(.warning, '找不到 Steam 客户端，跳过唤醒', tag: 'Steam');
      return false;
    }
    addLog(.info, '正在唤醒 Steam 客户端', tag: 'Steam');

    final deadline = DateTime.now().add(timeout ?? readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(pollInterval);
      if (await isRunning()) {
        addLog(.info, 'Steam 客户端已就绪', tag: 'Steam');
        return true;
      }
    }
    addLog(.warning, '等 Steam 客户端就绪超时，照常启动游戏', tag: 'Steam');
    return false;
  }

  /// 拉起客户端；找不到可执行文件返回 false
  static Future<bool> _spawnClient() async {
    try {
      // macOS 的 Steam 是 app bundle，得走 open（本机没验过）
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
