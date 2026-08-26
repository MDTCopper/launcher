import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// copper 风格滑条：轨道 + 填充 + 滑块，支持点击定位与拖动。
///
/// - 值域 [min] ~ [max]，拖动 / 点击按比例换算；[divisions] 非空时吸附刻度
/// - 拖拽期间显示浮标 [label](值文本)，松手隐藏
/// - 取色走 [AppColors]:已填部分 = 主题色，未填部分 = 边框色，滑块 = 卡片底
class CopperSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  const CopperSlider({
    super.key,
    required this.value,
    this.label,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
  });

  @override
  State<StatefulWidget> createState() => _CopperSliderState();
}

class _CopperSliderState extends State<CopperSlider>
    with SingleTickerProviderStateMixin {
  static const _kTrackHeight = 4.0;
  static const _kThumbSize = 14.0;
  static const _kHitHeight = 24.0;

  late final AnimationController _labelController;

  /// 拖动中的临时值(min~max)。
  double? _dragValue;

  /// 刻度换算：带 divisions 时吸附到最近刻度。
  double get _effectiveValue {
    final current = _dragValue ?? widget.value;
    final divisions = widget.divisions;
    if (divisions == null || divisions <= 0) return current;
    return (_valueToRatio(current) * divisions).round() / divisions *
        (widget.max - widget.min) +
        widget.min;
  }

  double _valueToRatio(double value) =>
      ((value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  double _ratioToValue(double ratio) =>
      widget.min + ratio * (widget.max - widget.min);

  @override
  void initState() {
    super.initState();
    _labelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _startDrag(double ratio) {
    _labelController.forward();
    final value = _ratioToValue(ratio);
    _dragValue = value;
    widget.onChangeStart?.call(value);
    setState(() {});
  }

  void _updateDrag(double ratio) {
    final value = _ratioToValue(ratio);
    _dragValue = value;
    widget.onChanged?.call(value);
    setState(() {});
  }

  void _endDrag(double ratio) {
    final value = _ratioToValue(ratio);
    _dragValue = null;
    widget.onChangeEnd?.call(value);
    _labelController.reverse();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final ratio = _valueToRatio(_effectiveValue);
        // 滑块中心可活动范围 = 轨道宽 - 滑块直径
        final thumbCenterLeft = ratio * (width - _kThumbSize);

        final track = Container(
          height: _kTrackHeight,
          decoration: BoxDecoration(
            color: colors.border,
            borderRadius: BorderRadius.circular(_kTrackHeight / 2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              // 填充比例 = value 比例
              widthFactor: ratio,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.interactive,
                  borderRadius: BorderRadius.circular(_kTrackHeight / 2),
                ),
              ),
            ),
          ),
        );

        final thumb = Positioned(
          left: thumbCenterLeft,
          top: (_kHitHeight - _kThumbSize) / 2,
          child: Container(
            width: _kThumbSize,
            height: _kThumbSize,
            decoration: BoxDecoration(
              color: colors.cardBackground,
              shape: BoxShape.circle,
              border: Border.all(color: colors.interactive, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        );

        return SizedBox(
          height: _kHitHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 点击 / 拖动都按水平位置换算
            onTapDown: (details) => _startDrag(
              (details.localPosition.dx / width).clamp(0.0, 1.0),
            ),
            onTapUp: (details) => _endDrag(
              (details.localPosition.dx / width).clamp(0.0, 1.0),
            ),
            onHorizontalDragStart: (details) => _startDrag(
              (details.localPosition.dx / width).clamp(0.0, 1.0),
            ),
            onHorizontalDragUpdate: (details) => _updateDrag(
              (details.localPosition.dx / width).clamp(0.0, 1.0),
            ),
            onHorizontalDragEnd: (_) => _endDrag(_valueToRatio(_effectiveValue)),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 轨道垂直居中于命中区
                Positioned(
                  left: 0,
                  right: 0,
                  top: (_kHitHeight - _kTrackHeight) / 2,
                  child: track,
                ),
                thumb,
                // 拖拽浮标：值文本浮在滑块上方
                Positioned(
                  left: thumbCenterLeft + _kThumbSize / 2,
                  top: 0,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, -0.2),
                    child: FadeTransition(
                      opacity: _labelController,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.elevatedBackground,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.border),
                        ),
                        child: Text(
                          widget.label ??
                              _effectiveValue.toStringAsFixed(
                                widget.divisions != null ? 0 : 2,
                              ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}