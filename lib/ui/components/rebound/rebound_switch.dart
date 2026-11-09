import 'package:copper_launcher/ui/components/core/copper_switch.dart';
import 'package:flutter/material.dart';

/// copper 风格开关：兼容外壳，内部是 [CopperSwitch]（M3 形制）
///
/// 旧的 48×26 轨道 + 颜色渐变实现已退役；现在只有圆球位移动画，颜色瞬切。
/// [onChanged] 为 null 即禁用态。
class ReboundSwitch extends StatelessWidget {
  const ReboundSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return CopperSwitch(
      value: value,
      onChanged: onChanged,
      enabled: onChanged != null,
    );
  }
}
