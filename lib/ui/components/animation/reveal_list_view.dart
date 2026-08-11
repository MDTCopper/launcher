import 'dart:async';

import 'package:copper_launcher/ui/components/scroll/list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'appear_item.dart';

/// 入场/浮现列表（AppearListView 重构版）。
///
/// 两种构造：
/// - 默认构造：全量 [items]，**错位入场**（无浮现，适合模块少、无性能压力的列表）
/// - [RevealListView.builder]：惰性构建（滚动到才构建），**错位入场 + 滚动浮现**；
///   配合高度预期（[itemExtent] / [prototypeItem] / [itemExtentBuilder] 三选一）
///   让总长精确可预测，滚动条不乱跳。
///
/// 浮现机制：条目首次构建时播放入场动画——进入页面按 index 错位（延迟递增），
/// 滚动后构建的条目立即浮现；已出现的条目滚动回来不重复动画。
///
/// 内部滚动容器复用 [CopperListView]（桌面滚动条/触控板/渐变遮罩）。
/// 需要回顶按钮时自行套 `BackToTopLayer`（传入同一个 [scrollController]）。
class RevealListView extends StatefulWidget {
  // ── 内容 ──
  final List<Widget?> items;
  final int? itemCount;
  final NullableIndexedWidgetBuilder? itemBuilder;

  // ── 高度预期（builder 惰性时三选一，精确总长）──
  final double? itemExtent;
  final Widget? prototypeItem;
  final ItemExtentBuilder? itemExtentBuilder;

  // ── 错位动画 ──
  final double interval; // item 出现间隔系数（相对 appearDuration）
  final int delay; // 首个 item 延迟 ms
  final Duration appearDuration;
  final Offset offset; // 起始位移

  // ── 滚动容器（透传 CopperListView）──
  final ScrollController? scrollController;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final double itemSpacing;
  final bool shrinkWrap;
  final bool fadeMask;

  const RevealListView({
    super.key,
    this.items = const [],
    this.interval = 0.3,
    this.delay = 0,
    this.appearDuration = const Duration(milliseconds: 200),
    this.offset = Offset.zero,
    this.scrollController,
    this.physics,
    this.padding,
    this.itemSpacing = 4.0,
    this.shrinkWrap = false,
    this.fadeMask = false,
  }) : itemCount = null,
       itemBuilder = null,
       itemExtent = null,
       prototypeItem = null,
       itemExtentBuilder = null;

  const RevealListView.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.itemExtent,
    this.prototypeItem,
    this.itemExtentBuilder,
    this.interval = 0.3,
    this.delay = 0,
    this.appearDuration = const Duration(milliseconds: 200),
    this.offset = Offset.zero,
    this.scrollController,
    this.physics,
    this.padding,
    this.itemSpacing = 4.0,
    this.shrinkWrap = false,
    this.fadeMask = false,
  }) : items = const [];

  @override
  State<StatefulWidget> createState() => _RevealListViewState();
}

class _RevealListViewState extends State<RevealListView> {
  late final ScrollController _scrollController;

  /// 错位入场窗口是否结束（结束后滚动构建的条目立即浮现）
  bool _entryDone = false;
  Timer? _entryTimer;

  /// 已播放过动画的条目 index（滚动回来不重复浮现）
  final Set<int> _animated = {};

  int get _count => widget.itemCount ?? widget.items.length;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();

    // 错位入场总时长 = 首延迟 + (n-1) 个间隔 + 最后 item 动画时长
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

  /// 条目错位延迟：delay + index 递增间隔
  int _delayFor(int index) =>
      widget.delay +
      (index * (widget.interval * widget.appearDuration.inMilliseconds)).round();

  Widget _wrapItem(int index, Widget item, {required bool animate}) {
    return Padding(
      padding: EdgeInsets.only(bottom: widget.itemSpacing),
      child: AppearItem(
        delayMs: animate ? (_entryDone ? 0 : _delayFor(index)) : 0,
        animate: animate,
        offset: widget.offset,
        duration: widget.appearDuration,
        child: item,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();

    if (widget.itemBuilder != null) {
      // 惰性：滚动到才构建，配合高度预期精确总长
      return CopperListView.builder(
        controller: _scrollController,
        physics: widget.physics,
        padding: widget.padding,
        shrinkWrap: widget.shrinkWrap,
        itemCount: widget.itemCount,
        itemExtent: widget.itemExtent,
        prototypeItem: widget.prototypeItem,
        itemExtentBuilder: widget.itemExtentBuilder,
        fadeMask: widget.fadeMask,
        itemBuilder: (context, index) {
          final item = widget.itemBuilder!(context, index);
          if (item == null) return const SizedBox.shrink();
          // 首次构建才播动画（滚动回来复用不重复浮现）
          final isFirstBuild = _animated.add(index);
          return _wrapItem(index, item, animate: isFirstBuild);
        },
      );
    }

    // 全量：错位入场（无浮现）
    return CopperListView(
      controller: _scrollController,
      physics: widget.physics,
      padding: widget.padding,
      shrinkWrap: widget.shrinkWrap,
      fadeMask: widget.fadeMask,
      children: [
        for (int i = 0; i < widget.items.length; i++)
          if (widget.items[i] != null)
            _wrapItem(i, widget.items[i]!, animate: true),
      ],
    );
  }
}
