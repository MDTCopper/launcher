import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
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

    final goHomeButton = index > 2 && goHome != null
        ? ReboundButton(onTap: goHome, child: Icon(Icons.keyboard_double_arrow_left),)
        : null;
    final onDownButton = index != 1
        ? ReboundButton(onTap: onDown, child: Icon(Icons.keyboard_arrow_left),)
        : null;
    final onUpButton = !(endPage ?? false)
        ? ReboundButton(onTap: onUp, child: Icon(Icons.keyboard_arrow_right),)
        : null;
    final goEndButton = endIndex != null && index != endIndex
        ? ReboundButton(onTap: goEnd, child: Icon(Icons.keyboard_double_arrow_right),)
        : null;

    SizedBox occupyBox(Widget? child)=> SizedBox(width: 32,child: child);

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
