import 'package:copper_launcher/ui/util/widget/feature_button.dart';
import 'package:flutter/material.dart';

class NavigationCollapseButton extends StatelessWidget {
  final bool collapse;
  final VoidCallback onTap;

  const NavigationCollapseButton({
    super.key,
    required this.collapse,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ReboundButton(
      padding: EdgeInsets.all(4),
      margin: EdgeInsets.symmetric(horizontal: 4),
      backgroundColor: Colors.transparent,
      hoverElevation: 0,
      onTap: onTap,
      child: AnimatedRotation(
        turns: collapse ? 0.5 : 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
        child: Icon(Icons.keyboard_arrow_left_rounded),
      ),
    );
  }
}
