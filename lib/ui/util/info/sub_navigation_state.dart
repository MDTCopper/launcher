import 'package:copper_launcher/core/app_config.dart';
import 'package:flutter/foundation.dart';

/// 二级导航（子页面右侧边栏）的收起状态：顶栏与各容器页共享。
///
/// 用 [ValueNotifier] 保证任一侧改动都能触发另一侧重建——config 本身不是
/// Listenable，直接写 config 不会让页面刷新（之前"点顶栏按钮没效果"的根因）。
final ValueNotifier<bool> subNavCollapseNotifier = ValueNotifier<bool>(
  config.setting.personalizationOptions.subNavigationCollapse,
);

/// 更新收起状态并写回 config（持久化），同时通知监听者重建。
void setSubNavCollapse(bool value) {
  subNavCollapseNotifier.value = value;
  config.setting.personalizationOptions.subNavigationCollapse = value;
  config.save();
}
