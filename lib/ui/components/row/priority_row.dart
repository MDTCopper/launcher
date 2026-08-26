import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 信息行的一条：任意 [child] + 丢弃优先级 [priority]。
///
/// 宽度取法：
/// - [text]/[icon]：文本便捷构造，宽度由 [PriorityRow] 内部用 [TextPainter]
///   实测(与渲染同一排版器，无预估误差)
/// - 任意自定义 [child]：传固定 [width]
class PriorityRowItem {
  final String? text;
  final IconData? icon;
  final TextStyle? textStyle;
  final Widget? child;
  final double? width;

  final double? minWidth;

  /// 空间不足时的丢弃顺序，数值越小越先被舍弃
  final int priority;

  const PriorityRowItem({
    this.text,
    this.icon,
    this.textStyle,
    this.child,
    this.width,
    this.minWidth,
    this.priority = 0,
  }) : assert(text != null || child != null, 'text 与 child 至少其一');

  /// 文本便捷构造：图标 + 文本
  factory PriorityRowItem.text({
    required String text,
    IconData? icon,
    TextStyle? textStyle,
    int priority = 0,
    double iconSize = 18,
    double textIconGap = 4,
    double? width,
    double? minWidth,
  }) {
    return PriorityRowItem(
      text: text,
      icon: icon,
      textStyle: textStyle,
      priority: priority,
      width: width,
      minWidth: minWidth,
    );
  }
}

class PriorityRow extends StatelessWidget {
  final List<PriorityRowItem> items;

  // ── 透传 Row 参数 ──

  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final TextDirection? textDirection;
  final MainAxisSize mainAxisSize;

  bool get _usesManualSpacing =>
      mainAxisAlignment == MainAxisAlignment.start ||
      mainAxisAlignment == MainAxisAlignment.end ||
      mainAxisAlignment == MainAxisAlignment.center;

  final double itemSpacing;

  final double iconSize;
  final double textIconGap;

  const PriorityRow({
    super.key,
    required this.items,
    this.mainAxisAlignment = MainAxisAlignment.spaceAround,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.textDirection,
    this.mainAxisSize = MainAxisSize.max,
    this.itemSpacing = 12,
    this.iconSize = 18,
    this.textIconGap = 4,
  });

  /// 一条的固有宽：固定 [width] 优先；否则文本 TextPainter 实测 + 图标宽；
  /// 再与 [minWidth] 取大(跨行占位)。
  double _measure(BuildContext context, PriorityRowItem item) {
    if (item.width != null) return item.width!;
    assert(item.text != null, '自定义 child 必须传 width');
    final style = item.textStyle ?? const TextStyle();
    final painter = TextPainter(
      text: TextSpan(text: item.text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final iconWidth = item.icon == null ? 0.0 : iconSize + textIconGap;
    final measured = painter.width + iconWidth;
    final minWidth = item.minWidth;
    return minWidth == null ? measured : math.max(measured, minWidth);
  }

  Widget _buildItem(BuildContext context, PriorityRowItem item) {
    Widget child;
    if (item.child != null) {
      child = item.child!;
    } else {
      child = Row(
        mainAxisSize: MainAxisSize.min,

        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (item.icon != null) Icon(item.icon, size: iconSize),
          if (item.icon != null) SizedBox(width: textIconGap),
          Flexible(
            child: Text(
              item.text!,
              style: item.textStyle ?? const TextStyle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    final fixedWidth = item.width;
    if (fixedWidth != null) {
      child = SizedBox(width: fixedWidth, child: child);
    } else {
      final minWidth = item.minWidth;
      if (minWidth != null) {
        child = ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: child,
        );
      }
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;

        final measured = [for (final item in items) _measure(context, item)];
        final total =
            measured.fold<double>(0, (sum, w) => sum + w) +
            itemSpacing * (items.length - 1);

        final kept = <int>[];
        if (total <= available + 0.01) {
          kept.addAll(List.generate(items.length, (i) => i));
        } else {
          final byPriority = List.generate(items.length, (i) => i)
            ..sort((a, b) => items[b].priority.compareTo(items[a].priority));
          var used = 0.0;
          for (final i in byPriority) {
            if (used + measured[i] <= available) {
              kept.add(i);
              used += measured[i] + itemSpacing;
            }
          }

          if (kept.isEmpty && items.isNotEmpty) {
            kept.add(byPriority.last);
          }
        }

        kept.sort();

        return Row(
          mainAxisAlignment: mainAxisAlignment,
          mainAxisSize: mainAxisSize,
          crossAxisAlignment: crossAxisAlignment,
          textDirection: textDirection,
          children: [
            for (int k = 0; k < kept.length; k++) ...[
              if (k > 0 && _usesManualSpacing) SizedBox(width: itemSpacing),
              _buildItem(context, items[kept[k]]),
            ],
          ],
        );
      },
    );
  }
}
