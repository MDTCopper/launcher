import 'package:flutter/material.dart';

///缓动进度条：值变化时平滑过渡到新值，避免进度跳变。
///
///任务系统的 [Task.progress] 是普通 double，直接塞进 [LinearProgressIndicator]
///会随更新跳变；这里用 [TweenAnimationBuilder] 手动实现缓动（任务本身无此能力）。
class EasedProgressBar extends StatelessWidget {
  ///当前进度（0~1）；null 表示不确定进度（转圈动画）。
  final double? value;

  ///值变化时的过渡时长
  final Duration duration;

  ///值变化时的缓动曲线
  final Curve curve;

  const EasedProgressBar({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    final current = value;
    if (current == null) {
      //不确定进度：交给 LinearProgressIndicator 自带转圈
      return LinearProgressIndicator();
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: current),
      duration: duration,
      curve: curve,
      builder: (context, animatedValue, child) => LinearProgressIndicator(
        value: animatedValue.clamp(0.0, 1.0),
      ),
    );
  }
}