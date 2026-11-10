import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 内核分段：**直接复用设计层 [TemplateSegment]**（视觉真源）
///
/// 保留设计里的「小立体」：选中格是上亮下暗的轻渐变，悬停整体挪一档，
/// 按下渐变反向（光的方向变化），未选中格是同色系零透明而不是透明黑。
class CuSegment extends StatelessWidget {
  const CuSegment({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.icons,
    this.enabled = true,
  });

  final List<String> options;
  final int value;
  final ValueChanged<int> onChanged;

  /// 与 [options] 等长的段内图标（可空）
  final List<IconData>? icons;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TemplateSegment(
      skin: cuSkinOf(context),
      options: options,
      value: value,
      onTap: onChanged,
      enabled: enabled,
      icons: icons,
    );
  }
}
