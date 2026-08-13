import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 滚动渐变遮罩：内容滚动时在起始/结束端显示渐隐遮罩（垂直：顶部/底部，
/// 水平：左侧/右侧），模拟内容"沉入/浮出"的效果
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _updateFade();
  }

  void _updateFade() {
    if (!widget.controller.hasClients) return;
    final maxScroll = widget.controller.position.maxScrollExtent;
    final offset = widget.controller.offset;
    setState(() {
      showStartFade = offset > 0;
      showEndFade = offset < maxScroll;
    });
  }

  /// 渐变遮罩：[start] 为 true 时起始端（顶部 / 左侧）渐隐，否则结束端。
  Widget _buildFade(bool show, bool start) {
    final colors = AppColors.of(context);
    // IgnorePointer：遮罩只做视觉渐隐，不拦截下层交互（点击 / 滚动 / 悬停）
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: show ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: _isVertical ? widget.fadeSize : double.infinity,
          width: _isVertical ? double.infinity : widget.fadeSize,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: _isVertical
                  ? (start ? Alignment.topCenter : Alignment.bottomCenter)
                  : (start ? Alignment.centerLeft : Alignment.centerRight),
              end: _isVertical
                  ? (start ? Alignment.bottomCenter : Alignment.topCenter)
                  : (start ? Alignment.centerRight : Alignment.centerLeft),
              colors: [
                colors.cardBackground,
                colors.cardBackground.withAlpha(0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isVertical)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildFade(showStartFade, true),
          )
        else
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: _buildFade(showStartFade, true),
          ),
        if (_isVertical)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildFade(showEndFade, false),
          )
        else
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _buildFade(showEndFade, false),
          ),
      ],
    );
  }
}
