import 'package:flutter/material.dart';

/// 设置条行：标题(可完全挤压) + 控件(优先保 [controlMinWidth])。
///
/// 行为语义：
/// 1. 可用宽度足够(可满足 标题固有宽 + 控件最小宽)：标题取固有 [titleWide]，
///    控件扩展占满剩余空间
/// 2. 可用宽度不足：控件保持 [controlMinWidth]，标题从固有宽开始被挤压
///    (ellipsis)，可一路压到 0——描述是最晚让位的一方
class SettingBarRow extends StatelessWidget {
  final String title;
  final Widget control;
  final double titleWide;
  final double controlMinWidth;
  final double gap;
  final TextStyle? titleStyle;

  const SettingBarRow({
    super.key,
    required this.title,
    required this.control,
    this.titleWide = 150,
    this.controlMinWidth = 100,
    this.gap = 8,
    this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        // 扣掉控件最小宽和间隙后，能留给标题的宽度(下限 0，可完全压没)
        final titleBudget = available - controlMinWidth - gap;
        final titleWidth = titleBudget >= titleWide
            ? titleWide
            : titleBudget.clamp(0.0, titleWide);

        return Row(
          children: [
            SizedBox(
              width: titleWidth,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            SizedBox(width: gap),
            // 控件区：占剩余空间，但不少于 controlMinWidth
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: controlMinWidth),
                child: control,
              ),
            ),
          ],
        );
      },
    );
  }
}