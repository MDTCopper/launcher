import 'package:flutter/material.dart';

/// 宿主环境给菜单的限制与出口
///
/// 菜单组件不认识应用里的具体东西（比如安卓那条辅助输入条），
/// 需要避让或换层时由宿主往这里登记
abstract final class ContextMenuHost {
  /// 屏幕底部被别的东西占住的高度；默认 0
  ///
  /// 菜单会把自己压在它上面，免得弹出来就被盖住 ——
  /// 安卓辅助输入条占的那条带子就是靠这条登记的
  static final ValueNotifier<double> bottomObstruction = ValueNotifier(0);

  /// 菜单插进哪个 Overlay；默认从 context 往上找根 Overlay
  ///
  /// 宿主可以把菜单提到更高的层：辅助输入条自带一个浮在应用内容之上的 Overlay，
  /// 不换层的话菜单会被它盖住
  static OverlayState? Function(BuildContext context)? overlayResolver;

  /// 同级菜单再次出现时，是否让同一个面板移动过去换内容；默认开
  ///
  /// 由宿主接到自己的设置项上，调用方没点名时按这条走；
  /// 用回调而不是固定值，设置改了立刻生效，不用在改动处再通知一遍
  static bool Function() relocateOnReopenOf = () => true;
}
