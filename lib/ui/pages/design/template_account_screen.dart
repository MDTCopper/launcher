import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 用户页（设计层版本，App 内可打开：`/template_account`，仅 debug 可见）
///
/// 功能面：社区账号登录 / 游戏内身份（名称 + 颜色 + 启动前覆写）/ 活跃数据 / 入口
class TemplateAccountScreen extends StatefulWidget {
  const TemplateAccountScreen({super.key});

  @override
  State<TemplateAccountScreen> createState() => _TemplateAccountScreenState();
}

class _TemplateAccountScreenState extends State<TemplateAccountScreen> {
  final _gameName = TextEditingController(text: 'Cubik65536');

  bool _loggedIn = true;
  bool _overrideIdentity = false;
  int _colorIndex = 0;

  static const _colors = <(String, Color?)>[
    ('游戏默认', null),
    ('铜色', Color(0xFFC89958)),
    ('钛蓝', Color(0xFF6593D8)),
    ('钍粉', Color(0xFFE587DD)),
    ('草绿', Color(0xFF90C86E)),
  ];

  @override
  void dispose() {
    _gameName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = TemplateSkin.ofContext(context);
    final compact = TemplateBreakpoints.isCompactWindow(
      MediaQuery.sizeOf(context).width,
    );

    return ColoredBox(
      color: skin.page,
      child: TemplateScrollView(
        skin: skin,
        padding: EdgeInsets.all(compact ? TemplateSpace.md : TemplateSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TemplateSpace.lg,
          children: [
            _profileCard(skin),
            _statsRow(skin),
            _communityCard(skin),
            _identityCard(skin),
            _entriesCard(skin),
          ],
        ),
      ),
    );
  }

  Widget _profileCard(TemplateSkin skin) {
    return TemplateCard(
      skin: skin,
      padding: const EdgeInsets.all(TemplateSpace.lg),
      child: Row(
        spacing: TemplateSpace.lg,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: skin.sunken,
              shape: BoxShape.circle,
              border: Border.all(color: skin.border),
            ),
            child: Icon(
              Icons.person_outline,
              size: 32,
              color: skin.textTertiary,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.xxs,
              children: [
                Row(
                  spacing: TemplateSpace.sm,
                  children: [
                    Flexible(
                      child: Text(
                        _loggedIn ? 'Cubik65536' : '未登录',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TemplateType.page.copyWith(
                          color: skin.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: _loggedIn ? skin.accentTint : skin.sunken,
                        borderRadius: BorderRadius.circular(
                          TemplateRadius.pill,
                        ),
                      ),
                      child: Text(
                        _loggedIn ? '已登录' : '离线',
                        style: TemplateType.micro.copyWith(
                          color: _loggedIn
                              ? skin.onAccentTint
                              : skin.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  _loggedIn
                      ? '社区 ID 100238 · 加入于 2025 年 3 月'
                      : '登录后可以加好友、收邀请、参与联机',
                  style: TemplateType.caption.copyWith(
                    color: skin.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (!_loggedIn)
            TemplateButton(
              skin: skin,
              label: '登录',
              icon: Icons.login,
              kind: TemplateButtonKind.solid,
              onTap: () => setState(() => _loggedIn = true),
            ),
        ],
      ),
    );
  }

  Widget _statsRow(TemplateSkin skin) {
    const stats = [('好友', '12'), ('邀请', '3'), ('通知', '7')];
    return Row(
      spacing: TemplateSpace.md,
      children: [
        for (final (label, value) in stats)
          Expanded(
            child: TemplateCard(
              skin: skin,
              padding: const EdgeInsets.symmetric(
                horizontal: TemplateSpace.md,
                vertical: TemplateSpace.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    value,
                    style: TemplateType.section.copyWith(
                      color: skin.textPrimary,
                    ),
                  ),
                  Text(
                    label,
                    style: TemplateType.caption.copyWith(
                      color: skin.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _communityCard(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '社区账号',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          TemplateTwoLine(
            skin: skin,
            title: _loggedIn ? '已登录 MdtBBS' : '未登录',
            desc: _loggedIn
                ? '用浏览器授权后可加好友、发邀请、上传云存档'
                : '点「登录」会复制授权链接，在浏览器里完成登录',
          ),
          Row(
            spacing: TemplateSpace.sm,
            children: [
              TemplateButton(
                skin: skin,
                label: _loggedIn ? '重新授权' : '登录',
                icon: Icons.open_in_new,
                kind: TemplateButtonKind.plain,
                onTap: () => setState(() => _loggedIn = true),
              ),
              TemplateButton(
                skin: skin,
                label: '刷新资料',
                icon: Icons.refresh,
                kind: TemplateButtonKind.quiet,
                onTap: () {},
              ),
              const Spacer(),
              if (_loggedIn)
                TemplateButton(
                  skin: skin,
                  label: '退出登录',
                  icon: Icons.logout,
                  kind: TemplateButtonKind.quiet,
                  danger: true,
                  onTap: () => setState(() => _loggedIn = false),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _identityCard(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '游戏内身份',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          Text(
            '这是进入游戏时显示的名字与颜色，和社区昵称互不影响',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
          TemplateInputRow(
            skin: skin,
            title: '游戏内名称',
            controller: _gameName,
            hint: '进入游戏后显示的名字',
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.sm,
            children: [
              Text(
                '颜色',
                style: TemplateType.caption.copyWith(color: skin.textSecondary),
              ),
              Wrap(
                spacing: TemplateSpace.sm,
                runSpacing: TemplateSpace.sm,
                children: [
                  for (var i = 0; i < _colors.length; i++) _colorChip(skin, i),
                ],
              ),
            ],
          ),
          TemplateSwitchRow(
            skin: skin,
            title: '启动前覆写',
            desc: '每次启动游戏时把上面的名称与颜色写进游戏配置',
            value: _overrideIdentity,
            onTap: () => setState(() => _overrideIdentity = !_overrideIdentity),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TemplateButton(
              skin: skin,
              label: '保存身份',
              icon: Icons.save_outlined,
              kind: TemplateButtonKind.solid,
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorChip(TemplateSkin skin, int index) {
    final (label, color) = _colors[index];
    final selected = index == _colorIndex;
    return GestureDetector(
      onTap: () => setState(() => _colorIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: TemplateSpace.sm,
          vertical: TemplateSpace.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? skin.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(TemplateRadius.control),
          border: Border.all(color: selected ? skin.borderStrong : skin.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: TemplateSpace.xs,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color ?? skin.textTertiary,
                shape: BoxShape.circle,
                border: Border.all(color: skin.border),
              ),
            ),
            Text(
              label,
              style: TemplateType.caption.copyWith(
                color: selected ? skin.textPrimary : skin.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entriesCard(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '快捷入口',
      child: Column(
        spacing: TemplateSpace.xs,
        children: [
          TemplateRow(
            skin: skin,
            onTap: () {},
            child: _entryContent(skin, Icons.people_outline, '好友', '12 位好友'),
          ),
          TemplateRow(
            skin: skin,
            onTap: () {},
            child: _entryContent(skin, Icons.notifications_none, '通知', '7 条未读'),
          ),
          TemplateRow(
            skin: skin,
            onTap: () {},
            child: _entryContent(skin, Icons.settings_outlined, '账户设置', ''),
          ),
        ],
      ),
    );
  }

  Widget _entryContent(
    TemplateSkin skin,
    IconData icon,
    String title,
    String trailing,
  ) {
    return Row(
      spacing: TemplateSpace.sm,
      children: [
        Icon(icon, size: 18, color: skin.textSecondary),
        Expanded(
          child: Text(
            title,
            style: TemplateType.item.copyWith(color: skin.textPrimary),
          ),
        ),
        if (trailing.isNotEmpty)
          Text(
            trailing,
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
        Icon(Icons.chevron_right, size: 16, color: skin.textTertiary),
      ],
    );
  }
}
