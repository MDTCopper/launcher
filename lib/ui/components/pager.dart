import 'package:copper_launcher/ui/components/core/copper_pressable.dart';
import 'package:flutter/material.dart';

class Pager extends StatelessWidget {
  const Pager(
    this.index, {
    super.key,
    this.endIndex,
    this.endPage,
    this.onDown,
    this.onUp,
    this.goHome,
    this.goEnd,
  }) : assert(
         (endIndex == null && goEnd == null) ||
             (endIndex != null) && (goEnd != null),
         index > 0,
       );
  final int index;
  final int? endIndex;
  final bool? endPage;
  final void Function()? onDown;
  final void Function()? onUp;
  final void Function()? goHome;
  final void Function()? goEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String text;
    if (endIndex != null) {
      text = '第 $index / $endIndex 页';
    } else {
      text = '第 $index 页';
    }

    Widget iconButton(IconData icon, VoidCallback? onTap) => CopperPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 18)),
    );

    final goHomeButton = index > 2 && goHome != null
        ? iconButton(Icons.keyboard_double_arrow_left, goHome)
        : null;
    final onDownButton = index != 1
        ? iconButton(Icons.keyboard_arrow_left, onDown)
        : null;
    final onUpButton = !(endPage ?? false)
        ? iconButton(Icons.keyboard_arrow_right, onUp)
        : null;
    final goEndButton = endIndex != null && index != endIndex
        ? iconButton(Icons.keyboard_double_arrow_right, goEnd)
        : null;

    SizedBox occupyBox(Widget? child) => SizedBox(width: 32, child: child);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          occupyBox(goHomeButton),
          occupyBox(onDownButton),
          Text(text),
          occupyBox(onUpButton),
          occupyBox(goEndButton),
        ],
      ),
    );
  }
}
