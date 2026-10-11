import 'package:copper_launcher/data/net/lanlink/lanlink_api.dart';
import 'package:copper_launcher/data/net/lanlink/lanlink_models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_api.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/lanlink/lanlink_service.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/pages/account/account_page.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const onlinePageRouteKey = '/online';

/// 联机页：**主线是 BBS 官方会话**（MindAuth OAuth，免密码），
/// 另留一个「MDT 兼容」块（LanLink 房间码加入，走匿名接口，不需要联机服务登录）。
///
/// 官方会话目前是控制面部分（建会话 / 加入码 / 对端）；进服数据通道（中继）待 P2/P3。
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

  AccountManager get _accounts => AccountManager.instance;
  LanLinkService get _lanlink => LanLinkService.instance;

  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  // ── 官方会话 ──
  MdtbbsMultiplayerCapabilities? _capabilities;
  MdtbbsCreatedSession? _created;
  MdtbbsSession? _current;
  List<MdtbbsPeer> _peers = const [];

  /// 恢复令牌：**内存暂存**，P5 再决定安全持久化（绑定用户与 client、一次性、会轮换）
  String _resumeToken = '';
  String _visibility = 'private';
  String _joinPolicy = 'friends';

  // ── MDT 兼容（LanLink 房间码）──
  LanLinkRoom? _mdtRoom;

  /// 页面是侧栏里的常驻单例：从别的页回来时 State 还活着，得靠路由刷新
  bool _ready = false;
  bool _wasCurrent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (_ready && current && !_wasCurrent) {
      _refreshAccount();
    }
    _wasCurrent = current;
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
    await _refreshAccount();
    await _refreshCapabilities();
    await _refreshCurrentSession();
    if (!mounted) return;
    setState(() {
      _mdtRoom = _lanlink.activeRoom;
      _ready = true;
    });
  }

  /// 账号态由账户层拥有，这里只读、不缓存
  Future<void> _refreshAccount() async {
    if (_accounts.isConfigured) {
      await _accounts.restore();
    }
    if (!mounted) return;
    setState(() {});
  }

  /// 拿 BBS 的 Bearer 令牌（过期内会自动刷新）；未登录返回 null
  Future<String?> _bbsToken() => _accounts.ensureAccessToken();

  Future<void> _refreshCapabilities() async {
    final token = await _bbsToken();
    if (token == null) return;
    try {
      final caps = await MdtbbsMultiplayerApi.capabilities(accessToken: token);
      if (!mounted) return;
      setState(() {
        _capabilities = caps;
        _visibility = caps.visibility.contains(_visibility)
            ? _visibility
            : (caps.visibility.isEmpty ? 'private' : caps.visibility.first);
        _joinPolicy = caps.joinPolicies.contains(_joinPolicy)
            ? _joinPolicy
            : (caps.joinPolicies.isEmpty ? 'friends' : caps.joinPolicies.first);
      });
    } on Object catch (error) {
      _showMessage('读取联机能力失败：$error', isError: true);
    }
  }

  Future<void> _refreshCurrentSession() async {
    final token = await _bbsToken();
    if (token == null) return;
    try {
      final session = await MdtbbsMultiplayerApi.currentSession(
        accessToken: token,
      );
      if (!mounted) return;
      setState(() => _current = session);
      if (session != null) await _refreshPeers(session.id);
    } on Object catch (error) {
      _showMessage('读取当前会话失败：$error', isError: true);
    }
  }

  Future<void> _refreshPeers(String sessionId) async {
    final token = await _bbsToken();
    if (token == null) return;
    try {
      final peers = await MdtbbsMultiplayerApi.peers(
        accessToken: token,
        sessionId: sessionId,
      );
      if (!mounted) return;
      setState(() => _peers = peers);
    } on Object catch (error) {
      _showMessage('读取对端失败：$error', isError: true);
    }
  }

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = isError;
    });
    // 页面很长，反馈只在页底会被误读成「没反应」；右下角通知保证看得见
    addNotice(
      icon: isError ? Icons.error_outline : Icons.check_circle_outline,
      title: isError ? '联机操作失败' : '联机',
      content: text,
      duration: const Duration(seconds: 8),
    );
  }

  // ── 官方会话动作 ──

  Future<void> _createSession() async {
    final token = await _bbsToken();
    if (token == null) {
      _showMessage('请先登录社区账号', isError: true);
      return;
    }
    final maxPlayers = int.tryParse(_maxPlayersController.text.trim()) ?? 8;
    if (maxPlayers < 2 || maxPlayers > 64) {
      _showMessage('人数上限要在 2–64 之间', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final created = await MdtbbsMultiplayerApi.createSession(
        accessToken: token,
        gameId: 'mindustry',
        activityName: _activityNameController.text.trim(),
        visibility: _visibility,
        joinPolicy: _joinPolicy,
        maxPlayers: maxPlayers,
      );
      _resumeToken = created.resumeToken;
      if (!mounted) return;
      setState(() {
        _created = created;
        _current = created.session;
      });
      _showMessage(
        created.joinCode == null
            ? '会话已创建（${created.session.id}）'
            : '会话已创建，加入码 ${created.joinCode}（只显示这一次，先记下来）',
      );
      await _refreshPeers(created.session.id);
    } on Object catch (error) {
      _showMessage('创建会话失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinByCode() async {
    final token = await _bbsToken();
    if (token == null) {
      _showMessage('请先登录社区账号', isError: true);
      return;
    }
    final code = _joinCodeController.text.trim();
    if (code.isEmpty) {
      _showMessage('请填加入码', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final session = await MdtbbsMultiplayerApi.resolveCode(
        accessToken: token,
        code: code,
      );
      final joined = await MdtbbsMultiplayerApi.join(
        accessToken: token,
        sessionId: session.id,
        joinCode: code,
      );
      _resumeToken = joined.resumeToken;
      if (!mounted) return;
      setState(() {
        _current = session;
        _created = null;
      });
      _showMessage('已加入会话（${session.id}）');
      await _refreshPeers(session.id);
    } on Object catch (error) {
      _showMessage('加入失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveSession() async {
    final session = _current;
    final token = await _bbsToken();
    if (session == null || token == null) return;
    setState(() => _busy = true);
    try {
      final outcome = await MdtbbsMultiplayerApi.leave(
        accessToken: token,
        sessionId: session.id,
      );
      _resumeToken = '';
      if (!mounted) return;
      setState(() {
        _current = null;
        _created = null;
        _peers = const [];
      });
      _showMessage(
        outcome.isOwnerLeaving
            ? '已退出；你是房主，会话进入 ${outcome.graceSeconds} 秒关闭宽限'
            : '已退出会话',
      );
    } on Object catch (error) {
      _showMessage('退出失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── MDT 兼容（LanLink 房间码，匿名可用）──

  Future<void> _resolveMdtRoom() async {
    final code = LanLinkRoomCode.tryParse(_mdtCodeController.text);
    if (code == null) {
      _showMessage('MDT 房间码形如 MDT-XXXXXX', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final room = await _lanlink.resolve(code);
      if (!mounted) return;
      setState(() => _mdtRoom = room);
      _showMessage(room == null ? '房间不存在或已关闭' : '已找到房间 ${room.code}');
    } on LanLinkException catch (error) {
      _showMessage(
        error.message.isEmpty ? '$error' : error.message,
        isError: true,
      );
    } on Object catch (error) {
      _showMessage('解析房间失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinMdtRoom(LanLinkRoom room) async {
    setState(() => _busy = true);
    try {
      final session = await _lanlink.join(room);
      _showMessage('已就绪：进游戏 → 加入游戏 → 局域网游戏里选「${session.roomName}」');
    } on LanLinkException catch (error) {
      _showMessage(
        error.message.isEmpty ? '$error' : error.message,
        isError: true,
      );
    } on Object catch (error) {
      _showMessage('加入失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveMdtRoom() async {
    await _lanlink.leave();
    if (!mounted) return;
    setState(() => _mdtRoom = null);
    _showMessage('已退出 MDT 房间');
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    _showMessage('$label 已复制：$text');
  }

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        _buildAccountStrip(),
        _buildOfficialPanel(),
        _buildMdtCompatPanel(),
        if (_message != null) _buildMessagePanel(),
      ],
    );
  }

  /// 链路状态条：官方会话需要社区账号（OAuth）；MDT 兼容不需要登录
  Widget _buildAccountStrip() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final bbs = _accounts.isLoggedIn;
    return ContentPanelModule(
      title: '账号状态',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Text(
            '${bbs ? '✓' : '×'} 社区账号（BBS）——官方会话需要；'
            'MDT 兼容不需要登录',
            style: theme.textTheme.bodySmall?.copyWith(
              color: bbs ? colors.itemSecondary : colors.error,
            ),
          ),
          if (!bbs)
            IconTextButton(
              icon: Icons.account_circle_outlined,
              content: '去账户页登录',
              onTap: () => Navigator.pushNamed(context, accountPageRouteKey),
            ),
        ],
      ),
    );
  }

  Widget _buildOfficialPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final caps = _capabilities;
    final session = _current;

    if (!_accounts.isLoggedIn) {
      return ContentPanelModule(
        title: '会话（官方）',
        child: Text(
          '登录社区账号后可用。官方会话走 MindAuth 授权，不需要密码。',
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
          '正在读取联机能力…',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.itemHint),
        ),
      );
    }
    if (!caps.usable) {
      return ContentPanelModule(
        title: '会话（官方）',
        child: Text(
          '站点当前未开放第三方联机会话（capabilities 显示不可用）',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
        ),
      );
    }

    return ContentPanelModule(
      title: '会话（官方）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Text(
            '创建或加入官方联机会话；进服数据通道（官方中继）还在开发中，'
            '目前是控制面部分。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          if (session != null)
            _buildOfficialSessionCard(session)
          else ...[
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: OutlinedTextField(
                    controller: _activityNameController,
                    label: '活动名（可选）',
                    enable: !_busy,
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: OutlinedTextField(
                    controller: _maxPlayersController,
                    label: '人数',
                    enable: !_busy,
                  ),
                ),
              ],
            ),
            Row(
              spacing: 8,
              children: [
                Text(
                  '可见 $_visibility / 加入策略 $_joinPolicy（默认私有+好友，'
                  '后续开放选择）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.itemSecondary,
                  ),
                ),
                IconTextButton(
                  icon: Icons.add_circle_outline,
                  content: '创建会话',
                  onTap: _busy ? null : _createSession,
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
                    enable: !_busy,
                    onEditingComplete: _joinByCode,
                  ),
                ),
                IconTextButton(
                  icon: Icons.login,
                  content: '加入',
                  onTap: _busy ? null : _joinByCode,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOfficialSessionCard(MdtbbsSession session) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final created = _created;
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
            created?.session.id == session.id && created != null
                ? '我创建的会话'
                : '已加入会话',
            style: theme.textTheme.titleSmall,
          ),
          if (created?.joinCode != null)
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    '加入码 ${created!.joinCode}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                IconTextButton(
                  icon: Icons.copy,
                  content: '复制',
                  onTap: () => _copy(created.joinCode!, '加入码'),
                ),
              ],
            ),
          Text(
            '${session.visibility} / ${session.joinPolicy}    '
            '人数 ${session.currentPlayers}/${session.maxPlayers}    '
            '状态 ${session.status}'
            '${_resumeToken.isEmpty ? '' : '    断线 60 秒内可恢复'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          if (_peers.isNotEmpty)
            Text(
              '对端：${_peers.map((p) => '${p.role == 'owner' ? '房主' : '成员'}(${p.status})').join('、')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
          Row(
            spacing: 8,
            children: [
              IconTextButton(
                icon: Icons.refresh,
                content: '刷新对端',
                onTap: _busy ? null : () => _refreshPeers(session.id),
              ),
              IconTextButton(
                icon: Icons.logout,
                content: '退出会话',
                onTap: _busy ? null : _leaveSession,
              ),
            ],
          ),
          Text(
            '进服数据通道（官方中继）开发中：目前还不能从这里真正进游戏。',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.itemHint),
          ),
        ],
      ),
    );
  }

  /// MDT 兼容：LanLink 房间码加入。**匿名可用**（房间信息是公开接口），
  /// 保留它是因为 MDT 模组用户都在这个生态里
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
            '加入 MDTBBS LanLink 模组开的房间：填房间码即可，不需要登录。'
            '（在 LanLink 里开房的用户会显示这个码）',
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
                    enable: !_busy,
                    onEditingComplete: _resolveMdtRoom,
                  ),
                ),
                IconTextButton(
                  icon: Icons.search,
                  content: '解析',
                  onTap: _busy ? null : _resolveMdtRoom,
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
            icon: Icons.login,
            content: '加入',
            onTap: _busy ? null : () => _joinMdtRoom(room),
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
            '已就绪：${room.name.isEmpty ? room.code : room.name}',
            style: theme.textTheme.titleSmall,
          ),
          Text(
            '进游戏 → 加入游戏 → 局域网游戏里选这个房间（${_lanlink.localAddress}）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          IconTextButton(
            icon: Icons.logout,
            content: '退出房间',
            onTap: _busy ? null : _leaveMdtRoom,
          ),
        ],
      ),
    );
  }

  Widget _buildMessagePanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return ContentPanelModule(
      title: '状态',
      child: Text(
        _message ?? '',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: _messageIsError
              ? theme.colorScheme.error
              : colors.itemSecondary,
        ),
      ),
    );
  }
}
