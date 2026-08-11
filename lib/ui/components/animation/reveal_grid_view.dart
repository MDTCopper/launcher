import 'dart:async';

import 'package:copper_launcher/ui/components/scroll/grid_view.dart';
import 'package:flutter/material.dart';

import 'appear_item.dart';

/// 入场/浮现网格（AppearGirdView 重构版），动画为**生长式**（scale + fade）。
///
/// 两种构造：
/// - 默认构造：全量 [items]，错位生长入场（无浮现）
/// - [RevealGridView.builder]：惰性构建，错位入场 + 滚动浮现；
///   惰性精确总长依赖 gridDelegate 的 mainAxisExtent（滚动条不乱跳）。
///
/// 内部滚动容器复用 [CopperGridView]（桌面滚动条/触控板/渐变遮罩）。
/// 需要回顶按钮时自行套 `BackToTopLayer`（传入同一个 [scrollController]）。
class RevealGridView extends StatefulWidget {
  // ── 内容 ──
  final List<Widget?> items;
  final int? itemCount;
  final NullableIndexedWidgetBuilder? itemBuilder;

  // ── 网格 ──
  final SliverGridDelegate gridDelegate;

  // ── 错位动画 ──
  final double interval;
  final int delay;
  final Duration appearDuration;
  final double startScale; // 生长起始缩放

  // ── 滚动容器（透传 CopperGridView）──
  final ScrollController? scrollController;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final double itemSpacing;
  final bool shrinkWrap;
  final bool fadeMask;

  const RevealGridView({
    super.key,
    this.items = const [],
    required this.gridDelegate,
    this.interval = 0.2,
    this.delay = 0,
    this.appearDuration = const Duration(milliseconds: 300),
    this.startScale = 0.75,
    this.scrollController,
    this.physics,
    this.padding,
    this.itemSpacing = 8.0,
    this.shrinkWrap = false,
    this.fadeMask = false,
  }) : itemCount = null,
       itemBuilder = null;

  const RevealGridView.builder({
    super.key,
    required this.gridDelegate,
    required this.itemCount,
    required this.itemBuilder,
    this.interval = 0.2,
    this.delay = 0,
    this.appearDuration = const Duration(milliseconds: 300),
    this.startScale = 0.75,
    this.scrollController,
    this.physics,
    this.padding,
    this.itemSpacing = 8.0,
    this.shrinkWrap = false,
    this.fadeMask = false,
  }) : items = const [];

  @override
  State<StatefulWidget> createState() => _RevealGridViewState();
}

class _RevealGridViewState extends State<RevealGridView> {
  late final ScrollController _scrollController;

  bool _entryDone = false;
  Timer? _entryTimer;
  final Set<int> _animated = {};

  int get _count => widget.itemCount ?? widget.items.length;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();

    final totalMs =
        widget.delay +
        ((_count - 1) *
                (widget.interval * widget.appearDuration.inMilliseconds))
            .round() +
        widget.appearDuration.inMilliseconds;
    _entryTimer = Timer(Duration(milliseconds: totalMs), () {
      if (mounted) setState(() => _entryDone = true);
    });
  }

  @override
  void dispose() {
    _entryTimer?.cancel();
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  int _delayFor(int index) =>
      widget.delay +
      (index * (widget.interval * widget.appearDuration.inMilliseconds)).round();

  Widget _wrapItem(int index, Widget item, {required bool animate}) {
    return Padding(
      padding: EdgeInsets.all(widget.itemSpacing / 2),
      child: AppearItem(
        delayMs: animate ? (_entryDone ? 0 : _delayFor(index)) : 0,
        animate: animate,
        scale: widget.startScale, // 生长式
        duration: widget.appearDuration,
        child: item,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();

    if (widget.itemBuilder != null) {
      // 惰性：滚动到才构建，配合 gridDelegate 的 mainAxisExtent 精确总长
      return CopperGridView.builder(
        controller: _scrollController,
        physics: widget.physics,
        padding: widget.padding,
        shrinkWrap: widget.shrinkWrap,
        gridDelegate: widget.gridDelegate,
        itemCount: widget.itemCount,
        fadeMask: widget.fadeMask,
        itemBuilder: (context, index) {
          final item = widget.itemBuilder!(context, index);
          if (item == null) return const SizedBox.shrink();
          final isFirstBuild = _animated.add(index);
          return _wrapItem(index, item, animate: isFirstBuild);
        },
      );
    }

    // 全量：错位生长入场（无浮现）
    return CopperGridView(
      controller: _scrollController,
      physics: widget.physics,
      padding: widget.padding,
      shrinkWrap: widget.shrinkWrap,
      gridDelegate: widget.gridDelegate,
      fadeMask: widget.fadeMask,
      children: [
        for (int i = 0; i < widget.items.length; i++)
          if (widget.items[i] != null)
            _wrapItem(i, widget.items[i]!, animate: true),
      ],
    );
  }
}
