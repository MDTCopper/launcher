import 'dart:async';
import 'dart:ui';

import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// 失败语义的通知图标：这类通知除了弹出来，还会落一条运行日志
///
/// 通知会自动消失，用户关掉 / 错过就查不到原因——失败类一律同时进日志
final _failureNoticeIcons = <IconData>{
  Icons.close,
  Icons.error,
  Icons.error_outline,
  Icons.delete_forever,
};

/// 成功语义的通知图标：不传 [tone] 时据此自动上色
final _successNoticeIcons = <IconData>{
  Icons.check,
  Icons.check_box_outlined,
  Icons.check_circle,
  Icons.check_circle_outline,
  Icons.cloud_done_outlined,
  Icons.download_done,
  Icons.task_alt,
};

/// 警告语义的通知图标
final _warningNoticeIcons = <IconData>{
  Icons.warning,
  Icons.warning_amber,
  Icons.warning_amber_outlined,
  Icons.search_off,
};

/// 失败语义的通知图标
final _errorNoticeIcons = <IconData>{
  Icons.close,
  Icons.error,
  Icons.error_outline,
};

/// 触摸平台把通知放屏幕底部，远离顶栏与刘海；桌面端仍在右上角
bool get _isTouchPlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// 通知语义：决定主色、默认图标与停留时长
///
/// [neutral] 走铜色，[success] / [warning] / [error] 分别取 [AppColors] 的语义色
enum CopperNoticeTone { neutral, success, warning, error }

/// 通知里唯一的动作按钮，比如「重试」「取消」「查看」
class CopperNoticeAction {
  const CopperNoticeAction({required this.label, required this.onPressed});

  final String label;

  final VoidCallback onPressed;
}

/// 进度条：[value] 为 0~1 时是确定进度，为 null 时是不确定进度
///
/// 带进度的通知默认常驻，由 [CopperNoticeHandle.update] / [CopperNoticeHandle.finish]
/// 原地更新，不重新弹一条
class CopperNoticeProgress {
  const CopperNoticeProgress(this.value)
    : assert(value == null || (value >= 0 && value <= 1), '进度必须在 0 到 1 之间');

  const CopperNoticeProgress.indeterminate() : value = null;

  final double? value;
}

/// 一条通知的句柄：用于原地更新进度 / 文案，或主动关掉
class CopperNoticeHandle {
  CopperNoticeHandle._(this._data);

  final _NoticeData _data;

  String get id => _data.id;

  /// [clearProgress] 为 true 时收起进度条，回到普通通知
  void update({
    String? title,
    String? content,
    CopperNoticeProgress? progress,
    CopperNoticeTone? tone,
    bool clearProgress = false,
  }) {
    _data.update(
      title: title,
      content: content,
      progress: progress,
      tone: tone,
      clearProgress: clearProgress,
    );
  }

  /// 长任务收尾：收起进度条、换成结果语义并开始自动消失计时
  void finish({
    String? title,
    String? content,
    CopperNoticeTone tone = CopperNoticeTone.success,
  }) {
    _data.finish(title: title, content: content, tone: tone);
  }

  void dismiss() => _data.requestDismiss();
}

/// 弹一条通知
///
/// 不传 [tone] 时按 [icon] 推断语义，所以现有调用不用改也能拿到对得上的颜色；
/// 传 [action] 会保证至少停留 6 秒，给用户反应时间；传 [progress] 默认常驻
CopperNoticeHandle? addNotice({
  IconData? icon,
  String? title,
  String? content,
  VoidCallback? onTap,
  Duration? duration,
  CopperNoticeTone? tone,
  CopperNoticeAction? action,
  CopperNoticeProgress? progress,
  bool? persistent,
  bool? showClose,
}) => NotificationManager.addNotice(
  icon: icon,
  title: title,
  content: content,
  onTap: onTap,
  duration: duration,
  tone: tone,
  action: action,
  progress: progress,
  persistent: persistent,
  showClose: showClose,
);

/// 弹一条完全自定义内容的通知，外观由 [widget] 自己负责
CopperNoticeHandle? addNoticeWidget({
  required Widget widget,
  VoidCallback? onTap,
  Duration duration = const Duration(seconds: 5),
}) => NotificationManager.addNoticeWidget(
  widget: widget,
  onTap: onTap,
  duration: duration,
);

class NotificationManager {
  static final NotificationManager _instance = NotificationManager._();
  factory NotificationManager() => _instance;
  NotificationManager._(); //保持单例

  static final _uuid = const Uuid();

  static final _globalKey = GlobalKey<_NotificationWidgetState>();
  static final NotificationWidget _widget = NotificationWidget(
    key: _globalKey,
    onDismiss: () {
      try {
        if (_overlayEntry?.mounted ?? false) _overlayEntry?.remove();
      } catch (e) {
        return;
      }
    },
  );

  static OverlayEntry? _overlayEntry;

  /// 当前挂载通知层的 Overlay；换树（热重载 / 测试换 MaterialApp）时据此重插
  static OverlayState? _overlay;

  /// 通知组件还没挂上时先存这里，由组件在 `initState` 里一次取走
  static final _pending = <_NoticeData>[];

  static CopperNoticeHandle? addNotice({
    BuildContext? context,
    IconData? icon,
    String? title,
    String? content,
    VoidCallback? onTap,
    Duration? duration,
    CopperNoticeTone? tone,
    CopperNoticeAction? action,
    CopperNoticeProgress? progress,
    bool? persistent,
    bool? showClose,
  }) {
    final resolvedTone = tone ?? _inferTone(icon);
    final isPersistent = persistent ?? progress != null;
    final effectiveDuration = _effectiveDuration(
      duration: duration,
      tone: resolvedTone,
      action: action,
      persistent: isPersistent,
    );
    final data = _NoticeData(
      id: _uuid.v4(),
      tone: resolvedTone,
      icon: icon,
      title: title,
      content: content,
      onTap: onTap,
      action: action,
      progress: progress,
      persistent: isPersistent,
      showClose:
          showClose ??
          (isPersistent ||
              resolvedTone == CopperNoticeTone.error ||
              resolvedTone == CopperNoticeTone.warning),
      duration: effectiveDuration,
    );

    _logFailure(icon, resolvedTone, title, content);

    context ??= PageKeyProvider.shellKey.currentContext;
    //shell 还没挂上（启动早期 / 退出阶段 / 单测）时静默跳过：这是 fire-and-forget
    //调用，异步里抛出来就是未捕获异常
    if (context == null) return null;
    _ensureOverlay(context);
    _deliver(data);
    return CopperNoticeHandle._(data);
  }

  static CopperNoticeHandle? addNoticeWidget({
    BuildContext? context,
    required Widget widget,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 5),
  }) {
    final data = _NoticeData(
      id: _uuid.v4(),
      customWidget: widget,
      onTap: onTap,
      duration: duration,
    );

    context ??= PageKeyProvider.shellKey.currentContext;
    if (context == null) return null;
    _ensureOverlay(context);
    _deliver(data);
    return CopperNoticeHandle._(data);
  }

  /// 通知层只插一次；同一帧连发多条时不能按 [OverlayEntry.mounted] 判断，
  /// 那时它还没进树，会重复插入、把同一个 GlobalKey 挂到两棵树上
  static void _ensureOverlay(BuildContext context) {
    final overlay = Overlay.of(context);
    if (identical(overlay, _overlay) && _overlayEntry != null) return;
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
    _overlay = overlay;
    _overlayEntry = OverlayEntry(builder: (context) => _buildOverlay(context));
    overlay.insert(_overlayEntry!);
  }

  static void _deliver(_NoticeData data) {
    final state = _globalKey.currentState;
    if (state != null) {
      state.addItem(data);
    } else {
      _pending.add(data);
    }
  }

  /// 组件首次挂载时取走首帧前攒下的通知
  static List<_NoticeData> takePending() {
    final pending = List<_NoticeData>.of(_pending);
    _pending.clear();
    return pending;
  }

  /// 默认时长按语义分档，长文案与错误多留一会儿
  static Duration _defaultDuration(CopperNoticeTone tone) => switch (tone) {
    CopperNoticeTone.success => const Duration(seconds: 3),
    CopperNoticeTone.warning => const Duration(seconds: 6),
    CopperNoticeTone.error => const Duration(seconds: 8),
    CopperNoticeTone.neutral => const Duration(seconds: 5),
  };

  static Duration _effectiveDuration({
    required Duration? duration,
    required CopperNoticeTone tone,
    required CopperNoticeAction? action,
    required bool persistent,
  }) {
    if (persistent) return Duration.zero;
    //显式给零与不写都表示「按语义取默认」，要常驻请用 [persistent]
    final requested = duration;
    var effective = requested == null || requested == Duration.zero
        ? _defaultDuration(tone)
        : requested;
    if (action != null && effective < const Duration(seconds: 6)) {
      effective = const Duration(seconds: 6);
    }
    return effective;
  }

  static CopperNoticeTone _inferTone(IconData? icon) {
    if (icon == null) return CopperNoticeTone.neutral;
    if (_successNoticeIcons.contains(icon)) return CopperNoticeTone.success;
    if (_warningNoticeIcons.contains(icon)) return CopperNoticeTone.warning;
    if (_errorNoticeIcons.contains(icon)) return CopperNoticeTone.error;
    return CopperNoticeTone.neutral;
  }

  static void _logFailure(
    IconData? icon,
    CopperNoticeTone tone,
    String? title,
    String? content,
  ) {
    final isFailure =
        tone == CopperNoticeTone.error ||
        (icon != null && _failureNoticeIcons.contains(icon));
    if (!isFailure) return;
    //消息先压成一行，异常原文常带换行
    final message = [
      title,
      content,
    ].whereType<String>().where((text) => text.isNotEmpty).join('：');
    if (message.isEmpty) return;
    addLog(.error, removeNewlines(message), tag: 'Notice');
  }

  /// 桌面贴右上角、让开 40 高的顶栏；触摸平台贴底部并让开系统手势区
  static Widget _buildOverlay(BuildContext context) {
    final touch = _isTouchPlatform;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return Positioned.fill(
      child: Padding(
        padding: touch
            ? EdgeInsets.fromLTRB(
                AppSpacing.group,
                AppSpacing.group,
                AppSpacing.group,
                safeBottom + AppSpacing.group,
              )
            : const EdgeInsets.only(top: 56, right: AppSpacing.group),
        child: Align(
          alignment: touch ? Alignment.bottomCenter : Alignment.topRight,
          child: _widget,
        ),
      ),
    );
  }
}

class NotificationWidget extends StatefulWidget {
  final VoidCallback onDismiss;

  const NotificationWidget({super.key, required this.onDismiss});

  @override
  State<StatefulWidget> createState() => _NotificationWidgetState();
}

class _NotificationWidgetState extends State<NotificationWidget> {
  /// 同时最多留几条；超出时先收掉最早的非常驻通知
  static const _maxVisible = 4;

  final _itemList = <_NoticeData>[];

  @override
  void initState() {
    super.initState();
    //首帧前攒下的通知也要过一遍上限，不能直接 addAll
    for (final data in NotificationManager.takePending()) {
      _append(data);
    }
  }

  void addItem(_NoticeData data) {
    if (!mounted || data.removalRequested) return;
    setState(() => _append(data));
  }

  /// 入队并执行上限：超出时先收掉最早的非常驻通知
  void _append(_NoticeData data) {
    if (data.removalRequested) return;
    if (_itemList.length >= _maxVisible) {
      final index = _itemList.indexWhere(
        (item) => !item.persistent && !item.removalRequested,
      );
      if (index >= 0) _itemList[index].requestDismiss();
    }
    _itemList.add(data);
  }

  /// 移除指定 id 的通知（定时器 / 滑动 / 点击共同入口）
  void _removeById(String id) {
    final index = _itemList.indexWhere((item) => item.id == id);
    if (index < 0) return;
    setState(() {
      _itemList.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final touch = _isTouchPlatform;
    return Container(
      constraints: BoxConstraints(maxWidth: touch ? double.infinity : 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: touch
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.end,
        children: [
          for (final item in _itemList)
            // key 必须落在 Column 的直接 children 上：藏在包装里时，
            // 删中间一条会让后面那条按 index 复用包装层、被重建并重播入场动画
            _NoticeItem(
              key: ValueKey(item.id),
              data: item,
              touchLayout: touch,
              onRemove: () => _removeById(item.id),
            ),
        ],
      ),
    );
  }
}

/// 通知条目：自持入场 / 退场动画 + 右滑删除 + 悬停暂停计时
///
/// - **入场**：仅 滑入 + 淡入（无展开动画），播完保持显示；桌面从右侧进、
///   触摸平台从下方进
/// - **退场**：分段 —— 点击先缩小（scale 1.0→0.92）→ 停顿 → 滑出+淡出 →
///   最后占位收缩（SizeTransition，下方通知才上移）
/// - **右滑删除**：跟手右移，超过 [dismissDistance] 松手即退场删除；
///   未超阈值松手回弹恢复（无删除背景层）
/// - 定时器到期也走同一退场路径，`onRemove` 只在退场动画结束后触发一次
class _NoticeItem extends StatefulWidget {
  final _NoticeData data;
  final bool touchLayout;
  final VoidCallback onRemove;

  const _NoticeItem({
    super.key,
    required this.data,
    required this.touchLayout,
    required this.onRemove,
  });

  @override
  State<_NoticeItem> createState() => _NoticeItemState();
}

class _NoticeItemState extends State<_NoticeItem>
    with TickerProviderStateMixin {
  static const _kEnterDuration = Duration(milliseconds: 280);
  static const _kPressDuration = Duration(milliseconds: 300);
  static const _kSwipeDuration = Duration(milliseconds: 300);
  static const _kShrinkDuration = Duration(milliseconds: 200);
  static const _kPressWait = Duration(milliseconds: 100);

  static const Curve _kEnterPositionCurve = Curves.easeOutBack;

  static const Curve _kEnterOpacityCurve = Curves.easeOutCubic;

  static const Curve _kPressCurve = Curves.easeOutCubic;

  static const Curve _kSwipeCurve = Curves.easeInCubic;

  static const Curve _kShrinkCurve = Curves.easeOutCubic;

  static const Curve _kDragBackCurve = Curves.easeOutBack;

  late final AnimationController _controller;

  late final AnimationController _pressController;

  late final AnimationController _swipeController;

  late final AnimationController _shrinkController;

  Timer? _waitTimer;

  /// 滑动未达阈值时的归位动画（_dragX 从当前位置缓慢回 0）
  late final AnimationController _dragBackController;
  late final Animation<double> _dragBackCurve;
  double _dragBackStart = 0;

  /// 退场动画结束后由父级移除本条目
  bool _removing = false;

  /// 是否由点击触发退场（点击删除先小段缩小，像被按下一样）；
  /// 滑动 / 定时触发无缩小段
  bool _byTap = false;
  Timer? _timer;

  /// 自动消失剩余时间；悬停时暂停，移开后接着走
  Duration _remaining = Duration.zero;
  DateTime _timerStartedAt = DateTime.now();
  bool _hovered = false;

  /// 右滑删除：手势累计偏移（正值右移）
  double _dragX = 0;

  /// 滑动删除阈值（px）
  static const _dismissDistance = 100.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _kEnterDuration);
    // 退场阶段 1：点击缩小（非点击直接用阶段 2）
    _pressController =
        AnimationController(vsync: this, duration: _kPressDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              // 缩小完成 → 停顿 _kPressWait → 划出淡化
              _waitTimer?.cancel();
              _waitTimer = Timer(_kPressWait, _startSwipe);
            }
          });
    // 退场阶段 2：划出 + 淡化 → 紧随占位收缩
    _swipeController =
        AnimationController(vsync: this, duration: _kSwipeDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _startShrink();
          });
    // 退场阶段 3：占位收缩 → 移除
    _shrinkController =
        AnimationController(vsync: this, duration: _kShrinkDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              widget.onRemove();
            }
          });
    // 滑动归位：easeOut 曲线从 _dragBackStart 缓慢收拢回 0
    _dragBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _dragBackCurve = CurvedAnimation(
      parent: _dragBackController,
      curve: _kDragBackCurve,
    );
    _dragBackController.addListener(() {
      setState(() {
        _dragX = _dragBackStart * (1 - _dragBackCurve.value);
      });
    });
    widget.data.addListener(_onDataChanged);
    // 首帧布局后播放入场（避免布局期间动画触发 paint）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
    if (widget.data.removalRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _remove());
    } else {
      _startTimer();
    }
  }

  @override
  void dispose() {
    widget.data.removeListener(_onDataChanged);
    _timer?.cancel();
    _waitTimer?.cancel();
    _controller.dispose();
    _pressController.dispose();
    _swipeController.dispose();
    _shrinkController.dispose();
    _dragBackController.dispose();
    super.dispose();
  }

  /// 进度 / 文案原地更新：刷新内容，必要时按新时长重新计时
  void _onDataChanged() {
    if (!mounted) return;
    if (widget.data.removalRequested) {
      _remove();
      return;
    }
    if (widget.data.restartTimer) {
      widget.data.restartTimer = false;
      _startTimer();
    }
    setState(() {});
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = null;
    _remaining = widget.data.duration;
    if (widget.data.persistent || _hovered) return;
    _timerStartedAt = DateTime.now();
    _timer = Timer(_remaining, () => _remove());
  }

  void _onHover(bool hovered) {
    if (_hovered == hovered) return;
    _hovered = hovered;
    if (widget.data.persistent) return;
    if (hovered) {
      _pauseTimer();
    } else {
      _resumeTimer();
    }
  }

  void _pauseTimer() {
    final timer = _timer;
    if (timer == null || !timer.isActive) return;
    final elapsed = DateTime.now().difference(_timerStartedAt);
    _remaining -= elapsed;
    if (_remaining < Duration.zero) _remaining = Duration.zero;
    timer.cancel();
    _timer = null;
  }

  void _resumeTimer() {
    if (_removing || _remaining <= Duration.zero) return;
    if (_timer?.isActive ?? false) return;
    _timerStartedAt = DateTime.now();
    _timer = Timer(_remaining, () => _remove());
  }

  void _remove({bool byTap = false}) {
    if (!mounted || _removing) return;
    widget.data.removalRequested = true;
    _timer?.cancel(); // 点击后自动消失计时器失效；其它删除路径同样停表
    _timer = null;
    _dragBackController.stop();
    setState(() {
      _removing = true;
      _byTap = byTap;
      // 保留 _dragX：退场 Slide 从当前滑动位置继续
    });
    if (_byTap) {
      _pressController.forward(from: 0);
    } else {
      _startSwipe();
    }
  }

  void _startSwipe() {
    if (!mounted || !_removing) return;
    _swipeController.forward(from: 0);
  }

  void _startShrink() {
    if (!mounted || !_removing) return;
    _shrinkController.forward(from: 0);
  }

  // ─── 右滑删除手势 ───

  void _onDragUpdate(DragUpdateDetails d) {
    if (_removing) return;
    _dragBackController.stop();
    setState(() {
      // delta.dx 是单帧增量，必须累计；否则 item 只动一下就被"定格"
      _dragX = (_dragX + d.delta.dx).clamp(0.0, _dismissDistance * 1.5);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_removing) return;
    if (_dragX >= _dismissDistance) {
      _remove();
    } else {
      // 未达阈值：缓慢归位
      _dragBackStart = _dragX;
      _dragBackController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final beginOffset = widget.touchLayout
        ? const Offset(0, 0.35)
        : const Offset(0.35, 0);
    final enterPosition = Tween(begin: beginOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: _kEnterPositionCurve),
    );

    final pressScale = _removing && _byTap
        ? Tween(begin: 1.0, end: 0.92).animate(
            CurvedAnimation(parent: _pressController, curve: _kPressCurve),
          )
        : const AlwaysStoppedAnimation(1.0);
    final enterOpacity = CurvedAnimation(
      parent: _controller,
      curve: _kEnterOpacityCurve,
    );

    final swipePosition = _removing
        ? Tween(begin: Offset.zero, end: beginOffset).animate(
            CurvedAnimation(parent: _swipeController, curve: _kSwipeCurve),
          )
        : const AlwaysStoppedAnimation(Offset.zero);

    final shrinkSize = _removing
        ? Tween(begin: 1.0, end: 0.0).animate(
            CurvedAnimation(parent: _shrinkController, curve: _kShrinkCurve),
          )
        : const AlwaysStoppedAnimation(1.0);

    // 合成：入场用 _controller（forward）；退场各阶段用独立 controller
    final swipeOpacity = _removing
        ? Tween(begin: 1.0, end: 0.0).animate(
            CurvedAnimation(parent: _swipeController, curve: _kSwipeCurve),
          )
        : const AlwaysStoppedAnimation(1.0);
    final opacity = _removing ? swipeOpacity : enterOpacity;
    final position = _removing ? swipePosition : enterPosition;
    final sizeFactor = _removing
        ? shrinkSize
        : const AlwaysStoppedAnimation(1.0);
    final scale = _removing ? pressScale : const AlwaysStoppedAnimation(1.0);

    // 视觉变换（Fade / Slide / Scale）只作用于通知卡片本身；
    // SizeTransition / 底部分隔放在最外层，见下方 return
    Widget content = FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: position,
        child: ScaleTransition(scale: scale, child: _buildBody(context)),
      ),
    );

    // ── 左滑删除 ──
    // _dragX 保留至退场：滑动删除时退场 Slide 从当前位置继续向左，
    // 点击/定时删除时 _dragX=0 从原位起飞
    content = Transform.translate(offset: Offset(_dragX, 0), child: content);

    // 点击/滑动区只覆盖卡片本身
    final Widget item = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.data.onTap?.call();
        // 常驻通知靠关闭按钮退场，避免手滑点掉还在跑的任务
        if (!widget.data.persistent) _remove(byTap: true);
      },
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: MouseRegion(
        onEnter: (_) => _onHover(true),
        onExit: (_) => _onHover(false),
        child: Semantics(
          // 进度每次跳动都播报会吵，收尾时去掉进度再交给 liveRegion
          liveRegion: widget.data.progress == null,
          container: true,
          child: content,
        ),
      ),
    );

    return SizeTransition(
      sizeFactor: sizeFactor,
      //纵向收缩不动宽度 ⇒ 这一层的盒子仍占满宽度；桌面把卡片靠右贴边，
      //触摸平台居中（药丸贴内容宽，不铺满）
      alignment: widget.touchLayout
          ? Alignment.center
          : const Alignment(1.0, -1.0),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.related + 4),
        child: item,
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final custom = widget.data.customWidget;
    if (custom != null) return custom;
    if (widget.data.isCompact) return _buildCompact(context);
    return _buildPanel(context);
  }

  // ─── 构建组件 ───

  /// 标题一行就能说清的短确认：细长药丸，不占一整张卡
  Widget _buildCompact(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final data = widget.data;
    final toneColor = _toneColor(colors, data.tone);
    final icon = data.icon;
    return _buildSurface(
      accent: toneColor,
      pill: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.group,
          vertical: AppSpacing.related,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: AppIconSize.inline, color: toneColor),
              const SizedBox(width: AppSpacing.tight),
            ],
            Flexible(
              child: Text(
                data.title!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.itemPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 需要解释 / 动作 / 进度的通知走卡片
  Widget _buildPanel(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final data = widget.data;
    final toneColor = _toneColor(colors, data.tone);
    final icon = data.icon ?? _defaultIcon(data.tone);

    final children = <Widget>[];
    if (data.title != null) {
      children.add(
        Text(
          data.title!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.itemPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (data.content != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.tight - 2));
      }
      children.add(
        Text(
          data.content!,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.itemSecondary,
          ),
        ),
      );
    }
    if (data.action != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.tight),
          child: Align(
            alignment: Alignment.centerRight,
            child: _buildAction(data.action!, toneColor),
          ),
        ),
      );
    }
    if (data.progress != null) {
      children.add(_buildProgress(data.progress!, toneColor));
    }

    return _buildSurface(
      accent: toneColor,
      pill: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.group,
          AppSpacing.related + 2,
          AppSpacing.related,
          AppSpacing.related + 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: AppIconSize.item, color: toneColor),
              ),
              const SizedBox(width: AppSpacing.related),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
            if (data.showClose) ...[
              const SizedBox(width: AppSpacing.tight),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _buildCloseButton(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAction(CopperNoticeAction action, Color toneColor) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: () {
        action.onPressed();
        _remove(byTap: true);
      },
      style: TextButton.styleFrom(
        foregroundColor: toneColor,
        minimumSize: Size(
          0,
          widget.touchLayout ? AppControlHeight.item : AppControlHeight.compact,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.related),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(action.label),
    );
  }

  Widget _buildCloseButton() {
    final colors = AppColors.of(context);
    final size = widget.touchLayout ? 40.0 : 24.0;
    return IconButton(
      onPressed: _remove,
      tooltip: '关闭',
      icon: const Icon(Icons.close),
      iconSize: widget.touchLayout ? 18 : 16,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      style: IconButton.styleFrom(
        foregroundColor: colors.itemHint,
        hoverColor: colors.splash,
      ),
    );
  }

  Widget _buildProgress(CopperNoticeProgress progress, Color toneColor) {
    final colors = AppColors.of(context);
    final value = progress.value;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.related),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: value ?? 0),
                duration: const Duration(milliseconds: 240),
                builder: (context, animated, _) => LinearProgressIndicator(
                  value: value == null ? null : animated,
                  minHeight: 4,
                  color: toneColor,
                  backgroundColor: toneColor.withAlpha(40),
                ),
              ),
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: AppSpacing.related),
            Text(
              '${(value * 100).round()}%',
              style: TextStyle(fontSize: 11, color: colors.itemSecondary),
            ),
          ],
        ],
      ),
    );
  }

  /// 悬浮卡片：半透明卡面 + 细描边；卡片左侧一道语义色，颜色由 [accent] 给
  Widget _buildSurface({
    required Color accent,
    required Widget child,
    required bool pill,
  }) {
    final colors = AppColors.of(context);
    final radius = BorderRadius.circular(
      pill ? AppRadius.item : AppRadius.panel,
    );
    return Material(
      color: Colors.transparent,
      elevation: pill ? 2 : 4,
      shadowColor: colors.shadow,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 6,
          sigmaY: 6,
          tileMode: TileMode.mirror,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.cardBackground.withAlpha(240),
            borderRadius: radius,
            border: Border.all(color: colors.border),
          ),
          child: pill
              ? child
              : ClipRRect(
                  borderRadius: radius,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: SizedBox(
                          width: 3,
                          child: ColoredBox(color: accent),
                        ),
                      ),
                      child,
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _NoticeData extends ChangeNotifier {
  _NoticeData({
    required this.id,
    this.customWidget,
    this.tone = CopperNoticeTone.neutral,
    this.icon,
    this.title,
    this.content,
    this.onTap,
    this.action,
    this.progress,
    this.persistent = false,
    this.showClose = false,
    this.duration = const Duration(seconds: 5),
  });

  final String id;

  final Widget? customWidget;

  CopperNoticeTone tone;

  IconData? icon;

  String? title;

  String? content;

  VoidCallback? onTap;

  CopperNoticeAction? action;

  CopperNoticeProgress? progress;

  bool persistent;

  bool showClose;

  Duration duration;

  /// 退场请求：定时器 / 关闭按钮 / 溢出清理都走它
  bool removalRequested = false;

  /// 内容更新后是否重置自动消失计时
  bool restartTimer = false;

  /// 一行标题、没有正文与动作的短确认走药丸
  bool get isCompact =>
      customWidget == null &&
      title != null &&
      content == null &&
      action == null &&
      progress == null &&
      !showClose;

  void update({
    String? title,
    String? content,
    CopperNoticeProgress? progress,
    CopperNoticeTone? tone,
    bool clearProgress = false,
  }) {
    if (title != null) this.title = title;
    if (content != null) this.content = content;
    if (tone != null) this.tone = tone;
    if (clearProgress) {
      this.progress = null;
    } else if (progress != null) {
      this.progress = progress;
    }
    restartTimer = true;
    notifyListeners();
  }

  /// 进度收尾：收起进度条、换成结果语义、恢复自动消失
  void finish({
    String? title,
    String? content,
    required CopperNoticeTone tone,
  }) {
    this.tone = tone;
    if (title != null) this.title = title;
    if (content != null) this.content = content;
    progress = null;
    persistent = false;
    duration = tone == CopperNoticeTone.error
        ? const Duration(seconds: 8)
        : const Duration(seconds: 4);
    restartTimer = true;
    notifyListeners();
  }

  void requestDismiss() {
    if (removalRequested) return;
    removalRequested = true;
    notifyListeners();
  }
}

/// 语义色：中性走铜色，其余取 [AppColors] 的语义色
Color _toneColor(AppColors colors, CopperNoticeTone tone) => switch (tone) {
  CopperNoticeTone.neutral => colors.interactive,
  CopperNoticeTone.success => colors.success,
  CopperNoticeTone.warning => colors.warning,
  CopperNoticeTone.error => colors.error,
};

/// 只传了语义、没传图标时的兜底图标；中性保持「无图标」的旧样子
IconData? _defaultIcon(CopperNoticeTone tone) => switch (tone) {
  CopperNoticeTone.success => Icons.check_circle_outline,
  CopperNoticeTone.warning => Icons.warning_amber_outlined,
  CopperNoticeTone.error => Icons.error_outline,
  CopperNoticeTone.neutral => null,
};
