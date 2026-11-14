import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 进度条：搬运设计层 [TemplateProgressBar]
/// （细轨 + 实心填充，默认高 12；支持不确定态与双段「已分配 / 已用」）
class CuProgress extends StatelessWidget {
  const CuProgress({
    super.key,
    required this.value,
    this.label,
    this.height = 12,
    this.enabled = true,
    this.indeterminate = false,
    this.secondary,
  });

  /// 0~1
  final double value;

  /// 右侧文字（如「42%」），为 null 时不显示
  final String? label;

  final double height;
  final bool enabled;
  final bool indeterminate;
  final double? secondary;

  @override
  Widget build(BuildContext context) {
    final skin = cuSkinOf(context);
    final bar = TemplateProgressBar(
      skin: skin,
      value: value,
      height: height,
      enabled: enabled,
      indeterminate: indeterminate,
      secondary: secondary,
    );

    if (label == null) return bar;
    return Row(
      spacing: TemplateSpace.sm,
      children: [
        Expanded(child: bar),
        Text(
          label!,
          style: TemplateType.caption.copyWith(color: skin.textSecondary),
        ),
      ],
    );
  }
}
