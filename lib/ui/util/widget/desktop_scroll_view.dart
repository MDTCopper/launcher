import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:copperlauncher_main/ui/util/mixin/stateful_mixin.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

///桌面端滚动容器，容纳可滚动组件，使之能通过鼠标滚轮顺滑滚动，必须搭配外部滚动控制器与官方提供的可滚动组件联动(适用于离散型滚轮)
///由于必须关闭物理效果，无法拖动界面进行滚动，也无法拖动滚动条，也不能通过触摸板滚动
///这里就自行构建了一个滚动条，做了基本的主题适配
class DesktopScrollViewContainer extends StatefulWidget {
  const DesktopScrollViewContainer({
    super.key,
    required this.controller,
    required this.child,

    this.scrollDirection = Axis.vertical, //默认垂直方向 todo 横向适配
    this.sensitivity = 1.5,
  });

  final Widget child;
  final double sensitivity; //滚动灵敏度
  final Axis scrollDirection;
  final ScrollController controller;

  @override
  State<StatefulWidget> createState() => _DesktopScrollViewContainerState();
}

class _DesktopScrollViewContainerState extends State<DesktopScrollViewContainer>
    with SingleTickerProviderStateMixin, StatefulMixin {
  static const _kMinThumbHeight = 20.0;
  static const _kFadeDuration = Duration(milliseconds: 300);
  static const _kAutoHideDelay = Duration(seconds: 1);

  static final _kDefaultThumbVisibility = WidgetStateProperty.resolveWith(
    (state) {},
  );

  late final ScrollController _controller = widget.controller;
  late final AnimationController _fadeController;

  // 仅用于保持鼠标相对滑块位置
  double _dragStartOffset = 0.0;

  // 目标滚动位置
  double _targetOffset = 0.0;

  // 按平台调整滚轮灵敏度
  double get _sensitivity {
    if (Platform.isMacOS) {
      return widget.sensitivity * 40.0;
    }
    return widget.sensitivity;
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: _kFadeDuration,
    );

    statesController.addListener(_stateUpdate);

    _controller.addListener(_onScroll); //滚轮滚动时显示滚动条

    //帧后回调,监听后续布局更改
    WidgetsBinding.instance.addPostFrameCallback(_listenLayoutChanges);
  }

  //帧回调，监听布局变化
  void _listenLayoutChanges(_) {
    if (!mounted) return;
    _updateScrollMetrics();
    // 持续监听后续布局更新
    WidgetsBinding.instance.addPostFrameCallback(_listenLayoutChanges);
  }

  late double _lastMaxScrollExtent = _controller.position.maxScrollExtent;
  void _updateScrollMetrics() {
    if (!_controller.hasClients) return;
    final currentMaxExtent = _controller.position.maxScrollExtent;
    if (currentMaxExtent == _lastMaxScrollExtent) return;

    setState(() {
      _lastMaxScrollExtent = currentMaxExtent;
      final offset = _controller.offset;
      if (currentMaxExtent <= 0.0 || offset > currentMaxExtent) {
        _controller.jumpTo(currentMaxExtent);
      }
    });
  }

  void _stateUpdate() {
    setState(() {
      if (isDisabled) {
        _fadeController.reverse();
        return;
      }
      if (isDragged || isScrolledUnder || isHovered) {
        _showScrollBar();
      }
      _resetHideTimer(); //状态更新后更新一次计时器，这样能保证非显示状态1秒后条能消失
    });
  }

  //只要滚动就会更新UI
  void _onScroll() => setState(_handleOutScroll);

  void _showScrollBar() {
    if (!_fadeController.isForwardOrCompleted) {
      _fadeController.forward();
    }
  }

  Timer? _autoHideTimer;
  void _resetHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(_kAutoHideDelay, () {
      if (!isHovered && !isDragged && !isScrolledUnder && mounted) {
        _fadeController.reverse();
      }
    });
  }

  void _handleOutScroll() {
    if (isDragged) return; //不响应拖动
    if (_isInnerScroll) return; //不响应内部滚动
    _targetOffset = _controller.offset;
    if (!isScrolledUnder) {
      setState(() {
        _showScrollBar();
        _resetHideTimer();
      });
    }
  }

  bool _isInnerScroll = false;
  Timer? _innerScrollTimer;
  void _handleScroll(PointerScrollEvent event) {
    _isInnerScroll = true;
    _innerScrollTimer?.cancel();
    _innerScrollTimer = Timer(const Duration(milliseconds: 300), () {
      _isInnerScroll = false;
    });

    final delta = event.scrollDelta.dy * _sensitivity;
    final minExtent = _controller.position.minScrollExtent;
    final maxExtent = _controller.position.maxScrollExtent;

    final isMin = (_targetOffset == minExtent && delta <= 0);
    final isMax = (_targetOffset == maxExtent && delta >= 0);
    if (isMin || isMax) return;

    final currentDelta = (_targetOffset - _controller.offset);
    final needReverse = (currentDelta * delta).isNegative;
    if (needReverse) _targetOffset = _controller.offset;

    _targetOffset += delta; // 累加偏移
    _targetOffset = _targetOffset.clamp(minExtent, maxExtent);

    _controller.animateTo(
      _targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.fastEaseInToSlowEaseOut,
    );
  }

  void _handleDragStart(
    DragStartDetails details,
    double thumbOffset,
    double thumbHeight,
    double trackHeight,
  ) {
    final localPos = details.localPosition.dy;
    final thumbTop = thumbOffset;
    final thumbBottom = thumbTop + thumbHeight;

    if (localPos >= thumbTop && localPos <= thumbBottom) {
      // 点击在滑块上 → 开始拖拽
      statesController.update(WidgetState.dragged, true);
      _dragStartOffset = localPos - thumbTop;
    } else {
      // 点击轨道快速跳转
      final ratio = (localPos - thumbHeight / 2) / (trackHeight - thumbHeight);
      _targetOffset =
          (ratio.clamp(0.0, 1.0)) * _controller.position.maxScrollExtent;
      _controller.animateTo(
        _targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastEaseInToSlowEaseOut,
      );
    }
  }

  //拖拽更新滑块
  void _handleDragUpdate(
    DragUpdateDetails details,
    double thumbHeight,
    double trackHeight,
  ) {
    if (!isDragged || !_controller.hasClients) return;
    final maxScroll = _controller.position.maxScrollExtent;

    if (maxScroll <= 0) return;

    final localPos = details.localPosition.dy;

    // 计算滑块新顶部位置（鼠标相对偏移）
    final newThumbTop = (localPos - _dragStartOffset).clamp(
      0.0,
      trackHeight - thumbHeight,
    );
    final ratio = newThumbTop / (trackHeight - thumbHeight);
    _targetOffset = ratio * maxScroll;
    _controller.jumpTo(_targetOffset);
  }

  void _handleDragEnd() {
    statesController.update(WidgetState.dragged, false);
  }

  Widget _buildListView() {
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        if (event is PointerScrollEvent) {
          _handleScroll(event);
        }
      },
      child: ScrollConfiguration(
        behavior: const MaterialScrollBehavior().copyWith(
          scrollbars: false,
          physics: const NeverScrollableScrollPhysics(),
        ),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
              statesController.update(WidgetState.scrolledUnder, true);
            } else if (n is ScrollEndNotification) {
              statesController.update(WidgetState.scrolledUnder, false);
            }
            return false;
          },
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildScrollBar() {
    final states = statesController.value;
    final theme = Theme.of(context).scrollbarTheme;
    final thumbColor =
        theme.thumbColor?.resolve(states) ?? Colors.grey.shade600;
    final thickness = theme.thickness?.resolve(states);
    final radius = BorderRadius.all(theme.radius ?? Radius.circular(8));
    //final trackVisibility = theme.trackVisibility;//默认可视
    final trackColor =
        theme.trackColor?.resolve(states) ?? Colors.grey.shade600.withAlpha(85);
    final trackBorderColor = theme.trackBorderColor?.resolve(states);

    return Align(
      alignment: Alignment.topRight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final position = _controller.position;
          // 如果最大偏移量为0，内容未溢出，不显示滚动条
          final maxScroll = position.maxScrollExtent;
          if (maxScroll <= 0) {
            if (isDragged) statesController.update(WidgetState.dragged, false);
            if (isHovered) statesController.update(WidgetState.hovered, false);
            return FadeTransition(
              opacity: _fadeController,
              child: Container(
                width: thickness ?? 8,
                height: constraints.maxHeight,
                decoration: BoxDecoration(
                  color: thumbColor,
                  borderRadius: radius,
                ),
              ),
            );
          }

          // 内容总高度 = 滚出 + 可见
          final viewportHeight = constraints.maxHeight;
          final contentHeight = maxScroll + viewportHeight;

          // 滑块高度按比例缩放不低于最小值
          final thumbRatio = viewportHeight / contentHeight;
          final thumbHeight = max(
            thumbRatio * viewportHeight,
            _kMinThumbHeight,
          );

          final currentScroll = position.pixels;
          final scrollRatio = currentScroll / maxScroll;

          // 滑块当前位置
          final maxThumbOffset = viewportHeight - thumbHeight;
          final thumbOffset = scrollRatio * maxThumbOffset;

          return MouseRegion(
            onEnter: (_) => statesController.update(WidgetState.hovered, true),
            onExit: (_) => statesController.update(WidgetState.hovered, false),
            child: GestureDetector(
              onVerticalDragStart:
                  (details) => _handleDragStart(
                    details,
                    thumbOffset,
                    thumbHeight,
                    viewportHeight,
                  ),
              onVerticalDragUpdate:
                  (details) =>
                      _handleDragUpdate(details, thumbHeight, viewportHeight),
              onVerticalDragEnd: (_) => _handleDragEnd(),
              behavior: HitTestBehavior.translucent,
              child: FadeTransition(
                opacity: _fadeController,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.fastOutSlowIn,
                  width: thickness ?? 8,
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: radius,
                    border:
                        trackBorderColor == null
                            ? null
                            : Border.all(color: trackBorderColor),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: thumbOffset),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.fastOutSlowIn,
                        decoration: BoxDecoration(
                          color: thumbColor,
                          borderRadius: radius,
                        ),
                        child: SizedBox(
                          height: thumbHeight,
                          width: thickness ?? 8,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildListView(),
        if (_controller.hasClients) _buildScrollBar(),
      ],
    );
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _innerScrollTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }
}
