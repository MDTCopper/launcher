import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'template_overlay.dart';
import 'template_skin.dart';
import 'template_widgets.dart';

/// 键帽：一个小圆角方块显示一个键名（Esc / Ctrl / F5 …）
class TemplateKeycap extends StatelessWidget {
  const TemplateKeycap({
    super.key,
    required this.skin,
    required this.label,
    this.size = 26,
    this.accent = false,
  });

  final TemplateSkin skin;
  final String label;
  final double size;

  /// 按下 / 强调时用主题色
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      padding: const EdgeInsets.symmetric(horizontal: TemplateSpace.sm),
      decoration: BoxDecoration(
        color: accent ? skin.accentTint : skin.sunken,
        borderRadius: BorderRadius.circular(TemplateRadius.control),
        border: Border.all(color: accent ? Colors.transparent : skin.border),
      ),
      // Center(widthFactor: 1) 按内容收窄：只给 alignment 会在 Wrap 里被拉满整行
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          label,
          style: TemplateType.micro.copyWith(
            color: accent ? skin.onAccentTint : skin.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 组合键：几个键帽用 `+` 连起来（`Ctrl` + `Shift` + `K`）
class TemplateKeyCombo extends StatelessWidget {
  const TemplateKeyCombo({
    super.key,
    required this.skin,
    required this.keys,
    this.emptyLabel = '未绑定',
    this.size = 26,
  });

  final TemplateSkin skin;
  final List<String> keys;
  final String emptyLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (keys.isEmpty) {
      return Text(
        emptyLabel,
        style: TemplateType.caption.copyWith(color: skin.textTertiary),
      );
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: TemplateSpace.xs,
      runSpacing: TemplateSpace.xs,
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0)
            Text(
              '+',
              style: TemplateType.micro.copyWith(color: skin.textTertiary),
            ),
          TemplateKeycap(skin: skin, label: keys[i], size: size),
        ],
      ],
    );
  }
}

/// 键位捕获面板：点开始后监听键盘，按下组合键即回报
///
/// 覆盖度审计 P1-16（现有 App 的键位捕获弹窗）；`Esc` 取消、只按修饰键不算数
class TemplateKeyCapture extends StatefulWidget {
  const TemplateKeyCapture({
    super.key,
    required this.skin,
    this.initial = const <String>[],
    this.onCaptured,
  });

  final TemplateSkin skin;
  final List<String> initial;

  /// 捕获完成回调；取消时为 null
  final ValueChanged<List<String>?>? onCaptured;

  @override
  State<TemplateKeyCapture> createState() => _TemplateKeyCaptureState();
}

class _TemplateKeyCaptureState extends State<TemplateKeyCapture> {
  final _focusNode = FocusNode();
  final Set<String> _pressed = <String>{};
  bool _listening = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  String _label(LogicalKeyboardKey key) {
    // 优先用按键自带的显示名（中文输入法下也稳定），没有就退回调试名
    final label = key.keyLabel;
    if (label.isNotEmpty) return label;
    return key.debugName ?? '未知键';
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_listening) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _listening = false);
      widget.onCaptured?.call(null);
      return KeyEventResult.handled;
    }

    final label = _label(key);
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (_isModifier(key)) {
        setState(() => _pressed.add(label));
      } else {
        setState(() {
          _pressed.add(label);
          _listening = false;
        });
        widget.onCaptured?.call(_pressed.toList());
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      setState(() => _pressed.remove(label));
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  bool _isModifier(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final shown = _listening && _pressed.isNotEmpty
        ? _pressed.toList()
        : widget.initial;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: TemplateSpace.md,
              vertical: TemplateSpace.lg,
            ),
            decoration: BoxDecoration(
              color: skin.sunken,
              borderRadius: BorderRadius.circular(TemplateRadius.card),
              border: Border.all(
                color: _listening ? skin.accent : skin.border,
                width: _listening ? 2 : 1,
              ),
            ),
            child: Center(
              child: _listening
                  ? Text(
                      _pressed.isEmpty ? '按下要绑定的键…' : '松开完成绑定',
                      style: TemplateType.item.copyWith(
                        color: skin.textSecondary,
                      ),
                    )
                  : TemplateKeyCombo(skin: skin, keys: shown, size: 30),
            ),
          ),
          Row(
            spacing: TemplateSpace.sm,
            children: [
              Expanded(
                child: Text(
                  _listening ? 'Esc 取消 · 只按修饰键不会结束' : '点「开始捕获」后按下组合键',
                  style: TemplateType.micro.copyWith(color: skin.textTertiary),
                ),
              ),
              TemplateButton(
                skin: skin,
                label: _listening ? '取消' : '开始捕获',
                icon: _listening ? Icons.close : Icons.keyboard,
                kind: TemplateButtonKind.plain,
                onTap: () {
                  setState(() {
                    _listening = !_listening;
                    _pressed.clear();
                  });
                  _focusNode.requestFocus();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 弹出键位捕获对话框：返回捕获到的组合键，取消返回 null
Future<List<String>?> showTemplateKeyCapture(
  BuildContext context, {
  required TemplateSkin skin,
  String title = '设置快捷键',
  List<String> initial = const <String>[],
}) {
  List<String>? captured;
  return showDialog<List<String>?>(
    context: context,
    barrierColor: skin.barrier,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(TemplateSpace.xl),
      child: TemplateDialog(
        skin: skin,
        icon: Icons.keyboard,
        title: title,
        content: TemplateKeyCapture(
          skin: skin,
          initial: initial,
          onCaptured: (keys) {
            if (keys == null) {
              Navigator.of(dialogContext).pop();
            } else {
              Navigator.of(dialogContext).pop(keys);
            }
          },
        ),
        actions: [
          TemplateButton(
            skin: skin,
            label: '关闭',
            icon: Icons.close,
            kind: TemplateButtonKind.quiet,
            onTap: () => Navigator.of(dialogContext).pop(captured),
          ),
        ],
      ),
    ),
  );
}
