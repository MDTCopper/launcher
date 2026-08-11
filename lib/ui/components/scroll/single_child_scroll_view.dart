import 'package:copper_launcher/ui/components/scroll/scroll_fade_mask.dart';
import 'package:copper_launcher/ui/util/widget/desktop_scroll_view.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Copper 单子滚动视图：桌面端套 [DesktopScrollViewContainer]（自研滚动条 +
/// 滚轮/触控板处理），非桌面端用官方 [SingleChildScrollView]（原生惯性/回弹），
/// 顶部底部可选渐变遮罩（[ScrollFadeMask]）。
///
/// [physics] 仅在非桌面端生效（桌面端由 DesktopScrollViewContainer 接管滚动，
/// 强制 NeverScrollableScrollPhysics）。
class CopperSingleChildScrollView extends StatefulWidget {
  final Widget child;
  final Axis scrollDirection;
  final bool reverse;
  final EdgeInsetsGeometry? padding;
  final bool? primary;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final DragStartBehavior dragStartBehavior;
  final Clip clipBehavior;
  final HitTestBehavior hitTestBehavior;
  final String? restorationId;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  // ── 桌面端滚动容器配置 ──
  final double sensitivity; // 滚轮灵敏度
  final double trackpadSensitivity; // 触控板灵敏度
  final double maxVelocity; // 触控板惯性速度上限
  final AlignmentGeometry? scrollbarAlignment; // 滚动条位置

  // ── 渐变遮罩 ──
  final bool fadeMask;

  const CopperSingleChildScrollView({
    super.key,
    required this.child,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.primary,
    this.physics,
    this.controller,
    this.dragStartBehavior = DragStartBehavior.start,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.restorationId,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.sensitivity = 1.5,
    this.trackpadSensitivity = 1.0,
    this.maxVelocity = 3000,
    this.scrollbarAlignment,
    this.fadeMask = true,
  });

  @override
  State<StatefulWidget> createState() => _CopperSingleChildScrollViewState();
}

class _CopperSingleChildScrollViewState
    extends State<CopperSingleChildScrollView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      padding: widget.padding,
      primary: widget.primary,
      physics: widget.physics,
      dragStartBehavior: widget.dragStartBehavior,
      clipBehavior: widget.clipBehavior,
      hitTestBehavior: widget.hitTestBehavior,
      restorationId: widget.restorationId,
      keyboardDismissBehavior: widget.keyboardDismissBehavior,
      child: widget.child,
    );
    if (isDesktop) {
      child = DesktopScrollViewContainer(
        controller: _scrollController,
        scrollDirection: widget.scrollDirection,
        sensitivity: widget.sensitivity,
        trackpadSensitivity: widget.trackpadSensitivity,
        maxVelocity: widget.maxVelocity,
        scrollbarAlignment: widget.scrollbarAlignment,
        child: child,
      );
    }
    if (widget.fadeMask) {
      child = ScrollFadeMask(
          controller: _scrollController,
          scrollDirection: widget.scrollDirection,
          child: child,
        );
    }

    return child;
  }
}
