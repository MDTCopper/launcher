import 'package:copper_launcher/data/net/lanlink/lanlink_api.dart';
import 'package:copper_launcher/data/net/lanlink/lanlink_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/lanlink/lanlink_service.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_multiplayer_service.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_models.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_multiplayer_state.dart';
import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/pages/account/account_page.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const onlinePageRouteKey = '/online';

/// 联机页：**主线是 BBS 官方会话**（MindAuth OAuth，免密码），
/// 另留一个「MDT 兼容」块（LanLink 房间码加入，走匿名接口，不需要登录）。
///
/// 本页**不持有会话状态、也不发网络请求**：官方那一半全部订阅
/// [MdtbbsMultiplayerService.state]，页内只剩输入框内容与 MDT 的临时解析结果
class OnlinePage extends StatefulWidget {
  const OnlinePage({super.key});

  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

class _OnlinePageState extends State<OnlinePage> {
  final _joinCodeController = TextEditingController();
  final _activityNameController = TextEditingController();
  final _maxPlayersController = TextEditingController(text: '8');
  final _mdtCodeController = TextEditingController();

  MdtbbsMultiplayerService get _mp => MdtbbsMultiplayerService.instance;
  LanLinkService get _lanlink => LanLinkService.instance;
  AccountManager get _accounts => AccountManager.instance;

  // 创建房间的选项（纯输入状态，留在页面）
  //
  // 默认按「给加入码」来：实测**只有不公开（unlisted）会返回加入码**，
  // private / friends 都不给（那两种得靠邀请，邀请还没做）
  String _visibility = 'unlisted';
  String _joinPolicy = 'open';

  // MDT 块自己的状态：与官方那半互不影响
  bool _mdtBusy = false;
  LanLinkRoom? _mdtRoom;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _joinCodeController.dispose();
    _activityNameController.dispose();
    _maxPlayersController.dispose();
    _mdtCodeController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    // 落盘状态先点亮，再核验能力（服务里已有状态时会直接跳过，不会重复拉）
    await _mp.restore();
    // 账号资料只在内存里没有时读一次（手机号验证态要用它），不是每次进页面都拉
    if (_accounts.isLoggedIn && _accounts.account == null) {
      try {
        await _accounts.loadAccount();
      } on Object {
        // 读不到就按未知处理，页面照常
      }
    }
    await _mp.loadCapabilities();
    if (!mounted) return;
    setState(() => _mdtRoom = _lanlink.activeRoom);
  }

  // ── MDT 兼容（LanLink 房间码，匿名可用） ──────────────────────

  Future<void> _resolveMdtRoom() async {
    final code = LanLinkRoomCode.tryParse(_mdtCodeController.text);
    if (code == null) {
      _showMdt('MDT 房间码格式：MDT-XXXXXX', isError: true);
      return;
    }
    setState(() => _mdtBusy = true);
    try {
      final room = await _lanlink.resolve(code);
      if (!mounted) return;
      setState(() => _mdtRoom = room);
      _showMdt(room == null ? '房间不存在或已关闭' : '已找到房间：${room.code}');
    } on LanLinkException catch (error) {
      _showMdt(error.message.isEmpty ? '$error' : error.message, isError: true);
    } on Object catch (error) {
      _showMdt('查询房间失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _mdtBusy = false);
    }
  }

  Future<void> _joinMdtRoom(LanLinkRoom room) async {
    setState(() => _mdtBusy = true);
    try {
      final session = await _lanlink.join(room);
      _showMdt('已就绪：进入游戏 → 加入游戏 → 在「局域网游戏」中选择「${session.roomName}」');
    } on LanLinkException catch (error) {
      _showMdt(error.message.isEmpty ? '$error' : error.message, isError: true);
    } on Object catch (error) {
      _showMdt('加入房间失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _mdtBusy = false);
    }
  }

  Future<void> _leaveMdtRoom() async {
    await _lanlink.leave();
    if (!mounted) return;
    setState(() => _mdtRoom = null);
    _showMdt('已离开房间');
  }

  void _showMdt(String text, {bool isError = false}) {
    if (isError) {
      addLogAndPrint(.warning, text, tag: 'Multiplayer');
    } else {
      addLogAndPrint(.info, text, tag: 'Multiplayer');
    }
    addNotice(
      icon: isError ? Icons.error_outline : Icons.check_circle_outline,
      title: isError ? '联机操作失败' : '联机',
      content: text,
      duration: const Duration(seconds: 6),
    );
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    _showMdt('$label 已复制：$text');
  }

  // ── 构建 ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // 账号态与服务状态一起订阅：登录 / 退出、会话变化都能立刻反映
      animation: Listenable.merge([_mp.state, _accounts.snapshot]),
      builder: (context, _) {
        final state = _mp.state.value;
        return ListContentPanel(
          items: [
            _buildAccountStrip(),
            if (state.lastMessage != null) _buildMessagePanel(state),
            _buildOfficialPanel(state),
            _buildMdtCompatPanel(),
          ],
        );
      },
    );
  }

  Widget _buildAccountStrip() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final loggedIn = _accounts.snapshot.value.loggedIn;
    return ContentPanelModule(
      title: '账号状态',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Text(
            loggedIn
                ? '✓ 社区账号：已登录（创建 / 加入房间需要；MDT 房间无需登录）'
                : '× 社区账号：未登录（创建 / 加入房间需要；MDT 房间无需登录）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: loggedIn ? colors.itemSecondary : colors.error,
            ),
          ),
          if (!loggedIn)
            IconTextButton(
              pressedScale: 0.96,
              icon: Icons.account_circle_outlined,
              content: '去账户页登录',
              onTap: () => Navigator.pushNamed(context, accountPageRouteKey),
            ),
        ],
      ),
    );
  }

  Widget _buildMessagePanel(MultiplayerState state) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return ContentPanelModule(
      title: '状态',
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              state.lastMessage ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: state.lastMessageIsError
                    ? theme.colorScheme.error
                    : colors.itemSecondary,
              ),
            ),
          ),
          IconTextButton(
            pressedScale: 0.96,
            icon: Icons.close,
            content: '知道了',
            onTap: _mp.clearMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildOfficialPanel(MultiplayerState state) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final caps = state.capabilities;

    if (!_accounts.snapshot.value.loggedIn) {
      return ContentPanelModule(
        title: '会话（官方）',
        child: Text(
          '登录社区账号后可用（MindAuth 授权，无需输入密码）。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.itemSecondary,
          ),
        ),
      );
    }
    if (caps == null) {
      return ContentPanelModule(
        title: '会话（官方）',
        child: Text(
          state.loadingCapabilities ? '正在读取联机功能…' : '正在准备…',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.itemHint),
        ),
      );
    }
    if (!caps.usable) {
      return ContentPanelModule(
        title: '会话（官方）',
        child: Text(
          '服务端当前未开放此功能',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
        ),
      );
    }
    if (!_accounts.snapshot.value.phoneVerified) {
      return ContentPanelModule(
        title: '会话（官方）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            Text(
              '手机号未验证：创建 / 加入房间会被服务端拒绝，请先到论坛完成手机号验证',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
            IconTextButton(
              pressedScale: 0.96,
              icon: Icons.refresh,
              content: '我已验证，重新检查',
              onTap: () => _accounts.loadAccount().then((_) {
                if (mounted) setState(() {});
              }),
            ),
          ],
        ),
      );
    }

    final session = state.session;
    return ContentPanelModule(
      title: '会话（官方）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Text(
            '创建房间后把加入码发给好友，或使用好友的加入码加入房间。'
            '（官方中继尚未完成，目前仅支持房间管理）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          if (state.anyBusy)
            Text(state.workloadLabel, style: theme.textTheme.bodySmall),
          if (session != null)
            _buildSessionCard(state, session)
          else if (state.waitingForSession)
            Text(
              '正在恢复房间…（加入码 ${state.joinCode ?? '—'}）',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemSecondary,
              ),
            )
          else ...[
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: OutlinedTextField(
                    controller: _activityNameController,
                    label: '活动名（可选）',
                    enable: !state.creating,
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: OutlinedTextField(
                    controller: _maxPlayersController,
                    label: '人数',
                    enable: !state.creating,
                  ),
                ),
              ],
            ),
            Text(
              '可见范围',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in caps.visibility)
                  ActionButton(
                    content: Text(_visibilityLabel(value)),
                    hint: _visibilityHint(value),
                    selected: _visibility == value,
                    enable: !state.creating,
                    onTap: () => setState(() {
                      _visibility = value;
                      // private 不能配 open，自动换成合法组合
                      if (value == 'private' && _joinPolicy == 'open') {
                        _joinPolicy = 'friends';
                      }
                    }),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
              ],
            ),
            Text(
              '加入方式',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in caps.joinPolicies)
                  ActionButton(
                    content: Text(_joinPolicyLabel(value)),
                    selected: _joinPolicy == value,
                    enable: !state.creating,
                    onTap: () => setState(() {
                      _joinPolicy = value;
                      // 反过来：open 与 private 不合，自动改成不公开
                      if (value == 'open' && _visibility == 'private') {
                        _visibility = 'unlisted';
                      }
                    }),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
              ],
            ),
            Text(
              _visibility == 'unlisted'
                  ? '创建后会给出加入码，发给好友即可加入'
                  : '这种可见范围不会给加入码（要邀请才能进，邀请还没做）',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _visibility == 'unlisted'
                    ? colors.itemHint
                    : colors.error,
              ),
            ),
            Row(
              spacing: 8,
              children: [
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.add_circle_outline,
                  content: '创建房间',
                  onTap: state.creating ? null : _createRoom,
                ),
              ],
            ),
            Text(
              '或者用加入码加入：',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: OutlinedTextField(
                    controller: _joinCodeController,
                    label: '加入码',
                    enable: !state.joining,
                    onEditingComplete: _joinRoom,
                  ),
                ),
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.login,
                  content: '加入房间',
                  onTap: state.joining ? null : _joinRoom,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createRoom() => _mp.create(
    activityName: _activityNameController.text.trim(),
    visibility: _visibility,
    joinPolicy: _joinPolicy,
    maxPlayers: int.tryParse(_maxPlayersController.text.trim()) ?? 8,
  );

  Future<void> _joinRoom() => _mp.joinByCode(_joinCodeController.text);

  Widget _buildSessionCard(MultiplayerState state, MdtbbsSession session) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final peers = state.peers;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text(
            state.self?.role == 'owner' ? '我创建的房间' : '已加入',
            style: theme.textTheme.titleSmall,
          ),
          if (state.joinCode != null)
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    '加入码 ${state.joinCode}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.copy,
                  content: '复制',
                  onTap: () => _copy(state.joinCode!, '加入码'),
                ),
              ],
            ),
          Text(
            '${_visibilityLabel(session.visibility)} · '
            '${_joinPolicyLabel(session.joinPolicy)}    '
            '${session.currentPlayers}/${session.maxPlayers} 人    '
            '${_statusLabel(session.status)}'
            '${state.heartbeatFailures == 0 ? '' : '    心跳异常 ${state.heartbeatFailures} 次'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          if (peers.isNotEmpty)
            Text(
              '成员：${peers.map((p) => '${_roleLabel(p.role)}·${_peerStatusLabel(p.status)}').join('、')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
          Row(
            spacing: 8,
            children: [
              if (!state.proxyRunning)
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.lan_outlined,
                  content: '启动联机通道',
                  onTap: state.startingProxy ? null : _mp.startProxy,
                )
              else
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.lan_outlined,
                  content: '停止联机通道',
                  onTap: state.stoppingProxy ? null : _mp.stopProxy,
                ),
              IconTextButton(
                pressedScale: 0.96,
                icon: Icons.refresh,
                content: '刷新成员',
                onTap: state.refreshingPeers
                    ? null
                    : () => _mp.refreshPeers(announce: true),
              ),
              IconTextButton(
                pressedScale: 0.96,
                icon: Icons.logout,
                content: '离开房间',
                onTap: state.leaving ? null : _mp.leave,
              ),
            ],
          ),
          if (state.proxyRunning)
            Text(
              '联机通道已启动：请在游戏中连接 ${state.localAddress}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
          Text(
            '官方中继尚未完成：目前可创建 / 加入房间、查看成员，暂不支持直接进入游戏。',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.itemHint),
          ),
        ],
      ),
    );
  }

  /// MDT 兼容：LanLink 房间码加入。**匿名可用**（房间信息是公开接口）
  Widget _buildMdtCompatPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final room = _lanlink.activeRoom;
    final joined = _lanlink.isJoined && room != null;

    return ContentPanelModule(
      title: 'MDT 兼容',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Text(
            '输入 LanLink 模组创建的房间码即可加入，无需登录。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          if (joined)
            _buildMdtJoinedCard(room)
          else if (_mdtRoom != null)
            _buildMdtRoomCard(_mdtRoom!)
          else
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: OutlinedTextField(
                    controller: _mdtCodeController,
                    label: 'MDT 房间码',
                    enable: !_mdtBusy,
                    onEditingComplete: _resolveMdtRoom,
                  ),
                ),
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.search,
                  content: '查询',
                  onTap: _mdtBusy ? null : _resolveMdtRoom,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMdtRoomCard(LanLinkRoom room) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text(
            room.name.isEmpty ? room.code : room.name,
            style: theme.textTheme.titleSmall,
          ),
          Text(
            '房主 ${room.ownerUsername}    节点 ${room.nodeName}    '
            '地址 ${room.relayAddress}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          IconTextButton(
            pressedScale: 0.96,
            icon: Icons.login,
            content: '加入房间',
            onTap: _mdtBusy ? null : () => _joinMdtRoom(room),
          ),
        ],
      ),
    );
  }

  Widget _buildMdtJoinedCard(LanLinkRoom room) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text(
            '已连接：${room.name.isEmpty ? room.code : room.name}'
            '（${_lanlink.isDirectJoined ? '直连' : '经节点中继'}）',
            style: theme.textTheme.titleSmall,
          ),
          Text(
            '进入游戏 → 加入游戏 → 在「局域网游戏」中选择该房间（${_lanlink.localAddress}）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          IconTextButton(
            pressedScale: 0.96,
            icon: Icons.logout,
            content: '离开房间',
            onTap: _mdtBusy ? null : _leaveMdtRoom,
          ),
        ],
      ),
    );
  }

  /// 服务端的枚举给用户看时都换成中文（英文值只留在代码里比对）
  String _visibilityLabel(String value) => switch (value) {
    'private' => '私有',
    'friends' => '好友可见',
    'unlisted' => '不公开',
    _ => value,
  };

  /// 可见范围对「能不能拿到加入码」的影响（只有不公开会给码）
  String _visibilityHint(String value) => switch (value) {
    'private' => '只让被邀请的人进；不给加入码',
    'friends' => '只让好友进；不给加入码',
    'unlisted' => '不在列表里露面，靠加入码进；会给码',
    _ => '',
  };

  String _joinPolicyLabel(String value) => switch (value) {
    'open' => '任何人可加入',
    'friends' => '仅好友可加入',
    'request' => '需申请',
    'invite_only' => '仅限邀请',
    _ => value,
  };

  String _statusLabel(String value) => switch (value) {
    'active' => '进行中',
    'closing' => '关闭中',
    'expired' => '已过期',
    _ => value,
  };

  String _roleLabel(String role) => role == 'owner' ? '房主' : '成员';

  String _peerStatusLabel(String status) => switch (status) {
    'active' => '在线',
    'joining' => '加入中',
    'disconnected' => '已断开',
    'expired' => '已过期',
    _ => status,
  };
}
