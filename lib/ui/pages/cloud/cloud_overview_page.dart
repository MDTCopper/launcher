import 'dart:async';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/cloud/cloud_save_service.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/domain/tasks/cloud_pull_task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_action_field.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_entry.dart';
import 'package:copper_launcher/ui/components/percent_bar.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/dialog/cloud_tag_conflict_dialog.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/pages/cloud/version_cloud_save_page.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:flutter/material.dart';

/// 账户抽屉里的「云存档」：只管**总开关**与容量
///
/// 按版本的启用 / 快照 / 调试都在「版本云存档管理」里，不在这儿重复
class CloudOverviewPage extends StatefulWidget {
  const CloudOverviewPage({super.key});

  @override
  State<CloudOverviewPage> createState() => _CloudOverviewPageState();
}

class _CloudOverviewPageState extends State<CloudOverviewPage> {
  CloudSaveQuota? _quota;
  bool _loading = false;

  AccountManager get _accounts => AccountManager.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    if (!_accounts.isLoggedIn) {
      setState(() => _quota = null);
      return;
    }
    setState(() => _loading = true);
    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) return;
      final quota = await CloudSaveService.quota(accessToken: token);
      if (mounted) setState(() => _quota = quota);
    } on Object {
      // 容量读不到不影响开关，静默
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CopperSingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.block),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.group,
          children: [
            _buildSwitchPanel(),
            _buildQuotaPanel(),
            _buildDefaultPanel(),
            _buildPullPanel(),
          ],
        ),
      ),
    );
  }

  /// 默认存档常驻行：它不绑实例，未上传也要让玩家看得到
  Widget _buildDefaultPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final version = config.versionOptions.selectedVersion;
    final state = version == null ? null : CloudSaveService.localState(version);
    final usable = version != null && !version.isolation;
    return ContentPanelModule(
      title: '默认存档',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          Text(
            usable
                ? (state == null
                      ? '还没上传；默认存档在云端唯一，不绑定实例'
                      : '已上传到云端；默认存档不绑定实例')
                : '默认存档属于未隔离的数据目录；切到一个未隔离版本再管理',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconTextButton(
              pressedScale: 0.96,
              icon: Icons.tune,
              content: '打开版本云存档管理',
              onTap: () => Navigator.pushNamed(
                context,
                versionCloudSavePageRouteKey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 从云端拉取：账号下任意一份存档拉回它已绑定的实例；没实例就新建
  Widget _buildPullPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final slots = _cloudSlots;
    return ContentPanelModule(
      title: '从云端拉取',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          Text(
            _pullTargetHint(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconTextButton(
              pressedScale: 0.96,
              icon: Icons.cloud_download_outlined,
              content: _loadingSlots
                  ? '读取中…'
                  : (slots == null ? '查看云端存档' : '重新读取'),
              onTap: (_loadingSlots || !_accounts.isLoggedIn)
                  ? null
                  : () => unawaited(_loadSlotsForPull()),
            ),
          ),
          if (slots != null && slots.isEmpty)
            Text(
              '账号下还没有任何云端存档',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemHint,
              ),
            ),
          for (final slot in slots ?? const <CloudSaveSlot>[])
            ContextMenuActionField(
              menuBuilder: (context) {
                final profile = _boundProfileOfSlot(slot);
                final boundTag = _boundTagOfSlot(slot);
                final isBound = boundTag != null;
                final isDefaultSlot =
                    slot.name.contains('默认存档') || profile == 'default';
                final currentVersion = config.versionOptions.selectedVersion;
                final boundToCurrent =
                    currentVersion != null &&
                    profile != null &&
                    profile == CloudSaveService.profileIdOf(currentVersion);
                return [
                  ContextMenuHeader(
                    isDefaultSlot
                        ? '默认存档'
                        : isBound
                        ? '已绑定：${_shortTag(boundTag)}'
                        : '未绑定本地版本',
                  ),
                  ContextMenuAction(
                    label: isDefaultSlot
                        ? '拉取到默认存档'
                        : isBound
                        ? '拉取到已绑定版本'
                        : '拉取并创建新版本',
                    icon: Icons.download,
                    onSelected: () => unawaited(_pullSlot(slot)),
                  ),
                  if (!isDefaultSlot)
                    ContextMenuAction(
                      label: boundToCurrent
                          ? '已绑定当前版本'
                          : isBound
                          ? '重新绑定到当前版本'
                          : '绑定到当前版本',
                      icon: Icons.link,
                      enabled: !boundToCurrent,
                      onSelected: boundToCurrent
                          ? null
                          : () => unawaited(_bindSlot(slot)),
                    ),
                  if (isBound && !isDefaultSlot)
                    ContextMenuAction(
                      label: '从已绑定版本解绑',
                      icon: Icons.link_off,
                      onSelected: () => _unbindSlot(slot),
                    ),
                  const ContextMenuDivider(),
                  ContextMenuAction(
                    label: '删除云端存档',
                    icon: Icons.delete_forever,
                    danger: true,
                    onSelected: () => _deleteSlot(slot),
                  ),
                  ContextMenuAction(
                    label: '打开版本云存档管理',
                    icon: Icons.tune,
                    onSelected: () => Navigator.pushNamed(
                      context,
                      versionCloudSavePageRouteKey,
                    ),
                  ),
                ];
              },
              child: Row(
                spacing: AppSpacing.related,
                children: [
                  Expanded(
                    child: Text(
                      _cloudSlotLabel(slot),
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconTextButton(
                    pressedScale: 0.96,
                    icon: Icons.download,
                    content: '拉取',
                    onTap: () => unawaited(_pullSlot(slot)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 拉取只认这份云存档已经绑定的实例；没有实例会新建一个
  String _pullTargetHint() {
    return '只拉进这份云存档已经绑定的实例；没有实例会新建一个隔离实例再绑定。'
        '要把某份云存档绑到当前版本，用行的铜菜单「绑定到当前版本」。';
  }

  String? _boundProfileOfSlot(CloudSaveSlot slot) =>
      CloudSaveService.profileIdBoundToSlot(slot.id);

  /// 菜单 / 行文字里只显示绑定 tag；默认存档显示「默认存档」
  String? _boundTagOfSlot(CloudSaveSlot slot) {
    final profile = _boundProfileOfSlot(slot);
    if (profile == null) return null;
    if (profile == 'default') return '默认存档';
    return CloudSaveService.versionOfProfile(profile)?.tag;
  }

  /// 云槽位名是「设备 · release · tag #短码」，列表里只留 tag，避免一行塞满
  String _cloudSlotLabel(CloudSaveSlot slot) {
    if (slot.name.contains('默认存档')) return '默认存档';
    final tag =
        CloudSaveService.boundTagOfSlotName(slot.name) ??
        CloudSaveService.releaseFromSlotName(slot.name);
    return _shortTag(tag);
  }

  String _shortTag(String tag, {int max = 28}) =>
      tag.length <= max ? tag : '${tag.substring(0, max - 1)}…';

  void _unbindSlot(CloudSaveSlot slot) {
    final profile = _boundProfileOfSlot(slot);
    if (profile == null) return;
    final version = CloudSaveService.versionOfProfile(profile);
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '从已绑定版本解绑？',
      content:
          '只删本机绑定；云端槽位 / 快照与本机存档都不动。\n'
          '解绑后这份云存档会显示「未绑定本地版本」。',
      action: () {
        try {
          if (version != null) {
            CloudSaveService.unbind(version);
          } else {
            CloudSaveService.discardProfileBinding(profile);
          }
          addNotice(icon: Icons.link_off, title: '已解绑云存档');
          setState(() {});
        } catch (error) {
          addNotice(
            icon: Icons.error_outline,
            title: '解绑失败',
            content: removeNewlines('$error'),
          );
        }
      },
    );
  }

  List<CloudSaveSlot>? _cloudSlots;
  bool _loadingSlots = false;

  Future<void> _loadSlotsForPull() async {
    setState(() => _loadingSlots = true);
    try {
      final token = await _accounts.ensureAccessToken();
      if (token == null) {
        addNotice(icon: Icons.info_outline, title: '先登录或检查网络');
        return;
      }
      final slots = await CloudSaveService.allSlots(accessToken: token);
      if (!mounted) return;
      setState(() => _cloudSlots = slots);
    } on Object catch (error) {
      addNotice(
        icon: Icons.close,
        title: '读取云端存档失败',
        content: removeNewlines('$error'),
      );
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  /// 本地实例 tag 与云端 boundTag 不同时先让玩家选；返回 false = 取消 / 处理失败
  Future<bool> _prepareTagBinding({
    required CloudSaveSlot slot,
    required String token,
  }) async {
    final version = config.versionOptions.selectedVersion;
    final cloudTag = CloudSaveService.boundTagOfSlotName(slot.name);
    if (version == null ||
        !version.isolation ||
        cloudTag == null ||
        cloudTag == version.tag) {
      return true;
    }
    final choice = await showCloudTagConflictPrompt(
      localTag: version.tag,
      cloudTag: cloudTag,
    );
    if (!mounted || choice == CloudTagChoice.cancel) return false;
    try {
      if (choice == CloudTagChoice.useCloud) {
        await CloudSaveService.adoptCloudTag(version, cloudTag);
        setState(() {});
      } else {
        await CloudSaveService.renameCloudSlotToLocalTag(
          accessToken: token,
          slotId: slot.id,
          version: version,
        );
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      addNotice(
        icon: Icons.error_outline,
        title: '处理标签失败',
        content: removeNewlines('$error'),
      );
      return false;
    }
  }

  Future<void> _pullSlot(CloudSaveSlot slot) async {
    final token = await _accounts.ensureAccessToken();
    if (token == null) return;
    final task = CloudPullTask(accessToken: token, slot: slot);
    addTask(task);
    await task.done;
    if (!mounted) return;
    addNotice(
      icon: Icons.cloud_download_outlined,
      title: task.error == null ? '从云拉取完成' : '从云拉取失败',
      content: task.error == null
          ? (task.result ?? '')
          : removeNewlines('${task.error}'),
    );
  }
  Future<void> _bindSlot(CloudSaveSlot slot) async {
    final token = await _accounts.ensureAccessToken();
    if (token == null) return;
    final version = config.versionOptions.selectedVersion;
    if (version == null) {
      addNotice(icon: Icons.info_outline, title: '先在主页选一个游戏版本');
      return;
    }
    if (!version.isolation &&
        CloudSaveService.boundTagOfSlotName(slot.name) != null) {
      addNotice(
        icon: Icons.info_outline,
        title: '这份云存档只在隔离模式下生效',
        content: '当前版本未隔离，绑定后不会按实例区分；要独立存档请先打开隔离数据目录。',
      );
    }
    if (!await _prepareTagBinding(slot: slot, token: token)) return;

    final profile = CloudSaveService.profileIdOf(version);
    final current = CloudSaveService.localState(version);
    final slotProfile = CloudSaveService.profileIdBoundToSlot(slot.id);
    final conflicts = <String>[
      if (current != null && current.slotId != slot.id)
        '当前版本已绑定到「${current.slotName ?? current.slotId}」',
      if (slotProfile != null && slotProfile != profile)
        '这份云存档已绑定到本机 ${slotProfile == 'default' ? '默认存档' : slotProfile}',
    ];
    if (conflicts.isEmpty) {
      await _completeBind(
        version: version,
        slot: slot,
        replacedProfile: null,
      );
      return;
    }
    if (!mounted) return;
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '覆盖现有绑定？',
      content:
          '${conflicts.join('；')}。\n'
          '继续会把当前版本 / 这份云存档改成新的绑定；另一方只解绑，不删云端、也不删本机存档。',
      action: () => unawaited(
        _completeBind(
          version: version,
          slot: slot,
          replacedProfile: slotProfile == profile ? null : slotProfile,
        ),
      ),
    );
  }

  Future<void> _completeBind({
    required Mindustry version,
    required CloudSaveSlot slot,
    required String? replacedProfile,
  }) async {
    try {
      if (replacedProfile != null) {
        CloudSaveService.discardProfileBinding(replacedProfile);
      }
      CloudSaveService.bindSlot(version, slot.id);
      if (!mounted) return;
      addNotice(
        icon: Icons.link,
        title: '已绑定到当前版本',
        content: '${version.tag} → ${slot.name}',
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      addNotice(
        icon: Icons.error_outline,
        title: '绑定失败',
        content: removeNewlines('$error'),
      );
    }
  }

  void _deleteSlot(CloudSaveSlot slot) {
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '删除云端存档？',
      content: '会删掉「${slot.name}」与它的全部历史快照；本机存档不受影响。',
      action: () async {
        try {
          final token = await _accounts.ensureAccessToken();
          if (token == null) return;
          await CloudSaveService.deleteSlot(
            accessToken: token,
            slotId: slot.id,
          );
          if (!mounted) return;
          setState(() {
            _cloudSlots = [
              for (final item in _cloudSlots ?? const <CloudSaveSlot>[])
                if (item.id != slot.id) item,
            ];
          });
          addNotice(icon: Icons.delete_forever, title: '已删除云端存档');
        } catch (error) {
          if (!mounted) return;
          addNotice(
            icon: Icons.error_outline,
            title: '删除失败',
            content: removeNewlines('$error'),
          );
        }
      },
    );
  }

  Widget _buildSwitchPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final enabled = CloudSaveService.globallyEnabled;
    return ContentPanelModule(
      title: '云存档',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          SwitchSettingBar(
            title: '启用云存档',
            value: enabled,
            onChanged: (value) {
              CloudSaveService.setGlobalEnabled(value);
              setState(() {});
            },
          ),
          Text(
            enabled
                ? '所有版本统一参与：启动游戏前拉云端、退出后自动上传'
                : '关着：所有版本都不参与云存档',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconTextButton(
              pressedScale: 0.96,
              icon: Icons.tune,
              content: '版本云存档管理',
              onTap: () => Navigator.pushNamed(
                context,
                versionCloudSavePageRouteKey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final quota = _quota;
    return ContentPanelModule(
      title: '云端容量',
      child: quota == null
          ? Text(
              _loading ? '读取中…' : (_accounts.isLoggedIn ? '读不到容量' : '登录后显示'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemHint,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.related,
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
                  '单个云包上限 ${formatBytes(quota.maxFileSizeBytes ?? 0)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.itemHint,
                  ),
                ),
              ],
            ),
    );
  }
}
