import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/feature/images.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:line_icons/line_icons.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);

    final copperLauncherTile = Row(
      children: [
        ClipOval(child: Image.asset(Images.copper, fit: .fitWidth, width: 40)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text('Copper Launcher'),
              Text(
                '版本：$appVersion (Build $appBuildNumber)',
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ],
    );

    final launcherAuthorTile = Row(
      children: [
        ClipOval(
          child: Image.asset(Images.rainfall, fit: .fitWidth, width: 40),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 2,
            children: [
              Text('rainfallllll（落雨）', style: theme.textTheme.bodyLarge),
              Text('Copper Launcher 开发者', style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ],
    );

    final loaderAuthorTile = Row(
      children: [
        ClipOval(child: Image.asset(Images.wxp, fit: .fitWidth, width: 40)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: .start,
          children: [
            Text('DSFdsfWxp'),
            Text('Copper Loader 开发者', style: theme.textTheme.labelMedium),
          ],
        ),
      ],
    );

    return ListContentPanel(
      items: [
        ContentPanelModule(
          title: '关于启动器',
          child: Column(
            spacing: 12,
            children: [
              copperLauncherTile,
              launcherAuthorTile,
              loaderAuthorTile,
              Row(
                spacing: 8,
                children: [
                  if (kDebugMode)
                    IconTextButton(
                      icon: Icons.update,
                      content: '检查更新',
                      onTap: () {},
                    ),
                  IconTextButton(
                    icon: LineIcons.github,
                    content: '项目仓库',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
        if (kDebugMode)
          ContentPanelModule(
            title: '鸣谢',
            child: Column(spacing: 12, children: [
              
            ],
          ),
          ),
        if (kDebugMode)
          ContentPanelModule(
            title: '赞助名单',
            child: Column(spacing: 12, children: [
              
            ],
          ),
          ),
        ContentPanelModule(
          title: '许可证',
          child: Column(spacing: 12, children: [
              
            ],
          ),
        ),
      ],
    );
  }
}
