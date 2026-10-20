import 'dart:async';

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

/// chips 的统一内边距（与项目其它页的 chips 一致）
const kChipPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);

/// 人数上限的常用值：比让人手输数字省事，也不会输错
const kMaxPlayerChoices = [2, 4, 8, 16, 32];

class OnlinePage extends StatefulWidget {
  const OnlinePage({super.key});

  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

class _OnlinePageState extends State<OnlinePage> {
  final _joinCodeController = TextEditingController();
  final _activityNameController = TextEditingController();
  final _maxPlayers = ValueNotifier<int>(8);
  final _mdtCodeController = TextEditingController();

  MdtbbsMultiplayerService get _mp => MdtbbsMultiplayerService.instance;
  LanLinkService get _lanlink => LanLinkService.instance;
  AccountManager get _accounts => AccountManager.instance;

  // 创建房间的选项（纯输入状态，留在页面）
  //
  // 默认「凭加入码」：实测**只有 unlisted 会返回加入码**，
  // private / friends 都不给（那两种得靠邀请，邀请还没做）
  String _visibility = 'private';
  String _joinPolicy = 'public';
  bool _advancedOpen = false;

  /// 「进房需我同意」：对应服务端的 `join_policy = request`。
  /// 单独做成开关而不是并列档位——它和「凭加入码」不是一个层级的事
  bool _requireApproval = false;

  // MDT 块自己的状态：与官方那半互不影响
  bool _mdtBusy = false;
  bool _mdtOpen = false;
  LanLinkRoom? _mdtRoom;
  List<LanLinkRoom> _publicRooms = const [];
  bool _publicRoomsLoading = false;

  Timer? _peerRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
    // 成员与人数每 10 秒静默刷新一次，页面不可见时跳过
    _peerRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshPeersIfVisible(),
    );
  }

  @override
  void dispose() {
    _peerRefreshTimer?.cancel();
    _joinCodeController.dispose();
    _activityNameController.dispose();
    _maxPlayers.dispose();
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
    // 房间名给个像样的默认值，好友在列表里看到的就不是 "mindustry" 了
    if (_activityNameController.text.trim().isEmpty) {
      final name = _accounts.account?.username;
      _activityNameController.text = name == null || name.isEmpty
          ? '我的房间'
          : '$name 的房间';
    }
    setState(() => _mdtRoom = _lanlink.activeRoom);
    unawaited(_loadPublicRooms());
  }

  /// 成员与人数自动刷新；只在页面可见、真在房间里时发请求
  void _refreshPeersIfVisible() {
    if (!mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final state = _mp.state.value;
    if (state.session == null || state.refreshingPeers || state.leaving) {
      return;
    }
    unawaited(_mp.refreshPeers());
  }

  /// 公开房间列表：LanLink 那边开房时勾了「公开」的房间会出现在这里，
  /// **任何人不用房间码就能看到直接加入**（官方 API 没有这个大厅）
  Future<void> _loadPublicRooms() async {
    if (_publicRoomsLoading) return;
    setState(() => _publicRoomsLoading = true);
    try {
      final rooms = await _lanlink.publicRooms();
      if (!mounted) return;
      setState(() => _publicRooms = rooms);
    } on Object catch (error) {
      addLogAndPrint(.warning, '拉公开房间失败：$error', tag: 'LanLink');
    } finally {
      if (mounted) setState(() => _publicRoomsLoading = false);
    }
  }

  // ── MDT 兼容（LanLink 房间码，匿名可用） ──────────────────────

  Future<void> _resolveMdtRoom() async {
    final code = LanLinkRoomCode.tryParse(_mdtCodeController.text);
    if (code == null) {
      _showMdt('房间码格式：MDT-XXXXXX', isError: true);
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

  /// 分享房间：服务端没有「公开」这种可见性（实测 public 会被 400 拒），
  /// 把房间信息发到群 / 论坛就是现在唯一的"公开"办法
  String _shareText(MdtbbsSession session) {
    final name = session.activityName?.trim();
    return '【Copper 联机】'
        '${name == null || name.isEmpty ? '联机房间' : name}\n'
        '房间码 ${_mp.state.value.joinCode}\n'
        '用 Copper 启动器 → 联机 → 加入房间，填这个码即可';
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
            if (state.lastMessage != null && state.session == null)
              _buildMessagePanel(state),
            _buildOfficialPanel(state),
            _buildMdtCompatPanel(),
          ],
        );
      },
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
        title: '联机',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            Text(
              '联机需要一个社区账号：登录后可以创建或加入房间',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
            IconTextButton(
              pressedScale: 0.96,
              icon: Icons.account_circle_outlined,
              content: '去账户页登录',
              onTap: () => Navigator.pushNamed(context, accountPageRouteKey),
            ),
            Text(
              '其他启动器（LanLink）的房间不用登录，在页面底部',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.itemHint,
              ),
            ),
          ],
        ),
      );
    }
    if (caps == null) {
      return ContentPanelModule(
        title: '房间',
        child: Text(
          state.loadingCapabilities ? '正在读取联机功能…' : '正在准备…',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.itemHint),
        ),
      );
    }
    if (!caps.usable) {
      return ContentPanelModule(
        title: '房间',
        child: Text(
          '服务端当前未开放此功能',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
        ),
      );
    }
    final session = state.session;
    if (state.waitingForSession) {
      return ContentPanelModule(
        title: '房间',
        child: Text(
          '正在恢复上次的房间…',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.itemSecondary,
          ),
        ),
      );
    }
    if (session != null) {
      return ContentPanelModule(
        title: '房间',
        child: _buildSessionCard(state, session),
      );
    }
    return _buildCreateJoinPanel(state, caps);
  }

  /// 未进房：创建 / 加入两张卡，高级选项默认折叠
  Widget _buildCreateJoinPanel(
    MultiplayerState state,
    MdtbbsMultiplayerCapabilities caps,
  ) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final phoneVerified = _accounts.snapshot.value.phoneVerified;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (state.anyBusy)
          Text(state.workloadLabel, style: theme.textTheme.bodySmall),
        ContentPanelModule(
          title: '创建房间',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              if (!phoneVerified)
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Text(
                        '手机号未验证：创建房间会被服务端拒绝',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ),
                    IconTextButton(
                      pressedScale: 0.96,
                      icon: Icons.refresh,
                      content: '重新检查',
                      onTap: () => _accounts.loadAccount().then((_) {
                        if (mounted) setState(() {});
                      }),
                    ),
                  ],
                ),
              OutlinedTextField(
                controller: _activityNameController,
                label: '房间名（好友看到的）',
                enable: !state.creating,
              ),
              Text(
                '人数',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.itemSecondary,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final count in kMaxPlayerChoices)
                    ActionButton(
                      content: Text('$count 人'),
                      selected: _maxPlayers.value == count,
                      enable: !state.creating,
                      onTap: () => setState(() => _maxPlayers.value = count),
                      padding: kChipPadding,
                    ),
                ],
              ),
              ActionButton(
                content: const Text('进房需我同意'),
                hint: '开着的话，符合加入条件的人也要等我批准才能进来',
                selected: _requireApproval,
                enable: !state.creating,
                onTap: () =>
                    setState(() => _requireApproval = !_requireApproval),
                padding: kChipPadding,
              ),
              Text(
                _requireApproval
                    ? '符合条件的人也要我同意后才进得来'
                    : '符合条件的人拿到房间码就能直接进',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.itemHint,
                ),
              ),
              IconTextButton(
                pressedScale: 0.96,
                icon: _advancedOpen
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                content: _advancedOpen ? '收起更多设置' : '更多设置',
                onTap: () => setState(() => _advancedOpen = !_advancedOpen),
              ),
              if (_advancedOpen) ...[
                Text(
                  '谁能看到房间',
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
                        onTap: () => setState(() => _visibility = value),
                        padding: kChipPadding,
                      ),
                  ],
                ),
                Text(
                  '谁能加入',
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
                        onTap: () => setState(() => _joinPolicy = value),
                        padding: kChipPadding,
                      ),
                  ],
                ),
              ],
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
            ],
          ),
        ),
        ContentPanelModule(
          title: '加入房间',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: OutlinedTextField(
                      controller: _joinCodeController,
                      label: '房间码',
                      enable: !state.joining,
                      onEditingComplete: _joinRoom,
                    ),
                  ),
                  IconTextButton(
                    pressedScale: 0.96,
                    icon: Icons.login,
                    content: '加入',
                    onTap: state.joining ? null : _joinRoom,
                  ),
                ],
              ),
              Text(
                '向房主要 6 位房间码',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.itemHint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 创建房间：值先按服务端 `capabilities` 兜一遍，再带上 `require_approval`
  Future<void> _createRoom() {
    final caps = _mp.state.value.capabilities;
    final visibility = (caps == null || caps.visibility.contains(_visibility))
        ? _visibility
        : (caps.visibility.isNotEmpty ? caps.visibility.first : 'private');
    final joinPolicy = (caps == null || caps.joinPolicies.contains(_joinPolicy))
        ? _joinPolicy
        : (caps.joinPolicies.isNotEmpty ? caps.joinPolicies.first : 'public');
    return _mp.create(
      activityName: _activityNameController.text.trim(),
      visibility: visibility,
      joinPolicy: joinPolicy,
      requireApproval: _requireApproval,
      maxPlayers: _maxPlayers.value,
    );
  }

  Future<void> _joinRoom() => _mp.joinByCode(_joinCodeController.text);

  Widget _buildSessionCard(MultiplayerState state, MdtbbsSession session) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final isOwner = state.self?.role == 'owner';
    final roomName = session.activityName?.trim();
    final online = state.onlinePeerCount;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  roomName == null || roomName.isEmpty ? '联机房间' : roomName,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                _roomStateLabel(state),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: state.proxyError != null
                      ? colors.error
                      : colors.itemSecondary,
                ),
              ),
            ],
          ),
          Text(
            '${online > 0 ? online : '—'} / ${session.maxPlayers} 人'
            '${state.heartbeatFailures == 0 ? '' : '   网络不稳定'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          if (state.peers.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                for (final peer in state.peers)
                  Text(
                    _memberLine(state, peer),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.itemSecondary,
                    ),
                  ),
              ],
            ),
          if (isOwner) ...[
            if (state.joinCode != null)
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Text(
                      '房间码 ${state.joinCode}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  IconTextButton(
                    pressedScale: 0.96,
                    icon: Icons.copy,
                    content: '复制',
                    onTap: () => _copy(state.joinCode!, '房间码'),
                  ),
                  IconTextButton(
                    pressedScale: 0.96,
                    icon: Icons.ios_share,
                    content: '分享',
                    onTap: () => _copy(_shareText(session), '房间信息'),
                  ),
                ],
              )
            else
              Text(
                '这个房间没有房间码，只能靠邀请',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.itemHint,
                ),
              ),
            Text(
              '把房间码发给好友，你先在游戏里开「主机」房间',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.itemHint,
              ),
            ),
          ] else
            Text(
              '等房主准备好，你再进游戏 → 加入游戏',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.itemHint,
              ),
            ),
          _buildRoomStateLine(state, isOwner, colors),
          Row(
            spacing: 8,
            children: [
              if (state.proxyError != null && !state.reconnecting)
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.refresh,
                  content: '重试',
                  onTap: state.startingProxy ? null : _mp.retryProxy,
                ),
              IconTextButton(
                pressedScale: 0.96,
                icon: isOwner ? Icons.stop_circle_outlined : Icons.logout,
                content: isOwner ? '关闭房间' : '离开房间',
                onTap: state.leaving ? null : _mp.leave,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _memberLine(MultiplayerState state, MdtbbsPeer peer) {
    final isSelf = state.self?.peerId == peer.peerId;
    return '${isSelf ? '我' : '成员'}（${_roleLabel(peer.role)}）'
        '· ${_peerStatusLabel(peer.status)}';
  }

  String _roomStateLabel(MultiplayerState state) {
    if (state.reconnecting) {
      return '● 正在重连（${state.reconnectAttempt}/3）…';
    }
    if (state.startingProxy) return '● 正在准备联机…';
    if (state.proxyRunning) return '● 可以进游戏了';
    if (state.proxyError != null) return '● 连不上联机服务器';
    return '● 准备中…';
  }

  Widget _buildRoomStateLine(
    MultiplayerState state,
    bool isOwner,
    AppColors colors,
  ) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: colors.itemSecondary,
    );
    if (state.proxyError != null) {
      return Text(state.proxyError!, style: style);
    }
    if (state.reconnecting) {
      return Text('联机断开了，正在自动重连…', style: style);
    }
    if (state.startingProxy) {
      return Text('正在准备联机，稍等…', style: style);
    }
    if (state.proxyRunning) {
      return Text(
        isOwner
            ? '准备好了：进游戏开「主机」房间，好友就能进来'
            : '准备好了：进游戏 → 加入游戏 → 在「局域网游戏」里选这个房间',
        style: style,
      );
    }
    return const SizedBox.shrink();
  }


  /// 其他启动器（LanLink）房间；默认折叠，匿名可用
  Widget _buildMdtCompatPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final room = _lanlink.activeRoom;
    final joined = _lanlink.isJoined && room != null;

    return ContentPanelModule(
      title: '其他启动器房间',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  _mdtOpen
                      ? 'LanLink 模组开的房间，不用登录'
                      : 'LanLink 房间码 / 公开房间（不用登录）',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.itemSecondary,
                  ),
                ),
              ),
              IconTextButton(
                pressedScale: 0.96,
                icon: _mdtOpen
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                content: _mdtOpen ? '收起' : '展开',
                onTap: () => setState(() => _mdtOpen = !_mdtOpen),
              ),
            ],
          ),
          if (joined)
            _buildMdtJoinedCard(room)
          else if (_mdtOpen) ...[
            Row(
              spacing: 8,
              children: [
                Text('公开房间', style: theme.textTheme.titleSmall),
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.refresh,
                  content: '刷新',
                  onTap: _publicRoomsLoading ? null : _loadPublicRooms,
                ),
              ],
            ),
            if (_publicRooms.isEmpty)
              Text(
                _publicRoomsLoading
                    ? '正在读取公开房间…'
                    : '现在没有公开房间（开房的人勾了「公开」才会出现在这里）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.itemHint,
                ),
              )
            else
              for (final room in _publicRooms) _buildPublicRoomRow(room),
            if (_mdtRoom != null)
              _buildMdtRoomCard(_mdtRoom!)
            else
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: OutlinedTextField(
                      controller: _mdtCodeController,
                      label: 'LanLink 房间码',
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
        ],
      ),
    );
  }

  /// 公开房间里的一行：不用码，点一下就进
  Widget _buildPublicRoomRow(LanLinkRoom room) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final canDirect = room.directCandidates.any((it) => it.isValid);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  room.name.isEmpty ? room.code : room.name,
                  style: theme.textTheme.bodyLarge,
                ),
                Text(
                  '房主 ${room.ownerUsername} · 服务器 ${room.nodeName}'
                  '${canDirect ? ' · 可直连' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.itemSecondary,
                  ),
                ),
              ],
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
            '房主 ${room.ownerUsername}    服务器 ${room.nodeName}    '
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
            '（${_lanlink.isDirectJoined ? '直连' : '经服务器中转'}）',
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
  /// 按「怎么才能进」命名，不按「公开程度」——
  /// 「私有」和「不公开」在中文里几乎同义，用户分不出来，
  /// 但一个是不给码（要邀请）、一个是给码（凭码就能进）
  String _visibilityLabel(String value) => switch (value) {
    'private' => '仅我可见',
    'friends' => '仅好友可见',
    'public' => '公开',
    'unlisted' => '凭房间码',
    _ => value,
  };

  /// 可见范围只决定「谁能在列表里发现」，不决定能不能加入
  String _visibilityHint(String value) => switch (value) {
    'private' => '列表里看不到这个房间；知道房间码 / 被邀请的人仍可能加入',
    'friends' => '⚠ 好友能在联机列表里看到（好友列表还没做）',
    'public' => '所有人都能在联机大厅看到这个房间',
    'unlisted' => '任何列表里都看不到；拿到房间码的人都能进',
    _ => '',
  };

  String _joinPolicyLabel(String value) => switch (value) {
    'invite_only' => '⚠ 仅受邀者（邀请还没做）',
    'friends' => '⚠ 仅好友（好友列表未做）',
    'public' => '拿到入口就能进',
    'open' => '有码即可进',
    'request' => '需我同意',
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
