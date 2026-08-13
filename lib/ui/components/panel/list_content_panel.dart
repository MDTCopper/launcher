import 'package:copper_launcher/ui/components/animation/reveal_list_view.dart';
import 'package:copper_launcher/ui/components/overlay_layer/back_to_top_layer.dart';
import 'package:flutter/material.dart';

/// 页面最基础骨架：负责滚动模块列表，带模块级错位入场动画。
///
/// 两种模式：
/// - 不传 [estimatedMaxScrollExtent]：全量模块（模块少时用），错位入场
/// - 传 [estimatedMaxScrollExtent]：**惰性模块**（模块多 / 大时用），
///   页面滚动只构建可见模块（模块自适应高度）；预测总长给滚动条
///   （thumb / 点击 / 拖动稳定，不乱跳）
///
/// 默认内置 [BackToTopLayer]（滚超阈值浮现回顶按钮），可用 [showBackToTop] 关闭。
class ListContentPanel extends StatefulWidget {
  final List<Widget?> items;
  final int delay;
  final double interval;
  final double itemSpacing;
  final EdgeInsetsGeometry? padding;
  final Offset offset;
  final ScrollController? controller;

  /// 预测总偏移（惰性模块时必传）：滚动条用此值计算（稳定）。
  /// 通常 = Σ 模块高度；不变列表静态维护，可变列表用函数计算。
  final double? estimatedMaxScrollExtent;

  /// 是否内置回顶按钮浮层（默认开启）。
  final bool showBackToTop;

  const ListContentPanel({
    super.key,
    required this.items,
    this.delay = 200,
    this.interval = 0.3,
    this.itemSpacing = 12.0,
    this.padding = const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
    this.offset = const Offset(-0.05, 0.0),
    this.controller,
    this.estimatedMaxScrollExtent,
    this.showBackToTop = true,
  });

  @override
  State<StatefulWidget> createState() => _ListContentPanelState();
}

class _ListContentPanelState extends State<ListContentPanel> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ScrollController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    // 惰性模块：只构建可见模块，滚动条用预测
    if (widget.estimatedMaxScrollExtent != null) {
      child = RevealListView.builder(
        itemCount: widget.items.length,
        itemBuilder: (context, i) =>
            widget.items[i] ?? const SizedBox.shrink(),
        estimatedMaxScrollExtent: widget.estimatedMaxScrollExtent,
        delay: widget.delay,
        interval: widget.interval,
        itemSpacing: widget.itemSpacing,
        padding: widget.padding,
        offset: widget.offset,
        scrollController: _controller,
        appearDuration: const Duration(milliseconds: 300),
      );
    } else {
      // 全量模块（模块少时用）
      child = RevealListView(
        items: widget.items,
        delay: widget.delay,
        interval: widget.interval,
        itemSpacing: widget.itemSpacing,
        padding: widget.padding,
        offset: widget.offset,
        scrollController: _controller,
        appearDuration: const Duration(milliseconds: 300),
      );
    }

    if (widget.showBackToTop) {
      child = BackToTopLayer(controller: _controller, child: child);
    }
    return child;
  }
}
