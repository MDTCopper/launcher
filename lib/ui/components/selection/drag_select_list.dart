import 'package:flutter/material.dart';

/// 支持拖拽连续选择的列表。
///
/// 行为：
/// - 点击某项：由 [itemBuilder] 构造的条目自身处理（如 tile 自带 onTap 切换选中）
/// - 按住拖动跨过多项：连续选中（拖动经过的每一项都切换为目标状态）
/// - 拖动目标状态由起点决定：起点已选中 → 拖过清除；起点未选中 → 拖过选中
///
/// 实现：外层 GestureDetector 的 onPanStart/Update/End（拖动竞技场——按下移动
/// 超过 slop 才判定拖动，点击不触发 pan，与条目自身的 onTap 互不干扰）。
/// 拖动路径命中用逐项几何计算。
class DragSelectList extends StatefulWidget {
  /// 条目构建器，[index] 为条目下标，[selected] 为当前选中态。
  /// 条目的点击（选中切换）由调用方在 [onToggle] 处理，条目需自带交互层
  /// （如 ReboundListTile 的 onTap），组件不会额外包裹点击层。
  final Widget Function(BuildContext context, int index, bool selected)
  itemBuilder;

  final int itemCount;

  /// 是否允许拖动连续选择（多选模式）
  final bool dragSelect;

  /// 当前选中集合（外部持有，需在 onToggle 后同步）
  final Set<int> selected;

  /// 某项选中态切换回调（点击或拖动命中）
  final void Function(int index, bool selected) onToggle;

  /// 拖动结束回调
  final VoidCallback? onDragEnd;

  /// 条目之间垂直间隔
  final double itemSpacing;

  final EdgeInsetsGeometry? padding;

  const DragSelectList({
    super.key,
    required this.itemBuilder,
    required this.itemCount,
    required this.selected,
    required this.onToggle,
    this.dragSelect = true,
    this.onDragEnd,
    this.itemSpacing = 8,
    this.padding,
  });

  @override
  State<DragSelectList> createState() => _DragSelectListState();
}

class _DragSelectListState extends State<DragSelectList> {
  /// 拖动中最后命中的 index；避免同一项重复切换
  int _lastHitIndex = -1;

  /// 拖动起点状态：起点已选中 → 整段拖过为“清除”；否则为“选中”
  bool _dragTarget = false;

  /// 是否处于拖动手势（按住移动超过拖拽阈值后置 true）
  bool _dragging = false;

  final List<GlobalKey> _itemKeys = [];

  @override
  Widget build(BuildContext context) {
    if (_itemKeys.length != widget.itemCount) {
      _itemKeys
        ..clear()
        ..addAll(List.generate(widget.itemCount, (_) => GlobalKey()));
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) {
        if (!widget.dragSelect) return;
        _dragging = true;
        _lastHitIndex = -1;
        // 起点状态决定整段目标
        final index = _itemIndexAtGlobal(details.globalPosition);
        if (index >= 0) {
          _dragTarget = !widget.selected.contains(index);
        }
      },
      onPanUpdate: (details) {
        if (!widget.dragSelect || !_dragging) return;
        final index = _itemIndexAtGlobal(details.globalPosition);
        if (index >= 0 && index != _lastHitIndex) {
          _lastHitIndex = index;
          widget.onToggle(index, _dragTarget);
        }
      },
      onPanEnd: (_) => _endDrag(),
      onPanCancel: _endDrag,
      child: SingleChildScrollView(
        padding: widget.padding,
        child: Column(
          spacing: widget.itemSpacing,
          children: [
            for (var i = 0; i < widget.itemCount; i++)
              SizedBox(
                key: _itemKeys[i],
                child: widget.itemBuilder(context, i, widget.selected.contains(i)),
              ),
          ],
        ),
      ),
    );
  }

  void _endDrag() {
    if (!_dragging) return;
    _dragging = false;
    _lastHitIndex = -1;
    widget.onDragEnd?.call();
  }

  /// 全局坐标 → 条目下标（逐项几何命中）
  int _itemIndexAtGlobal(Offset global) {
    for (var i = 0; i < _itemKeys.length; i++) {
      final box = _itemKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(global)) return i;
    }
    return -1;
  }
}