import 'package:copper_launcher/ui/components/scroll/scroll_fade_mask.dart';
import 'package:copper_launcher/ui/util/widget/desktop_scroll_view.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Copper 列表视图：桌面端套 [DesktopScrollViewContainer]（自研滚动条 +
/// 滚轮/触控板处理），非桌面端用官方 [ListView]（原生物理），
/// 可选顶部底部渐变遮罩（[ScrollFadeMask]）。
///
/// [physics] 仅在非桌面端生效（桌面端由 DesktopScrollViewContainer 接管滚动）。
class CopperListView extends StatefulWidget {
  // ── 滚动配置（透传 ListView）──
  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final double? itemExtent;
  final Widget? prototypeItem;
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

  /// 预测最大偏移（惰性列表提供）：滚动条用预测计算，避免惰性估算跳变。
  final double? estimatedMaxScrollExtent;

  /// 默认构造：直接传 children。
  const CopperListView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.itemExtent,
    this.prototypeItem,
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
    this.estimatedMaxScrollExtent,
  }) : itemBuilder = null,
       itemCount = null;

  /// builder 构造：itemBuilder + itemCount 惰性构建。
  const CopperListView.builder({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.itemExtent,
    this.prototypeItem,
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
    this.estimatedMaxScrollExtent,
  }) : children = const [];

  @override
  State<StatefulWidget> createState() => _CopperListViewState();
}

class _CopperListViewState extends State<CopperListView> {
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
    final ListView listView;
    if (widget.itemBuilder != null) {
      listView = ListView.builder(
        controller: _scrollController,
        scrollDirection: widget.scrollDirection,
        reverse: widget.reverse,
        primary: widget.primary,
        physics: widget.physics,
        shrinkWrap: widget.shrinkWrap,
        padding: widget.padding,
        itemExtent: widget.itemExtent,
        prototypeItem: widget.prototypeItem,
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
      listView = ListView(
        controller: _scrollController,
        scrollDirection: widget.scrollDirection,
        reverse: widget.reverse,
        primary: widget.primary,
        physics: widget.physics,
        shrinkWrap: widget.shrinkWrap,
        padding: widget.padding,
        itemExtent: widget.itemExtent,
        prototypeItem: widget.prototypeItem,
        cacheExtent: widget.cacheExtent,
        dragStartBehavior: widget.dragStartBehavior,
        keyboardDismissBehavior: widget.keyboardDismissBehavior,
        restorationId: widget.restorationId,
        clipBehavior: widget.clipBehavior,
        hitTestBehavior: widget.hitTestBehavior,
        children: widget.children,
      );
    }

    Widget child = listView;
    // shrinkWrap（嵌入父滚动容器、无界约束）时不需要桌面滚动容器 / 渐变遮罩：
    // - 桌面容器内部 Stack/Align 依赖有界约束，无界下会崩溃
    // - shrinkWrap 不独立滚动，父级滚动容器已处理滚动
    if (isDesktop && !widget.shrinkWrap) {
      child = DesktopScrollViewContainer(
        controller: _scrollController,
        scrollDirection: widget.scrollDirection,
        sensitivity: widget.sensitivity,
        trackpadSensitivity: widget.trackpadSensitivity,
        maxVelocity: widget.maxVelocity,
        scrollbarAlignment: widget.scrollbarAlignment,
        estimatedMaxScrollExtent: widget.estimatedMaxScrollExtent,
        child: child,
      );
    }
    if (widget.fadeMask && !widget.shrinkWrap) {
      child = ScrollFadeMask(
          controller: _scrollController,
          scrollDirection: widget.scrollDirection,
          child: child,
        );
    }

    return child;
  }
}
