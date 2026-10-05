import 'dart:math' as math;

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

import 'drill_paint.dart';

/// 铜钻头装载循环：线条化的 Mindustry 机械钻头
///
/// 层次照 `Drill.java` 那张机械钻头的四层（底座 / 钻头 / 顶盖 / 矿物）线条化：
/// 底座 → 四片钻臂 → 顶盖 → 轮毂亮点 → 铜粒
///
/// 一个 [cycle] 走一步：钻臂转到下一个 90 度 → 轮毂亮点闪一下 → 从中心弹出一粒铜
///
/// 三种状态：
/// - [DrillLoadingState.spinning]：不停转，一步接一步
/// - [DrillLoadingState.completing]：只转一次，转到头时弹出铜粒，然后停住
/// - [DrillLoadingState.error]：只转一次，转到头后轮毂亮点转红、整套金属略微泛红，停住
///
/// **切状态会等当前这一步走完**（转完那 90 度再进新状态），所以不会看到半路被打断的钻头；
/// 等待期间连点也只会记下最后一次要去的状态
///
/// 纯 `CustomPaint` 绘制，不依赖任何图片资源，任意尺寸都清晰
class DrillLoading extends StatefulWidget {
  const DrillLoading({
    super.key,
    this.state = DrillLoadingState.spinning,
    this.size = 56,
    this.cycle = const Duration(milliseconds: 1600),
    this.onCycleFinished,
    this.probe,
  });

  /// 要去哪个状态；切过去要等当前这一步走完
  final DrillLoadingState state;

  /// 边长；钻头尽量占满，只给弹出的铜粒留一点余量
  final double size;

  /// 走一步的时长（转一次 + 闪一下 + 弹一粒铜）
  final Duration cycle;

  /// 每走完一步回调一次
  final VoidCallback? onCycleFinished;

  /// 读回组件当前的内部状态；传 null 就不用
  ///
  /// 挂起的状态要等这一步走完才轮到它，用它验证 / 同步状态，不必给子组件挂 `GlobalKey<State>`
  final DrillStateProbe? probe;

  @override
  State<DrillLoading> createState() => _DrillLoadingState();
}

/// 组件内部状态的可读镜像；由调用方建好传进 [DrillLoading.probe]
class DrillStateProbe {
  /// 正在生效的状态
  DrillLoadingState active = DrillLoadingState.spinning;

  /// 等这一步走完就切过去的状态；null 表示没有待切
  DrillLoadingState? pending;

  /// 当前这一步走到哪（0~1）
  double step = 0;
}

/// 铜钻头的三种状态
enum DrillLoadingState {
  /// 旋转态：不停转
  spinning,

  /// 结束态：转一次、途中弹铜
  completing,

  /// 错误态：转一次后转红停住
  error,
}

class _DrillLoadingState extends State<DrillLoading>
    with TickerProviderStateMixin {
  /// 一步里起转占的比例，其余作为停顿；一个 [cycle] 正好是"转一次 + 弹一次铜"
  static const double _spinPortion = 0.6;

  /// 一段停顿占的比例
  static const double _spinPausePortion = 1 - _spinPortion;

  /// 过冲幅度：冲过目标角度这么多（弧度），再被"拉"回来
  static const double _spinOvershoot = 0.08;

  /// 过冲峰值出现在这一步的哪个位置
  static const double _spinPeakAt = 0.72;

  /// 铜粒只在这段周期里飞：正好在起转那一段之内，也就是"旋转途中弹出来"
  static const double _chipFrom = 0.32;
  static const double _chipTo = 0.58;

  /// 铜粒落地时的重力下沉量，占钻头半径的比例
  static const double _chipGravity = 0.5;

  /// 掷出方向的水平分量上限：越小越偏正上方
  static const double _chipSpread = 0.35;

  /// 铜粒的掷出方向（弧度）；每步随机一次，但永远朝上
  double _chipAngle = 0;

  /// 掷方向的随机源：固定种子，免得每次重建组件时序列跳
  final math.Random _random = math.Random(20261005);

  /// 闪光衰减后到下一轮起转之间的余量
  static const double _lightTail = 0.2;

  /// 亮点在脉冲之外的常亮底
  static const double _lightFloor = 0.15;

  late final AnimationController _controller;
  late final AnimationController _flashController;

  /// 钻头是否停在"转完了"的位置；只有这里可以切状态
  bool _settled = false;

  /// 是否停在"转完了"那半段；只有这里可以切状态，免得看见半路被打断的钻头
  bool _inPause = false;

  /// 上一帧的步进度，用来认出 `repeat()` 的回卷
  double _lastStepValue = 0;

  /// 正在 / 已经生效的状态
  late DrillLoadingState _mode = widget.state;

  /// 等当前步走完再切过去的状态；null 表示没有待切
  DrillLoadingState? _pendingState;

  /// 钻头转角：一步从 0 转到 90 度
  ///
  /// 过冲长在**收尾**处：一路减速冲过目标角、再被拉回来停住 ——
  /// 读数像"速度来不及停"，而不是"停住了又突然动一下"
  late final TweenSequence<double> _spinSequence = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.0, end: math.pi / 2).chain(
        CurveTween(
          curve: const SingleOvershootCurve(
            overshoot: _spinOvershoot,
            peakAt: _spinPeakAt,
          ),
        ),
      ),
      weight: _spinPortion,
    ),
    TweenSequenceItem(
      tween: Tween(begin: math.pi / 2, end: math.pi / 2),
      weight: _spinPausePortion,
    ),
  ]);

  /// 轮毂亮点的亮度：起转到头时闪到最亮（就是"钻到了"那一下），随后回落
  late final TweenSequence<double> _lightSequence = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: _lightFloor,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: _spinPortion,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: _lightFloor,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 1 - _lightTail,
    ),
    TweenSequenceItem(
      tween: Tween(begin: _lightFloor, end: _lightFloor),
      weight: _lightTail,
    ),
  ]);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.cycle)
      ..addStatusListener(_onStepStatus)
      ..addListener(_onStepTick);
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    )..addListener(_onFlashTick);
    // 起始状态也要走一遍启动逻辑：初始就是结束 / 错误态时，那一步同样得转起来
    _applyMode(widget.state);
  }

  @override
  void didUpdateWidget(covariant DrillLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cycle != widget.cycle) _controller.duration = widget.cycle;
    if (oldWidget.state != widget.state) {
      _requestState(widget.state);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _flashController.dispose();
    super.dispose();
  }

  /// 请求切到 [target]
  ///
  /// 一律先挂起、延到帧后再落地：
  /// - 正在转那半段时，落地要等这一步走完（[_finishStep] 里的 `_canSwitchNow` 把着）
  /// - [didUpdateWidget] 是 build 期间跑的，直接落地会重置控制器、同步回调
  ///   [DrillLoading.onCycleFinished]，父组件在回调里 `setState` 就炸
  ///   "setState() called during build"
  void _requestState(DrillLoadingState target) {
    if (target == _mode && _pendingState == null) return;

    setState(() => _pendingState = target);
    _publishProbe();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = _pendingState;
      if (pending == null || !_canSwitchNow) return;
      _applyMode(pending);
    });
  }

  /// 只有"转完了、停在停顿里"才允许切状态，免得看见半路被打断的钻头
  bool get _canSwitchNow => !_controller.isAnimating || _settled || _inPause;

  /// 把内部状态同步给调用方传进来的 [DrillLoading.probe]
  void _publishProbe() {
    widget.probe
      ?..active = _mode
      ..pending = _pendingState;
  }

  void _applyMode(DrillLoadingState target) {
    // 归零控制器的那一下会同步触发监听器，得挡住（它会把"归零"当成一次回卷）
    _applyingMode = true;
    _mode = target;
    _pendingState = null;
    _settled = false;
    _controller.value = 0;
    _lastStepValue = 0;
    _inPause = false;
    widget.probe?.step = 0;
    _applyingMode = false;

    _publishProbe();
    if (mounted) setState(() {});

    switch (target) {
      case DrillLoadingState.spinning:
        _flashController.reverse();
        _startIfNeeded();
      case DrillLoadingState.completing:
        // 只转一次：转完停在 1，铜粒留在弹出的位置；方向现在就掷定
        _rollChipAngle();
        if (!_controller.isAnimating) _controller.forward(from: 0);
      case DrillLoadingState.error:
        _flashController.forward(from: 0);
        if (!_controller.isAnimating) _controller.forward(from: 0);
    }
  }

  /// 不确定态才需要自己驱动；停下后要等状态切换或 resume 再起
  void _startIfNeeded() {
    if (_mode != DrillLoadingState.spinning) return;
    if (!_controller.isAnimating) _controller.repeat();
  }

  void _onFlashTick() => setState(() {});

  /// 在 [_applyMode] 里把控制器归零的那一下，值也是往回跳，得挡住那次误报
  bool _applyingMode = false;

  /// 每一帧都更新"是否转完了"；`repeat()` 自己回卷、**从不发 completed**，
  /// 所以旋转态的"这一步结束"只能靠值往回跳认出来，切换也在这里落地
  void _onStepTick() {
    final value = _controller.value;
    final wrapped = value < _lastStepValue;
    _lastStepValue = value;
    _inPause = value >= _spinPortion;
    widget.probe?.step = value;
    if (!wrapped || _applyingMode) return;
    // 回卷 = 这一步结束；只跑一次的完成 / 错误态走 status 回调，别报两次
    if (_mode == DrillLoadingState.spinning) _finishStep();
  }

  /// 一步走完：先发回调，再把挂起的切换落地
  void _finishStep() {
    widget.onCycleFinished?.call();
    final pending = _pendingState;
    if (pending != null) {
      _applyMode(pending);
      return;
    }
    if (_mode != DrillLoadingState.spinning) {
      setState(() => _settled = true);
      return;
    }
    // 旋转态：在这一步结束时就把下一粒铜的方向掷好，弹出时直接用
    _rollChipAngle();
  }

  /// 掷下一粒铜的方向：每次随机，但**限定不向下**
  ///
  /// 画布 y 向下，所以 y 分量取负；x 在 [-1, 1] 上随机 ⇒ 水平方向落在 (0°, 180°)，
  /// 也就是只会朝上半圈飞出去
  void _rollChipAngle() {
    final sin = -math.sqrt(1 - _chipSpread * _chipSpread);
    final t = _random.nextDouble() * 2 - 1;
    final x = t * _chipSpread;
    final y = sin * (1 - t.abs());
    _chipAngle = math.atan2(y, x);
  }

  void _onStepStatus(AnimationStatus status) {
    // 只跑一次的完成 / 错误态由状态回调收尾；旋转态走上面的回卷检测
    if (status != AnimationStatus.completed) return;
    if (_mode == DrillLoadingState.spinning) return;
    _finishStep();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isError = _mode == DrillLoadingState.error;
    final tint = isError ? _flashController.value : 0.0;

    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final cycle = _controller.value.clamp(0.0, 1.0);
          // 只有结束态弹铜：错误态是"没钻出东西"，一个铜粒都不出
          final showChip = _mode == DrillLoadingState.completing;
          return CustomPaint(
            painter: _DrillLoadingPainter(
              spin: _spinSequence.transform(cycle),
              light: isError
                  ? _flashController.value
                  : _lightSequence.transform(cycle),
              chipFlight: showChip ? _chipFlight(cycle) : null,
              chipAngle: _chipAngle,
              chipGravity: _chipGravity,
              tint: tint,
              tone: DrillTone.of(context),
              hubColor: isError ? colors.error : colors.interactive,
              drillScale:
                  widget.size * DrillPaint.drillRadiusRatio / DrillPaint.grid,
            ),
          );
        },
      ),
    );
  }

  /// 铜粒的飞行进度；不在弹出窗口内返回 null
  double? _chipFlight(double cycle) {
    if (cycle < _chipFrom) return null;
    return ((cycle - _chipFrom) / (_chipTo - _chipFrom)).clamp(0, 1);
  }
}

class _DrillLoadingPainter extends CustomPainter {
  _DrillLoadingPainter({
    required this.spin,
    required this.light,
    required this.chipFlight,
    required this.chipAngle,
    required this.chipGravity,
    required this.tint,
    required this.tone,
    required this.hubColor,
    required this.drillScale,
  });

  /// 各层描边宽（贴图网格单位）：线条化靠它撑形状，给太粗整块会糊成一片灰
  static const double _baseStrokeWidth = 1.4;
  static const double _bladeStrokeWidth = 1.1;
  static const double _topStrokeWidth = 1.1;

  /// 钻头当前转角（弧度）
  final double spin;

  /// 轮毂亮点的亮度（0~1）
  final double light;

  /// 铜粒飞行进度；null 表示这一步不出铜
  final double? chipFlight;

  /// 铜粒的掷出方向（弧度）
  final double chipAngle;

  /// 铜粒末端的重力下沉量，占钻头半径的比例
  final double chipGravity;

  /// 出错泛红的程度（0~1）
  final double tint;

  final DrillTone tone;

  /// 轮毂亮点的颜色：正常暖色、出错转红
  final Color hubColor;

  final double drillScale;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final drillRadius = size.shortestSide * DrillPaint.drillRadiusRatio;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    _paintBase(canvas);
    _paintBlades(canvas);
    _paintTop(canvas);
    DrillPaint.paintHubLight(canvas, drillScale, hubColor, light);
    _paintChip(canvas, drillRadius);
    canvas.restore();
  }

  /// 底座：八边形台面，四片钻臂都落在它上面
  void _paintBase(Canvas canvas) {
    final plate = DrillPaint.octagon(
      DrillPaint.baseHalf * drillScale,
      DrillPaint.baseCorner * drillScale,
    );
    canvas.drawPath(
      plate,
      Paint()
        ..style = PaintingStyle.fill
        ..color = tone.baseFill,
    );
    canvas.drawPath(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _baseStrokeWidth * drillScale
        ..color = _tintStroke(tone.baseStroke, DrillPaint.errorBaseTint),
    );
  }

  /// 四片钻臂整体绕中心旋转
  ///
  /// 填充画并集；描边画"并集减去内缩并集"的环带，所以交汇处一条线都没有
  void _paintBlades(Canvas canvas) {
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = tone.bladeFill;
    final outline = Paint()
      ..style = PaintingStyle.fill
      ..color = _tintStroke(tone.bladeStroke, DrillPaint.errorBladeTint);

    canvas.save();
    canvas.rotate(spin);
    canvas.scale(drillScale);
    canvas.drawPath(DrillPaint.bladeUnion(), fill);
    canvas.drawPath(DrillPaint.bladeOutline(_bladeStrokeWidth), outline);
    canvas.restore();
  }

  /// 顶盖：压住钻臂的根部，只让伸出顶盖的那一截露出来当"在转的钻头"
  void _paintTop(Canvas canvas) {
    final cap = DrillPaint.octagon(
      DrillPaint.topHalf * drillScale,
      3.5 * drillScale,
    );
    canvas.drawPath(
      cap,
      Paint()
        ..style = PaintingStyle.fill
        ..color = tone.topFill,
    );
    canvas.drawPath(
      cap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _topStrokeWidth * drillScale
        ..color = _tintStroke(tone.topStroke, DrillPaint.errorTopTint),
    );
  }

  /// 铜粒：这一步钻完的产物，从中心按 [_chipAngle] 掷出去，落点受重力往下压
  void _paintChip(Canvas canvas, double drillRadius) {
    final flight = chipFlight;
    if (flight == null) return;

    // 起点贴着轮毂；重力让轨迹在末段往下沉，所以是斜抛不是直线
    // 飞到头正好落在控件内：方向越接近正上方，钻头半径那 0.53 倍就越顶，
    // 所以末段只给到 0.62 个半径，再加 0.5 的重力下沉也在范围内
    final distance = drillRadius * (0.15 + 0.62 * flight);
    final gravity = drillRadius * chipGravity * flight * flight;
    canvas.save();
    canvas.translate(
      distance * math.cos(chipAngle),
      distance * math.sin(chipAngle) + gravity,
    );
    canvas.rotate(flight * math.pi / 3);
    DrillPaint.paintItem(
      canvas,
      drillScale * (1 - 0.4 * flight),
      opacity: 1 - flight,
    );
    canvas.restore();
  }

  Color _tintStroke(Color color, double amount) =>
      DrillPaint.tinted(color, amount * tint);

  @override
  bool shouldRepaint(covariant _DrillLoadingPainter oldDelegate) {
    return oldDelegate.spin != spin ||
        oldDelegate.light != light ||
        oldDelegate.chipFlight != chipFlight ||
        oldDelegate.chipAngle != chipAngle ||
        oldDelegate.chipGravity != chipGravity ||
        oldDelegate.tint != tint ||
        oldDelegate.tone != tone ||
        oldDelegate.hubColor != hubColor ||
        oldDelegate.drillScale != drillScale;
  }
}
