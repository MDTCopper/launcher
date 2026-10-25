/// 抽屉 / 弹层里的内容想「跳到某个页面」时的统一出口
///
/// 这些内容不在页面导航栈里（抽屉是 Scaffold 的，弹层是 root overlay），
/// 直接 `Navigator.pushNamed` 会压在整个壳外面；由 [AppShell] 注册处理函数，
/// 负责**先收起抽屉**再切页面。
class AppNavigation {
  AppNavigation._();

  /// 由壳在初始化时注册
  static void Function(String route)? handler;

  /// 跳到一个根页面（会顺手把抽屉收起来）
  static void goTo(String route) => handler?.call(route);
}
