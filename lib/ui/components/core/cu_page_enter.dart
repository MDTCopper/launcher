import 'dart:async';

import 'package:flutter/material.dart';

/// 页面内容入场：淡入 + 向上浮出（位移按**像素**算，不是比例）
///
/// 项目里列表用的 `AppearItem` 走 `SlideTransition`（比例位移，适合列表项），
/// 页面级入场用这个：固定 10 像素的上浮更稳，不会因卡片高度不同而位移夸张
class CuPageEnter extends StatefulWidget {
  const CuPageEnter({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 220),
    this.offsetY = 10,
    this.animate = true,
  });

  final Widget child;

  /// 错位入场延迟
  final Duration delay;

  final Duration duration;

  /// 起始下移的像素数（向上浮出）
  final double offsetY;

  final bool animate;

  @override
  State<CuPageEnter> createState() => _CuPageEnterState();
}

class _CuPageEnterState extends State<CuPageEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.animate ? 0 : 1,
  );
  late final Animation<double> _curved = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) return;
    // 首帧布局完成后再起跑，避免布局期间触发动画
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.delay == Duration.zero) {
        _controller.forward();
        return;
      }
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) {
        final progress = _curved.value;
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, widget.offsetY * (1 - progress)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
