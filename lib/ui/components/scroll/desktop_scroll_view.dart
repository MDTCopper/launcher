import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:copper_launcher/ui/util/mixin/stateful_mixin.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

///桌面端滚动容器，容纳可滚动组件，使之能通过鼠标滚轮顺滑滚动，必须搭配外部滚动控制器与官方提供的可滚动组件联动(适用于离散型滚轮)
///
///由于必须关闭物理效果，无法拖动界面进行滚动，也无法拖动滚动条，也不能通过触摸板滚动
///
///这里就自行构建了一个滚动条，做了基本的主题适配
class DesktopScrollViewContainer extends StatefulWidget {
  const DesktopScrollViewContainer({
    super.key,
    required this.controller,
    required this.child,

    this.scrollDirection = Axis.vertical,
    this.sensitivity = 1.5,
    this.trackpadSensitivity = 0.33,
    this.scrollbarAlignment,
    this.maxVelocity = 2000,
    this.estimatedMaxScrollExtent,
  });

  final Widget child;

  /// 离散滚轮灵敏度
  final double sensitivity;

  /// 触控板灵敏度
  final double trackpadSensitivity;

  final Axis scrollDirection;

  /// 滚动条位置（默认：垂直滚动条在右侧，水平滚动条在底部）
  final AlignmentGeometry? scrollbarAlignment;

  /// 预测最大偏移（惰性列表提供）：滚动条 thumb / 点击 / 拖动用此值计算，
  /// 避免惰性列表 maxScrollExtent 估算（平均外推）导致的跳变
  /// 不传则用 position.maxScrollExtent。到达实际边界时自动重校为实际值
  final double? estimatedMaxScrollExtent;

  /// 触控板惯性速度上限（px/s），<= 0 表示不限速
  /// 速度经 tanh 非线性映射：低速≈真实，高速渐近逼近该值
  final double maxVelocity;

  final ScrollController controller;

  @override
  State<StatefulWidget> createState() => _DesktopScrollViewContainerState();
}

class _DesktopScrollViewContainerState extends State<DesktopScrollViewContainer>
    with TickerProviderStateMixin, StatefulMixin {
  static const _kMinThumbHeight = 20.0;
  static const _kFadeDuration = Duration(milliseconds: 300);
  static const _kAutoHideDelay = Duration(seconds: 1);

  static final _kDefaultThumbVisibility = WidgetStateProperty.resolveWith(
    (state) {},
  );

  late final ScrollController _controller = widget.controller;
  late final AnimationController _fadeController;

  /// 触控板惯性模拟控制器（离手速度 → 减速滑行）
  late final AnimationController _inertiaController;

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

  bool get _isVertical => widget.scrollDirection == Axis.vertical;

  // ── 滚动条 hover 时的有效灵敏度（窄区域需要更灵敏）──

  bool get _isScrollbarHovered => isHovered;

  /// 滚动条有效最大偏移：预测优先（稳定），到达实际边界后重校为实际值。
  double? _effectiveMax;

  double get _scrollMax =>
      _effectiveMax ??
      widget.estimatedMaxScrollExtent ??
      _controller.position.maxScrollExtent;

  /// 滚轮有效灵敏度：滚动条 hover 时 ×2
  double get _effectiveScrollSensitivity =>
      _sensitivity * (_isScrollbarHovered ? 2 : 1);

  /// 触控板有效灵敏度：滚动条 hover 时 ×2
  double get _effectiveTrackpadSensitivity =>
      widget.trackpadSensitivity * (_isScrollbarHovered ? 2 : 1);

  /// 惯性速度有效上限：滚动条 hover 时 ×2
  double get _effectiveMaxVelocity =>
      widget.maxVelocity * (_isScrollbarHovered ? 2 : 1);

  // 主轴滚动增量（垂直取 dy，水平取 dx）
  double _axisDelta(Offset delta) => _isVertical ? delta.dy : delta.dx;

  // 主轴本地坐标（垂直取 dy，水平取 dx）
  double _axisLocal(Offset local) => _isVertical ? local.dy : local.dx;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: _kFadeDuration,
    );

    // 惯性控制器 value 跟随 Simulation 的真实滚动位置（offset 可能远超 0~1），
    // 必须放开 value 边界，否则被 clamp 到 [0,1] 导致滚动条瞬间回顶
    _inertiaController =
        AnimationController(
            vsync: this,
            lowerBound: double.negativeInfinity,
            upperBound: double.infinity,
          )
          ..addListener(_onInertia)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed ||
                status == AnimationStatus.dismissed) {
              _targetOffset = _controller.offset;
            }
          });

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
      // 最大偏移变化（如切页换内容）：失效已校准的 _effectiveMax，
      // 让 _scrollMax 回落重新计算，否则沿用冻结旧值会算出错误的 thumb
      // （旧值偏小 → thumb 撑满槽 + 交互异常），直到回到边界才恢复
      _effectiveMax = null;
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
  void _onScroll() {
    if (_controller.hasClients) {
      final position = _controller.position;
      // 越界检测：offset 超过当前最大偏移时自动回弹
      if (position.pixels > position.maxScrollExtent) {
        _controller.jumpTo(position.maxScrollExtent);
        return;
      }
      // 到达实际边界 → 把预测重校为实际值（滚动条对齐；底部内容全构建后精确）
      if (position.pixels >= position.maxScrollExtent - 1 ||
          position.pixels <= position.minScrollExtent + 1) {
        if (_effectiveMax != position.maxScrollExtent) {
          _effectiveMax = position.maxScrollExtent;
        }
      }
    }
    setState(_handleOutScroll);
  }

  @override
  void didUpdateWidget(covariant DesktopScrollViewContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 预测更新（外层 rebuild / 可变列表）：重置重校，重新用新预测
    if (oldWidget.estimatedMaxScrollExtent != widget.estimatedMaxScrollExtent) {
      _effectiveMax = null;
    }
  }

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

  /// 判断滚轮方向是否还能继续滚动（未到边界）。
  bool _canScroll(PointerScrollEvent event) {
    if (!_controller.hasClients) return false;
    final raw = _isVertical
        ? event.scrollDelta.dy
        : (event.scrollDelta.dx != 0
              ? event.scrollDelta.dx
              : event.scrollDelta.dy);
    final position = _controller.position;
    if (raw > 0) return position.pixels < position.maxScrollExtent;
    if (raw < 0) return position.pixels > position.minScrollExtent;
    return false;
  }

  void _handleScroll(PointerScrollEvent event) {
    _stopInertia();
    _isInnerScroll = true;
    _innerScrollTimer?.cancel();
    _innerScrollTimer = Timer(const Duration(milliseconds: 300), () {
      _isInnerScroll = false;
    });

    // 鼠标滚轮：垂直列表取 dy；横向列表取 dx，若无水平滚轮（dx=0）则回退到 dy，
    // 让普通鼠标滚轮也能滚动横向内容
    final double rawDelta;
    if (_isVertical) {
      rawDelta = event.scrollDelta.dy;
    } else {
      rawDelta = event.scrollDelta.dx != 0
          ? event.scrollDelta.dx
          : event.scrollDelta.dy;
    }
    final delta = rawDelta * _effectiveScrollSensitivity;
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

  // ── 触控板连续滚动（PanZoom 手势）──

  /// 手势起点的滚动位置（触控板从起点跟随手指，jumpTo 即时跟随）
  double _panZoomOffset = 0.0;

  /// 最近几次触控板滚动的 (缩放后 delta, 时间秒) 样本，用于估算离手速度
  final List<(double, double)> _recentPan = [];

  /// 当前正在处理 PanZoom 手势的容器（嵌套滚动时最内层优先）。
  static _DesktopScrollViewContainerState? _panZoomOwner;

  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    // 嵌套滚动：hit test 从内到外，最内层先收到 start，成为 PanZoom 处理者
    _panZoomOwner ??= this;
    _stopInertia();
    _isInnerScroll = true;
    _recentPan.clear();
    _panZoomOffset = _controller.offset;
  }

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    // 嵌套滚动：只有当前处理者响应；owner 被释放（内层到边界）时接管
    if (_panZoomOwner != null && _panZoomOwner != this) return;
    _panZoomOwner ??= this;

    _isInnerScroll = true;
    _innerScrollTimer?.cancel();
    _innerScrollTimer = Timer(const Duration(milliseconds: 300), () {
      _isInnerScroll = false;
    });

    // 触控板：沿主轴移动（垂直：手指下滑 → offset 减小；水平：手指右滑 → offset 减小）
    // 独立于滚轮的 trackpadSensitivity；滚动条 hover 时翻倍
    final delta = _axisDelta(event.panDelta) * _effectiveTrackpadSensitivity;
    final minExtent = _controller.position.minScrollExtent;
    final maxExtent = _controller.position.maxScrollExtent;

    _panZoomOffset = (_panZoomOffset - delta).clamp(minExtent, maxExtent);
    // 连续手势走 jumpTo，即时跟随无动画延迟
    _controller.jumpTo(_panZoomOffset);

    // 到边界继续越界滚动 → 释放处理权，让外层（若有）接管剩余滚动
    if ((_panZoomOffset == minExtent && delta > 0) ||
        (_panZoomOffset == maxExtent && delta < 0)) {
      _panZoomOwner = null;
    }

    // 记录速度样本（缩放后的 delta + 时间秒）
    _recentPan.add((delta, event.timeStamp.inMicroseconds / 1e6));
    if (_recentPan.length > 5) _recentPan.removeAt(0);

    if (!isScrolledUnder) {
      setState(() {
        _showScrollBar();
        _resetHideTimer();
      });
    }
  }

  void _handlePanZoomEnd(PointerPanZoomEndEvent event) {
    if (_panZoomOwner == this) _panZoomOwner = null;
    _isInnerScroll = false;
    _targetOffset = _controller.offset;

    // 用最近样本估算离手速度（缩放后 delta 总合 / 时间跨度）
    double velocity = 0;
    if (_recentPan.length >= 2) {
      final first = _recentPan.first;
      final last = _recentPan.last;
      final dt = last.$2 - first.$2;
      if (dt > 0) {
        double total = 0;
        for (final sample in _recentPan) {
          total += sample.$1;
        }
        velocity = total / dt;
      }
    }
    _recentPan.clear();

    // 离手惯性：用结束速度模拟减速滑行
    _startInertia(velocity);
  }

  /// 停止惯性模拟（新输入介入时调用）。
  void _stopInertia() {
    if (_inertiaController.isAnimating) _inertiaController.stop();
  }

  /// 惯性模拟：离手速度 → ClampingScrollSimulation 减速（到边界拖停）。
  void _startInertia(double velocityPxPerSecond) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final min = position.minScrollExtent;
    final max = position.maxScrollExtent;
    if (max <= min) return;

    // 速度映射：低速≈真实、高速渐近上限（tanh），避免超速惯性
    final mapped = _mapVelocity(velocityPxPerSecond);
    // 触控板方向：panY 正（手指下滑）→ offset 减小，故取负
    final v = -mapped;
    if (v.abs() < 1) return; // 速度太小不启动

    _inertiaController.animateWith(
      ClampingScrollSimulation(position: position.pixels, velocity: v),
    );
  }

  /// 速度映射函数：`vMax * tanh(v / vMax)`（dart:math 无 tanh，用 exp 等价式）。
  ///
  /// - 低速（`v << vMax`）≈ 真实速度
  /// - 高速渐近逼近 [maxVelocity]，不会超速
  /// - [maxVelocity] <= 0 时不限速
  double _mapVelocity(double velocity) {
    final vMax = _effectiveMaxVelocity.abs();
    if (vMax <= 0) return velocity;
    final x = velocity / vMax;
    // tanh(x) = (e^(2x) - 1) / (e^(2x) + 1)；|x| 过大时 exp 溢出，直接趋近 ±1
    if (x.abs() > 10) return velocity.isNegative ? -vMax : vMax;
    final e = exp(2 * x);
    return vMax * (e - 1) / (e + 1);
  }

  void _onInertia() {
    if (!_controller.hasClients) return;
    final min = _controller.position.minScrollExtent;
    final max = _controller.position.maxScrollExtent;
    _controller.jumpTo(_inertiaController.value.clamp(min, max));
  }

  void _handleDragStart(
    DragStartDetails details,
    double thumbOffset,
    double thumbHeight,
    double trackHeight,
  ) {
    final localPos = _axisLocal(details.localPosition);
    final thumbTop = thumbOffset;
    final thumbBottom = thumbTop + thumbHeight;

    if (localPos >= thumbTop && localPos <= thumbBottom) {
      // 点击在滑块上 → 开始拖拽
      statesController.update(WidgetState.dragged, true);
      _dragStartOffset = localPos - thumbTop;
    } else {
      // 点击轨道快速跳转（用预测 _scrollMax，稳定不跳；clamp 实际边界）
      final ratio = (localPos - thumbHeight / 2) / (trackHeight - thumbHeight);
      _targetOffset = (ratio.clamp(0.0, 1.0)) * _scrollMax;
      final minExtent = _controller.position.minScrollExtent;
      final maxExtent = _controller.position.maxScrollExtent;
      _controller.animateTo(
        _targetOffset.clamp(minExtent, maxExtent),
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
    final maxScroll = _scrollMax;

    if (maxScroll <= 0) return;

    final localPos = _axisLocal(details.localPosition);

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
        if (event is! PointerScrollEvent) return;
        // 嵌套滚动：内层还能滚时消费事件（resolver 保证只有最内层处理，
        // 外层不响应）；内层到边界时不注册，事件自然冒泡到外层滚动容器
        if (_canScroll(event)) {
          GestureBinding.instance.pointerSignalResolver.register(
            event,
            (e) => _handleScroll(e as PointerScrollEvent),
          );
        }
      },
      // 触控板：Flutter 桌面端（macOS 等）把两指平移发成 PanZoom 手势，
      // 不产生 PointerScrollEvent，需单独处理（连续滚动走 jumpTo 即时跟随）
      onPointerPanZoomStart: _handlePanZoomStart,
      onPointerPanZoomUpdate: _handlePanZoomUpdate,
      onPointerPanZoomEnd: _handlePanZoomEnd,
      child: ScrollConfiguration(
        behavior: const MaterialScrollBehavior().copyWith(
          scrollbars: false,
          physics: const NeverScrollableScrollPhysics(),
        ),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            // 只响应本容器（depth 0）的滚动，忽略内层嵌套滚动冒泡上来的通知，
            // 避免滚动内层时外层滚动条误显示
            if (n.depth != 0) return false;
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
    final thickness = theme.thickness?.resolve(states) ?? 8;
    final radius = BorderRadius.all(theme.radius ?? Radius.circular(8));
    //final trackVisibility = theme.trackVisibility;//默认可视
    final trackColor =
        theme.trackColor?.resolve(states) ?? Colors.grey.shade600.withAlpha(85);
    final trackBorderColor = theme.trackBorderColor?.resolve(states);

    final isVertical = _isVertical;
    // 滚动条位置：默认垂直在右侧、水平在底部，可覆盖
    final alignment =
        widget.scrollbarAlignment ??
        (isVertical ? Alignment.centerRight : Alignment.bottomCenter);

    return Align(
      alignment: alignment,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final position = _controller.position;
          // 如果最大偏移量为0，内容未溢出，不显示滚动条
          final maxScroll = _scrollMax;
          if (maxScroll <= 0) {
            if (isDragged) statesController.update(WidgetState.dragged, false);
            if (isHovered) statesController.update(WidgetState.hovered, false);
            return FadeTransition(
              opacity: _fadeController,
              child: Container(
                width: isVertical ? thickness : constraints.maxWidth,
                height: isVertical ? constraints.maxHeight : thickness,
                decoration: BoxDecoration(
                  color: thumbColor,
                  borderRadius: radius,
                ),
              ),
            );
          }

          // 主轴尺寸（垂直=高，水平=宽），内容总长 = 滚出 + 可见
          final mainSize = isVertical
              ? constraints.maxHeight
              : constraints.maxWidth;
          final contentSize = maxScroll + mainSize;

          // 滑块主轴尺寸按比例缩放不低于最小值
          final thumbRatio = mainSize / contentSize;
          final thumbMain = max(thumbRatio * mainSize, _kMinThumbHeight);

          final currentScroll = position.pixels;
          final scrollRatio = currentScroll / maxScroll;

          // 滑块主轴位置
          final maxThumbOffset = mainSize - thumbMain;
          final thumbOffset = scrollRatio * maxThumbOffset;

          // 拖拽手势按轴选择；用 RawGestureDetector 限定只接受鼠标设备，
          // 触控板双指（trackpad）不触发拖拽（走 PanZoom 滚动分支），
          // 避免"轨道跳转 + 反向拖动"的误触
          final Widget dragArea = RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: {
              if (isVertical)
                VerticalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      VerticalDragGestureRecognizer
                    >(
                      () =>
                          VerticalDragGestureRecognizer()
                            ..supportedDevices = {PointerDeviceKind.mouse},
                      (instance) {
                        instance
                          ..onStart = (details) {
                            _handleDragStart(
                              details,
                              thumbOffset,
                              thumbMain,
                              mainSize,
                            );
                          }
                          ..onUpdate = (details) {
                            _handleDragUpdate(details, thumbMain, mainSize);
                          }
                          ..onEnd = (_) {
                            _handleDragEnd();
                          }
                          ..onCancel = _handleDragEnd;
                      },
                    )
              else
                HorizontalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      HorizontalDragGestureRecognizer
                    >(
                      () =>
                          HorizontalDragGestureRecognizer()
                            ..supportedDevices = {PointerDeviceKind.mouse},
                      (instance) {
                        instance
                          ..onStart = (details) {
                            _handleDragStart(
                              details,
                              thumbOffset,
                              thumbMain,
                              mainSize,
                            );
                          }
                          ..onUpdate = (details) {
                            _handleDragUpdate(details, thumbMain, mainSize);
                          }
                          ..onEnd = (_) {
                            _handleDragEnd();
                          }
                          ..onCancel = _handleDragEnd;
                      },
                    ),
            },
            child: FadeTransition(
              opacity: _fadeController,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.fastOutSlowIn,
                width: isVertical ? thickness : mainSize,
                height: isVertical ? mainSize : thickness,
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: radius,
                  border: trackBorderColor == null
                      ? null
                      : Border.all(color: trackBorderColor),
                ),
                child: Align(
                  alignment: isVertical
                      ? Alignment.topCenter
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: isVertical
                        ? EdgeInsets.only(top: thumbOffset)
                        : EdgeInsets.only(left: thumbOffset),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.fastOutSlowIn,
                      decoration: BoxDecoration(
                        color: thumbColor,
                        borderRadius: radius,
                      ),
                      child: SizedBox(
                        width: isVertical ? thickness : thumbMain,
                        height: isVertical ? thumbMain : thickness,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          return MouseRegion(
            onEnter: (_) => statesController.update(WidgetState.hovered, true),
            onExit: (_) => statesController.update(WidgetState.hovered, false),
            // 滚动条上也支持离散滚轮滚动（滚轮事件在此转发给 _handleScroll）
            child: Listener(
              onPointerSignal: (PointerSignalEvent event) {
                if (event is PointerScrollEvent) _handleScroll(event);
              },
              child: dragArea,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      // passthrough：约束透传给 ListView，Stack 尺寸 = 内容。
      // expand 会在无界约束（shrinkWrap 上下文，如模块内）下崩溃；
      // 页面级有界约束下 ListView 默认撑满，行为不变
      fit: StackFit.passthrough,
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
    _inertiaController.dispose();
    super.dispose();
  }
}
