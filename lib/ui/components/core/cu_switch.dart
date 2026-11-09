import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 内核开关：M3 形制（槽实色、圆球亮/暗、球内 开=勾 / 关=叉）
///
/// 颜色不插值（换主题不慢半拍），只有圆球位置做 200ms 位移；
/// 点击热区按原生开关的 48 高取，方便与设置行对齐
class CuSwitch extends StatelessWidget {
  const CuSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
  });

  /// 原生开关的默认热区高度
  static const double height = kMinInteractiveDimension;

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  static const double _trackWidth = 52;
  static const double _trackHeight = 32;
  static const double _thumbSize = 24;
  static const double _pad = 4;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final canTap = enabled && onChanged != null;

    return Semantics(
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canTap ? () => onChanged!(!value) : null,
        child: MouseRegion(
          cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: SizedBox(
            width: _trackWidth,
            height: height,
            child: Center(
              child: Container(
                width: _trackWidth,
                height: _trackHeight,
                decoration: BoxDecoration(
                  color: !enabled
                      ? colors.lowBackgroundOnCard
                      : value
                      ? colors.interactive
                      : colors.inputBackground,
                  borderRadius: BorderRadius.circular(_trackHeight / 2),
                  border: Border.all(
                    color: !enabled
                        ? colors.lowBackgroundOnCard
                        : colors.border,
                  ),
                ),
                child: Stack(
                  children: [
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      alignment: value
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: _pad),
                        child: Container(
                          width: _thumbSize,
                          height: _thumbSize,
                          decoration: BoxDecoration(
                            color: colors.cardBackground,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            value ? Icons.check : Icons.close,
                            size: 14,
                            color: enabled
                                ? colors.itemSecondary
                                : colors.itemHint,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
