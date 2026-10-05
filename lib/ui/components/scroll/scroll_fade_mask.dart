import 'package:flutter/material.dart';

/// 滚动渐变遮罩：内容滚动时在起始/结束端沿线淡化（垂直：顶部/底部，
/// 水平：左侧/右侧），模拟内容"沉入/浮出"的效果
///
/// 用 shader 遮罩按不透明度淡化组件自身，不铺任何颜色 —— 淡出后露出的是
/// 真实背景，落在卡片、弹层、页面哪种底色上都对
///
/// 遮罩一直挂在树上，到边界那一端把不透明度置 1；淡化随滚动重绘直接切过来，
/// 不做补间
class ScrollFadeMask extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
  final Axis scrollDirection;
  final double fadeSize; // 遮罩宽度（水平）/ 高度（垂直）

  const ScrollFadeMask({
    super.key,
    required this.child,
    required this.controller,
    this.scrollDirection = Axis.vertical,
    this.fadeSize = 20,
  });

  @override
  State<StatefulWidget> createState() => _ScrollFadeMaskState();
}

class _ScrollFadeMaskState extends State<ScrollFadeMask>
    with WidgetsBindingObserver {
  bool showStartFade = false; // 起始端（顶部 / 左侧）
  bool showEndFade = false; // 结束端（底部 / 右侧）

  bool get _isVertical => widget.scrollDirection == Axis.vertical;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateFade);
    WidgetsBinding.instance.addObserver(this);
    _updateFade();
    // initState 时位置还没接上，帧后再算一次，否则首帧到边界那一端不淡化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateFade();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateFade);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _updateFade();
  }

  @override
  void didUpdateWidget(covariant ScrollFadeMask oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_updateFade);
      widget.controller.addListener(_updateFade);
      _updateFade();
    }
  }

  void _updateFade() {
    if (!widget.controller.hasClients) return;
    final position = widget.controller.position;
    final showStart = position.pixels > 0;
    final showEnd = position.pixels < position.maxScrollExtent;
    if (showStart == showStartFade && showEnd == showEndFade) return;
    setState(() {
      showStartFade = showStart;
      showEndFade = showEnd;
    });
  }

  /// 两端淡化：起始端从全透明渐入，结束端渐出到全透明；只淡一端时另一端
  /// 全程不透明，两端都淡化时中间按不透明段插值（太窄就直接首尾相接）
  ///
  /// [stop] 是遮罩长度占主轴长度的比例，由 [build] 按实际约束算出来
  LinearGradient _buildFadeGradient(double stop) {
    const opaque = Color(0xFF000000);
    const transparent = Color(0x00000000);

    // 两端都不淡化（内容没溢出、或正停在两端之间）：给一段全不透明渐变，
    // 颜色数不少于 2 是 shader 的硬要求
    if (!showStartFade && !showEndFade) {
      return const LinearGradient(colors: [opaque, opaque]);
    }

    final stops = <double>[];
    final colors = <Color>[];

    if (showStartFade) {
      stops.addAll([0.0, stop]);
      colors.addAll([transparent, opaque]);
    }
    if (showEndFade) {
      final start = showStartFade ? 1 - stop : 0.0;
      stops.addAll([start, 1.0]);
      colors.addAll([opaque, transparent]);
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: _isVertical ? Alignment.bottomLeft : Alignment.topRight,
      colors: colors,
      stops: stops,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mainAxisLength = _isVertical
            ? constraints.maxHeight
            : constraints.maxWidth;
        // 主轴无界（如 shrinkWrap 的列表）时沿该轴没有可淡化的长度
        if (mainAxisLength <= 0 || !mainAxisLength.isFinite) {
          return widget.child;
        }

        // 遮罩不能超过主轴一半，否则两端淡化会啃到中间
        final stop = (widget.fadeSize / mainAxisLength).clamp(0.0, 0.5);
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => _buildFadeGradient(stop).createShader(
            Rect.fromLTWH(0, 0, bounds.width, bounds.height),
          ),
          child: widget.child,
        );
      },
    );
  }
}
