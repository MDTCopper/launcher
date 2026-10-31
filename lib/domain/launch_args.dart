/// 启动器命令行：只有这里判断「这次进程是什么角色」
///
/// 入口（桌面快捷方式 / 启动脚本 / Android 宿主）只负责把参数或 intent 交进来，
/// 具体分流在 `main` 里按这个结果做
class LaunchArgs {
  LaunchArgs({
    this.launchVersionId,
    this.resumeVersionId,
    this.service = false,
    this.adoptAll = false,
    this.recover = false,
  });

  /// `--launch-version <id>`：快捷启动入口（脚本 / 桌面快捷方式）
  final String? launchVersionId;

  /// `--resume-launch <id>`：服务被阻塞后拉起的 UI，把这一局交回界面
  final String? resumeVersionId;

  /// `--cloud-service`：本进程是无界面云存档服务
  final bool service;

  /// `--adopt-all`：接管服务死后遗留的会话
  final bool adoptAll;

  /// `--recover`：补做服务死后没上传的退出同步
  final bool recover;

  /// 是否快捷启动触发（需要先决定交给 UI 还是自己进服务）
  bool get isQuickLaunch => launchVersionId != null && !service;

  /// UI 要处理的启动请求（`--resume-launch` 优先）
  String? get uiVersionId => resumeVersionId ?? launchVersionId;

  static LaunchArgs parse(List<String> args) {
    String? valueAfter(String flag) {
      for (var i = 0; i < args.length; i++) {
        final arg = args[i];
        if (arg == flag) {
          if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
            return args[i + 1];
          }
          return null;
        }
        final prefix = '$flag=';
        if (arg.startsWith(prefix)) {
          final value = arg.substring(prefix.length);
          return value.isEmpty ? null : value;
        }
      }
      return null;
    }

    return LaunchArgs(
      launchVersionId: valueAfter('--launch-version'),
      resumeVersionId: valueAfter('--resume-launch'),
      service: args.contains('--cloud-service'),
      adoptAll: args.contains('--adopt-all'),
      recover: args.contains('--recover'),
    );
  }
}
