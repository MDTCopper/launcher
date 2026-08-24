import 'package:copper_launcher/core/app_config.dart';
import 'package:flutter/widgets.dart';

/// 二级导航（容器页右侧边栏）的收起状态，顶栏与各容器页共享；
/// config 不是 Listenable，直接写它不会重建页面，这里用 [ValueNotifier]
/// 作为可通知的共享源，任一侧改动都会触发另一侧重建
final ValueNotifier<bool> subNavigationCollapseNotifier = ValueNotifier<bool>(
  config.setting.personalizationOptions.subNavigationCollapse,
);

/// 更新收起状态，写回 config 持久化，并通知监听者重建
void setSubNavigationCollapse(bool value) {
  subNavigationCollapseNotifier.value = value;
  config.setting.personalizationOptions.subNavigationCollapse = value;
  config.save();
}

/// 混入容器页 [State]，自动监听 [subNavigationCollapseNotifier]；
/// 顶栏切换右侧边栏收起态时，容器页在 Navigator 里不会自动重建，
/// 混入后 initState 注册监听、dispose 移除、变化时 setState，让本页二级导航同步；
/// 同时提供 [collapse] 读写，免去每页重复写 getter/setter
mixin SubNavigationCollapseListener<T extends StatefulWidget> on State<T> {
  bool get collapse => subNavigationCollapseNotifier.value;
  set collapse(bool value) => setSubNavigationCollapse(value);

  @override
  void initState() {
    super.initState();
    subNavigationCollapseNotifier.addListener(_onSubNavigationCollapseChanged);
  }

  @override
  void dispose() {
    subNavigationCollapseNotifier.removeListener(_onSubNavigationCollapseChanged);
    super.dispose();
  }

  void _onSubNavigationCollapseChanged() {
    if (mounted) setState(() {});
  }
}
