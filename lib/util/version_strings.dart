/// 版本串的解析与拼装（纯 Dart，无 Flutter 依赖）
///
/// 构建脚本 `tool/build_release.dart` 用它算通道序号、拼显示版本 / tag / 产物名。
/// 启动器侧读同一个格式的是 `domain/launcher_update.dart` 的 `parseLocalVersion` 与
/// `LauncherVersion.tag` —— 那边为了比大小会解析成 `SemVer` 对象，这里只做字符串层面的事，
/// **两处格式必须一致**（`v<版本>` / `v<版本> <通道> <序号>`）
library;

/// 一次发布对应的版本信息
///
/// 管道：正式版只有版本号；内测 / 公测额外带通道与**通道序号**
/// （序号是「同一个版本号、同一个通道里的第几次」，与全局构建号 `appBuildNumber` 不是一回事）
class ReleaseVersion {
  const ReleaseVersion({required this.version, this.channel, this.seq});

  /// 形如 `0.2.0`
  final String version;

  /// `alpha` / `beta`；正式版为 null
  final String? channel;

  /// 通道序号（`alpha` 后面那个数字）；正式版为 null
  final int? seq;

  bool get isPrerelease => channel != null && channel!.isNotEmpty;

  /// 界面显示（也写进 `app_constant.dart` 的 appVersion）：`v0.2.0` / `v0.2.0 alpha 6`
  String get display => isPrerelease ? 'v$version $channel $seq' : 'v$version';

  /// release tag 形态（与产物名同源）：`v0.2.0` / `v0.2.0-alpha6`
  String get tag => isPrerelease ? 'v$version-$channel$seq' : 'v$version';

  /// pubspec / 安装包版本（不带 `v`）：`0.2.0` / `0.2.0-alpha6`
  String get semver => isPrerelease ? '$version-$channel$seq' : version;

  /// 产物名里的通道段：`-alpha6` / 空串
  String get packageChannelPart => isPrerelease ? '-$channel$seq' : '';
}

/// 解析显示版本：`v0.2.0` / `v0.2.0 alpha 6`
///
/// 版本号必须是三段数字、带通道就必须有序号；对不上返回 null（调用方按 1 兜底）
ReleaseVersion? parseDisplayVersion(String displayVersion) {
  final parts = displayVersion
      .trim()
      .replaceFirst(RegExp('^v'), '')
      .split(RegExp(r'\s+'));
  if (parts.isEmpty) return null;

  final version = parts.first;
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) return null;
  if (parts.length == 1) return ReleaseVersion(version: version);
  if (parts.length < 3) return null;

  final seq = int.tryParse(parts[2]);
  if (seq == null) return null;
  return ReleaseVersion(version: version, channel: parts[1], seq: seq);
}

/// 下一个通道序号：**同一版本号 + 同一通道**接着数；版本号或通道变了就从 1 开始
///
/// [currentDisplayVersion] 传仓库里记的当前版本（`app_constant.dart` 的 appVersion），
/// 读不出来时当 1
int nextChannelSeq({
  required String? currentDisplayVersion,
  required String version,
  required String channel,
}) {
  final current = currentDisplayVersion == null
      ? null
      : parseDisplayVersion(currentDisplayVersion);
  if (current == null) return 1;
  if (current.version != version || current.channel != channel) return 1;
  return (current.seq ?? 0) + 1;
}
