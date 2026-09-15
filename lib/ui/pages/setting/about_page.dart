import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/feature/images.dart';
import 'package:copper_launcher/ui/pages/setting/license_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:line_icons/line_icons.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                  IconTextButton(
                    icon: Icons.update,
                    content: '检查更新',
                    onTap: () {},
                  ),
                  IconTextButton(
                    icon: LineIcons.github,
                    content: '项目仓库',
                    onTap: () async {
                      await launchUrl(
                        Uri.parse(launcherRepoUrl),
                        mode: LaunchMode.inAppWebView,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        //鸣谢：游戏本体 / 地图站 / 镜像节点
        ContentPanelModule(
          title: '鸣谢',
          child: Column(
            crossAxisAlignment: .start,
            spacing: 8,
            children: [
              Text('Mindustry（Anuken）—— 游戏本体'),
              Text('MindustryTop —— 地图站资源'),
              Text('GitHub 镜像节点提供者 —— 加速下载'),
            ],
          ),
        ),
        if (kDebugMode)
          ContentPanelModule(
            title: '赞助名单',
            child: Column(spacing: 12, children: []),
          ),
        ContentPanelModule(
          title: '加入我们',
          child: Text('todo 加入我们'),
        ),
        //开源许可
        ContentPanelModule(
          title: '许可证',
          child: Column(
            crossAxisAlignment: .start,
            spacing: 8,
            children: [
              Text('本项目基于 MIT 许可证开源'),
              IconTextButton(
                icon: Icons.description_outlined,
                content: '查看开源许可',
                onTap: () => Navigator.pushNamed(
                  context,
                  licensePageRouteKey,
                  arguments: {'lead': '设置', 'title': '开源许可'},
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
