import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 联机页（设计层版本，App 内可打开：`/template_online`，仅 debug 可见）
///
/// 只保留功能面：开房 / 加房 / 房间状态 / 房间配置 / 局域网 / 邀请与申请
class TemplateOnlineScreen extends StatefulWidget {
  const TemplateOnlineScreen({super.key});

  @override
  State<TemplateOnlineScreen> createState() => _TemplateOnlineScreenState();
}

class _TemplateOnlineScreenState extends State<TemplateOnlineScreen> {
  final _roomName = TextEditingController(text: 'Cubik65536 的服务器');
  final _roomCode = TextEditingController();
  final _friendId = TextEditingController();

  bool _inRoom = true;
  bool _isHost = true;
  bool _lanLink = false;
  int _visibility = 0;
  int _maxPlayers = 8;

  static const _visibilities = ['公开', '仅好友', '仅邀请'];

  static const _players = [
    ('Cubik65536', '房主'),
    ('落雨 innocent', '玩家'),
    ('[讷西]', '玩家'),
  ];

  static const _invites = [
    ('柳高原铁', '想加入你的房间', '3 分钟前'),
    ('MindistryX客户端', '收到了你的好友请求', '1 小时前'),
  ];

  @override
  void dispose() {
    _roomName.dispose();
    _roomCode.dispose();
    _friendId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = TemplateSkin.ofContext(context);
    final windowWidth = MediaQuery.sizeOf(context).width;
    final compact = TemplateBreakpoints.isCompactWindow(windowWidth);

    return ColoredBox(
      color: skin.page,
      child: TemplateScrollView(
        skin: skin,
        padding: EdgeInsets.all(compact ? TemplateSpace.md : TemplateSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TemplateSpace.lg,
          children: [
            _lead(skin),
            _roomStatus(skin),
            compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: TemplateSpace.md,
                    children: [_hostCard(skin), _guestCard(skin)],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: TemplateSpace.md,
                    children: [
                      Expanded(child: _hostCard(skin)),
                      Expanded(child: _guestCard(skin)),
                    ],
                  ),
            _lanLinkCard(skin),
            _roomSettings(skin),
            _playersSection(skin),
            _invitesSection(skin),
          ],
        ),
      ),
    );
  }

  Widget _lead(TemplateSkin skin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TemplateSpace.xs,
      children: [
        Text(
          '联机',
          style: TemplateType.page.copyWith(color: skin.textPrimary),
        ),
        Text(
          '和好友共用同一局游戏：一方开房拿到房间码，另一方输入房间码加入；'
          '局域网内也可以直接走 LanLink',
          style: TemplateType.caption.copyWith(
            color: skin.textTertiary,
            height: 18 / 12,
          ),
        ),
      ],
    );
  }

  Widget _roomStatus(TemplateSkin skin) {
    if (!_inRoom) {
      return TemplateNotice(
        skin: skin,
        tone: TemplateNoticeTone.info,
        text: '当前没有加入房间，先创建一间或输入房间码加入',
        icon: Icons.people_outline,
      );
    }
    return TemplateSection(
      skin: skin,
      title: '当前房间',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          Row(
            spacing: TemplateSpace.md,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TemplateSpace.xxs,
                  children: [
                    Text(
                      _roomName.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TemplateType.section.copyWith(
                        color: skin.textPrimary,
                      ),
                    ),
                    Text(
                      _isHost ? '你是房主 · ${_visibilities[_visibility]} · 最多 $_maxPlayers 人' : '你是客人 · 等待房主开始',
                      style: TemplateType.caption.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              _roomCodeChip(skin),
            ],
          ),
          Row(
            spacing: TemplateSpace.sm,
            children: [
              TemplateButton(
                skin: skin,
                label: _isHost ? '关闭房间' : '退出房间',
                icon: _isHost ? Icons.stop_circle_outlined : Icons.logout,
                kind: TemplateButtonKind.plain,
                danger: true,
                onTap: () => setState(() => _inRoom = false),
              ),
              TemplateButton(
                skin: skin,
                label: '复制房间码',
                icon: Icons.copy,
                kind: TemplateButtonKind.quiet,
                onTap: () {},
              ),
              const Spacer(),
              TemplateButton(
                skin: skin,
                label: '换房主',
                icon: Icons.swap_horiz,
                kind: TemplateButtonKind.quiet,
                onTap: () => setState(() => _isHost = !_isHost),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roomCodeChip(TemplateSkin skin) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.md,
        vertical: TemplateSpace.sm,
      ),
      decoration: BoxDecoration(
        color: skin.sunken,
        borderRadius: BorderRadius.circular(TemplateRadius.control),
        border: Border.all(color: skin.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 2,
        children: [
          Text(
            'MDT-7F3K9Q',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: skin.accentText,
            ),
          ),
          Text(
            '房间码',
            style: TemplateType.micro.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _hostCard(TemplateSkin skin) {
    return TemplateCard(
      skin: skin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.sm,
        children: [
          Row(
            spacing: TemplateSpace.sm,
            children: [
              Icon(Icons.wifi_tethering, size: 20, color: skin.accent),
              Text(
                '我是房主',
                style: TemplateType.section.copyWith(color: skin.textPrimary),
              ),
            ],
          ),
          Text(
            '在这台机器上开局，把房间码发给朋友',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
          const SizedBox(height: TemplateSpace.xs),
          TemplateButton(
            skin: skin,
            label: _inRoom && _isHost ? '房间已开启' : '创建房间',
            icon: Icons.play_circle_outline,
            kind: TemplateButtonKind.solid,
            expanded: true,
            enabled: !(_inRoom && _isHost),
            onTap: () => setState(() {
              _inRoom = true;
              _isHost = true;
            }),
          ),
        ],
      ),
    );
  }

  Widget _guestCard(TemplateSkin skin) {
    return TemplateCard(
      skin: skin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.sm,
        children: [
          Row(
            spacing: TemplateSpace.sm,
            children: [
              Icon(Icons.login, size: 20, color: skin.accent),
              Text(
                '我是客人',
                style: TemplateType.section.copyWith(color: skin.textPrimary),
              ),
            ],
          ),
          Text(
            '输入朋友发来的房间码加入房间',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
          const SizedBox(height: TemplateSpace.xs),
          TemplateTextField(
            skin: skin,
            controller: _roomCode,
            hint: '房间码（MDT-XXXXXX）',
          ),
          TemplateButton(
            skin: skin,
            label: '加入房间',
            icon: Icons.group_add_outlined,
            kind: TemplateButtonKind.solid,
            expanded: true,
            onTap: () => setState(() {
              _inRoom = true;
              _isHost = false;
            }),
          ),
        ],
      ),
    );
  }

  Widget _lanLinkCard(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '局域网',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          TemplateSwitchRow(
            skin: skin,
            title: 'LanLink 局域网发现',
            desc: '同一局域网内自动发现房间，不经过服务器；跨网段不可用',
            value: _lanLink,
            onTap: () => setState(() => _lanLink = !_lanLink),
          ),
          if (_lanLink)
            TemplateNotice(
              skin: skin,
              tone: TemplateNoticeTone.success,
              text: '已加入 LanLink 房间，最近 3 台设备可见',
              icon: Icons.lan_outlined,
            ),
        ],
      ),
    );
  }

  Widget _roomSettings(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '房间配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          TemplateInputRow(
            skin: skin,
            title: '房间名',
            controller: _roomName,
            hint: '好友看到的房间名',
          ),
          Row(
            spacing: TemplateSpace.md,
            children: [
              Expanded(
                child: TemplateSelectRow(
                  skin: skin,
                  title: '可见性',
                  value: _visibilities[_visibility],
                  onTap: () => setState(
                    () => _visibility = (_visibility + 1) % _visibilities.length,
                  ),
                ),
              ),
              Expanded(
                child: TemplateSelectRow(
                  skin: skin,
                  title: '人数上限',
                  value: '$_maxPlayers 人',
                  onTap: () => setState(
                    () => _maxPlayers = _maxPlayers == 8 ? 16 : 8,
                  ),
                ),
              ),
            ],
          ),
          TemplateCollapse(
            skin: skin,
            title: '高级选项',
            subtitle: '端口 / 中继 / 允许旁观',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: TemplateSpace.sm,
              children: [
                TemplateSliderRow(
                  skin: skin,
                  title: '端口偏移',
                  value: 0,
                  label: '+0',
                  minLabel: '0',
                  maxLabel: '+10',
                ),
                TemplateSwitchRow(
                  skin: skin,
                  title: '允许旁观',
                  desc: '旁观者可以看地图但不能操作单位',
                  value: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playersSection(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '房间玩家（${_players.length}）',
      child: Column(
        spacing: TemplateSpace.xs,
        children: [
          for (final (name, role) in _players)
            TemplateRow(
              skin: skin,
              child: Row(
                spacing: TemplateSpace.sm,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: skin.sunken,
                    child: Text(
                      name.characters.first,
                      style: TemplateType.micro.copyWith(
                        color: skin.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TemplateType.item.copyWith(
                        color: skin.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    role,
                    style: TemplateType.caption.copyWith(
                      color: role == '房主'
                          ? skin.accentText
                          : skin.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _invitesSection(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '邀请与申请',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          for (final (name, desc, time) in _invites)
            TemplateRow(
              skin: skin,
              child: Row(
                spacing: TemplateSpace.sm,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TemplateType.item.copyWith(
                            color: skin.textPrimary,
                          ),
                        ),
                        Text(
                          desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TemplateType.caption.copyWith(
                            color: skin.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    time,
                    style: TemplateType.micro.copyWith(color: skin.textTertiary),
                  ),
                  TemplateButton(
                    skin: skin,
                    label: '同意',
                    icon: Icons.check,
                    kind: TemplateButtonKind.plain,
                    onTap: () {},
                  ),
                  TemplateButton(
                    skin: skin,
                    label: '忽略',
                    icon: Icons.close,
                    kind: TemplateButtonKind.quiet,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          Row(
            spacing: TemplateSpace.sm,
            children: [
              Expanded(
                child: TemplateTextField(
                  skin: skin,
                  controller: _friendId,
                  hint: '好友用户 ID（数字）',
                ),
              ),
              TemplateButton(
                skin: skin,
                label: '加好友',
                icon: Icons.person_add_alt,
                kind: TemplateButtonKind.plain,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}
