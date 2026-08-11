import 'dart:async';

import 'package:copper_launcher/ui/feature/feature_curve.dart';
import 'package:flutter/material.dart';

/// 单条目入场动画：自持 [AnimationController]，延迟后播放（淡入 + 位移 + 生长）。
///
/// - [delayMs] > 0：错位入场（进入页面时按 index 递增延迟）
/// - [delayMs] = 0：滚动浮现（惰性构建时立即播放）
/// - [animate] = false：直接显示（滚动回来复用已出现的条目，不重复动画）
class AppearItem extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final Duration duration;
  final Offset offset; // 起始位移（列表用）
  final double scale; // 起始缩放（网格生长式用，默认 1 即不缩放）
  final Curve curve;
  final bool animate;

  const AppearItem({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.duration = const Duration(milliseconds: 200),
    this.offset = Offset.zero,
    this.scale = 1,
    this.curve = FeatureCurves.reboundIn,
    this.animate = true,
  });

  @override
  State<StatefulWidget> createState() => _AppearItemState();
}

class _AppearItemState extends State<AppearItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _position;
  late final Animation<double> _scale;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    _fade = curved;
    _position = Tween(begin: widget.offset, end: Offset.zero).animate(curved);
    _scale = Tween(begin: widget.scale, end: 1.0).animate(curved);

    if (widget.animate && widget.delayMs > 0) {
      _timer = Timer(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _controller.forward();
      });
    } else if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0; // 不动画：直接显示最终态
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget result = FadeTransition(opacity: _fade, child: widget.child);
    if (widget.offset != Offset.zero) {
      result = SlideTransition(position: _position, child: result);
    }
    if (widget.scale != 1) {
      result = ScaleTransition(scale: _scale, child: result);
    }
    return result;
  }
}
