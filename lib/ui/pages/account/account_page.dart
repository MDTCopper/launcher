import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/mindustry/player_colors.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/input/color_picker.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/percent_bar.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/components/setting_bar/input_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

const accountPageRouteKey = '/account';

/// 账户页：**游戏内身份**（名字 / 颜色）+ **社区身份**（BBS 账号）
///
/// - 游戏内身份是**全局一份**（存 `config.setting.gameUsers` 里当前选中的那条），
///   启动前按开关覆写进 `settings.bin`（`uuid` 是联机身份，不覆写）
/// - 社区身份走 MDTBBS：登录后显示用户名与头像；云存档、联机、好友都用它
/// - 登录与游戏内身份**互不依赖**：没登录也能改名字与颜色
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _nameController = TextEditingController();

  int _color = defaultPlayerColor;
  bool _override = true;
  bool _busy = false;
  MdtbbsAccount? _account;
  CloudSaveQuota? _quota;

  AccountManager get _accounts => AccountManager.instance;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAccount());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ── 游戏内身份 ──

  void _loadIdentity() {
    final user = config.setting.currentGameUser;
    _nameController.text = user?.name ?? '';
    _color = resolvePlayerColor(user?.color ?? 0);
    _override =
        config.setting.getCustomSetting('game_user_override', true) == true;
  }

  void _saveIdentity() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      addNotice(icon: Icons.close, title: '保存失败', content: '游戏内名称不能为空');
      return;
    }

    // 全局一份身份：没有就建一条并选中
    var user = config.setting.currentGameUser;
    if (user == null) {
      user = GameUser(
        id: 'account_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        uuid: '',
        color: _color,
      );
      config.setting.gameUsers.add(user);
    }
    user.name = name;
    user.color = _color;
    config.setting.selectGameUser(user);
    config.save();

    addLog(
      .info,
      '游戏内身份：$name（颜色 ${_color.toRadixString(16)}）',
      tag: 'Account',
    );
    addNotice(icon: Icons.check, title: '已保存游戏内身份', content: name);
    if (mounted) setState(() {});
  }

  void _setOverride(bool value) {
    config.setting.customSetting['game_user_override'] = value;
    config.save();
    setState(() => _override = value);
  }

  /// 名字颜色：预设 16 色 + 自定义取色，都在一个弹窗里
  Future<void> _pickColor() async {
    final picked = await showAnimatedDialog<int>(
      context: context,
      pageBuilder: (_, _, _) => _ColorPaletteDialog(color: _color),
    );
    if (picked == null || !mounted) return;
    setState(() => _color = picked);
  }

  // ── 社区身份 ──

  Future<void> _loadAccount() async {
    final accounts = _accounts;
    if (!accounts.isConfigured) return;
    try {
      await accounts.restore();
      if (!accounts.isLoggedIn) return;
      final account = await accounts.loadAccount();
      final token = await accounts.ensureAccessToken();
      final quota = token == null
          ? null
          : await CloudSaveService.quota(accessToken: token);
      if (!mounted) return;
      setState(() {
        _account = account;
        _quota = quota;
      });
      // 名字还空着就拿 BBS 用户名当默认（用户自己改过就听用户的）
      if (_nameController.text.trim().isEmpty) {
        final username = account.username;
        if (username != null && username.isNotEmpty) {
          setState(() => _nameController.text = username);
        }
      }
    } catch (error) {
      addLog(.warning, '账户页读账号失败：${removeNewlines('$error')}', tag: 'Account');
    }
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      await _accounts.login();
      if (!mounted) return;
      addNotice(icon: Icons.check, title: '已登录 BBS');
      await _loadAccount();
    } catch (error) {
      if (!mounted) return;
      addNotice(
        icon: Icons.close,
        title: '登录没成功',
        content: removeNewlines('$error'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _logout() {
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '退出 BBS 账号？',
      content: '会撤销这个启动器的登录凭证并清掉本地账号信息；云端存档不受影响',
      action: () async {
        await _accounts.logout();
        if (!mounted) return;
        setState(() => _account = null);
        addNotice(icon: Icons.logout, title: '已退出登录');
      },
    );
  }

  // ── 构建 ──

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        _buildIdentityPanel(),
        _buildCommunityPanel(),
        _buildQuotaPanel(),
        _buildCloudSavePanel(),
      ],
    );
  }

  Widget _buildIdentityPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '游戏内身份',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          InputSettingBar(
            title: '游戏内名称',
            controller: _nameController,
            titleWide: 96,
          ),
          Row(
            spacing: 12,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: arcToColor(_color),
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.border),
                ),
              ),
              Text(
                '#${arcToColor(_color).toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                style: theme.textTheme.bodyMedium,
              ),
              const Spacer(),
              IconTextButton(
                icon: Icons.palette_outlined,
                content: '选择颜色',
                onTap: _pickColor,
              ),
            ],
          ),
          SwitchSettingBar(
            title: '启动前覆写',
            wide: 96,
            value: _override,
            onChanged: _setOverride,
          ),
          Text(
            _override
                ? '启动游戏前，把这里的名称与颜色写进 settings.bin（uuid 是联机身份，不动）'
                : '不覆写：游戏里的名称与颜色自己说了算',
            style: theme.textTheme.labelMedium,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconTextButton(
              icon: Icons.save_outlined,
              content: '保存身份',
              onTap: _saveIdentity,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final account = _account;

    if (!_accounts.isConfigured) {
      return ContentPanelModule(
        title: '社区账号',
        child: Text(
          '这个构建没配 BBS client_id，社区功能不可用',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.itemHint),
        ),
      );
    }

    if (account == null) {
      return ContentPanelModule(
        title: '社区账号',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(
              '登录 BBS 后可以同步存档、联机、加好友；'
              '登录在系统浏览器里完成，启动器不接触你的密码。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
            Row(
              spacing: 12,
              children: [
                IconTextButton(
                  icon: Icons.login,
                  content: '登录 BBS',
                  onTap: _busy ? null : _login,
                ),
                if (_busy)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return ContentPanelModule(
      title: '社区账号',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 12,
            children: [
              _buildAvatar(account),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      account.username ?? account.subject,
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (account.phoneVerified == false)
                      Text(
                        '手机号未验证（云端写操作会被拒）',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.error,
                        ),
                      ),
                  ],
                ),
              ),
              IconTextButton(icon: Icons.logout, content: '退出', onTap: _logout),
            ],
          ),
          Text(
            '云存档、联机与好友都用这个账号；好友等社区功能接入后再放这里',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }

  /// 云端用量（登录后才有）
  Widget _buildQuotaPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final quota = _quota;

    return ContentPanelModule(
      title: '云端用量',
      child: quota == null
          ? Text(
              _accounts.isLoggedIn ? '读取中…' : '登录后显示',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemHint,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                PercentBar(
                  total: (quota.limitBytes ?? 1).toDouble(),
                  dataList: [
                    PercentBarData(value: (quota.usedBytes ?? 0).toDouble()),
                  ],
                ),
                Text(
                  '${formatBytes(quota.usedBytes ?? 0)} / '
                  '${formatBytes(quota.limitBytes ?? 0)}'
                  '　槽位 ${quota.slotsUsed ?? 0}/${quota.slotsLimit ?? 0}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.itemSecondary,
                  ),
                ),
                Text(
                  '单个云包上限 ${formatBytes(quota.maxFileSizeBytes ?? 0)}；'
                  '模组默认只记清单不带字节（带字节很容易超上限）',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.itemHint,
                  ),
                ),
                if (quota.maxUnpinnedVersionsPerSlot != null ||
                    quota.maxUnpinnedAgeDays != null)
                  Text(
                    '未固定的快照：最多保留 '
                    '${quota.maxUnpinnedVersionsPerSlot ?? '?'} 版 / '
                    '${quota.maxUnpinnedAgeDays ?? '?'} 天；要长期留就固定它',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.itemHint,
                    ),
                  ),
              ],
            ),
    );
  }

  /// 云存档：按**当前选中版本**启用
  ///
  /// 开关按数据目录记（同步单元就是它），共用一份目录的版本共用同一个开关 —— 那种
  /// 情况必须写清楚，不然用户会以为「这是这个版本自己的设置」
  Widget _buildCloudSavePanel() {
    final theme = Theme.of(context);
    final version = config.versionOptions.selectedVersion;

    if (version == null) {
      return ContentPanelModule(
        title: '云存档',
        child: Text(
          '先在主页选一个游戏版本——云存档是按版本的数据目录来的',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final enabled = CloudSaveService.isEnabled(version);
    final shared =
        CloudSaveService.versionsSharingDataPath(
          version,
          config.versionOptions.versionFolds.expand((fold) => fold.versions),
        ) -
        1;
    return ContentPanelModule(
      title: '云存档',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          SwitchSettingBar(
            title: '启用云存档',
            value: enabled,
            onChanged: (value) => _setCloudEnabled(version, value),
          ),
          Text('当前版本：${version.tag}', style: theme.textTheme.labelMedium),
          if (shared > 0)
            Text(
              '这个版本与其他 $shared 个版本共用数据目录，开关是这份目录的',
              style: theme.textTheme.labelMedium,
            ),
          Text('上传 / 恢复在「版本设置 → 云存档」里', style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }

  void _setCloudEnabled(Mindustry version, bool value) {
    CloudSaveService.setEnabled(version, value);
    setState(() {});
    addLog(
      .info,
      '[${version.tag}] 云存档${value ? '开启' : '关闭'}，数据目录：${version.dataPath}',
      tag: 'Cloud',
    );
  }

  Widget _buildAvatar(MdtbbsAccount account) {
    final colors = AppColors.of(context);
    final avatar = account.avatar;
    final fallback = Icon(
      Icons.account_circle,
      size: 48,
      color: colors.itemSecondary,
    );

    return ClipOval(
      child: SizedBox(
        width: 48,
        height: 48,
        child: avatar == null || avatar.isEmpty
            ? fallback
            : Image.network(
                avatar,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// 名字颜色弹窗：预设色 + 自定义取色
class _ColorPaletteDialog extends StatelessWidget {
  const _ColorPaletteDialog({required this.color});

  final int color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final current = resolvePlayerColor(color);

    return Center(
      child: Material(
        elevation: 8,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border(top: BorderSide(color: colors.border, width: 1.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text('名字颜色', style: theme.textTheme.titleMedium),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in playerColors)
                    _ColorDot(
                      color: arcToColor(preset),
                      selected: preset == current,
                      onTap: () => Navigator.pop(context, preset),
                    ),
                ],
              ),
              Row(
                spacing: 12,
                children: [
                  IconTextButton(
                    icon: Icons.colorize,
                    content: '自定义',
                    onTap: () async {
                      final picked = await showColorPickerDialog(
                        context: context,
                        initialColor: arcToColor(current),
                      );
                      if (picked == null || !context.mounted) return;
                      Navigator.pop(context, colorToArc(picked));
                    },
                  ),
                  IconTextButton(
                    icon: Icons.restart_alt,
                    content: '游戏默认',
                    onTap: () => Navigator.pop(context, defaultPlayerColor),
                  ),
                  const Spacer(),
                  IconTextButton(
                    icon: Icons.close,
                    content: '取消',
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 色点
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, this.selected = false, this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ReboundContainer(
      borderRadius: BorderRadius.circular(20),
      backgroundColor: Colors.transparent,
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colors.interactive : colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 16,
                color:
                    ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black,
              )
            : null,
      ),
    );
  }
}
