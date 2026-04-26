import 'package:copperlauncher_main/data/net_asset.dart';
import 'package:copperlauncher_main/ui/util/dialog/custom_animated_dialog.dart';
import 'package:copperlauncher_main/ui/util/framework/content_panel.dart';

import 'package:copperlauncher_main/ui/util/widget/feature_list_tile.dart';
import 'package:copperlauncher_main/ui/util/widget/future/readme_loader.dart';
import 'package:copperlauncher_main/ui/util/widget/pager.dart';
import 'package:copperlauncher_main/ui/util/widget/rebound_container.dart';
import 'package:copperlauncher_main/util/downloader.dart';
import 'package:copperlauncher_main/util/format/string_cleaner.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:line_icons/line_icons.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constant/app_constant.dart';
import '../../../util/widget/feature_button.dart';
import '../../../util/widget/future/mod_icon_loader.dart';

class ModDownload extends StatefulWidget {
  const ModDownload({super.key});

  @override
  State<StatefulWidget> createState() => _ModDownloadState();
}

class _ModDownloadState extends State<ModDownload> {
  late ModOfficialListMeta mod;

  int index = 1;

  static final Map<String, List<ModGithubMeta>> modAssetsMap = {};

  List<ModGithubMeta> get assets => modAssetsMap[mod.repo] ?? [];

  var headers = {
    'User-Agent': 'MindustryModDownloader',
    'Authorization': 'token $githubToken',
  };

  bool endPage = false;
  Future<bool> _fetchModAssets({int page = 1}) async {
    final length = modAssetsMap[mod.repo]?.length ?? 0;
    if (length >= page * 25) return true;
    if (length % 100 != 0) endPage = true;
    if (endPage) return true;

    var rope = 'https://api.github.com/repos/${mod.repo}/releases';
    try {
      final res = await dio.get<List>(
        '$rope?page=${page ~/ 4 + 1}&per_page=100',
        options: Options(headers: headers),
      );
      //print('$rope?page=${page ~/ 4 + 1}&per_page=100');

      final modAssets =
          res.data!
              .map<ModGithubMeta>((it) => ModGithubMeta.fromJson(it))
              .toList();
      if (modAssets.length < 100) endPage = true;
      if (modAssets.isEmpty && index > 1) index--; //发现没有新的内容添加就直接减
      //print(modAssets.length);
      if (modAssetsMap[mod.repo] == null) {
        modAssetsMap[mod.repo] = modAssets;
      } else {
        modAssetsMap[mod.repo]!.addAll(modAssets);
      }
      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }

  Widget _buildVersionTile(ModGithubMeta asset) {
    Widget buildOverView(IconData icon, String data) {
      return ConstrainedBox(
        constraints: BoxConstraints(minWidth: 90),
        child: Row(children: [Icon(icon), Text(data)]),
      );
    }

    return ReboundListTile(
      borderRadius: BorderRadius.circular(4),
      title: Text(asset.name),
      subtitle: Row(
        spacing: 8,
        children: [
          buildOverView(Icons.folder_outlined, asset.releaseNum),
          buildOverView(
            Icons.update,
            asset.releaseDate.split('T').first,
          ),
          if (asset.assets.firstOrNull != null)
            buildOverView(
              Icons.arrow_downward,
              asset.assets.first.downloadCount.toString(),
            ),
        ],
      ),
      onTap: () {},
      trailing: ReboundIconButton(
        icon: Icons.outbond_outlined,
        content: '版本详情',
        onTap: () {},
      ),
    );
  }

  //todo https://raw.githubusercontent.com/ {Yuria-Shikibe/NewHorizonMod} / {main/tag_name} / {mod.hjson/.json}
  //用这个可以访问不同版本的json文件，这样就可以统计各个版本最小游戏版本了，然后可以本地存储一下
  Widget _buildWarningBar() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withAlpha(100),
          width: 2,
        ),
      ),
      padding: EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '由于githubAPI对匿名访问有 60次/小时 的限制，请不要短时间访问多个模组，访问过的模组已经缓存；'
              '如有条件，可以到设置中添加github访问token',
              maxLines: 2,
            ),
          ),
          ReboundContainer(
            backgroundColor: Colors.transparent,
            pressedScale: 0.75,
            borderRadius: BorderRadius.circular(4),
            onTap: () {},
            child: Icon(Icons.arrow_outward_outlined),
          ),
          SizedBox(width: 4),
          ReboundContainer(
            backgroundColor: Colors.transparent,
            pressedScale: 0.75,
            borderRadius: BorderRadius.circular(4),
            onTap: () {},
            child: Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  void _showReadme() => showAnimatedDialog(
    context: context,
    pageBuilder: (_, _, _) => Center(child: ModNetReadmeLoader(mod: mod)),
  );

  void _move(int to) => setState(() {
    index = to;
  });

  void _goToUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.inAppWebView);
  }

  //模组无对应资产时，提醒用户无资源，然后提供源码下载方式
  //模组仓库有三种情况：
  // 1.有构筑资源
  // 2.有历史源码，但没有构筑资源 => zipball_url => 没有下载量信息
  // 3.根本没发布版本 => 提供源码下载方法

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    mod = args!['mod']!;
    final theme = Theme.of(context);
    return ListContentPanel(
      items: [
        ContentPanelModule(
          child: Row(
            children: [
              SizedBox(
                height: 96,
                width: 96,
                child: ModNetworkIcon(modMeta: mod, size: 96),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  spacing: 4,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(mod.name, style: theme.textTheme.displayMedium),
                        SizedBox(width: 16),
                        Icon(Icons.star_border_sharp),
                        SizedBox(width: 4),
                        Text(
                          mod.stars.toString(),
                          style: theme.textTheme.titleLarge?.copyWith(),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            generalizeText(mod.author),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      generalizeText(mod.description),
                      style: TextStyle(height: 1.25),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      spacing: 8,
                      children: [
                        ReboundIconButton(
                          icon: Icons.info_outline,
                          content: '模组详情',
                          onTap: () {},
                        ),
                        ReboundIconButton(
                          icon: LineIcons.readme,
                          content: 'README',
                          onTap: () => _showReadme(),
                        ),
                        ReboundIconButton(
                          icon: Icons.file_open_outlined,
                          content: '源码仓库',
                          onTap:
                              () => _goToUrl('https://github.com/${mod.repo}'),
                        ),
                        ReboundIconButton(
                          icon: FontAwesomeIcons.github,
                          content: '作者主页',
                          onTap:
                              () => _goToUrl(
                                'https://github.com/${mod.repo.split('/').first}',
                              ),
                        ),
                        Expanded(child: SizedBox()),
                        ReboundIconButton(
                          icon: Icons.download,
                          content: '最新版本',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Text('如果有条件，请到github给模组们sart!', style: theme.textTheme.bodySmall),
        _buildWarningBar(),
        FutureBuilder<bool>(
          future: _fetchModAssets(page: index),
          builder: (_, s) {
            if (s.connectionState == ConnectionState.waiting) {
              return CircularProgressIndicator();
            }
            if (assets.isEmpty) return Text('wu');

            int begin = (index - 1) * 25;
            int end;
            if (assets.length < index * 25) {
              end = assets.length;
            } else {
              end = index * 25;
            }

            return ContentPanelModule(
              title: '版本列表',
              child: Column(
                spacing: 8,
                children: [
                  for (int i = begin; i < end; i++)
                    _buildVersionTile(assets[i]),
                  Pager(
                    index,
                    endPage: endPage,
                    onDown: () => _move(--index),
                    onUp: () => _move(++index),
                    goHome: () => _move(1),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
