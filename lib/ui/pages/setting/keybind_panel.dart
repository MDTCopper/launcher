import 'dart:io';

import 'package:copper_launcher/data/mindustry/settings/key_code.dart';
import 'package:copper_launcher/data/mindustry/settings/keybind_metadata.dart';
import 'package:copper_launcher/data/mindustry/settings/keybind_settings.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

import 'key_capture_dialog.dart';

/// 游戏内键位编辑
///
/// 键位存在游戏 `settings.bin` 的 `keybind-default-keyboard-<名>-*` 键里，
/// 与启动器其它设置项不同：这里**直接改**选中版本的 settings.bin，
/// 不经过启动器自己的覆盖补丁（键位要跟着云存档整份同步）
class KeybindPanel extends StatefulWidget {
  const KeybindPanel({super.key, required this.version, required this.specs});

  final Mindustry version;
  final List<KeybindSpec> specs;

  @override
  State<StatefulWidget> createState() => _KeybindPanelState();
}

class _KeybindPanelState extends State<KeybindPanel> {
  late MindustrySettings _settings;

  /// 文件在、但解不开：一律不给改，免得把玩家的其它设置写坏
  bool _unreadable = false;

  /// 这个版本还没跑过游戏，改键位会新建 settings.bin
  bool _missingFile = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant KeybindPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.version.id != widget.version.id) _load();
  }

  void _load() {
    final path = widget.version.settingPath;
    _missingFile = !File(path).existsSync();
    _settings = MindustrySettings.fromFile(path);
    _unreadable = !_settings.readable;
  }

  // ── 读写 ──

  /// 某个键位当前的自定义值；null = 游戏默认
  MindustryKeybindValue? _valueOf(KeybindSpec spec) =>
      _settings.keybindValue(spec.name);

  bool get _hasCustom =>
      widget.specs.any((spec) => _settings.keybindValue(spec.name) != null);

  /// 单键键位写回；[ordinal] 是 arc KeyCode 序号
  Future<void> _writeSingle(KeybindSpec spec, int ordinal) async {
    _settings.setKeybindSingle(spec.name, ordinal);
    await _save('${spec.title} → ${_labelOf(ordinal)}');
  }

  /// 轴键位写回：只换一侧，另一侧保持当前值（没自定义就用默认）
  Future<void> _writeAxis(
    KeybindSpec spec, {
    required bool maxSide,
    required int ordinal,
  }) async {
    final current = _valueOf(spec);
    final fallbackMin = _ordinalOfName(spec.defaultKey);
    final fallbackMax = _ordinalOfName(spec.defaultKeyMax ?? spec.defaultKey);
    final min = maxSide ? (current?.min ?? fallbackMin) : ordinal;
    final max = maxSide ? ordinal : (current?.max ?? fallbackMax);
    _settings.setKeybindAxis(spec.name, min, max);
    await _save('${spec.title} → ${_labelOf(min)} / ${_labelOf(max)}');
  }

  Future<void> _save(String action) async {
    //先按内存里的新值刷新界面，写盘失败再读回磁盘上的真实状态
    if (mounted) setState(() => _missingFile = false);
    try {
      await _settings.saveAsync();
      addLog(.info, '[${widget.version.tag}] 键位已写入：$action', tag: 'Version');
    } catch (e) {
      addNotice(
        icon: Icons.close,
        title: '保存键位失败',
        content: '写入 settings.bin 失败，键位没有改动',
      );
      addLog(
        .error,
        '[${widget.version.tag}] 保存键位失败：$action，${removeNewlines('$e')}',
        tag: 'Version',
      );
      if (mounted) setState(_load);
    }
  }

  Future<void> _reset(KeybindSpec spec) async {
    _settings.resetKeybind(spec.name);
    await _save('${spec.title} 恢复默认');
  }

  Future<void> _resetAll() async {
    for (final spec in widget.specs) {
      _settings.resetKeybind(spec.name);
    }
    await _save('全部键位恢复默认');
  }

  // ── 捕获 ──

  Future<void> _captureSingle(KeybindSpec spec) async {
    if (_unreadable) return;
    final code = await showKeyCaptureDialog(
      context,
      title: spec.title,
      hint: '键盘键、鼠标键、滚轮都可以；想取消请点下面的按钮',
    );
    if (code == null || !mounted) return;
    await _writeSingle(spec, code.ordinal);
  }

  Future<void> _captureAxis(KeybindSpec spec, {required bool maxSide}) async {
    if (_unreadable) return;
    final code = await showKeyCaptureDialog(
      context,
      title: '${spec.title}（${maxSide ? '正方向' : '负方向'}）',
      hint: '键盘键、鼠标键、滚轮都可以；想取消请点下面的按钮',
    );
    if (code == null || !mounted) return;
    await _writeAxis(spec, maxSide: maxSide, ordinal: code.ordinal);
  }

  void _confirmResetAll() {
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '恢复默认键位',
      content: '把 ${widget.specs.length} 个键位都恢复成游戏默认值？',
      action: () => _resetAll(),
    );
  }

  // ── 显示值 ──

  String _labelOf(int ordinal) =>
      mindustryKeyCodeOf(ordinal)?.label ?? '键码 $ordinal';

  int _ordinalOfName(String name) =>
      mindustryKeyCodeNamed(name)?.ordinal ?? mindustryUnsetKeyOrdinal;

  /// 单键键位显示的文字：自定义优先，否则是目录里的默认键
  String _singleLabel(KeybindSpec spec) {
    final value = _valueOf(spec);
    if (value == null) return _labelOf(_ordinalOfName(spec.defaultKey));
    if (value.isAxis) {
      return '${_labelOf(value.min!)} / ${_labelOf(value.max!)}';
    }
    return _labelOf(value.key!);
  }

  /// 轴键位某一侧的序号
  int _axisOrdinal(KeybindSpec spec, {required bool maxSide}) {
    final value = _valueOf(spec);
    if (value != null && value.isAxis) {
      return maxSide ? value.max! : value.min!;
    }
    final fallback = maxSide
        ? (spec.defaultKeyMax ?? spec.defaultKey)
        : spec.defaultKey;
    return _ordinalOfName(fallback);
  }

  // ── 构建 ──

  Widget _buildKeyChip({
    required String label,
    required bool customized,
    required VoidCallback onTap,
  }) {
    final colors = AppColors.of(context);
    final borderRadius = BorderRadius.circular(4);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: customized ? colors.interactive : colors.border,
        ),
      ),
      child: ReboundContainer(
        borderRadius: borderRadius,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        backgroundColor: colors.highBackgroundOnCard,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: customized ? colors.interactive : colors.itemPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(KeybindSpec spec) {
    final colors = AppColors.of(context);
    final customized = _valueOf(spec) != null;

    final resetButton = ReboundButton(
      padding: const EdgeInsets.all(2),
      margin: const EdgeInsets.only(left: 4),
      backgroundColor: colors.cardBackground,
      child: Icon(
        Icons.settings_backup_restore,
        size: 18,
        color: customized ? colors.interactive : colors.itemHint,
      ),
      onTap: customized ? () => _reset(spec) : null,
    );

    return Row(
      spacing: 8,
      children: [
        Expanded(child: Text(spec.title)),
        if (spec.axis) ...[
          _buildKeyChip(
            label: _labelOf(_axisOrdinal(spec, maxSide: false)),
            customized: customized,
            onTap: () => _captureAxis(spec, maxSide: false),
          ),
          _buildKeyChip(
            label: _labelOf(_axisOrdinal(spec, maxSide: true)),
            customized: customized,
            onTap: () => _captureAxis(spec, maxSide: true),
          ),
        ] else
          _buildKeyChip(
            label: _singleLabel(spec),
            customized: customized,
            onTap: () => _captureSingle(spec),
          ),
        resetButton,
      ],
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.itemSecondary,
    );

    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('改动直接写入这个数据目录的 settings.bin，游戏下次启动生效', style: hintStyle),
              if (Platform.isAndroid) Text('移动端大多数键位无法使用', style: hintStyle),
              if (_missingFile) Text('还没有这个文件，改键位会新建一份', style: hintStyle),
              if (_unreadable)
                Text(
                  'settings.bin 读不出来，暂不能改键位',
                  style: hintStyle?.copyWith(color: colors.error),
                ),
            ],
          ),
        ),
        ReboundButton(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          backgroundColor: colors.lowBackgroundOnCard,
          child: Text(
            '全部恢复默认',
            style: TextStyle(
              color: _hasCustom ? colors.itemPrimary : colors.itemHint,
            ),
          ),
          onTap: _hasCustom ? _confirmResetAll : null,
        ),
      ],
    );
  }

  /// 按分组排好的行；组标题只在组第一行前出现
  List<Widget> _buildRows() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final rows = <Widget>[];
    KeybindGroup? group;

    for (final spec in widget.specs) {
      if (spec.group != group) {
        group = spec.group;
        rows.add(
          Padding(
            padding: EdgeInsets.only(top: rows.isEmpty ? 4 : 12, bottom: 2),
            child: Text(
              group.title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.interactive,
              ),
            ),
          ),
        );
      }
      rows.add(_buildRow(spec));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_buildHeader(), if (!_unreadable) ..._buildRows()],
    );
  }
}
