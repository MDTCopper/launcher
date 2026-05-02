import 'dart:io';

import 'package:copperlauncher_main/core/app_config.dart';
import 'package:copperlauncher_main/data/net_asset.dart';
import 'package:copperlauncher_main/domain/task_manager.dart';
import 'package:copperlauncher_main/domain/tasks/download_mod.dart';
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
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:line_icons/line_icons.dart';
import 'package:path/path.dart' as p;
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

  static final Map<String, List<ModGithubMeta>> modMetasMap = {};

  List<ModGithubMeta> get metas => modMetasMap[mod.repo] ?? [];

  bool endPage = false;

  Future<bool> _fetchModMetas({int page = 1}) async {
    final length = modMetasMap[mod.repo]?.length ?? 0;
    if (length >= page * 25) return true;
    if (length % 100 != 0) endPage = true;
    if (endPage) return true;

    var repo = 'https://api.github.com/repos/${mod.repo}/releases';
    try {
      final res = await dio.get<List>(
        '$repo?page=${page ~/ 4 + 1}&per_page=100',
        options: Options(headers: modDownloadHeaders),
      );
      //print('$repo?page=${page ~/ 4 + 1}&per_page=100');

      final modMetas =
          res.data!
              .map<ModGithubMeta>((it) => ModGithubMeta.fromJson(it))
              .toList();
      if (modMetas.length < 100) endPage = true;
      if (modMetas.isEmpty && index > 1) index--; //发现没有新的内容添加就直接减
      //print(modAssets.length);
      if (modMetasMap[mod.repo] == null) {
        modMetasMap[mod.repo] = modMetas;
      } else {
        modMetasMap[mod.repo]!.addAll(modMetas);
      }
      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }

  Widget _buildVersionTile(ModGithubMeta mod) {
    Widget buildOverView(IconData icon, String data) {
      return ConstrainedBox(
        constraints: BoxConstraints(minWidth: 90),
        child: Row(children: [Icon(icon), Text(data)]),
      );
    }

    return ReboundListTile(
      borderRadius: BorderRadius.circular(4),
      title: Text(mod.name),
      subtitle: Row(
        spacing: 8,
        children: [
          buildOverView(Icons.folder_outlined, mod.releaseNum),
          buildOverView(Icons.update, mod.releaseDate.split('T').first),
          if (mod.assets.firstOrNull != null)
            buildOverView(
              Icons.arrow_downward,
              mod.assets.first.downloadCount.toString(),
            ),
        ],
      ),
      onTap: () => _buildDownloadPopup(mod),
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

  void _buildDownloadPopup(ModGithubMeta mod) {
    showAnimatedDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 350),
      animationType: DialogAnimation.leapOut,
      pageBuilder: (context, _, _) {
        return _ModDownloadPopupPage(this.mod, mod);
      },
    );
  }

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
  // 2.有历史源码，但没有构筑资源 => tag拼接 => 没有下载量信息
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
          future: _fetchModMetas(page: index),
          builder: (_, s) {
            if (s.connectionState == ConnectionState.waiting) {
              return CircularProgressIndicator();
            }
            if (metas.isEmpty) return Text('wu');

            int begin = (index - 1) * 25;
            int end;
            if (metas.length < index * 25) {
              end = metas.length;
            } else {
              end = index * 25;
            }

            return ContentPanelModule(
              title: '版本列表',
              child: Column(
                spacing: 8,
                children: [
                  for (int i = begin; i < end; i++) _buildVersionTile(metas[i]),
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

class _ModDownloadPopupPage extends StatefulWidget {
  final ModOfficialListMeta modListMeta;
  final ModGithubMeta modMeta;

  const _ModDownloadPopupPage(this.modListMeta, this.modMeta);

  @override
  State<StatefulWidget> createState() => _ModDownloadPopupPageState();
}

class _ModDownloadPopupPageState extends State<_ModDownloadPopupPage> {
  late final modListMeta = widget.modListMeta;
  late final modMeta = widget.modMeta;
  final version = config.versionOptions.selectedVersion;

  //todo 下载到选择的版本中,如果不是支持版本警告一下,处理一下空存储路径
  void _download() async {
    if (await _checkModExist()) {
      print('模组已存在，请检查文件');
      return;
    }

    addTask(
      DownloadJavaModTask(
        modListMeta: modListMeta,
        modMeta: modMeta,
        path: version!.modsPath!,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  //mod命名规则：模组名-版本.(jar/zip)
  Future<bool> _checkModExist() async {
    if (version?.modsPath == null) return false;
    var fileName = '${modListMeta.name}-${modMeta.name}';
    if (modListMeta.hasJava) {
      fileName += '.jar';
    } else {
      fileName += '.zip';
    }
    final path = p.join(version!.modsPath!, fileName);
    final file = File(path);
    return await file.exists();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final url = modMeta.assets.firstOrNull?.url;

    print(url);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Material(
          color: Colors.transparent,
          elevation: 4,
          shadowColor: Colors.black,
          child: Container(
            width: 500,
            padding: EdgeInsets.all(8),
            constraints: BoxConstraints(maxHeight: 380),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              spacing: 8,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    ReboundButton(
                      child: Icon(Icons.arrow_back_ios_new),
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                    ),
                    Text(
                      '下载 ${modMeta.name}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),

                Text('将下载至当前版本 [${version?.tag}]'),
                Text('存储路径: ${version?.modsPath}'),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
        ReboundButton(
          pressedScale: 0.95,
          elevation: 2,
          hoverElevation: 4,
          onTap: () => _download(),
          child: SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.file_download_outlined,
                  size: 40,
                  color: theme.colorScheme.secondary,
                ),
                Text(
                  '开始下载',
                  style: theme.textTheme.displayMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
