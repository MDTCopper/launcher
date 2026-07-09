import 'package:copperlauncher_main/ui/shell/navigation_rail.dart';
import 'package:copperlauncher_main/ui/util/route/page_key_provider.dart';
import 'package:flutter/cupertino.dart';

mixin SubRoute {
  void register(String key, List<SubRailSection> sections) {
    final state = PageKeyProvider.shellKey.currentState;
    if (state == null) throw Exception('未找到shell');
    state.registerSubRoute(key, sections);
  }

  void registerKey(String key) {
    final state = PageKeyProvider.shellKey.currentState;
    if (state == null) throw Exception('未找到shell');
    state.registerSubRouteKey(key);
  }
}

///子路由混合，用于在主导航器上注册新路由页面的导航器
///
/// 多个同等级路由下的页面需要混合同一个mixin，以实现多页联动
///
/// 使用时，必须创建一个新的mixin实现SubRouteMixin并重写方法
///
/// **更多情况只用于页面内分项导航，可以通过这个进行注册页面导航器**
///
mixin SubRouteMixin<T extends StatefulWidget> on State<T> implements SubRoute {
  late final List<SubRailSection> sections = [];

  //todo init注册导航器，dispose注销
  // 同等级路由进行切换时新页面优先init然后dispose
  // 这里使用key来进行出栈入栈，这样不会导致莫名的状态切换
  // 不过可以尝试直接用导航器列表来入栈出栈

  @override
  void initState() {
    super.initState();
    final key = PageKeyProvider.shellKey;
  }

  @override
  void dispose() {
    super.dispose();
  }
}

///
mixin GameSettingPageRouteMixin implements SubRouteMixin {}

/// 主导航栏的导航器注册器组件，导航栏注册导航器的组件持有
///
/// **该组件与`AppShell`深度绑定，必须在环境中存在**
///
/// 提供了一套标准的导航器容器，容器可以进行一定的自定义，但也可以直接定义一个新的组件
///
/// 在init中在导航栏注册自己的导航器，需要在dispose注销，否则导航器会混乱
///
/// 有3种可用的导航器注册：
/// - 仅进行页面内的内容切换
/// - 进行进一步的push
/// - 同等级路由的replace
class NavigatorRegister {
  NavigatorRegister({required this.key, required this.navigator});

  String key;

  NavigatorContainer navigator;

  void register() {
    final state = PageKeyProvider.shellKey.currentState;
    if (state == null) throw Exception('未找到shell');
  }

  void unregister() {
    final state = PageKeyProvider.shellKey.currentState;
    if (state == null) throw Exception('未找到shell');
  }
}

///导航器容器
class NavigatorContainer {}
