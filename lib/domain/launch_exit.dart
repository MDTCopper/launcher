/// 退出事件行的解析与归类
///
/// 这里不碰 IO 与 Flutter，只做纯判定，方便单独核对
library;

/// 退出事件行的形态：桥与桌面两侧都只发 `exit <退出码>`
final RegExp _exitLinePattern = RegExp(r'^exit (-?\d+)$');

/// 从日志行里取出退出码；不是退出行时返回 null
///
/// 游戏 stdout 里带 `exit` 的普通日志不是退出事件，只看锚定的 `exit <码>`
int? parseExitCodeLine(String line) {
  final match = _exitLinePattern.firstMatch(line.trim());
  final codeText = match?.group(1);
  if (codeText == null) return null;
  return int.tryParse(codeText);
}

/// 退出码归类
enum LaunchExitKind {
  /// 游戏自己正常结束
  normal,

  /// 被启动器主动停止
  stopped,

  /// 异常退出；Windows 崩溃码是负的 NTSTATUS，也落这里
  crashed,
}

/// 按退出码判这一局怎么结束的
///
/// 只认整数本身：崩溃码 `-1073741819` 里含 `0`，不能按子串判成正常退出
LaunchExitKind classifyExitCode(int? code) {
  if (code == 0) return LaunchExitKind.normal;
  if (code == -1) return LaunchExitKind.stopped;
  return LaunchExitKind.crashed;
}
