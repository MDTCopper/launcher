import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 内核开关：**直接复用设计层 [TemplateSwitch]**（视觉真源）
///
/// 保留设计里的全部元素：52×32 轨道、2px 描边、球体拉伸、弹簧回弹、
/// 拖动切换、球内 叉→勾 形变、暗色球体掺主题色。
class CuSwitch extends StatelessWidget {
  const CuSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
  });

  /// 原生开关的默认热区高度（单行设置 tile 也按它对齐）
  static const double height = TemplateSwitch.height;

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && onChanged != null;
    return TemplateSwitch(
      skin: cuSkinOf(context),
      value: value,
      onTap: () => onChanged?.call(!value),
      enabled: canTap,
    );
  }
}
