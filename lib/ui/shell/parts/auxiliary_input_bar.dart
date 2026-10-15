import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 输入法上方那条全局辅助输入条
///
/// 启动器在 Android 上不让输入法改动自己的尺寸，输入改由这条承接：
/// 哪个输入框聚焦，条里显示的就是哪个框的内容，在条里打字等于在那个框里打字
/// 条浮在键盘上沿，原输入框被键盘盖住也能看清自己在输什么
class AuxiliaryInputBar extends StatefulWidget {
  const AuxiliaryInputBar({super.key, required this.child});

  final Widget child;

  /// 密码框与只读框不接管：前者的内容不能镜像到这条公开的条上
  static bool accepts(EditableTextState state) =>
      !state.widget.obscureText && !state.widget.readOnly;

  @override
  State<AuxiliaryInputBar> createState() => _AuxiliaryInputBarState();
}

/// 条的显隐与落点：接管到了输入框、且输入法真在屏上时才浮出来
typedef _BarState = ({bool visible, double keyboardInset});

class _AuxiliaryInputBarState extends State<AuxiliaryInputBar> {
  final inputController = TextEditingController();
  final inputFocusNode = FocusNode(debugLabel: '辅助输入条');

  final barState = ValueNotifier<_BarState>((visible: false, keyboardInset: 0));

  /// 收起 / 弹出的动画时长
  static const barAnimationDuration = Duration(milliseconds: 180);

  /// 当前接管的输入框
  EditableTextState? holder;

  /// 双向同步的互触发保护：两边写的是同一份内容，回调会互相触发
  bool syncing = false;

  /// 焦点可能在 build / dispose 途中变化，刷新统一挪到帧后
  bool refreshScheduled = false;

  /// 上一帧条是不是可见：用来抓「键盘被系统收起」那一瞬
  bool wasVisible = false;

  /// 条要浮在 navigator 之上（弹窗里的输入框也得接管），
  /// 而 EditableText 的选区把手 / 菜单要一个 Overlay 祖先，
  /// 所以自带一个只装这条的 Overlay，挂在 navigator 的旁边而不是里面
  late final OverlayEntry barEntry = OverlayEntry(builder: _buildBarHost);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChanged);
    inputController.addListener(_pushToHolder);
    _handleFocusChanged();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChanged);
    _detachHolder();
    inputController.dispose();
    inputFocusNode.dispose();
    barState.dispose();
    super.dispose();
  }

  /// 接管对象已经销毁时拿不到内容，别去碰它那份控制器
  TextEditingController? get holderController =>
      holder != null && holder!.mounted ? holder!.widget.controller : null;

  // ── 接管 ──

  void _handleFocusChanged() {
    // 条自己拿到焦点：接管对象不变，不然点条的那一瞬就丢目标了
    if (FocusManager.instance.primaryFocus == inputFocusNode) return;

    final next = _editableOf(FocusManager.instance.primaryFocus);
    if (next == holder) return;

    _detachHolder();
    holder = next;
    if (next != null) {
      next.widget.controller.addListener(_pullFromHolder);
      _pullFromHolder();
    }
    _scheduleRefresh();
  }

  EditableTextState? _editableOf(FocusNode? node) {
    final state = node?.context?.findAncestorStateOfType<EditableTextState>();
    return state != null && AuxiliaryInputBar.accepts(state) ? state : null;
  }

  void _detachHolder() {
    // removeListener 允许对已销毁的控制器调用，正好用来兜住「输入框先销毁」那一档
    holder?.widget.controller.removeListener(_pullFromHolder);
    holder = null;
  }

  // ── 双向同步 ──

  void _pullFromHolder() {
    if (syncing) return;
    final value = holderController?.value;
    if (value == null) return;

    syncing = true;
    inputController.value = value;
    syncing = false;
  }

  void _pushToHolder() {
    if (syncing) return;
    final controller = holderController;
    if (controller == null) return;

    syncing = true;
    // 组字范围只属于各自那条输入连接，别带给对方
    controller.value = inputController.value.copyWith(
      composing: TextRange.empty,
    );
    syncing = false;
  }

  // ── 交互 ──

  /// 收起输入：两边焦点一起放掉
  ///
  /// 只放条自己的不够 —— 原输入框还握着焦点时会自己把输入法再请求回来
  void _finish() => _releaseFocus();

  /// 放掉条与原输入框的焦点
  ///
  /// 键盘被系统收起（输入法自己的退出键 / 返回）时不放焦点的话，
  /// 条被摘掉那一刻焦点会甩回原输入框，输入法又被拉起来
  void _releaseFocus() {
    if (inputFocusNode.hasFocus) inputFocusNode.unfocus();
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary != inputFocusNode) primary.unfocus();
  }

  /// 键盘自己收起了：等这一帧走完再放焦点
  ///
  /// 现在放的话条还在树上、动画也还没播，放到帧后正好赶在条被摘掉之前
  void _scheduleFocusRelease() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _releaseFocus();
    });
  }

  void _scheduleRefresh() {
    if (refreshScheduled) return;
    refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refreshScheduled = false;
      if (mounted) setState(() {});
    });
  }

  // ── 构建 ──

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    // 条只借键盘上方那块地方，启动器自己的布局一动不动
    final visible = holder != null && keyboardInset > 0;
    // 键盘被系统收起（输入法自己的退出键 / 返回）时，趁条还在树上先把焦点放掉
    if (wasVisible && !visible) _scheduleFocusRelease();
    wasVisible = visible;
    barState.value = (visible: visible, keyboardInset: keyboardInset);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(child: Overlay(initialEntries: [barEntry])),
      ],
    );
  }

  Widget _buildBarHost(BuildContext context) {
    return ValueListenableBuilder<_BarState>(
      valueListenable: barState,
      builder: (context, state, _) {
        // 用 AnimatedSwitcher 而不是直接换成 SizedBox：收起要滑下去、淡出去，
        // 而且退场那几帧条还挂在树上（焦点正好在这段时间里被放掉）
        return AnimatedSwitcher(
          duration: barAnimationDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.25),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: state.visible
              ? Align(
                  key: const ValueKey('bar'),
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: state.keyboardInset),
                    child: _buildInputBar(),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('bar-hidden')),
        );
      },
    );
  }

  Widget _buildInputBar() {
    final colors = AppColors.of(context);
    // 横屏时挖孔在左右两侧，条里的输入别伸进挖孔
    final safe = MediaQuery.viewPaddingOf(context);

    return Material(
      color: colors.cardBackground,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colors.border,
              width: AppBorderWidth.hairline,
            ),
          ),
        ),
        padding: EdgeInsets.only(
          left: safe.left + AppSpacing.group,
          right: safe.right + AppSpacing.group,
          top: AppSpacing.related,
          bottom: AppSpacing.related,
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedTextField(
                controller: inputController,
                focusNode: inputFocusNode,
                onEditingComplete: _finish,
              ),
            ),
            const SizedBox(width: AppSpacing.related),
            ActionButton(content: const Text('完成'), onTap: _finish),
          ],
        ),
      ),
    );
  }
}
