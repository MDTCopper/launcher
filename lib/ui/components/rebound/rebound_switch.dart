import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../rebound/rebound_container.dart';

/// copper 风格开关：轨道 + 滑块，选中/未选中之间平滑过渡。
///
/// - 由 [AnimationController] 驱动滑块横移与轨道/滑块颜色渐变
/// - 双模式取色走 [AppColors](交互层强调 + 卡片底色),不直接引用原色
/// - 轨道圆角胶囊(半高)，滑块为圆形阴影小片
class ReboundSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const ReboundSwitch({super.key, required this.value, this.onChanged});

  @override
  State<StatefulWidget> createState() => _ReboundSwitchState();
}

class _ReboundSwitchState extends State<ReboundSwitch>
    with SingleTickerProviderStateMixin {
  static const _kTrackWidth = 48.0;
  static const _kTrackHeight = 26.0;
  static const _kThumbSize = 20.0;
  static const _kThumbInset = 3.0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (widget.value) _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ReboundSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final animation = CurvedAnimation(
          parent: _controller,
          curve: Curves.ease,
        );

        // 轨道：未选中 = 边框色，选中 = 主题色
        final trackColor = ColorTween(
          begin: colors.border,
          end: colors.interactive,
        ).animate(animation).value;

        // 滑块：未选中 = 次要文本色，选中 = 卡片底(在主题色轨道上反白)
        final thumbColor = ColorTween(
          begin: colors.itemSecondary,
          end: colors.itemOnInteractive,
        ).animate(animation).value;

        // 滑块横移：从左侧 inset 到右侧(轨道宽 - 滑块 - 两侧 inset)
        final thumbLeft = Tween<double>(
          begin: _kThumbInset,
          end: _kTrackWidth - _kThumbSize - _kThumbInset,
        ).animate(animation).value;

        return ReboundContainer(
          onTap: widget.onChanged == null
              ? null
              : () => widget.onChanged?.call(!widget.value),
          pressedScale: 0.9,
          borderRadius: BorderRadius.circular(_kTrackHeight / 2),
          padding: EdgeInsets.zero,
          child: Container(
            width: _kTrackWidth,
            height: _kTrackHeight,
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(_kTrackHeight / 2),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: thumbLeft,
                  child: Container(
                    width: _kThumbSize,
                    height: _kThumbSize,
                    decoration: BoxDecoration(
                      color: thumbColor,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
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