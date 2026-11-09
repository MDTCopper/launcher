import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 内核进度条：线性（确定进度）/ 不确定（来回滑动）
///
/// 多段占比（旧 `PercentBar`）与边框进度（旧 `BorderProgress`）后续以
/// `CuProgress.segments` / `.border` 形式补，先满足下载/任务卡。
class CuProgress extends StatelessWidget {
  const CuProgress({
    super.key,
    this.value,
    this.label,
    this.height = 6,
    this.color,
  });

  /// 0~1；null 表示不确定进度
  final double? value;

  /// 右侧文字（如「42%」），为 null 时不显示
  final String? label;

  final double height;

  /// 进度色，默认主题色
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final barColor = color ?? colors.interactive;

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: colors.inputBackground)),
            if (value != null)
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value!.clamp(0.0, 1.0),
                heightFactor: 1,
                child: ColoredBox(color: barColor),
              )
            else
              const _IndeterminateBar(),
          ],
        ),
      ),
    );

    if (label == null) return bar;

    return Row(
      spacing: AppSpacing.related,
      children: [
        Expanded(child: bar),
        Text(
          label!,
          style: textTheme.bodySmall?.copyWith(color: colors.itemSecondary),
        ),
      ],
    );
  }
}

/// 不确定进度：一条 30% 宽的高亮块来回滑动（只动位置，颜色不插值）
class _IndeterminateBar extends StatefulWidget {
  const _IndeterminateBar();

  @override
  State<_IndeterminateBar> createState() => _IndeterminateBarState();
}

class _IndeterminateBarState extends State<_IndeterminateBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FractionallySizedBox(
          alignment: Alignment(-1 + 1.4 * _controller.value, 0),
          widthFactor: 0.3,
          heightFactor: 1,
          child: ColoredBox(color: colors.interactive),
        );
      },
    );
  }
}
