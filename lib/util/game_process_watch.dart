import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

/// 自更新重启后的游戏进程
///
/// 游戏点确认后自己 `Runtime.exec` 起一个新 JVM、再让旧进程退出，启动器手里只剩旧 PID；
/// 新进程的命令行带 `-Dbecopy=<原本体绝对路径>`（之后每次更新都会继续传），
/// 按这个认人 —— 比看父子关系稳：Linux 上父进程一退，子进程就被 reparent 掉了
///
/// 认不出来一律返回 null / false，调用方按「没接管」收尾，不会把任务卡死
class GameProcessWatch {
  GameProcessWatch._();

  /// 找命令行里带 `becopy = <本体文件名>` 的那个 java 进程；超时返回 null
  ///
  /// Windows 查 CIM 的 CommandLine，Linux 读 `/proc/<pid>/cmdline`，macOS 查 `ps`
  static Future<int?> findRestartedGame(
    String becopyPath, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final marker = p.basename(becopyPath).trim().toLowerCase();
    if (marker.isEmpty) return null;

    // 新进程在旧进程退出前就起好了，正常情况下第一次就能认到；
    // 重试只兜 PowerShell 起不来 / 查询偶发失败，别一直刷
    final deadline = DateTime.now().add(timeout);
    var attempts = 0;
    while (attempts < 3) {
      attempts++;
      final pid = await _findByCommandLine(marker);
      if (pid != null) return pid;
      if (!DateTime.now().isBefore(deadline)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    return null;
  }

  /// 进程还在吗
  static bool isAlive(int pid) {
    if (pid <= 0) return false;
    try {
      if (Platform.isWindows) return _windowsAlive(pid);
      if (Platform.isLinux) return Directory('/proc/$pid').existsSync();
      if (Platform.isMacOS) {
        return Process.runSync('ps', ['-p', '$pid', '-o', 'pid=']).exitCode ==
            0;
      }
    } catch (_) {
      // 查不出来按已结束处理，交给调用方正常收尾
    }
    return false;
  }

  /// 结束进程
  static bool kill(int pid) {
    if (pid <= 0) return false;
    try {
      return Process.killPid(pid);
    } catch (_) {
      return false;
    }
  }

  static Future<int?> _findByCommandLine(String marker) async {
    try {
      if (Platform.isWindows) return await _windowsFind(marker);
      if (Platform.isLinux) return _linuxFind(marker);
      if (Platform.isMacOS) return _macFind(marker);
    } catch (_) {
      // 查不出来当作没有
    }
    return null;
  }

  /// PowerShell 的 CIM 查询：java 进程 + 命令行里含本体文件名
  static Future<int?> _windowsFind(String marker) async {
    const template =
        "Get-CimInstance Win32_Process -Filter \"Name='java.exe'\" | "
        "Where-Object { \$_.CommandLine -and "
        "\$_.CommandLine.ToLower().Contains('__MARKER__') } | "
        r'ForEach-Object { $_.ProcessId }';

    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      template.replaceAll('__MARKER__', marker.replaceAll("'", "''")),
    ]).timeout(const Duration(seconds: 15));
    if (result.exitCode != 0) return null;

    final pids = parsePidLines('${result.stdout}');
    return pids.isEmpty ? null : pids.first;
  }

  /// `/proc/<pid>/cmdline` 是 NUL 分隔的参数表
  static int? _linuxFind(String marker) {
    for (final entity in Directory('/proc').listSync()) {
      final pid = int.tryParse(p.basename(entity.path));
      if (pid == null) continue;

      try {
        final file = File('${entity.path}/cmdline');
        if (!file.existsSync()) continue;
        final commandLine = String.fromCharCodes(
          file.readAsBytesSync(),
        ).toLowerCase();
        if (commandLine.contains('-dbecopy=') && commandLine.contains(marker)) {
          return pid;
        }
      } catch (_) {
        // 进程刚好退出 / 没权限读：跳过
      }
    }
    return null;
  }

  static int? _macFind(String marker) {
    final result = Process.runSync('ps', ['-A', '-o', 'pid=,command=']);
    if (result.exitCode != 0) return null;

    return parsePsCommandLines('${result.stdout}', marker);
  }

  /// 一行一个 PID（PowerShell 输出 / `/proc` 的子进程表都这形态）
  static List<int> parsePidLines(String output) => const LineSplitter()
      .convert(output)
      .map((line) => int.tryParse(line.trim()))
      .whereType<int>()
      .toList();

  /// `ps -A -o pid=,command=`：第一个字段是 PID，剩下的是命令行
  static int? parsePsCommandLines(String output, String marker) {
    for (final line in const LineSplitter().convert(output)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final space = trimmed.indexOf(RegExp(r'\s'));
      if (space <= 0) continue;

      final pid = int.tryParse(trimmed.substring(0, space));
      if (pid == null) continue;
      if (trimmed.substring(space).toLowerCase().contains(marker)) return pid;
    }
    return null;
  }

  static bool _windowsAlive(int pid) {
    final handle = OpenProcess(PROCESS_SYNCHRONIZE, false, pid);
    if (handle.error != 0 || !handle.value.isValid) return false;

    try {
      final wait = WaitForSingleObject(handle.value, 0);
      return wait.value == WAIT_TIMEOUT;
    } finally {
      handle.value.close();
    }
  }
}
