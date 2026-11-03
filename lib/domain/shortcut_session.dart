/// 本次游戏是不是「从桌面快捷方式进来的」——退出后行为按这个区分
///
/// 快捷方式拉起游戏时打个标记，[LaunchMindustryTask] 收尾时取走：
/// 只有快捷方式启动的局才按设置决定回桌面还是回启动器，普通启动不受影响
class ShortcutSession {
  ShortcutSession._();

  static bool _launchedFromShortcut = false;

  /// 快捷方式拉起游戏时调用
  static void markLaunchedFromShortcut() => _launchedFromShortcut = true;

  /// 只读查询，不清空标记
  static bool get isLaunchedFromShortcut => _launchedFromShortcut;

  /// 取走标记（取完清空）：true 表示这一局是快捷方式启动的
  static bool takeLaunchedFromShortcut() {
    final value = _launchedFromShortcut;
    _launchedFromShortcut = false;
    return value;
  }
}
