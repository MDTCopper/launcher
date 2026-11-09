import 'package:copper_launcher/ui/components/core/cu_switch.dart';
import 'package:flutter/material.dart';

/// copper 风格开关：兼容外壳，内部是 [CuSwitch]（M3 形制）
///
/// 只有圆球位移动画，颜色瞬切
/// [onChanged] 为 null 即禁用态
class ReboundSwitch extends StatelessWidget {
  const ReboundSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return CuSwitch(
      value: value,
      onChanged: onChanged,
      enabled: onChanged != null,
    );
  }
}
