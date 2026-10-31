/// 快捷启动请求：命令行参数或已有实例通过单实例 metadata 转发过来
///
/// 只用于桌面端：`--launch-version <version.id>` 由桌面快捷方式 / 启动脚本带入
class LaunchRequest {
  const LaunchRequest(this.versionId);

  /// 命令行参数名；值紧跟其后（UUID，不含空格）
  static const String argument = '--launch-version';

  /// 单实例 metadata 里的动作名，与 [argument] 不是同一层：一个是进程参数，一个是 gRPC 通知
  static const String action = 'launch_version';

  final String versionId;

  /// 从 `main(List<String> args)` 里取；没有请求 / 缺值返回 null
  static LaunchRequest? fromArguments(List<String> args) {
    for (var index = 0; index < args.length; index++) {
      final current = args[index];
      if (current == argument) {
        final value = index + 1 < args.length ? args[index + 1].trim() : '';
        return value.isEmpty ? null : LaunchRequest(value);
      }
      final prefix = '$argument=';
      if (current.startsWith(prefix)) {
        final value = current.substring(prefix.length).trim();
        return value.isEmpty ? null : LaunchRequest(value);
      }
    }
    return null;
  }

  /// 转给已运行实例的 metadata
  Map<String, dynamic> toMetadata() => {
    'action': action,
    'version_id': versionId,
  };

  /// 从单实例 onFocus 回调里取；不是快捷启动请求返回 null
  static LaunchRequest? fromMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null || metadata['action'] != action) return null;
    final versionId = '${metadata['version_id'] ?? ''}'.trim();
    return versionId.isEmpty ? null : LaunchRequest(versionId);
  }
}
