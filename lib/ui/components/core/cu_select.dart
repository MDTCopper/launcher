import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 下拉选项
class CuSelectOption<T> {
  const CuSelectOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// 内核下拉选择：复用项目既有的 [DropdownLayer]（展开面板、选中态、外点关闭都在它那）
///
/// 只做三件事：把 [CuSelectOption] 映射成 [DropdownOption]、套 `AppColors` 配色、
/// 补禁用态。**不用官方 MenuAnchor**。
class CuSelect<T> extends StatelessWidget {
  const CuSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hint = '请选择',
    this.enabled = true,
    this.expanded = false,
  });

  final List<CuSelectOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String hint;
  final bool enabled;

  /// 撑满可用宽度
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    Widget select = DropdownLayer<T>(
      initialValue: value,
      hintText: hint,
      options: [
        for (final option in options)
          DropdownOption(
            value: option.value,
            label: option.label,
            leading: option.icon == null
                ? null
                : Icon(option.icon, size: 16, color: colors.itemSecondary),
          ),
      ],
      onSelect: onChanged,
      width: expanded ? double.infinity : 240,
      menuHeight: (options.length * 40.0).clamp(80.0, 280.0),
      color: colors.cardBackground,
      hoverColor: colors.highBackgroundOnCard,
    );

    if (!enabled) {
      select = Opacity(opacity: 0.5, child: IgnorePointer(child: select));
    }
    return select;
  }
}
