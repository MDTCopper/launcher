import 'package:flutter/material.dart';

/// 启动游戏时盖住启动器的一层主题色：淡入、显示启动阶段，游戏画面出来后淡出
///
/// 游戏窗口是另一个 Activity；它盖上来之前，启动器这一层已经是纯色，玩家看不到
/// 启动器界面在切换动画里被截到一半的样子。
class LaunchVeil {
  LaunchVeil._();

  static final ValueNotifier<LaunchVeilState> state = ValueNotifier(
    const LaunchVeilState(),
  );

  /// 当前主题的页面背景色；桥里的同色罩子用它，避免启动器罩子与游戏窗口之间露出黑
  static Color? backgroundColor;

  static DateTime? _shownAt;

  static void show(String status) {
    _shownAt = DateTime.now();
    state.value = LaunchVeilState(visible: true, status: status);
  }

  static void update(String status) {
    final current = state.value;
    if (!current.visible) {
      show(status);
      return;
    }
    if (current.status == status) return;
    state.value = LaunchVeilState(visible: true, status: status);
  }

  static void hide() {
    _shownAt = null;
    final current = state.value;
    if (!current.visible) return;
    state.value = LaunchVeilState(visible: false, status: current.status);
  }

  /// 启动很快时也让淡入至少走完，否则只闪一帧
  static Future<void> ensureVisibleFor(Duration duration) async {
    final shownAt = _shownAt;
    if (shownAt == null) return;
    final elapsed = DateTime.now().difference(shownAt);
    if (elapsed < duration) {
      await Future<void>.delayed(duration - elapsed);
    }
  }
}

class LaunchVeilState {
  const LaunchVeilState({this.visible = false, this.status = ''});

  final bool visible;
  final String status;
}

/// 挂在 `MaterialApp.builder` 上，盖住 navigator、弹窗和辅助输入条
class LaunchVeilHost extends StatefulWidget {
  const LaunchVeilHost({super.key, required this.child});

  final Widget child;

  @override
  State<LaunchVeilHost> createState() => _LaunchVeilHostState();
}

class _LaunchVeilHostState extends State<LaunchVeilHost>
    with WidgetsBindingObserver {
  bool _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      // 从游戏回来：游戏已经退出，启动罩不该再留着
      _wasBackgrounded = false;
      LaunchVeil.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    LaunchVeil.backgroundColor = theme.scaffoldBackgroundColor;
    return ValueListenableBuilder<LaunchVeilState>(
      valueListenable: LaunchVeil.state,
      child: widget.child,
      builder: (context, veil, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            child!,
            AbsorbPointer(
              absorbing: veil.visible,
              child: IgnorePointer(
                ignoring: !veil.visible,
                child: AnimatedOpacity(
                  opacity: veil.visible ? 1 : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  child: ColoredBox(
                    color: theme.scaffoldBackgroundColor,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              veil.status,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '请稍候…',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
