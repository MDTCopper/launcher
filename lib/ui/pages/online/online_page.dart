import 'dart:async';

import 'package:copper_launcher/data/net/lanlink/lanlink_api.dart';
import 'package:copper_launcher/data/net/lanlink/lanlink_models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_models.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_multiplayer_models.dart';
import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/domain/lanlink/lanlink_service.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_friends_service.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_multiplayer_service.dart';
import 'package:copper_launcher/domain/mdtbbs/mdtbbs_multiplayer_state.dart';
import 'package:copper_launcher/ui/components/animation/animated_expansion.dart';
import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/avatar/user_avatar.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/pages/account/account_page.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_friends_api.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const onlinePageRouteKey = '/online';

/// 页面内的三块，不走路由
enum _OnlineView { entry, host, guest }

const _maxPlayerChoices = [2, 4, 8, 16, 32];

const _roomPresets = [
  (label: '仅邀请可进', visibility: 'private', joinPolicy: 'invite_only'),
  (label: '仅好友可进', visibility: 'friends', joinPolicy: 'friends'),
  (label: '公开', visibility: 'public', joinPolicy: 'public'),
];

class OnlinePage extends StatefulWidget {
  const OnlinePage({super.key});

  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

class _OnlinePageState extends State<OnlinePage> {
  _OnlineView _view = _OnlineView.entry;

  final _roomNameController = TextEditingController();
  final _joinCodeController = TextEditingController();
  final _inviteUserIdController = TextEditingController();

  int _maxPlayers = 8;
  String _visibility = 'private';
  String _joinPolicy = 'invite_only';
  bool _requireApproval = false;
  Timer? _retryTicker;
  Timer? _peerTicker;

  /// 上一帧是否在房间里：用来判断「刚退出房间」，退出后回到入口页
  bool _wasInSession = false;

  MdtbbsMultiplayerService get _mp => MdtbbsMultiplayerService.instance;
  MdtbbsFriendsService get _friends => MdtbbsFriendsService.instance;
  AccountManager get _accounts => AccountManager.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
    _wasInSession = _mp.state.value.inSession;
    _mp.state.addListener(_onMultiplayerStateChanged);
    _retryTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_mp.state.value.proxyRetryAt == null) return;
      setState(() {});
    });
    // 房主会切到游戏再切回来：不主动拉，玩家列表会一直停在离开前的样子
    _peerTicker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      final state = _mp.state.value;
      if (!state.inSession || state.refreshingPeers) return;
      unawaited(_mp.refreshPeers());
      unawaited(_mp.refreshSessionStatus());
    });
  }

  @override
  void dispose() {
    _mp.state.removeListener(_onMultiplayerStateChanged);
    _retryTicker?.cancel();
    _peerTicker?.cancel();
    _mp.stopInvitePolling();
    _roomNameController.dispose();
    _joinCodeController.dispose();
    _inviteUserIdController.dispose();
    super.dispose();
  }

  /// 退出 / 被关闭房间后回到入口页，不在房间视图里空着
  void _onMultiplayerStateChanged() {
    final inSession = _mp.state.value.inSession;
    final was = _wasInSession;
    _wasInSession = inSession;
    if (!was || inSession || _view == _OnlineView.entry) return;
    if (!mounted) return;
    setState(() => _view = _OnlineView.entry);
  }

  Future<void> _initialize() async {
    await _mp.restore();
    unawaited(_mp.refreshPeers());
    unawaited(_mp.refreshSessionStatus());
    if (_accounts.isLoggedIn && _accounts.account == null) {
      try {
        await _accounts.loadAccount();
      } on Object {
        // 读不到就按未知处理，页面照常
      }
    }
    await _mp.loadCapabilities();
    if (_accounts.isLoggedIn) unawaited(_friends.load());
    if (!mounted) return;
    if (_roomNameController.text.trim().isEmpty) {
      final name = _accounts.account?.username;
      _roomNameController.text = name == null || name.isEmpty
          ? '我的房间'
          : '$name 的房间';
    }
    final state = _mp.state.value;
    if (state.inSession) {
      _setView(
        state.self?.role == 'owner' ? _OnlineView.host : _OnlineView.guest,
      );
    }
    // LanLink 的桥在服务层活着，重新进页面要把它那条状态画出来
    setState(() {});
  }

  void _setView(_OnlineView view) {
    if (!mounted) return;
    setState(() => _view = view);
    if (view == _OnlineView.guest) {
      _mp.startInvitePolling();
      unawaited(_mp.refreshInvites());
    } else {
      _mp.stopInvitePolling();
    }
  }

  bool _ensureLoggedIn() {
    if (_accounts.snapshot.value.loggedIn) return true;
    addNotice(
      icon: Icons.account_circle_outlined,
      title: '需要社区账号',
      content: '创建或加入房间需要先登录社区账号',
    );
    return false;
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    addNotice(
      icon: Icons.copy_all_outlined,
      title: '已复制',
      content: '$label：$text',
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _createRoom() async {
    final caps = _mp.state.value.capabilities;
    if (caps != null && (!caps.usable || !caps.relayEnabled)) {
      addNotice(
        icon: Icons.info_outline,
        title: '服务端暂未开放',
        content: caps.usable ? '联机中继当前不可用' : '联机功能当前未开放',
      );
      return;
    }
    if (!_ensureLoggedIn()) return;
    final visibility = (caps == null || caps.visibility.contains(_visibility))
        ? _visibility
        : (caps.visibility.isNotEmpty ? caps.visibility.first : 'private');
    final joinPolicy =
        (caps == null || caps.joinPolicies.contains(_joinPolicy))
        ? _joinPolicy
        : (caps.joinPolicies.isNotEmpty ? caps.joinPolicies.first : 'public');
    await _stopLanLinkIfJoined();
    await _mp.create(
      activityName: _roomNameController.text.trim().isEmpty
          ? '我的房间'
          : _roomNameController.text.trim(),
      visibility: visibility,
      joinPolicy: joinPolicy,
      requireApproval:
          (caps?.requireApprovalSupported ?? true) && _requireApproval,
      maxPlayers: _maxPlayers,
    );
  }

  Future<void> _joinByCode() async {
    if (!_ensureLoggedIn()) return;
    final raw = _joinCodeController.text.trim();
    final code = _normalizeJoinCode(raw);
    if (code.isEmpty) {
      addNotice(
        icon: Icons.error_outline,
        title: raw.isEmpty ? '还没有房间码' : '房间码格式不对',
        content: raw.isEmpty
            ? '先向房主要 6 位房间码'
            : '房间码是 6~12 位十六进制；也可以直接粘贴分享文本',
      );
      return;
    }
    _joinCodeController.text = code;
    await _stopLanLinkIfJoined();
    await _mp.joinByCode(code);
  }

  /// 两种联机都占本机 6567 与组播 20151，同时开必冲突
  Future<void> _stopLanLinkIfJoined() async {
    if (!LanLinkService.instance.isJoined) return;
    await LanLinkService.instance.leave();
    if (mounted) setState(() {});
  }

  Future<void> _showLanLinkJoin() async {
    if (_mp.state.value.inSession) {
      addNotice(
        icon: Icons.info_outline,
        title: '先退出官方联机房间',
        content: 'LanLink 与官方联机都占本机 6567 端口，同时开会冲突',
      );
      return;
    }
    final room = await showAnimatedDialog<LanLinkRoom>(
      context: context,
      pageBuilder: (context, _, _) => const _LanLinkJoinDialog(),
    );
    if (!mounted || room == null) return;
    setState(() {});
    addNotice(
      icon: Icons.cable,
      title: '已加入 LanLink 房间',
      content: '${room.code} ${room.displayName} · 进游戏在「局域网游戏」里找它',
      duration: const Duration(seconds: 8),
    );
  }

  Future<void> _leaveLanLink() async {
    await LanLinkService.instance.leave();
    if (!mounted) return;
    setState(() {});
    addNotice(icon: Icons.link_off, title: '已离开 LanLink 房间');
  }

  /// 从整段分享文本里抠出房间码；没有就按原样大写
  String _normalizeJoinCode(String input) {
    final text = input.trim();
    final match = RegExp(r'[0-9a-fA-F]{6,12}').firstMatch(text);
    final code = (match?.group(0) ?? text).toUpperCase();
    // 服务端限制 code <= 32 字符，别把整段日志/链接直接发过去
    return code.length <= 32 ? code : '';
  }

  Future<void> _pasteJoinCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    final code = _normalizeJoinCode(text);
    if (code.isEmpty) return;
    _joinCodeController.text = code;
  }

  Future<void> _confirmCloseRoom() async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      pageBuilder: (context, _, _) => const _ConfirmDialog(
        title: '关闭房间？',
        message: '关闭后房间码会失效，成员会被断开；重新开房会生成新的房间码。',
        confirmLabel: '关闭房间',
      ),
    );
    if (confirmed == true) await _mp.leave();
  }

  /// 房主重建房间：换一个 Peer，绕开失败分配的 120 秒额度
  Future<void> _rebuildRoom() async {
    final state = _mp.state.value;
    if (state.self?.role != 'owner') {
      addNotice(
        icon: Icons.info_outline,
        title: '只有房主能重建',
        content: '成员先退出房间，再让房主重新开房',
      );
      return;
    }
    if (state.inSession) {
      await _mp.leave();
      for (var attempt = 0; attempt < 40; attempt++) {
        if (_mp.state.value.session == null) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (_mp.state.value.session != null) {
        addNotice(
          icon: Icons.error_outline,
          title: '房间没关掉',
          content: '稍等一下再试',
        );
        return;
      }
    }
    await _createRoom();
  }

  Future<void> _joinInvite(MdtbbsInvite invite) async {
    await _mp.acceptInvite(invite.inviteId);
  }

  Future<void> _showInviteDialog() async {
    final state = _mp.state.value;
    if (!state.inSession) {
      addNotice(
        icon: Icons.info_outline,
        title: '先开启房间',
        content: '房间开启后才能邀请好友',
      );
      return;
    }
    await showAnimatedDialog(
      context: context,
      pageBuilder: (context, _, _) => _InviteFriendDialog(
        roomCode: state.joinCode,
        onInvite: (userId) => _mp.inviteFriend(userId),
        onCopyCode: state.joinCode == null
            ? null
            : () => _copy(state.joinCode!, '房间码'),
      ),
    );
  }

  String _shareText(MultiplayerState state) {
    final name = state.session?.activityName?.trim();
    return '【Copper 联机】'
        '${name == null || name.isEmpty ? '联机房间' : name}\n'
        '房间码 ${state.joinCode ?? '—'}\n'
        '房间码只是入口；能不能进看房间的加入方式\n'
        '用 Copper 启动器 → 联机 → 我是客人，输入这个码';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _mp.state,
        _accounts.snapshot,
        _friends.state,
      ]),
      builder: (context, _) {
        final state = _mp.state.value;
        final loggedIn = _accounts.snapshot.value.loggedIn;
        final view = switch (_view) {
          _OnlineView.entry => _buildEntry(state, loggedIn),
          _OnlineView.host => _buildHost(state, loggedIn),
          _OnlineView.guest => _buildGuest(state, loggedIn),
        };
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, animation) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0.03, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(key: ValueKey(_view), child: view),
        );
      },
    );
  }

  // ── 入口 ────────────────────────────────────────────────────

  Widget _buildEntry(MultiplayerState state, bool loggedIn) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return CopperSingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.block),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final buttons = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.group,
              children: [
                if (state.inSession) _buildResumeCard(state),
                _buildBigModeButton(
                  icon: Icons.meeting_room_outlined,
                  title: '我是房主',
                  subtitle: '创建房间，把房间码发给朋友',
                  onTap: () => _setView(_OnlineView.host),
                ),
                _buildBigModeButton(
                  icon: Icons.login,
                  title: '我是客人',
                  subtitle: '输入房间码加入朋友的房间',
                  onTap: () => _setView(_OnlineView.guest),
                ),
                _buildBigModeButton(
                  icon: Icons.cable,
                  title: 'LanLink',
                  subtitle: '用社区模组的 MDT-XXXXXX 房间码加入',
                  onTap: _showLanLinkJoin,
                ),
                if (LanLinkService.instance.isJoined)
                  _buildLanLinkPanel(LanLinkService.instance.activeRoom),
                if (!loggedIn)
                  Row(
                    spacing: AppSpacing.related,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: AppIconSize.item,
                        color: colors.itemHint,
                      ),
                      Expanded(
                        child: Text(
                          '还没登录：创建 / 加入房间需要社区账号',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.itemHint,
                          ),
                        ),
                      ),
                      IconTextButton(
                        pressedScale: 0.96,
                        icon: Icons.account_circle_outlined,
                        content: '去登录',
                        onTap: () => Navigator.pushNamed(
                          context,
                          accountPageRouteKey,
                        ),
                      ),
                    ],
                  ),
              ],
            );
            final disclaimer = _buildDisclaimer(state);
            final side = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.block,
              children: [buttons],
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.block,
                children: [disclaimer, side],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.block,
              children: [
                Expanded(child: disclaimer),
                SizedBox(width: 360, child: side),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBigModeButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return ReboundButton(
      onTap: onTap,
      pressedScale: 0.97,
      borderRadius: BorderRadius.circular(AppRadius.panel),
      backgroundColor: colors.cardBackground,
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.block,
          vertical: AppSpacing.section,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.panel),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          spacing: AppSpacing.section,
          children: [
            Icon(icon, size: AppIconSize.large, color: colors.interactive),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.itemSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: AppIconSize.inline,
              color: colors.itemHint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanLinkPanel(LanLinkRoom? room) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final name = room == null || room.displayName.isEmpty
        ? 'LanLink 房间'
        : room.displayName;
    return ContentPanelModule(
      title: 'LanLink 已加入',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          Text('${room?.code ?? ''}  $name', style: theme.textTheme.titleSmall),
          Text(
            '本机桥 ${LanLinkService.instance.localAddress}；'
            '进游戏在「局域网游戏」里找它',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconTextButton(
              pressedScale: 0.96,
              icon: Icons.link_off,
              content: '离开 LanLink 房间',
              onTap: _leaveLanLink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimer(MultiplayerState state) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return ContentPanelModule(
      title: '联机',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          Text(
            '官方的联机功能还在测试。房间码只发给信任的人，不要发到公开场合。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          Text(
            '可见范围只决定谁能发现房间，加入方式只决定谁有资格；'
            '房间码、邀请链接、大厅点击都只是入口，不是权限。',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.itemHint),
          ),
          Text(
            '房间数据由社区中继转发，服务器忙的时候可能要等一会儿才能连上；'
            '进入游戏后优先在「局域网游戏」里找房间，找不到再直连页面提示的地址。',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.itemHint),
          ),
          Text(
            'LanLink 走社区模组的房间码（MDT-XXXXXX），与本机官方联机不能同时开：'
            '两者都占 6567 端口。',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.itemHint),
          ),
          if (state.lastMessage != null)
            Text(
              state.lastMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: state.lastMessageIsError
                    ? theme.colorScheme.error
                    : colors.itemSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResumeCard(MultiplayerState state) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final isOwner = state.self?.role == 'owner';
    return ContentPanelModule(
      title: '你有一个进行中的房间',
      child: Row(
        spacing: AppSpacing.related,
        children: [
          Expanded(
            child: Text(
              '${state.session?.activityName ?? '联机房间'}'
              '${state.joinCode == null ? '' : ' · ${state.joinCode}'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
          ),
          IconTextButton(
            pressedScale: 0.96,
            icon: Icons.meeting_room_outlined,
            content: '回到房间',
            onTap: () => _setView(isOwner ? _OnlineView.host : _OnlineView.guest),
          ),
        ],
      ),
    );
  }

  // ── 房主 ────────────────────────────────────────────────────

  Widget _buildHost(MultiplayerState state, bool loggedIn) {
    return Column(
      children: [
        _buildHostHeader(state),
        Expanded(
          child: ListContentPanel(
            items: [_buildHostBody(state, loggedIn)],
            showBackToTop: false,
          ),
        ),
      ],
    );
  }

  Widget _buildHostHeader(MultiplayerState state) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final code = state.joinCode;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.block,
        AppSpacing.section,
        AppSpacing.block,
        AppSpacing.related,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final codeBlock = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  '房间码 · ${state.self?.role == 'owner' ? '房主' : '成员'}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.itemHint,
                  ),
                ),
                if (code == null)
                  Text(
                    state.creating
                        ? '正在开启房间…'
                        : state.inSession
                        ? '房间已开启，但服务端没有给房间码'
                        : '开启房间以获取房间码',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.itemHint,
                    ),
                  )
                else
                  InkWell(
                    onTap: () => _copy(code, '房间码'),
                    child: Text(
                      code,
                      style:
                          (compact
                                  ? theme.textTheme.headlineMedium
                                  : theme.textTheme.displaySmall)
                              ?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                    ),
                  ),
              ],
            ),
          );
          final action = _buildHeaderAction(state);
          final copyShare = <Widget>[
            if (code != null) ...[
              IconTextButton(
                pressedScale: 0.96,
                icon: Icons.copy,
                content: '复制',
                onTap: () => _copy(code, '房间码'),
              ),
              IconTextButton(
                pressedScale: 0.96,
                icon: Icons.ios_share,
                content: '分享',
                onTap: () => _copy(_shareText(state), '房间信息'),
              ),
            ],
          ];
          if (!compact) {
            return Row(
              spacing: AppSpacing.related,
              children: [
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.arrow_back,
                  content: '返回',
                  onTap: () => _setView(_OnlineView.entry),
                ),
                const SizedBox(width: AppSpacing.related),
                codeBlock,
                ...copyShare,
                const SizedBox(width: AppSpacing.group),
                action,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.related,
            children: [
              Row(
                spacing: AppSpacing.related,
                children: [
                  IconTextButton(
                    pressedScale: 0.96,
                    icon: Icons.arrow_back,
                    content: '返回',
                    onTap: () => _setView(_OnlineView.entry),
                  ),
                  codeBlock,
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: AppSpacing.related,
                children: [...copyShare, action],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderAction(MultiplayerState state) {
    if (state.self?.role == 'owner') {
      return IconTextButton(
        pressedScale: 0.96,
        icon: state.inSession
            ? Icons.stop_circle_outlined
            : Icons.play_circle_outline,
        content: state.inSession
            ? (state.leaving ? '正在关闭…' : '关闭房间')
            : (state.creating ? '正在开启…' : '开启房间'),
        onTap: state.inSession
            ? (state.leaving ? null : _confirmCloseRoom)
            : (state.creating ? null : _createRoom),
      );
    }
    if (state.inSession) {
      return IconTextButton(
        pressedScale: 0.96,
        icon: Icons.logout,
        content: state.leaving ? '正在离开…' : '离开房间',
        onTap: state.leaving ? null : _mp.leave,
      );
    }
    return IconTextButton(
      pressedScale: 0.96,
      icon: Icons.play_circle_outline,
      content: state.creating ? '正在开启…' : '开启房间',
      onTap: state.creating ? null : _createRoom,
    );
  }

  Widget _buildHostBody(MultiplayerState state, bool loggedIn) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final status = _buildRoomStatusPanel(state);
        final config = AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(
            key: ValueKey(state.inSession),
            child: _buildConfigPanel(state, loggedIn),
          ),
        );
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.group,
            children: [status, config],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.group,
          children: [
            Expanded(child: status),
            SizedBox(width: 320, child: config),
          ],
        );
      },
    );
  }

  Widget _buildConfigPanel(MultiplayerState state, bool loggedIn) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final caps = state.capabilities;
    final locked = state.inSession || state.creating;
    final visibility = _effectiveVisibility(caps);
    final joinPolicy = _effectiveJoinPolicy(caps);
    final approvalSupported = caps?.requireApprovalSupported ?? true;

    if (state.inSession) return _buildConfigTable(state);

    return ContentPanelModule(
      title: '房间配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          if (state.lastMessage != null && state.lastMessageIsError)
            Text(
              state.lastMessage!,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          if (!loggedIn)
            Row(
              spacing: AppSpacing.related,
              children: [
                Expanded(
                  child: Text(
                    '登录后才能开启房间',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.account_circle_outlined,
                  content: '去登录',
                  onTap: () =>
                      Navigator.pushNamed(context, accountPageRouteKey),
                ),
              ],
            ),
          Text('房间名', style: theme.textTheme.labelMedium),
          OutlinedTextField(
            controller: _roomNameController,
            label: '好友看到的房间名',
            enable: !locked,
          ),
          Text('人数', style: theme.textTheme.labelMedium),
          Wrap(
            spacing: AppSpacing.related,
            runSpacing: AppSpacing.related,
            children: [
              for (final count in _maxPlayerChoices)
                ActionButton(
                  content: Text('$count 人'),
                  selected: _maxPlayers == count,
                  enable: !locked,
                  onTap: () => setState(() => _maxPlayers = count),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.group,
                    vertical: AppSpacing.tight,
                  ),
                ),
            ],
          ),
          Row(
            spacing: AppSpacing.related,
            children: [
              Expanded(
                child: Text(
                  '进房需我同意',
                  style: theme.textTheme.labelMedium,
                ),
              ),
              ActionButton(
                content: Text(_requireApproval ? '开' : '关'),
                selected: _requireApproval,
                enable: !locked && approvalSupported,
                onTap: () =>
                    setState(() => _requireApproval = !_requireApproval),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.group,
                  vertical: AppSpacing.tight,
                ),
              ),
            ],
          ),
          Text(
            approvalSupported
                ? (_requireApproval
                      ? '符合加入条件的人也要我同意才进得来'
                      : '符合条件的人拿到房间码就能直接进')
                : '服务端暂不支持「需我同意」这一项',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.itemHint),
          ),
          Divider(color: colors.border, height: 1),
          Text('无脑配置预设', style: theme.textTheme.labelMedium),
          Wrap(
            spacing: AppSpacing.related,
            runSpacing: AppSpacing.related,
            children: [
              for (final preset in _roomPresets)
                ActionButton(
                  content: Text(preset.label),
                  hint:
                      '${_visibilityLabel(preset.visibility)} + '
                      '${_joinPolicyLabel(preset.joinPolicy)}',
                  selected:
                      _visibility == preset.visibility &&
                      _joinPolicy == preset.joinPolicy,
                  enable: !locked,
                  onTap: () => setState(() {
                    _visibility = preset.visibility;
                    _joinPolicy = preset.joinPolicy;
                  }),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.group,
                    vertical: AppSpacing.tight,
                  ),
                ),
            ],
          ),
          AnimatedExpansion(
            title: const Text('高级选项'),
            color: colors.cardBackground,
            children: [
              if (caps == null)
                Text(
                  '正在读取服务端能力…',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.itemHint,
                  ),
                )
              else ...[
                Text('谁能看到房间', style: theme.textTheme.labelMedium),
                IgnorePointer(
                  ignoring: locked,
                  child: DropdownLayer<String>(
                    initialValue: visibility,
                    options: [
                      for (final value in caps.visibility)
                        DropdownOption(
                          value: value,
                          label: _visibilityLabel(value),
                        ),
                    ],
                    onSelect: (value) {
                      if (!locked) setState(() => _visibility = value);
                    },
                  ),
                ),
                Text('谁能加入', style: theme.textTheme.labelMedium),
                IgnorePointer(
                  ignoring: locked,
                  child: DropdownLayer<String>(
                    initialValue: joinPolicy,
                    options: [
                      for (final value in caps.joinPolicies)
                        DropdownOption(
                          value: value,
                          label: _joinPolicyLabel(value),
                        ),
                    ],
                    onSelect: (value) {
                      if (!locked) setState(() => _joinPolicy = value);
                    },
                  ),
                ),
                Text(
                  '官方 1.7.0：可见范围与加入方式是两个正交单选，'
                  '「需我同意」是独立的 require_approval 布尔。',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.itemHint,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigTable(MultiplayerState state) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final session = state.session;
    final visibility = session?.visibility ?? _visibility;
    final joinPolicy = session?.joinPolicy ?? _joinPolicy;
    final approval = session?.requireApproval ?? _requireApproval;
    return ContentPanelModule(
      title: '房间配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          _buildInfoRow('房间名', session?.activityName ?? '—'),
          _buildInfoRow('人数', '${session?.maxPlayers ?? _maxPlayers} 人'),
          _buildInfoRow('可见范围', _visibilityLabel(visibility)),
          _buildInfoRow('加入方式', _joinPolicyLabel(joinPolicy)),
          _buildInfoRow('需我同意', approval ? '是' : '否'),
          const SizedBox(height: AppSpacing.tight),
          Text(
            '房间已开启，改配置要先关闭房间',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.itemHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        spacing: AppSpacing.related,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.itemHint,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 客人 ────────────────────────────────────────────────────

  Widget _buildGuest(MultiplayerState state, bool loggedIn) {
    final inRoom = state.inSession;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.block,
            AppSpacing.section,
            AppSpacing.block,
            AppSpacing.related,
          ),
          child: Row(
            children: [
              IconTextButton(
                pressedScale: 0.96,
                icon: Icons.arrow_back,
                content: '返回',
                onTap: () => _setView(_OnlineView.entry),
              ),
              const Spacer(),
              Text(
                inRoom ? '房间' : '加入房间',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (inRoom)
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.logout,
                  content: state.leaving ? '正在离开…' : '离开房间',
                  onTap: state.leaving ? null : _mp.leave,
                )
              else
                const SizedBox(width: 72),
            ],
          ),
        ),
        Expanded(
          child: inRoom
              ? ListContentPanel(
                  items: [_buildRoomStatusPanel(state)],
                  showBackToTop: false,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // 宽且够高才按 5:4 分区；手机上固定比例会把内容顶出屏幕
                    final split =
                        constraints.maxWidth >= 760 &&
                        constraints.maxHeight >= 560;
                    if (split) {
                      return Column(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Align(
                              alignment: const Alignment(0, 0.25),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 420,
                                ),
                                child: _buildJoinCodePanel(state, loggedIn),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: ListContentPanel(
                              items: [_buildInvitesPanel(state, loggedIn)],
                              showBackToTop: false,
                            ),
                          ),
                        ],
                      );
                    }
                    return CopperSingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.block,
                          0,
                          AppSpacing.block,
                          AppSpacing.block,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: AppSpacing.block,
                          children: [
                            _buildJoinCodePanel(state, loggedIn),
                            _buildInvitesPanel(state, loggedIn),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildJoinCodePanel(MultiplayerState state, bool loggedIn) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return ContentPanelModule(
      title: '输入房间码',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          if (!loggedIn)
            Text(
              '加入房间需要先登录社区账号',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          OutlinedTextField(
            controller: _joinCodeController,
            label: '房间码',
            enable: !state.joining,
            onEditingComplete: _joinByCode,
          ),
          OverflowBar(
            alignment: MainAxisAlignment.start,
            spacing: AppSpacing.related,
            overflowSpacing: AppSpacing.related,
            children: [
              IconTextButton(
                pressedScale: 0.96,
                icon: Icons.login,
                content: state.joining ? '正在加入…' : '加入房间',
                onTap: state.joining ? null : _joinByCode,
              ),
              IconTextButton(
                pressedScale: 0.96,
                icon: Icons.content_paste,
                content: '粘贴',
                onTap: state.joining ? null : _pasteJoinCode,
              ),
              if (!loggedIn)
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.account_circle_outlined,
                  content: '去登录',
                  onTap: () =>
                      Navigator.pushNamed(context, accountPageRouteKey),
                ),
            ],
          ),
          Text(
            '向房主要 6 位房间码。房间码只是入口，能不能进看房主设的加入方式；'
            '加入后进游戏，在「局域网游戏」里找房间',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.itemHint,
            ),
          ),
        ],
      ),
    );
  }

  /// 收到的房间邀请：好友列表搬去账户抽屉了，联机页只留跟「进这个房间」有关的东西
  Widget _buildInvitesPanel(MultiplayerState state, bool loggedIn) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final invites = state.invites;
    return ContentPanelModule(
      title: '收到的邀请',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          if (!loggedIn)
            Text(
              '登录后可以看到好友发来的房间邀请',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.itemHint,
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    invites.isEmpty ? '还没有收到邀请' : '共  条',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.itemSecondary,
                    ),
                  ),
                ),
                IconTextButton(
                  pressedScale: 0.96,
                  icon: Icons.refresh,
                  content: state.loadingInvites ? '正在刷新…' : '刷新',
                  onTap: state.loadingInvites
                      ? null
                      : () => _mp.refreshInvites(announce: true),
                ),
              ],
            ),
            for (final invite in invites) _buildInviteRow(state, invite),
            if (invites.isEmpty)
              Text(
                '好友在「好友」页或房间里点「邀请」；也可以直接把房间码发给朋友',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.itemHint,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildInviteRow(MultiplayerState state, MdtbbsInvite invite) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final busy = state.busyInviteId == invite.inviteId;
    final name = invite.session?.activityName?.trim();
    return Row(
      spacing: AppSpacing.related,
      children: [
        Expanded(
          child: Text(
            '用户 ${invite.senderUserId} 邀请你加入'
            '${name == null || name.isEmpty ? '房间' : '「$name」'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
        ),
        IconTextButton(
          pressedScale: 0.96,
          icon: Icons.login,
          content: busy ? '正在加入…' : '加入',
          onTap: busy ? null : () => _joinInvite(invite),
        ),
      ],
    );
  }

  // ── 房间状态（房主 / 客人都用） ─────────────────────────────

  Widget _buildRoomStatusPanel(MultiplayerState state) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final session = state.session;
    final peers = state.peers;
    return ContentPanelModule(
      title: '房间玩家',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          if (session == null)
            Text(
              state.resuming ? '正在恢复房间…' : '还没有开启房间',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemHint,
              ),
            )
          else ...[
            Row(
              spacing: AppSpacing.related,
              children: [
                Expanded(
                  child: Text(
                    session.activityName?.trim().isNotEmpty == true
                        ? session.activityName!
                        : '联机房间',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${state.onlinePeerCount > 0 ? state.onlinePeerCount : '—'}'
                  ' / ${session.maxPlayers} 人',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.itemSecondary,
                  ),
                ),
              ],
            ),
            if (session.status == 'closing' || session.status == 'expired')
              Text(
                session.status == 'closing' ? '房间正在关闭' : '房间已过期',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.error,
                ),
              ),
            Text(
              _roomPhaseLabel(state),
              style: theme.textTheme.bodySmall?.copyWith(
                color: state.proxyError != null
                    ? colors.error
                    : state.proxyRunning
                    ? theme.colorScheme.primary
                    : colors.itemSecondary,
              ),
            ),
            if (peers.isEmpty)
              Text(
                '还没有成员加入',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.itemHint,
                ),
              )
            else
              for (final peer in peers) _buildPeerRow(state, peer),
            if (state.heartbeatFailures > 0)
              Text(
                '网络不稳定（心跳失败 ${state.heartbeatFailures} 次）',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.error,
                ),
              ),
            if (state.proxyError != null) ...[
              Text(
                state.proxyError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.error,
                ),
              ),
              if (state.proxyRetryAt != null)
                Text(
                  _retrySuffix(state).replaceAll(RegExp(r'[（）]'), ''),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.itemHint,
                  ),
                ),
              Wrap(
                spacing: AppSpacing.related,
                runSpacing: AppSpacing.related,
                children: [
                  IconTextButton(
                    pressedScale: 0.96,
                    icon: Icons.refresh,
                    content: (() {
                      final seconds = _retrySeconds(state);
                      return seconds != null && seconds > 0
                          ? '$seconds 秒后可重试'
                          : '重试';
                    })(),
                    onTap: state.startingProxy || (_retrySeconds(state) ?? 0) > 0
                        ? null
                        : _mp.retryProxy,
                  ),
                  if (state.self?.role == 'owner')
                    IconTextButton(
                      pressedScale: 0.96,
                      icon: Icons.restart_alt,
                      content: '重建房间',
                      onTap: state.leaving ? null : _rebuildRoom,
                    ),
                  IconTextButton(
                    pressedScale: 0.96,
                    icon: Icons.copy_all_outlined,
                    content: '复制诊断',
                    onTap: () => _copy(
                      _diagnostics(state),
                      '诊断信息',
                    ),
                  ),
                ],
              ),
            ],
            _buildGameHint(state),
          ],
          if (state.inSession) ...[
            const SizedBox(height: AppSpacing.tight),
            if (state.self?.role == 'owner') _buildInviteTile(state),
          ],
        ],
      ),
    );
  }

  /// 房间里非好友成员的公开资料（按 userId 缓存，取到一次就够）
  final Map<String, MdtbbsFriendUser> _peerProfiles = {};
  final Set<String> _peerProfileLoading = {};
  final Set<String> _friendRequestSent = {};

  /// 成员头像：自己用账号头像，好友用好友资料，陌生人用拉到的公开资料
  String? _peerAvatarUrl(String userId, {required bool isSelf}) {
    if (isSelf) return AccountManager.instance.snapshot.value.avatarUrl;
    for (final entry in MdtbbsFriendsService.instance.state.value.friends) {
      if ('${entry.user.userId}' == userId) return entry.user.avatarUrl;
    }
    return _peerProfiles[userId]?.avatarUrl;
  }

  bool _isFriend(String userId) {
    for (final entry in MdtbbsFriendsService.instance.state.value.friends) {
      if ('${entry.user.userId}' == userId) return true;
    }
    return false;
  }

  String? _peerName(String userId) {
    final profile = _peerProfiles[userId];
    if (profile != null && profile.username.isNotEmpty) return profile.username;
    for (final entry in MdtbbsFriendsService.instance.state.value.friends) {
      if ('${entry.user.userId}' == userId) return entry.user.username;
    }
    return null;
  }

  void _ensurePeerProfile(String userId) {
    final id = int.tryParse(userId);
    if (id == null || id <= 0) return;
    if (_peerProfiles.containsKey(userId) ||
        _peerProfileLoading.contains(userId)) {
      return;
    }
    _peerProfileLoading.add(userId);
    unawaited(() async {
      try {
        final token = await AccountManager.instance.ensureAccessToken();
        if (token == null) return;
        final profile = await MdtbbsFriendsApi.userProfile(
          accessToken: token,
          userId: id,
        );
        if (!mounted) return;
        setState(() => _peerProfiles[userId] = profile);
      } on Object {
        // 读不到就继续显示「用户 <id>」
      } finally {
        _peerProfileLoading.remove(userId);
      }
    }());
  }

  Future<void> _addPeerAsFriend(String userId) async {
    final id = int.tryParse(userId);
    if (id == null || id <= 0 || _friendRequestSent.contains(userId)) return;
    try {
      final token = await AccountManager.instance.ensureAccessToken();
      if (token == null) {
        addNotice(icon: Icons.info_outline, title: '先登录，或检查网络');
        return;
      }
      await MdtbbsFriendsApi.sendRequest(
        accessToken: token,
        targetUserId: id,
      );
      if (!mounted) return;
      setState(() => _friendRequestSent.add(userId));
      addNotice(icon: Icons.check, title: '已发送好友请求');
    } on Object catch (error) {
      addNotice(
        icon: Icons.close,
        title: '加好友失败',
        content: removeNewlines('$error'),
      );
    }
  }

  Widget _buildPeerRow(MultiplayerState state, MdtbbsPeer peer) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final isSelf = state.self?.peerId == peer.peerId;
    final active = peer.status == 'active';
    final friend = _isFriend(peer.userId);
    // 非好友又没资料：先拉一次公开资料，把名字显示出来
    if (!isSelf && !friend) _ensurePeerProfile(peer.userId);
    final known = _peerName(peer.userId);
    final name = isSelf ? '我' : (known ?? '用户 ${peer.userId}');
    return Row(
      spacing: AppSpacing.related,
      children: [
        UserAvatar(
          url: _peerAvatarUrl(peer.userId, isSelf: isSelf),
          size: 24,
          fallbackIcon: active ? Icons.person : Icons.person_off_outlined,
        ),
        Expanded(
          child: Text(
            '$name（${peer.role == 'owner' ? '房主' : '成员'}）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
        ),
        if (!isSelf && !friend)
          IconTextButton(
            pressedScale: 0.96,
            icon: Icons.person_add_alt,
            content: _friendRequestSent.contains(peer.userId) ? '已发送' : '加好友',
            onTap: _friendRequestSent.contains(peer.userId)
                ? null
                : () => unawaited(_addPeerAsFriend(peer.userId)),
          ),
        Text(
          _peerStatusLabel(peer.status),
          style: theme.textTheme.labelSmall?.copyWith(
            color: active ? colors.itemSecondary : colors.itemHint,
          ),
        ),
      ],
    );
  }

  Widget _buildInviteTile(MultiplayerState state) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return ReboundButton(
      onTap: _showInviteDialog,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(AppRadius.item),
      backgroundColor: colors.highBackgroundOnCard,
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.related,
          vertical: AppSpacing.related,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.item),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          spacing: AppSpacing.related,
          children: [
            Icon(
              Icons.person_add_alt,
              size: AppIconSize.item,
              color: colors.interactive,
            ),
            Expanded(
              child: Text(
                '邀请好友加入',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.itemSecondary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: AppIconSize.item,
              color: colors.itemHint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameHint(MultiplayerState state) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final isOwner = state.self?.role == 'owner';
    final String hint;
    if (!state.proxyRunning) {
      hint = state.proxyError != null
          ? '联机通道没起来，先点上面的「重试」'
          : '正在准备联机通道…';
    } else if (isOwner) {
      hint = '进游戏并开「主机」房间，好友就能进来';
    } else {
      hint = '进游戏 → 加入游戏 → 在「局域网游戏」里找房间'
          '（没出现就直连 ${state.localAddress ?? '127.0.0.1:6567'}）';
    }
    return Text(
      hint,
      style: theme.textTheme.labelSmall?.copyWith(color: colors.itemHint),
    );
  }

  String _roomPhaseLabel(MultiplayerState state) {
    final retry = _retrySuffix(state);
    return switch (state.phase) {
      MultiplayerPhase.restoring => '正在恢复房间…',
      MultiplayerPhase.creating => '正在开启房间…',
      MultiplayerPhase.joining => '正在加入房间…',
      MultiplayerPhase.reconnecting =>
        '联机断开了，正在重连（${state.reconnectAttempt}/3）…$retry',
      MultiplayerPhase.preparing => '正在准备联机…',
      MultiplayerPhase.ready => '可以进游戏了',
      MultiplayerPhase.failed => '连不上联机服务器$retry',
      MultiplayerPhase.leaving => '正在离开房间…',
      MultiplayerPhase.idle => '房间已开启，等待准备联机',
    };
  }

  int? _retrySeconds(MultiplayerState state) {
    final at = state.proxyRetryAt;
    if (at == null) return null;
    final seconds = at.difference(DateTime.now()).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  String _retrySuffix(MultiplayerState state) {
    final seconds = _retrySeconds(state);
    if (seconds == null) return '';
    return seconds <= 0 ? '（正在重试…）' : '（$seconds 秒后自动重试）';
  }

  String _diagnostics(MultiplayerState state) {
    return [
      'session=${state.session?.id ?? '—'}',
      'peer=${state.self?.peerId ?? '—'}',
      'role=${state.self?.role ?? '—'}',
      'joinCode=${state.joinCode ?? '—'}',
      'proxy=${state.proxyRunning}',
      'local=${state.localAddress ?? '—'}',
      'reconnect=${state.reconnectAttempt}',
      'heartbeatFailures=${state.heartbeatFailures}',
      'error=${state.proxyError ?? '—'}',
    ].join('\n');
  }

  String _effectiveVisibility(MdtbbsMultiplayerCapabilities? caps) {
    if (caps == null) return _visibility;
    if (caps.visibility.contains(_visibility)) return _visibility;
    return caps.visibility.isNotEmpty ? caps.visibility.first : _visibility;
  }

  String _effectiveJoinPolicy(MdtbbsMultiplayerCapabilities? caps) {
    if (caps == null) return _joinPolicy;
    if (caps.joinPolicies.contains(_joinPolicy)) return _joinPolicy;
    return caps.joinPolicies.isNotEmpty
        ? caps.joinPolicies.first
        : _joinPolicy;
  }

  String _visibilityLabel(String value) => switch (value) {
    'private' => '不在列表里出现',
    'friends' => '仅好友列表可见',
    'public' => '所有人可见',
    'unlisted' => '不在列表里出现',
    _ => value,
  };

  String _joinPolicyLabel(String value) => switch (value) {
    'invite_only' => '仅受邀者',
    'friends' => '仅好友',
    'public' => '任何入口都可进',
    'open' => '拿到房间码就能进',
    'request' => '需我同意',
    _ => value,
  };

  String _peerStatusLabel(String status) => switch (status) {
    'active' => '在线',
    'joining' => '加入中',
    'disconnected' => '已断开',
    'expired' => '已过期',
    _ => status,
  };
}

/// 通用确认框：返回 true 表示用户确认
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Center(
      child: Material(
        color: Colors.transparent,
        elevation: 6,
        child: Container(
          width: (MediaQuery.sizeOf(context).width - 32).clamp(0, 420),
          padding: const EdgeInsets.all(AppSpacing.block),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.related,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.itemSecondary,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: AppSpacing.related,
                children: [
                  IconTextButton(
                    pressedScale: 0.96,
                    icon: Icons.close,
                    content: '取消',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  IconTextButton(
                    pressedScale: 0.96,
                    icon: Icons.check,
                    content: confirmLabel,
                    onTap: () => Navigator.of(context).pop(true),
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

/// 邀请好友：从好友列表里点，或者手填用户 ID 兜底
class _InviteFriendDialog extends StatefulWidget {
  const _InviteFriendDialog({
    required this.roomCode,
    required this.onInvite,
    this.onCopyCode,
  });

  final String? roomCode;
  final Future<void> Function(int userId) onInvite;
  final VoidCallback? onCopyCode;

  @override
  State<_InviteFriendDialog> createState() => _InviteFriendDialogState();
}

class _InviteFriendDialogState extends State<_InviteFriendDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  int? _busyUserId;
  String? _error;

  MdtbbsFriendsService get _friends => MdtbbsFriendsService.instance;
  MdtbbsMultiplayerService get _mp => MdtbbsMultiplayerService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_friends.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(int userId) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyUserId = userId;
      _error = null;
    });
    try {
      await widget.onInvite(userId);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyUserId = null;
        });
      }
    }
  }

  Future<void> _sendTyped() async {
    final userId = int.tryParse(_controller.text.trim());
    if (userId == null || userId <= 0) {
      setState(() => _error = '填对方的用户 ID（数字）');
      return;
    }
    await _send(userId);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_friends.state, _mp.state]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = AppColors.of(context);
        final friends = _friends.state.value;
        final state = _mp.state.value;
        // 手机上好友多或键盘弹出时内容会比屏幕高：整体可滚，别让弹框顶穿
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Material(
              color: Colors.transparent,
              elevation: 6,
              child: Container(
                width: (MediaQuery.sizeOf(context).width - 32).clamp(0, 440),
                padding: const EdgeInsets.all(AppSpacing.block),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.panel),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.related,
                  children: [
                    Text('邀请好友加入', style: theme.textTheme.titleMedium),
                    Text(
                      friends.friends.isEmpty
                          ? '还没有好友；可以先把房间码发给他，或在下面填用户 ID'
                          : '点好友右边的「邀请」，邀请 5 分钟内有效',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.itemHint,
                      ),
                    ),
                    for (final entry in friends.sortedFriends)
                      _buildFriendTile(entry, state),
                    OutlinedTextField(
                      controller: _controller,
                      label: '好友用户 ID（数字）',
                      enable: !_busy,
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    OverflowBar(
                      alignment: MainAxisAlignment.start,
                      spacing: AppSpacing.related,
                      overflowSpacing: AppSpacing.related,
                      children: [
                        IconTextButton(
                          pressedScale: 0.96,
                          icon: Icons.copy,
                          content: '复制房间码',
                          onTap: widget.onCopyCode == null
                              ? null
                              : () {
                                  widget.onCopyCode!();
                                  Navigator.of(context).pop();
                                },
                        ),
                        IconTextButton(
                          pressedScale: 0.96,
                          icon: Icons.close,
                          content: '取消',
                          onTap: _busy
                              ? null
                              : () => Navigator.of(context).pop(),
                        ),
                        IconTextButton(
                          pressedScale: 0.96,
                          icon: Icons.person_add_alt,
                          content: _busy ? '正在发送…' : '发送邀请',
                          onTap: _busy ? null : _sendTyped,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFriendTile(MdtbbsFriendEntry entry, MultiplayerState state) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final userId = entry.user.userId;
    final inRoom = state.peers.any((peer) => peer.userId == '$userId');
    final invited = state.sentInvites.any(
      (invite) => invite.targetUserId == '$userId',
    );
    final busy = _busyUserId == userId;
    final label = inRoom
        ? '已在房间'
        : invited
        ? '已邀请'
        : busy
        ? '正在邀请…'
        : '邀请';
    return Row(
      spacing: AppSpacing.related,
      children: [
        UserAvatar(url: entry.user.avatarUrl, size: 24),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: entry.isOnline ? colors.success : colors.itemHint,
          ),
        ),
        Expanded(
          child: Text(
            entry.user.username.isEmpty ? '用户 $userId' : entry.user.username,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        IconTextButton(
          pressedScale: 0.96,
          icon: Icons.send,
          content: label,
          onTap: (_busy || invited || inRoom) ? null : () => _send(userId),
        ),
      ],
    );
  }
}

/// LanLink 加入：填 `MDT-XXXXXX`，解析房间后起本机桥
class _LanLinkJoinDialog extends StatefulWidget {
  const _LanLinkJoinDialog();

  @override
  State<_LanLinkJoinDialog> createState() => _LanLinkJoinDialogState();
}

class _LanLinkJoinDialogState extends State<_LanLinkJoinDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = LanLinkRoomCode.tryParse(_controller.text);
    if (code == null) {
      setState(() => _error = '房间码是 MDT- 加 6 位，例如 MDT-8FB633');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final room = await LanLinkService.instance.resolve(code);
      if (room == null) {
        if (mounted) setState(() => _error = '房间不存在或已关闭');
        return;
      }
      await LanLinkService.instance.join(room);
      if (mounted) Navigator.of(context).pop(room);
    } on LanLinkException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.message.isEmpty
            ? '加入失败${error.code.isEmpty ? '' : '（${error.code}）'}'
            : error.message,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '加入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Center(
      child: Material(
        color: Colors.transparent,
        elevation: 6,
        child: Container(
          width: (MediaQuery.sizeOf(context).width - 32).clamp(0, 420),
          padding: const EdgeInsets.all(AppSpacing.block),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.related,
            children: [
              Text('LanLink 加入', style: theme.textTheme.titleMedium),
              Text(
                '填房主给的 MDT-XXXXXX 房间码；加入后进游戏，在「局域网游戏」里找这个房间',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.itemHint,
                ),
              ),
              OutlinedTextField(
                controller: _controller,
                label: '房间码（MDT-XXXXXX）',
                enable: !_busy,
                onEditingComplete: _join,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: AppSpacing.related,
                overflowSpacing: AppSpacing.related,
                children: [
                  IconTextButton(
                    pressedScale: 0.96,
                    icon: Icons.close,
                    content: '取消',
                    onTap: _busy ? null : () => Navigator.of(context).pop(),
                  ),
                  IconTextButton(
                    pressedScale: 0.96,
                    icon: Icons.login,
                    content: _busy ? '正在加入…' : '加入房间',
                    onTap: _busy ? null : _join,
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
