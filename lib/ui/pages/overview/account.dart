import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/data/mindustry_settings.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/action_slide_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/menu_layer.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';

import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:flutter/material.dart';

///账户管理页路由（左侧主导航「概览 > 账户」）。
const accountPageRouteKey = '/user';

///账户管理页面。
///
///页面首先读取当前选中版本的 settings.bin 中的玩家信息
///（`name` / `uuid` / `color-0`）作为临时用户信息，可编辑后保存为账户；
///账户保存在 config（[Setting.accounts]）中。
///账户项支持：点击选择、左滑露出删除、右键/长按弹出操作菜单。
///启动游戏时，选中的账户会自动覆盖 settings 的相关字段。
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<StatefulWidget> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  ///当前选中的游戏版本（其 settings.bin 作为临时用户信息来源）。
  Mindustry? get _mindustry => config.versionOptions.selectedVersion;

  final _nameController = TextEditingController();
  final _uuidController = TextEditingController();
  int _color = 0;

  @override
  void initState() {
    super.initState();
    _loadFromSetting();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _uuidController.dispose();
    super.dispose();
  }

  ///读取当前版本 settings.bin（失败或未选择版本时返回 null）。
  MindustrySettings? _readSetting() {
    final mindustry = _mindustry;
    if (mindustry == null) return null;
    return MindustrySettings.fromFile(mindustry.settingPath);
  }

  ///从 settings 载入临时用户信息。
  void _loadFromSetting() {
    final setting = _readSetting();
    _nameController.text = setting?.name ?? '';
    _uuidController.text = setting?.uuid ?? '';
    _color = setting?.color0 ?? 0;
  }

  ///把临时用户信息保存为新账户并选中。
  void _saveAccount() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('账户名称不能为空')));
      return;
    }
    final account = Account(
      id: 'acc_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      uuid: _uuidController.text.trim(),
      color: _color,
    );
    config.setting.accounts.add(account);
    config.setting.selectAccount(account);
    config.save();
    setState(() {});
  }

  void _selectAccount(Account account) {
    config.setting.selectAccount(account);
    config.save();
    setState(() {});
  }

  void _deleteAccount(Account account) {
    config.setting.accounts.remove(account);
    if (config.setting.currentAccountId == account.id) {
      config.setting.currentAccountId = '';
    }
    config.save();
    setState(() {});
  }

  ///把账户信息载入临时编辑区。
  void _loadToEdit(Account account) {
    _nameController.text = account.name;
    _uuidController.text = account.uuid;
    _color = account.color;
    setState(() {});
  }

  // ── 临时用户信息区 ──

  Widget _buildTemporaryPanel() {
    return ContentPanelModule(
      title: '临时用户信息',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: OutlinedTextField(
                  label: '玩家名',
                  controller: _nameController,
                ),
              ),
              Expanded(
                child: OutlinedTextField(
                  label: '玩家 UUID',
                  controller: _uuidController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('名字颜色'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in _presetColors)
                _ColorDot(
                  color: _arcToFlutter(color),
                  selected: _color == color,
                  onTap: () => setState(() => _color = color),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              IconTextButton(
                icon: Icons.save_outlined,
                content: '保存为账户',
                onTap: _saveAccount,
              ),
              IconTextButton(
                icon: Icons.refresh,
                content: '从设置重新载入',
                onTap: () => setState(_loadFromSetting),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 已保存账户区 ──

  Widget _buildAccountsPanel() {
    final accounts = config.setting.accounts;
    final currentId = config.setting.currentAccountId;

    return ContentPanelModule(
      title: '已保存账户（启动时自动使用选中的账户）',
      child: accounts.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '暂无账户，在上方填写临时信息后点击「保存为账户」',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final account in accounts)
                  _buildAccountItem(account, current: account.id == currentId),
              ],
            ),
    );
  }

  Widget _buildAccountItem(Account account, {required bool current}) {
    final colors = AppColors.of(context);

    // 行内容：色点 + 名称/UUID + 选中标记
    Widget row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _ColorDot(
            color: _arcToFlutter(account.color),
            size: 28,
            selected: current,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  style: TextStyle(
                    color: _arcToFlutter(account.color),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  account.uuid.isEmpty ? '（无 UUID）' : account.uuid,
                  style: TextStyle(color: colors.itemHint, fontSize: 12),
                ),
              ],
            ),
          ),
          if (current)
            Icon(Icons.check_circle, color: colors.interactive)
          else
            Icon(Icons.radio_button_unchecked, color: colors.itemHint),
        ],
      ),
    );

    // 整行点击选择
    row = ReboundButton(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(8),
      onTap: () => _selectAccount(account),
      child: row,
    );

    // 左滑露出删除按钮（移动端风格）
    row = ActionSlideLayer(
      actions: [
        SizedBox(
          width: 64,
          child: Container(
            color: colors.error,
            alignment: Alignment.center,
            child: ReboundButton(
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(0),
              onTap: () => _deleteAccount(account),
              child: Icon(Icons.delete_outline, color: Colors.white),
            ),
          ),
        ),
      ],
      child: row,
    );

    // 右键 / 长按弹出操作菜单（桌面端风格）
    // key 标识账户：删除某项后 Flutter 按 key 复用 Element，
    // 避免 ActionSlideLayer 的打开状态串到下一个组件。
    return MenuLayer(
      key: ValueKey(account.id),
      child: row,
      menuBuilder: (context, controller) => [
        _menuItem(
          context,
          icon: Icons.check,
          label: '设为当前',
          onTap: () {
            _selectAccount(account);
            controller.dismiss();
          },
        ),
        _menuItem(
          context,
          icon: Icons.edit_outlined,
          label: '载入到编辑',
          onTap: () {
            _loadToEdit(account);
            controller.dismiss();
          },
        ),
        _menuItem(
          context,
          icon: Icons.delete_outline,
          label: '删除',
          danger: true,
          onTap: () {
            _deleteAccount(account);
            controller.dismiss();
          },
        ),
      ],
    );
  }

  Widget _menuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final colors = AppColors.of(context);
    final color = danger ? colors.error : colors.itemPrimary;
    return SizedBox(
      width: 120,
      child: ReboundButton(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildTemporaryPanel(),
        const SizedBox(height: 12),
        _buildAccountsPanel(),
      ],
    );
  }
}

///预设名字颜色（arc `rgba8888` 编码：0xRRGGBBAA）。
const _presetColors = <int>[
  0xFFFFFFFF, // 白
  0xFF0000FF, // 红
  0xFF8800FF, // 橙
  0xFFFF00FF, // 黄
  0x00FF00FF, // 绿
  0x00FFFFFF, // 青
  0x0000FFFF, // 蓝
  0xFF00DDFF, // 品红
  0xAAAAAAFF, // 灰
  0x3B2F2FFF, // 深棕
];

///arc 0xRRGGBBAA → Flutter Color。
///
/// arc `rgba8888` 的字节布局：R << 24 | G << 16 | B << 8 | A。
Color _arcToFlutter(int arc) => Color.fromARGB(
  arc & 0xFF,
  (arc >> 24) & 0xFF,
  (arc >> 16) & 0xFF,
  (arc >> 8) & 0xFF,
);

///颜色圆点（选择器与账户列表共用）。
class _ColorDot extends StatelessWidget {
  final Color color;
  final double size;
  final bool selected;
  final VoidCallback? onTap;

  const _ColorDot({
    required this.color,
    this.size = 40,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? colors.interactive : colors.border,
          width: selected ? 3 : 1,
        ),
      ),
    );
    if (onTap == null) return dot;
    return ReboundButton(
      borderRadius: BorderRadius.circular(size / 2),
      onTap: onTap,
      child: dot,
    );
  }
}
