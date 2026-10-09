import 'package:copper_launcher/domain/account/account_manager.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/pages/account/account_page.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

const onlinePageRouteKey = '/online';

/// 联机页（**骨架**）：局域网 / 直连 + 社区联机
///
/// - **局域网 / 直连**不需要 BBS 账号（将来接 easyTier 这类组网也放这一区）
/// - **社区联机**走 BBS（Presence / Join Intent），要登录；那两项客户端能力还在审核，
///   所以这里先只给状态说明，不摆点了没反应的按钮
class OnlinePage extends StatefulWidget {
  const OnlinePage({super.key});

  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

class _OnlinePageState extends State<OnlinePage> {
  bool _loggedIn = false;

  AccountManager get _accounts => AccountManager.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAccount());
  }

  Future<void> _loadAccount() async {
    if (!_accounts.isConfigured) return;
    await _accounts.restore();
    if (!mounted) return;
    setState(() => _loggedIn = _accounts.isLoggedIn);
  }

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(items: [_buildLanPanel(), _buildCommunityPanel()]);
  }

  Widget _buildLanPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return ContentPanelModule(
      title: '局域网 / 直连',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            '同一局域网里直接连、或者手动填地址连；这一区不需要 BBS 账号。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          Text(
            '（待做：局域网发现、地址直连；将来接 easyTier 这类组网也放这里）',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityPanel() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    if (!_loggedIn) {
      return ContentPanelModule(
        title: '社区联机',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(
              '社区联机（好友房 / 加入邀请）需要 BBS 账号；'
              '登录在「概览 → 账户」里完成。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.itemSecondary,
              ),
            ),
            Row(
              spacing: 12,
              children: [
                IconTextButton(
                  icon: Icons.account_circle_outlined,
                  content: '去账户页登录',
                  onTap: () =>
                      Navigator.pushNamed(context, accountPageRouteKey),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return ContentPanelModule(
      title: '社区联机',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            '已登录 BBS。联机要用到的两项客户端能力（Presence / Join Intent）还在审核，'
            '过了之后再在这里接好友房与加入邀请。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
          Text(
            '（待做：在线状态、好友房列表、接收 copper-launcher://join 邀请）',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
