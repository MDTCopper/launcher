import 'package:copper_launcher/ui/components/scroll/scroll_fade_mask.dart';
import 'package:copper_launcher/ui/util/widget/desktop_scroll_view.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Copper 网格视图：桌面端套 [DesktopScrollViewContainer]（自研滚动条 +
/// 滚轮/触控板处理），非桌面端用官方 [GridView]（原生物理），
/// 可选顶部底部渐变遮罩（[ScrollFadeMask]）。
///
/// [physics] 仅在非桌面端生效（桌面端由 DesktopScrollViewContainer 接管滚动）。
class CopperGridView extends StatefulWidget {
  // ── 滚动配置（透传 GridView）──
  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final SliverGridDelegate gridDelegate;
  final double? cacheExtent;
  final DragStartBehavior dragStartBehavior;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final String? restorationId;
  final Clip clipBehavior;
  final HitTestBehavior hitTestBehavior;

  // ── 内容（默认构造用 children，builder 构造用 itemBuilder/itemCount）──
  final List<Widget> children;
  final NullableIndexedWidgetBuilder? itemBuilder;
  final int? itemCount;

  // ── 桌面端滚动容器配置 ──
  final double sensitivity;
  final double trackpadSensitivity;
  final double maxVelocity;
  final AlignmentGeometry? scrollbarAlignment;

  // ── 渐变遮罩 ──
  final bool fadeMask;

  /// 默认构造：gridDelegate + children。
  const CopperGridView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    required this.gridDelegate,
    this.cacheExtent,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.children = const [],
    this.sensitivity = 1.5,
    this.trackpadSensitivity = 1.0,
    this.maxVelocity = 3000,
    this.scrollbarAlignment,
    this.fadeMask = true,
  }) : itemBuilder = null,
       itemCount = null;

  /// builder 构造：gridDelegate + itemBuilder + itemCount 惰性构建。
  const CopperGridView.builder({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    required this.gridDelegate,
    required this.itemBuilder,
    this.itemCount,
    this.cacheExtent,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.sensitivity = 1.5,
    this.trackpadSensitivity = 1.0,
    this.maxVelocity = 3000,
    this.scrollbarAlignment,
    this.fadeMask = true,
  }) : children = const [];

  @override
  State<StatefulWidget> createState() => _CopperGridViewState();
}

class _CopperGridViewState extends State<CopperGridView> {
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
    final GridView gridView;
    if (widget.itemBuilder != null) {
      gridView = GridView.builder(
        controller: _scrollController,
        scrollDirection: widget.scrollDirection,
        reverse: widget.reverse,
        primary: widget.primary,
        physics: widget.physics,
        shrinkWrap: widget.shrinkWrap,
        padding: widget.padding,
        gridDelegate: widget.gridDelegate,
        itemBuilder: widget.itemBuilder!,
        itemCount: widget.itemCount,
        cacheExtent: widget.cacheExtent,
        dragStartBehavior: widget.dragStartBehavior,
        keyboardDismissBehavior: widget.keyboardDismissBehavior,
        restorationId: widget.restorationId,
        clipBehavior: widget.clipBehavior,
        hitTestBehavior: widget.hitTestBehavior,
      );
    } else {
      gridView = GridView(
        controller: _scrollController,
        scrollDirection: widget.scrollDirection,
        reverse: widget.reverse,
        primary: widget.primary,
        physics: widget.physics,
        shrinkWrap: widget.shrinkWrap,
        padding: widget.padding,
        gridDelegate: widget.gridDelegate,
        cacheExtent: widget.cacheExtent,
        dragStartBehavior: widget.dragStartBehavior,
        keyboardDismissBehavior: widget.keyboardDismissBehavior,
        restorationId: widget.restorationId,
        clipBehavior: widget.clipBehavior,
        hitTestBehavior: widget.hitTestBehavior,
        children: widget.children,
      );
    }

    Widget child = gridView;
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
