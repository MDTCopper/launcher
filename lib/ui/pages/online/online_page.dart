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
  String _visibility = 'unlisted';
  String _joinPolicy = 'open';
  bool _advancedOpen = false;

  /// 「进房需我同意」：对应服务端的 `join_policy = request`。
  /// 单独做成开关而不是并列档位——它和「凭加入码」不是一个层级的事
  bool _requireApproval = false;

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
            Text('创建房间', style: theme.textTheme.titleSmall),
            OutlinedTextField(
              controller: _activityNameController,
              label: '房间名（好友看到的）',
              enable: !state.creating,
            ),
            Text(
              '人数上限',
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
              hint: '开着的话，别人拿到加入码也得等我批准才能进来',
              selected: _requireApproval,
              enable: !state.creating,
              onTap: () => setState(() => _requireApproval = !_requireApproval),
              padding: kChipPadding,
            ),
            Text(
              _requireApproval
                  ? '创建后会给出加入码；别人用码申请，我同意后才进得来'
                  : '创建后会给出加入码，谁拿到码谁能进',
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
                      padding: kChipPadding,
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
                        // 反过来：open 与 private 不合，自动改成凭加入码
                        if (value == 'open' && _visibility == 'private') {
                          _visibility = 'unlisted';
                        }
                      }),
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
            Text('加入房间', style: theme.textTheme.titleSmall),
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
    joinPolicy: _requireApproval ? 'request' : _joinPolicy,
    maxPlayers: _maxPlayers.value,
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
  /// 按「怎么才能进」命名，不按「公开程度」——
  /// 「私有」和「不公开」在中文里几乎同义，用户分不出来，
  /// 但一个是不给码（要邀请）、一个是给码（凭码就能进）
  String _visibilityLabel(String value) => switch (value) {
    'private' => '邀请制',
    'friends' => '好友可见',
    'unlisted' => '凭加入码',
    _ => value,
  };

  /// 可见范围对「能不能拿到加入码」的影响（只有 unlisted 会给码）
  ///
  /// 好友与邀请这两档依赖我们还没做的功能（好友列表 / 邀请流程），
  /// 提示里直接写明，别让用户选了才发现用不了
  String _visibilityHint(String value) => switch (value) {
    'private' => '⚠ 只有被我邀请的人能进；不给加入码（邀请功能还没做）',
    'friends' => '⚠ 只有好友能进；不给加入码（好友列表还没做）',
    'unlisted' => '不在大厅里露面；持有加入码的人都能进（会给码）',
    _ => '',
  };

  String _joinPolicyLabel(String value) => switch (value) {
    'open' => '有码即可进',
    'friends' => '⚠ 仅好友（好友列表未做）',
    'request' => '需我同意',
    'invite_only' => '⚠ 仅邀请（邀请未做）',
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
