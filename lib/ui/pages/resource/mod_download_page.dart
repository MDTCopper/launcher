import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/data/net_asset.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/download_mod.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/overlay_layer/menu_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/action_slide_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/popup_overlay.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:copper_launcher/ui/feature/images.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';

import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/components/future/readme_loader.dart';
import 'package:copper_launcher/ui/components/pager.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/downloader.dart';
import 'package:copper_launcher/util/io/path_selector.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hjson_dart/hjson_dart.dart';
import 'package:line_icons/line_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_constant.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import '../../components/future/mod_icon_loader.dart';
import '../../components/row/priority_row.dart';
import '../../components/tips/warning_bar.dart';
import '../../vars.dart';

///模组仓库有三种情况：
///
/// 1.有构筑资源
///
/// 2.有历史源码，但没有构筑资源 => tag拼接 => 没有下载量信息
///
/// 3.根本没发布版本 => 提供源码下载方法
class ModDownloadPage extends StatefulWidget {
  const ModDownloadPage({super.key});

  @override
  State<StatefulWidget> createState() => _ModDownloadPageState();
}

class _ModDownloadPageState extends State<ModDownloadPage> {
  late ModOfficialListMeta modListMeta;
  final selectedVersion = config.versionOptions.selectedVersion;

  int index = 1;

  int perPage = 25;

  static final Map<String, List<ModGithubMeta>> modMetasMapCache = {};

  List<ModGithubMeta> get metas => modMetasMapCache[modListMeta.repo] ?? [];

  bool endPage = false;

  Future<bool> _fetchModMetas({int page = 1}) async {
    final length = modMetasMapCache[modListMeta.repo]?.length ?? 0;
    if (length >= page * 25) return true;
    if (length % 100 != 0) endPage = true;
    if (endPage) return true;

    var repo = 'https://api.github.com/repos/${modListMeta.repo}/releases';
    try {
      final res = await dio.get<List>(
        '$repo?page=${page ~/ 4 + 1}&per_page=100',
        options: Options(headers: modDownloadHeaders),
      );
      //print('$repo?page=${page ~/ 4 + 1}&per_page=100');

      final modMetas = res.data!
          .map<ModGithubMeta>((it) => ModGithubMeta.fromJson(it))
          .toList();
      if (modMetas.length < 100) endPage = true;
      if (modMetas.isEmpty && index > 1) index--; //发现没有新的内容添加就直接减1
      //print(modAssets.length);
      if (modMetasMapCache[modListMeta.repo] == null) {
        modMetasMapCache[modListMeta.repo] = modMetas;
      } else {
        modMetasMapCache[modListMeta.repo]!.addAll(modMetas);
      }
      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }

  //todo https://raw.githubusercontent.com/ {Yuria-Shikibe/NewHorizonMod} / {main/tag_name} / {mod.hjson/.json}
  //用这个可以访问不同版本的json文件，这样就可以统计各个版本最小游戏版本了，然后可以本地存储一下

  // @override
  // void initState() {
  //   minGameVersionsCache.clear();
  //   super.initState();
  // }

  static final Map<String, Future<String?>> minGameVersionsCache = {};

  Future<String?> _getMinGameVersion(ModGithubMeta mod) async {
    final url = '$githubRAW/${modListMeta.repo}/${mod.releaseNum}';
    List<String> jsons;
    if (modListMeta.hasJava) {
      jsons = ['hjson', 'json'];
    } else {
      jsons = ['json', 'hjson'];
    }
    Map<String, dynamic> map = {};
    for (final json in jsons) {
      try {
        print('$url/mod.$json');
        final res = await dio.get('$url/mod.$json');

        if (res.statusCode != 200) continue;
        final content = res.data as String;
        map.addAll(hjsonDecode(content, strict: false) as Map<String, dynamic>);
        if (map.isNotEmpty) break;
      } catch (e) {
        print(e);
        continue;
      }
    }

    if (map.isEmpty) {
      for (final json in jsons) {
        try {
          print('$url/assets/mod.$json');
          final res = await dio.get('$url/mod.$json');

          if (res.statusCode != 200) continue;
          final content = res.data as String;
          map.addAll(
            hjsonDecode(content, strict: false) as Map<String, dynamic>,
          );
          if (map.isNotEmpty) break;
        } catch (e) {
          print(e);
          continue;
        }
      }
    }

    final min = map['minGameVersion'];
    return min == null ? null : 'v$min';
  }

  Widget _buildVersionTile(ModGithubMeta mod) {
    Widget buildOverView(IconData icon, String data) {
      return ConstrainedBox(
        constraints: BoxConstraints(minWidth: 110),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            SizedBox(width: 2),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 140),
              child: Text(data, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
    }

    final minGameVersion = minGameVersionsCache[mod.releaseNum] ??=
        _getMinGameVersion(mod);

    final tile = ReboundListTile(
      borderRadius: BorderRadius.circular(4),
      title: Text(mod.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: PriorityRow(
        crossAxisAlignment: CrossAxisAlignment.start,
        items: [
          // 版本号：核心信息，永不丢
          PriorityRowItem(
            priority: 0,
            width: 140,
            child: buildOverView(Icons.folder_outlined, mod.releaseNum),
          ),
          // 兼容性：异步加载，次重要(支持版本信息保留)
          PriorityRowItem(
            priority: 1,
            width: 160,
            child: FutureBuilder(
              future: minGameVersion,
              builder: (_, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return buildOverView(Icons.source_outlined, '...');
                }
                if (s.hasData) {
                  final version = selectedVersion;
                  if (version == null) {
                    return buildOverView(Icons.source_outlined, s.data!);
                  }

                  bool support;
                  final modMin = double.parse(s.data!.substring(1));
                  if (modListMeta.hasJava) {
                    final minGameVersion = minJavaModGameVersionModifier
                        .resultOf(version.releaseDouble);
                    support =
                        modMin >= minGameVersion &&
                        modMin <= version.releaseDouble;
                  } else {
                    final minGameVersion = minModGameVersionModifier.resultOf(
                      version.releaseDouble,
                    );
                    support =
                        modMin >= minGameVersion &&
                        modMin <= version.releaseDouble;
                  }

                  if (support) {
                    return buildOverView(
                      Icons.check_outlined,
                      '支持 (${s.data!})',
                    );
                  } else if (support == false) {
                    return buildOverView(
                      Icons.close_outlined,
                      '可能不支持 (${s.data!})',
                    );
                  } else {
                    return buildOverView(Icons.info_outlined, s.data!);
                  }
                } else {
                  return buildOverView(Icons.source_outlined, 'XXX');
                }
              },
            ),
          ),
          // 日期：中了优先级
          PriorityRowItem(
            priority: 2,
            width: 130,
            child: buildOverView(
              Icons.update,
              mod.releaseDate.split('T').first,
            ),
          ),
          // 下载数：最先丢
          if (mod.assets.firstOrNull != null)
            PriorityRowItem(
              priority: 3,
              width: 110,
              child: buildOverView(
                Icons.arrow_downward,
                mod.assets.first.downloadCount.toString(),
              ),
            ),
        ],
      ),
      onTap: () => _buildDownloadPopup(mod),
    );

    // 滑动菜单：移动端使用；桌面端 debug 模式下可测试
    Widget swipeChild = tile;
    if (isMobile || (isDesktop && kDebugMode)) {
      swipeChild = ActionSlideLayer(
        actions: _buildSwipeActions(context, mod),
        child: tile,
      );
    }

    // 右键菜单（桌面端）/ 长按菜单（多端）：内容 = 构建 tile 时未用的下载源码 / 版本详情
    return MenuLayer(
      rightClickTrigger: true,
      longPressTrigger: true,
      menuBuilder: (context, controller) =>
          _buildMenuItems(context, mod, controller),
      child: swipeChild,
    );
  }

  /// 菜单项：图标 + 文本
  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final color = AppColors.of(context).itemPrimary;
    return SizedBox(
      width: 120,
      child: ReboundButton(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }

  /// 右键 / 长按菜单内容：下载源码 + 版本详情（构建 tile 时未用的 trailing）
  List<Widget> _buildMenuItems(
    BuildContext context,
    ModGithubMeta mod,
    PopupOverlayController controller,
  ) {
    return [
      if (modListMeta.hasJava)
        _buildMenuItem(
          context,
          icon: Icons.folder_outlined,
          label: '下载源码',
          onTap: () {
            _buildDownloadPopup(mod, downloadSource: true);
            controller.dismiss();
          },
        ),
      _buildMenuItem(
        context,
        icon: Icons.outbond_outlined,
        label: '版本详情',
        onTap: () {
          _buildDownloadPopup(mod);
          controller.dismiss();
        },
      ),
    ];
  }

  /// 滑动菜单动作：下载源码 + 版本详情
  List<Widget> _buildSwipeActions(BuildContext context, ModGithubMeta mod) {
    final colors = AppColors.of(context);
    Widget action({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        width: 88,
        child: Container(
          color: colors.interactive,
          alignment: Alignment.center,
          child: ReboundButton(
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(0),
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: colors.itemOnInteractive),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: colors.itemOnInteractive,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return [
      if (modListMeta.hasJava)
        action(
          icon: Icons.folder_outlined,
          label: '下载源码',
          onTap: () => _buildDownloadPopup(mod, downloadSource: true),
        ),
      action(
        icon: Icons.outbond_outlined,
        label: '版本详情',
        onTap: () => _buildDownloadPopup(mod),
      ),
    ];
  }

  Widget? _buildWarningBar() {
    return buildWarningBar(
      context,
      'warning bar of mod download page enable',
      '由于githubAPI对匿名访问有 60次/小时 的限制，请不要短时间访问多个模组，访问过的模组已经缓存；'
          '如有条件，可以到设置中添加github访问token',
      onTap: () => setState(() {}), // 关闭后刷新移除本条，与 util 版关闭写入配置的行为配合
    );
  }

  void _showReadme() => showAnimatedDialog(
    context: context,
    pageBuilder: (_, _, _) =>
        Center(child: ModNetReadmeLoader(mod: modListMeta)),
  );

  void _buildDownloadPopup(ModGithubMeta? mod, {bool downloadSource = false}) {
    showAnimatedDialog(
      context: context,
      pageBuilder: (context, _, _) {
        return _ModDownloadPopupPage(
          modListMeta,
          mod,
          downloadSource: downloadSource,
        );
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

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    modListMeta = args!['mod']!;
    final theme = Theme.of(context);
    return ListContentPanel(
      items: [
        ContentPanelModule(
          child: Row(
            children: [
              SizedBox(
                height: 96,
                width: 96,
                child: ModNetworkIcon(modMeta: modListMeta, size: 96),
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
                        Text(
                          modListMeta.name,
                          style: theme.textTheme.displayMedium,
                        ),
                        SizedBox(width: 16),
                        Icon(Icons.star_border_sharp),
                        SizedBox(width: 4),
                        Text(
                          modListMeta.stars.toString(),
                          style: theme.textTheme.titleLarge?.copyWith(),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            generalizeText(modListMeta.author),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      generalizeText(modListMeta.description),
                      style: TextStyle(height: 1.25),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        IconTextButton(
                          icon: Icons.info_outline,
                          content: '模组详情',
                          onTap: () {},
                        ),
                        IconTextButton(
                          icon: LineIcons.readme,
                          content: 'README',
                          onTap: () => _showReadme(),
                        ),
                        IconTextButton(
                          icon: Icons.file_open_outlined,
                          content: '源码仓库',
                          onTap: () => _goToUrl(
                            'https://github.com/${modListMeta.repo}',
                          ),
                        ),
                        IconTextButton(
                          icon: FontAwesomeIcons.github,
                          content: '作者主页',
                          onTap: () => _goToUrl(
                            'https://github.com/${modListMeta.repo.split('/').first}',
                          ),
                        ),
                        IconTextButton(
                          icon: Icons.download,
                          content: '最新版本',
                          onTap: () => _buildDownloadPopup(metas.firstOrNull),
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
            Widget child;

            if (s.connectionState == ConnectionState.waiting) {
              child = CircularProgressIndicator();
            } else if (metas.isEmpty) {
              child = ContentPanelModule(
                child: Column(
                  spacing: 8,
                  children: [
                    Text('(*´･д･)?', style: theme.textTheme.titleLarge),
                    Text(
                      '该模组没有发布任何版本，可以点击最新版本下载源码',
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(
                      '!!!  注意：模组可能因处于开发阶段，没有发布任何版本，存在不能正常载入的情况  !!!',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            } else {
              int begin = (index - 1) * perPage;
              int end;
              if (metas.length < index * perPage) {
                end = metas.length;
              } else {
                end = index * perPage;
              }
              child = ContentPanelModule(
                title: '版本列表',
                child: Column(
                  spacing: 8,
                  children: [
                    for (int i = begin; i < end; i++)
                      _buildVersionTile(metas[i]),
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
            }

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchOutCurve: Curves.ease,
              switchInCurve: Curves.ease,
              transitionBuilder: (child, animation) {
                final opacity = CurvedAnimation(
                  parent: animation,
                  curve: Interval(0.4, 1.0),
                );

                final scale = Tween(begin: 0.6, end: 1.0).animate(
                  CurvedAnimation(parent: animation, curve: Interval(0.0, 1.0)),
                );

                return FadeTransition(
                  opacity: opacity,
                  child: ScaleTransition(
                    alignment: Alignment.topCenter,
                    scale: scale,
                    child: child,
                  ),
                );
              },
              layoutBuilder: (child, animation) {
                return Align(alignment: Alignment.topCenter, child: child);
              },
              child: child,
            );
          },
        ),
      ],
    );
  }
}

class _ModDownloadPopupPage extends StatefulWidget {
  final bool downloadSource;
  final ModOfficialListMeta modListMeta;
  final ModGithubMeta? modMeta;

  const _ModDownloadPopupPage(
    this.modListMeta,
    this.modMeta, {
    this.downloadSource = false,
  });

  @override
  State<StatefulWidget> createState() => _ModDownloadPopupPageState();
}

class _ModDownloadPopupPageState extends State<_ModDownloadPopupPage> {
  late final modListMeta = widget.modListMeta;
  late final modMeta = widget.modMeta;
  final version = config.versionOptions.selectedVersion;
  String? otherSavePath;

  //todo 下载到选择的版本中,如果不是支持版本警告一下,处理一下空存储路径
  void _download() async {
    if (modListMeta.hasJava && !widget.downloadSource) {
      addTask(
        DownloadJavaModTask(
          modListMeta: modListMeta,
          modMeta: modMeta!,
          savePath: version?.modsPath ?? otherSavePath!,
        ),
      );
    } else {
      addTask(
        DownloadZipModTask(
          modListMeta,
          modMeta,
          version?.modsPath ?? otherSavePath!,
        ),
      );
    }

    if (mounted) Navigator.pop(context);
  }

  Widget _buildVersionTile() {
    final theme = Theme.of(context);
    if (version == null) return Text('未选中任何版本，将下载至默认路径下');

    return Column(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('将下载到当前选中的版本', style: theme.textTheme.bodyLarge),
        // Expanded(child: SizedBox()),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Image.asset(
                version!.launcher == LauncherType.copper
                    ? Images.copper
                    : Images.mindustry,
                scale: 1.5,
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    version!.tag,
                    style: theme.textTheme.bodyLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(version!.releaseNum, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPathTile() {
    final theme = Theme.of(context);

    final savePath = otherSavePath ?? version?.modsPath;

    if (savePath == null) {
      return Text('未选中任何版本,请先选择版本或自定义存储路径');
    }

    return Column(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('存储路径', style: theme.textTheme.bodyLarge),
        Row(
          spacing: 8,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  savePath,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (otherSavePath != null)
              ReboundButton(
                child: Icon(Icons.delete),
                onTap: () => setState(() {
                  otherSavePath = null;
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTile() {
    final theme = Theme.of(context);

    if (otherSavePath != null || version == null) return _buildPathTile();

    return Column(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVersionTile(),
        if (!(version?.isolation ?? false))
          Text(
            '当前版本未隔离,将下载至默认路径,建议到设置中开启隔离模式',
            style: theme.textTheme.bodySmall,
          ),
        _buildPathTile(),
      ],
    );
  }

  void _chooseOtherSavePath() async {
    otherSavePath = await PathSelector.selectDirectory(
      initialDirectory: version?.modsPath,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    Expanded(
                      child: Text(
                        '下载 ${modMeta?.name ?? modListMeta.name}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    SizedBox(width: 8),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.fastEaseInToSlowEaseOut,
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: 400),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeOut,
                    transitionBuilder: (child, animation) {
                      final opacity = CurvedAnimation(
                        parent: animation,
                        curve: Interval(0.7, 1.0),
                        reverseCurve: Interval(0.7, 1.0),
                      );

                      return FadeTransition(opacity: opacity, child: child);
                    },
                    child: KeyedSubtree(
                      key: ValueKey(otherSavePath ?? ''),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: _buildTile(),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: IconTextButton(
                    icon: Icons.file_open_outlined,
                    content: '选择其他路径',
                    onTap: () => _chooseOtherSavePath(),
                  ),
                ),
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
