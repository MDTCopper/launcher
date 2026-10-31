import 'launch_request.dart';

/// 生成启动脚本：脚本只负责把「启动这个版本」投递给启动器，不再自己拼 java 参数
///
/// 这样脚本、桌面快捷方式、以后的其它入口都走同一个 `--launch-version` 入口，
/// 启动参数 / Java / 加载器 / 云存档全部由启动器现有启动链决定
class LaunchScript {
  LaunchScript._();

  /// 脚本文件名
  static String fileName({required bool windows}) =>
      windows ? '启动游戏.bat' : '启动游戏.sh';

  /// 生成脚本内容；[launcherPath] 取生成时启动器 exe 的绝对路径
  static String build({
    required bool windows,
    required String launcherPath,
    required String versionId,
  }) {
    final arguments = '${LaunchRequest.argument} $versionId';
    return windows
        ? _windows(launcherPath: launcherPath, arguments: arguments)
        : _posix(launcherPath: launcherPath, arguments: arguments);
  }

  static String _windows({
    required String launcherPath,
    required String arguments,
  }) {
    return '''
@echo off
chcp 65001 >nul
set "LAUNCHER=$launcherPath"
if not exist "%LAUNCHER%" (
  echo 找不到启动器：%LAUNCHER%
  pause
  exit /b 1
)
start "" "%LAUNCHER%" $arguments
''';
  }

  static String _posix({
    required String launcherPath,
    required String arguments,
  }) {
    final quoted = "'${launcherPath.replaceAll("'", "'\\''")}'";
    return '''
#!/bin/sh
LAUNCHER=$quoted
if [ ! -x "\$LAUNCHER" ]; then
  echo "找不到启动器：\$LAUNCHER" >&2
  exit 1
fi
"\$LAUNCHER" $arguments &
''';
  }
}
