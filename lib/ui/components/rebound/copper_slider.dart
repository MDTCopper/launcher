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
    with TickerProviderStateMixin {
  static const _kTrackHeight = 6.0;
  static const _kThumbSize = 18.0;
  static const _kHitHeight = 28.0;

  late final AnimationController _labelController;

  /// 点击跳转动画：从当前显示位置缓动到点击目标。
  late final AnimationController _jumpController;

  /// 跳转起点 / 终点(0~1 比例)。
  double _jumpStart = 0;
  double _jumpTarget = 0;

  /// 动画中的连续插值(未吸附)，动画结束置 null 交回外部值。
  double? _jumpValue;

  /// 拖动中的临时值(min~max)。
  double? _dragValue;

  /// 当前显示值：动画插值 > 拖动临时值 > 外部 [widget.value]。
  double get _displayValue => _jumpValue ?? _dragValue ?? widget.value;

  /// 比例 → 吸附刻度后的值：带 [divisions] 时四舍五入到最近刻度，
  /// 否则原样换算。所有对外回调(change/changeStart/changeEnd)统一用它，
  /// 保证显示与赋值一致。
  double _snapValue(double ratio) {
    final divisions = widget.divisions;
    final raw = _ratioToValue(ratio);
    if (divisions == null || divisions <= 0) return raw;
    final snappedRatio = (ratio * divisions).round() / divisions;
    return _ratioToValue(snappedRatio);
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
    _jumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )
      ..addListener(() {
        // 位置连续插值(不吸附)，让滑块平滑滑到目标
        final t = Curves.easeOutCubic.transform(_jumpController.value);
        final ratio = _jumpStart + (_jumpTarget - _jumpStart) * t;
        setState(() => _jumpValue = _ratioToValue(ratio));
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        // 到位后提交吸附值并收浮标
        final finalValue = _snapValue(_jumpTarget);
        setState(() => _jumpValue = null);
        widget.onChanged?.call(finalValue);
        widget.onChangeEnd?.call(finalValue);
        _labelController.reverse();
      });
  }

  @override
  void dispose() {
    _jumpController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  /// 点击跳转：从当前显示位置缓动到 [targetRatio] 对应刻度。
  void _jumpTo(double targetRatio) {
    _jumpController.stop();
    _jumpStart = _valueToRatio(_displayValue);
    _jumpTarget = targetRatio;
    _jumpValue = null;
    _labelController.forward();
    _jumpController.forward(from: 0);
  }

  void _startDrag(double ratio) {
    // 拖动打断跳转动画，改为实时跟手
    _jumpController.stop();
    _jumpValue = null;
    _labelController.forward();
    final value = _snapValue(ratio);
    _dragValue = value;
    widget.onChangeStart?.call(value);
    setState(() {});
  }

  void _updateDrag(double ratio) {
    final value = _snapValue(ratio);
    _dragValue = value;
    widget.onChanged?.call(value);
    setState(() {});
  }

  void _endDrag(double ratio) {
    final value = _snapValue(ratio);
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
        // 显示比例：动画插值连续过渡，否则吸附外部值
        final ratio = _valueToRatio(_displayValue);
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
            // 点击：等手势竞技裁决(确认是 tap 而非 drag)后，从当前位置缓动跳转
            onTapUp: (details) => _jumpTo(
              (details.localPosition.dx / width).clamp(0.0, 1.0),
            ),
            onTapCancel: () => _jumpController.stop(),
            // 拖动：实时跟手(优先于 tap 竞技胜出)
            onHorizontalDragStart: (details) => _startDrag(
              (details.localPosition.dx / width).clamp(0.0, 1.0),
            ),
            onHorizontalDragUpdate: (details) => _updateDrag(
              (details.localPosition.dx / width).clamp(0.0, 1.0),
            ),
            onHorizontalDragEnd: (_) => _endDrag(_valueToRatio(_displayValue)),
            child: Stack(
              alignment: Alignment.center,
              // 浮标越出命中区上方，需放开裁剪
              clipBehavior: Clip.none,
              children: [
                // 轨道垂直居中于命中区
                Positioned(
                  left: 0,
                  right: 0,
                  top: (_kHitHeight - _kTrackHeight) / 2,
                  child: track,
                ),
                thumb,
                // 拖拽浮标：值文本浮在滑块上方偏外(translation 负 Y 上移)
                Positioned(
                  left: thumbCenterLeft + _kThumbSize / 2,
                  top: 0,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, -1.0),
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
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          widget.label ??
                              _displayValue.toStringAsFixed(
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