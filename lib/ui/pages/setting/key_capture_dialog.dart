import 'dart:async';

import 'package:copper_launcher/data/mindustry/settings/key_code.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/window_ime.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 弹窗捕获一个键位；用户取消时返回 null
Future<MindustryKeyCode?> showKeyCaptureDialog(
  BuildContext context, {
  required String title,
  String? hint,
}) {
  return showAnimatedDialog<MindustryKeyCode>(
    context: context,
    barrierDismissible: false,
    pageBuilder: (_, _, _) => _KeyCapturePage(title: title, hint: hint),
  );
}

/// 键位捕获页：等一个键盘键 / 鼠标键 / 滚轮，直接返回对应的键码
///
/// 用 [HardwareKeyboard] 的全局处理器收键盘，不依赖焦点；鼠标与滚轮靠铺满
/// 整屏的 [Listener]。只有「取消」按钮那一下不当作按键，其余点击都算
class _KeyCapturePage extends StatefulWidget {
  const _KeyCapturePage({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  State<StatefulWidget> createState() => _KeyCapturePageState();
}

class _KeyCapturePageState extends State<_KeyCapturePage> {
  /// 「取消」按钮的位置：点在它上面时不当作按键捕获
  final GlobalKey _cancelKey = GlobalKey();

  /// 捕获到还不认识的键时给用户的提示
  String? _message;

  /// 是否已经关掉；退出动画还没走完时页面仍然挂着，
  /// 这期间再按一个键或再点一次取消不能再 pop 一次（会把底下那页也 pop 掉）
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
    // 捕获期间不接输入法：先让它把焦点与输入连接放掉，免得上一个输入框
    // 的输入法还在拦按键（中文输入法拦下来时只送 Process 键，绑不了）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _detachInputMethod();
    });
  }

  @override
  void dispose() {
    _restoreInputMethod();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  /// 摘掉输入法：放焦点 + 收起软键盘，再让 runner 把窗口的 IMM32 上下文摘掉
  ///
  /// 桌面端光靠 Dart 侧收不到键：中文输入法会把按键拦成 VK_PROCESSKEY，
  /// Flutter 直接跳过这些下键事件，只能由窗口线程把输入法摘掉
  void _detachInputMethod() {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(
      SystemChannels.textInput
          .invokeMethod<void>('TextInput.hide')
          .catchError((Object _) {}),
    );
    unawaited(
      WindowIme.detach().then((detached) {
        const targets = ['无上下文或非 Windows', '有焦点的窗口', 'Flutter 视图', '顶层窗口'];
        final target = WindowIme.lastTarget;
        final where = target >= 0 && target < targets.length
            ? targets[target]
            : '未知窗口';
        addLog(
          .info,
          '[KeyCapture] 窗口输入法上下文：${detached ? '已摘掉（$where）' : '未摘（$where）'}',
          tag: 'Version',
        );
      }),
    );
  }

  void _restoreInputMethod() => unawaited(WindowIme.restore());

  bool _handleKey(KeyEvent event) {
    if (_closed) return true;
    if (event is! KeyDownEvent) return false;

    // 输入法处理键（中文输入法拦键时送 Process）不当作要绑的键
    if (event.logicalKey == LogicalKeyboardKey.process) return true;

    final code = mindustryKeyCodeNamed(_arcKeyNames[event.logicalKey] ?? '');
    if (code == null) {
      setState(() => _message = '这个键不能绑定，换一个试试');
      return true;
    }
    _finish(code);
    return true;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_closed) return;
    if (_isOnCancelButton(event.position)) return;

    final code = _arcKeyForButtons(event.buttons);
    if (code == null) return;
    _finish(code);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (_closed) return;
    if (event is! PointerScrollEvent) return;
    final code = mindustryKeyCodeNamed('scroll');
    if (code != null) _finish(code);
  }

  /// 点在「取消」按钮上时不捕获；按钮自己处理点击
  bool _isOnCancelButton(Offset position) {
    final box = _cancelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    return (Offset.zero & box.size).contains(box.globalToLocal(position));
  }

  MindustryKeyCode? _arcKeyForButtons(int buttons) {
    if (buttons & kBackMouseButton != 0)
      return mindustryKeyCodeNamed('mouseBack');
    if (buttons & kForwardMouseButton != 0) {
      return mindustryKeyCodeNamed('mouseForward');
    }
    if (buttons & kMiddleMouseButton != 0) {
      return mindustryKeyCodeNamed('mouseMiddle');
    }
    if (buttons & kSecondaryButton != 0) {
      return mindustryKeyCodeNamed('mouseRight');
    }
    if (buttons & kPrimaryButton != 0)
      return mindustryKeyCodeNamed('mouseLeft');
    return null;
  }

  /// 关弹窗只走这一个出口：先摘掉键盘处理器、恢复输入法，再 pop；[code] 为空是取消
  void _finish(MindustryKeyCode? code) {
    if (_closed || !mounted) return;
    _closed = true;
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _restoreInputMethod();
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerSignal: _handlePointerSignal,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Material(
              elevation: 8,
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    top: BorderSide(color: colors.border, width: 1.5),
                    left: BorderSide(color: colors.border, width: 0.75),
                    right: BorderSide(color: colors.border, width: 0.75),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12,
                  children: [
                    Row(
                      spacing: 8,
                      children: [
                        Icon(
                          Icons.keyboard_outlined,
                          color: colors.interactive,
                        ),
                        Expanded(
                          child: Text(
                            '重新绑定',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      '请按一个键',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colors.interactive,
                      ),
                    ),
                    Text(
                      widget.hint ?? '键盘键、鼠标键、滚轮都可以',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.itemSecondary,
                      ),
                    ),
                    if (_message != null)
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ReboundButton(
                        key: _cancelKey,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        backgroundColor: colors.lowBackgroundOnCard,
                        child: Text('取消'),
                        onTap: () => _finish(null),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flutter 逻辑键 → arc `KeyCode` 枚举名
///
/// 只收键盘这一套；游戏里的手柄键不在启动器里改
final Map<LogicalKeyboardKey, String> _arcKeyNames = {
  LogicalKeyboardKey.keyA: 'a',
  LogicalKeyboardKey.keyB: 'b',
  LogicalKeyboardKey.keyC: 'c',
  LogicalKeyboardKey.keyD: 'd',
  LogicalKeyboardKey.keyE: 'e',
  LogicalKeyboardKey.keyF: 'f',
  LogicalKeyboardKey.keyG: 'g',
  LogicalKeyboardKey.keyH: 'h',
  LogicalKeyboardKey.keyI: 'i',
  LogicalKeyboardKey.keyJ: 'j',
  LogicalKeyboardKey.keyK: 'k',
  LogicalKeyboardKey.keyL: 'l',
  LogicalKeyboardKey.keyM: 'm',
  LogicalKeyboardKey.keyN: 'n',
  LogicalKeyboardKey.keyO: 'o',
  LogicalKeyboardKey.keyP: 'p',
  LogicalKeyboardKey.keyQ: 'q',
  LogicalKeyboardKey.keyR: 'r',
  LogicalKeyboardKey.keyS: 's',
  LogicalKeyboardKey.keyT: 't',
  LogicalKeyboardKey.keyU: 'u',
  LogicalKeyboardKey.keyV: 'v',
  LogicalKeyboardKey.keyW: 'w',
  LogicalKeyboardKey.keyX: 'x',
  LogicalKeyboardKey.keyY: 'y',
  LogicalKeyboardKey.keyZ: 'z',
  LogicalKeyboardKey.digit0: 'num0',
  LogicalKeyboardKey.digit1: 'num1',
  LogicalKeyboardKey.digit2: 'num2',
  LogicalKeyboardKey.digit3: 'num3',
  LogicalKeyboardKey.digit4: 'num4',
  LogicalKeyboardKey.digit5: 'num5',
  LogicalKeyboardKey.digit6: 'num6',
  LogicalKeyboardKey.digit7: 'num7',
  LogicalKeyboardKey.digit8: 'num8',
  LogicalKeyboardKey.digit9: 'num9',
  LogicalKeyboardKey.numpad0: 'numpad0',
  LogicalKeyboardKey.numpad1: 'numpad1',
  LogicalKeyboardKey.numpad2: 'numpad2',
  LogicalKeyboardKey.numpad3: 'numpad3',
  LogicalKeyboardKey.numpad4: 'numpad4',
  LogicalKeyboardKey.numpad5: 'numpad5',
  LogicalKeyboardKey.numpad6: 'numpad6',
  LogicalKeyboardKey.numpad7: 'numpad7',
  LogicalKeyboardKey.numpad8: 'numpad8',
  LogicalKeyboardKey.numpad9: 'numpad9',
  LogicalKeyboardKey.numpadAdd: 'plus',
  LogicalKeyboardKey.numpadSubtract: 'minus',
  LogicalKeyboardKey.numpadMultiply: 'asterisk',
  LogicalKeyboardKey.numpadDivide: 'slash',
  LogicalKeyboardKey.numpadDecimal: 'period',
  LogicalKeyboardKey.numpadEqual: 'equals',
  LogicalKeyboardKey.numpadComma: 'comma',
  LogicalKeyboardKey.f1: 'f1',
  LogicalKeyboardKey.f2: 'f2',
  LogicalKeyboardKey.f3: 'f3',
  LogicalKeyboardKey.f4: 'f4',
  LogicalKeyboardKey.f5: 'f5',
  LogicalKeyboardKey.f6: 'f6',
  LogicalKeyboardKey.f7: 'f7',
  LogicalKeyboardKey.f8: 'f8',
  LogicalKeyboardKey.f9: 'f9',
  LogicalKeyboardKey.f10: 'f10',
  LogicalKeyboardKey.f11: 'f11',
  LogicalKeyboardKey.f12: 'f12',
  LogicalKeyboardKey.arrowUp: 'up',
  LogicalKeyboardKey.arrowDown: 'down',
  LogicalKeyboardKey.arrowLeft: 'left',
  LogicalKeyboardKey.arrowRight: 'right',
  LogicalKeyboardKey.shiftLeft: 'shiftLeft',
  LogicalKeyboardKey.shiftRight: 'shiftRight',
  LogicalKeyboardKey.controlLeft: 'controlLeft',
  LogicalKeyboardKey.controlRight: 'controlRight',
  LogicalKeyboardKey.altLeft: 'altLeft',
  LogicalKeyboardKey.altRight: 'altRight',
  LogicalKeyboardKey.backquote: 'backtick',
  LogicalKeyboardKey.minus: 'minus',
  LogicalKeyboardKey.equal: 'equals',
  LogicalKeyboardKey.bracketLeft: 'leftBracket',
  LogicalKeyboardKey.bracketRight: 'rightBracket',
  LogicalKeyboardKey.backslash: 'backslash',
  LogicalKeyboardKey.intlBackslash: 'backslash',
  LogicalKeyboardKey.semicolon: 'semicolon',
  LogicalKeyboardKey.quote: 'apostrophe',
  LogicalKeyboardKey.comma: 'comma',
  LogicalKeyboardKey.period: 'period',
  LogicalKeyboardKey.slash: 'slash',
  LogicalKeyboardKey.space: 'space',
  LogicalKeyboardKey.enter: 'enter',
  LogicalKeyboardKey.numpadEnter: 'enter',
  LogicalKeyboardKey.escape: 'escape',
  LogicalKeyboardKey.tab: 'tab',
  LogicalKeyboardKey.backspace: 'backspace',
  LogicalKeyboardKey.delete: 'del',
  LogicalKeyboardKey.insert: 'insert',
  LogicalKeyboardKey.home: 'home',
  LogicalKeyboardKey.end: 'end',
  LogicalKeyboardKey.pageUp: 'pageUp',
  LogicalKeyboardKey.pageDown: 'pageDown',
  LogicalKeyboardKey.capsLock: 'capsLock',
  LogicalKeyboardKey.printScreen: 'printScreen',
  LogicalKeyboardKey.scrollLock: 'scrollLock',
  LogicalKeyboardKey.pause: 'pause',
  LogicalKeyboardKey.contextMenu: 'application',
  LogicalKeyboardKey.audioVolumeUp: 'volumeUp',
  LogicalKeyboardKey.audioVolumeDown: 'volumeDown',
  LogicalKeyboardKey.audioVolumeMute: 'mute',
  LogicalKeyboardKey.mediaPlayPause: 'mediaPlayPause',
  LogicalKeyboardKey.mediaStop: 'mediaStop',
  LogicalKeyboardKey.mediaTrackNext: 'mediaNext',
  LogicalKeyboardKey.mediaTrackPrevious: 'mediaPrevious',
  LogicalKeyboardKey.mediaFastForward: 'mediaFastForward',
  LogicalKeyboardKey.mediaRewind: 'mediaRewind',
};
