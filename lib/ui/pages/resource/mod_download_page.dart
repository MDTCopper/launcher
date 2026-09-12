import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/data/min_game_versions.dart';
import 'package:copper_launcher/data/net_asset.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/download_mod.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/overlay_layer/action_menu.dart';
import 'package:copper_launcher/ui/components/overlay_layer/menu_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/action_slide_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/popup_overlay.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/animation/animated_opacity_size.dart';
import 'package:copper_launcher/util/io/print_on_debug.dart';
import 'package:copper_launcher/ui/feature/images.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';

import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/components/future/readme_loader.dart';
import 'package:copper_launcher/ui/components/pager.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/format/time_since.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/path_selector.dart';
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

  /// 当前页的加载 Future，按页缓存。
  ///
  /// 若在 build 里直接 `_fetchModMetas(page: index)`，每次重建都会新建 Future，
  /// FutureBuilder 会退回 waiting 再完成——列表闪烁、动画重复触发
  Future<bool>? _fetchFuture;
  int _fetchFuturePage = -1;

  Future<bool> get _fetchFutureOfCurrentPage {
    if (_fetchFuture == null || _fetchFuturePage != index) {
      _fetchFuturePage = index;
      _fetchFuture = _fetchModMetas(page: index);
    }
    return _fetchFuture!;
  }

  Future<bool> _fetchModMetas({int page = 1}) async {
    final length = modMetasMapCache[modListMeta.repo]?.length ?? 0;
    if (length >= page * 25) return true;
    if (length % 100 != 0) endPage = true;
    if (endPage) return true;

    var repo = 'https://api.github.com/repos/${modListMeta.repo}/releases';
    try {
      final res = await cio.get<List>(
        '$repo?page=${page ~/ 4 + 1}&per_page=100',
        headers: modDownloadHeaders,
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
      // 刷新头部「最新版本/下载源码」按钮文案（依赖 metas 是否有 release）
      if (mounted) setState(() {});
      return true;
    } catch (e) {
      printOnDebug(e);
      return false;
    }
  }

  //https://raw.githubusercontent.com/ {Yuria-Shikibe/NewHorizonMod} / {main/tag_name} / {mod.hjson/.json}
  //用这个可以访问不同版本的json文件，这样就可以统计各个版本最小游戏版本了，然后可以本地存储一下

  static final Map<String, Future<String?>> minGameVersionsCache = {};

  Future<String?> _getMinGameVersion(ModGithubMeta mod) async {
    final url = '$githubRAW/${modListMeta.repo}/${mod.tag}';
    List<String> jsons;
    if (modListMeta.hasJava) {
      jsons = ['hjson', 'json'];
    } else {
      jsons = ['json', 'hjson'];
    }
    Map<String, dynamic> map = {};
    for (final json in jsons) {
      try {
        printOnDebug('$url/mod.$json');
        final res = await cio.get('$url/mod.$json');

        if (res.statusCode != 200) continue;
        final content = res.data as String;
        map.addAll(hjsonDecode(content, strict: false) as Map<String, dynamic>);
        if (map.isNotEmpty) break;
      } catch (e) {
        printOnDebug(e);
        continue;
      }
    }

    if (map.isEmpty) {
      for (final json in jsons) {
        try {
          printOnDebug('$url/assets/mod.$json');
          final res = await cio.get('$url/assets/mod.$json');

          if (res.statusCode != 200) continue;
          final content = res.data as String;
          map.addAll(
            hjsonDecode(content, strict: false) as Map<String, dynamic>,
          );
          if (map.isNotEmpty) break;
        } catch (e) {
          printOnDebug(e);
          continue;
        }
      }
    }

    final min = map['minGameVersion'];
    return min == null ? null : 'v$min';
  }

  Widget _buildVersionTile(ModGithubMeta mod) {
    Widget buildOverView(IconData icon, String data) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          SizedBox(width: 2),
          Text(data, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      );
    }

    final minGameVersion = minGameVersionsCache[mod.tag] ??= _getMinGameVersion(
      mod,
    );

    Widget buildSupportInfo() => FutureBuilder(
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
            final minGameVersion = MinGameVersions.instance.java.resultOf(
              version.releaseDouble,
            );
            support =
                modMin >= minGameVersion && modMin <= version.releaseDouble;
          } else {
            final minGameVersion = MinGameVersions.instance.mod.resultOf(
              version.releaseDouble,
            );
            support =
                modMin >= minGameVersion && modMin <= version.releaseDouble;
          }

          if (support) {
            return buildOverView(Icons.check_outlined, '支持 (${s.data!})');
          } else if (support == false) {
            return buildOverView(Icons.close_outlined, '可能不支持 (${s.data!})');
          } else {
            return buildOverView(Icons.info_outlined, s.data!);
          }
        } else {
          return buildOverView(Icons.source_outlined, 'XXX');
        }
      },
    );

    final tile = ReboundListTile(
      hoverElevation: 4,
      borderRadius: BorderRadius.circular(4),
      onTap: () => _buildDownloadPopup(mod),
      title: Text(mod.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          SizedBox(
            width: 120,
            child: buildOverView(Icons.folder_outlined, mod.tag),
          ),

          Expanded(
            child: PriorityRow(
              crossAxisAlignment: CrossAxisAlignment.start,
              items: [
                PriorityRowItem(
                  priority: 3,
                  width: 140,
                  child: buildSupportInfo(),
                ),

                PriorityRowItem(
                  priority: 2,
                  width: 90,
                  child: buildOverView(
                    Icons.update,
                    mod.releaseDate.split('T').first,
                  ),
                ),

                if (mod.assets.firstOrNull != null)
                  PriorityRowItem(
                    priority: 1,
                    width: 120,
                    child: buildOverView(
                      Icons.arrow_downward,
                      mod.assets.first.downloadCount.toString(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    // 组合菜单：右键 / 长按（MenuLayer）+ 左滑（ActionSlideLayer）
    return ActionMenu(
      menuBuilder: (_, controller) => _buildMenuItems(mod, controller),
      actions: _buildSwipeActions(mod),
      child: tile,
    );
  }

  /// 右键 / 长按菜单内容
  List<Widget> _buildMenuItems(
    ModGithubMeta mod,
    PopupOverlayController controller,
  ) {
    return [
      MenuButton(
        icon: Icon(Icons.folder_outlined),
        label: '下载源码',
        onTap: () {
          _buildDownloadPopup(mod, downloadSource: true);
          controller.dismiss();
        },
      ),
      MenuButton(
        icon: Icon(Icons.outbond_outlined),
        label: '版本详情',
        onTap: () {
          // 版本详情 = 跳转到 GitHub 该 tag 的详情页
          _goToUrl(
            'https://github.com/${modListMeta.repo}/releases/tag/${mod.tag}',
          );
          controller.dismiss();
        },
      ),
    ];
  }

  /// 滑动菜单动作：下载源码 + 版本详情
  List<Widget> _buildSwipeActions(ModGithubMeta mod) {
    return [
      const SizedBox(width: 4),
      SlideActionButton(
        icon: Icon(Icons.folder_outlined),
        label: '下载源码',
        onTap: () => _buildDownloadPopup(mod, downloadSource: true),
      ),
      const SizedBox(width: 4),
      SlideActionButton(
        icon: Icon(Icons.outbond_outlined),
        label: '版本详情',
        onTap: () => _goToUrl(
          'https://github.com/${modListMeta.repo}/releases/tag/${mod.tag}',
        ),
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

  /// 模组详情：完整描述 + 兼容性 + 最新版本 + 动作入口
  ///
  /// 列表卡片上的描述只显示 3 行，这里给完整信息，且把「最低游戏版本是否
  /// 满足当前选中版本」直接判出来（阈值与版本列表同一套 [MinGameVersions]）
  void _showDetail() => showAnimatedDialog(
    context: context,
    pageBuilder: (dialogContext, _, _) =>
        Center(child: _buildModDetailPanel(dialogContext)),
  );

  /// [dialogContext] 必须是弹窗自己的 context：主题 / MediaQuery 依赖要落在
  /// 弹窗元素上——若借用页面的 context，关闭弹窗后页面仍带着 MediaQuery 依赖，
  /// 一调整窗口就会反复重建页面（列表反复刷新、switcher 动画重复触发）
  Widget _buildModDetailPanel(BuildContext dialogContext) {
    final theme = Theme.of(dialogContext);
    final colors = AppColors.of(dialogContext);
    final size = MediaQuery.of(dialogContext).size;
    final latest = metas.firstOrNull;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        elevation: 2,
        child: SizedBox(
          width: (size.width * 0.55).clamp(420.0, 760.0),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 14,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 72,
                      width: 72,
                      child: ModNetworkIcon(modMeta: modListMeta, size: 72),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          Text(
                            modListMeta.name,
                            style: theme.textTheme.headlineMedium,
                          ),
                          Text(
                            '${modListMeta.author}   ·   ${modListMeta.repo}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.itemSecondary,
                            ),
                          ),
                          Row(
                            spacing: 6,
                            children: [
                              Icon(Icons.star_border_sharp, size: 16),
                              Text(
                                '${modListMeta.stars}',
                                style: theme.textTheme.bodyMedium,
                              ),
                              SizedBox(width: 10),
                              Text(
                                '更新于 ${timeSince(modListMeta.lastUpdated)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.itemHint,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                //最低游戏版本 + 兼容性、类型、最新版本
                Column(
                  spacing: 8,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(
                      theme,
                      colors,
                      '最低游戏版本',
                      Row(
                        spacing: 10,
                        children: [
                          Text(
                            modListMeta.minGameVersion,
                            style: theme.textTheme.titleMedium,
                          ),
                          _buildCompatBadge(theme),
                        ],
                      ),
                    ),
                    if (_typesOfMeta() case final type?)
                      _buildDetailRow(
                        theme,
                        colors,
                        '类型',
                        Text(type, style: theme.textTheme.bodyLarge),
                      ),
                    _buildDetailRow(
                      theme,
                      colors,
                      '最新版本',
                      Text(
                        latest == null
                            ? '未发布任何版本'
                            : [
                                latest.tag,
                                //没有附件的版本不显示体积
                                if (_largestAssetSize(latest) > 0)
                                  _sizeText(_largestAssetSize(latest)),
                                latest.releaseDate.split('T').first,
                              ].join('   ·   '),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),

                //描述（列表里截断，这里给完整内容）
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: size.height * 0.3),
                  child: CopperSingleChildScrollView(
                    child: Column(
                      spacing: 6,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('描述', style: theme.textTheme.titleMedium),
                        Text(
                          generalizeText(modListMeta.description),
                          style: const TextStyle(height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 类型文本：只用官方列表声明的 hasScripts / hasJava。
  ///
  /// 不回看历史 release 去猜类型——模组自己不维护发布（最新版本没附件等）
  /// 是模组的问题；官方列表也没声明时返回 null（调用方不显示该行）
  String? _typesOfMeta() {
    final types = [
      if (modListMeta.hasScripts) '脚本',
      if (modListMeta.hasJava) 'Java',
    ];
    return types.isEmpty ? null : types.join(' + ');
  }

  Widget _buildDetailRow(
    ThemeData theme,
    AppColors colors,
    String label,
    Widget value,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 96,
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.itemHint),
        ),
      ),
      Expanded(child: value),
    ],
  );

  /// 兼容性徽标：该模组声明的最低游戏版本能否在当前选中版本上跑
  Widget _buildCompatBadge(ThemeData theme) {
    final support = _compatForSelectedVersion();
    final version = selectedVersion;
    final (text, color) = switch (support) {
      true => ('支持', theme.colorScheme.primary),
      false => ('不支持', theme.colorScheme.error),
      null => ('未选择版本', theme.colorScheme.outline),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: color.withAlpha(30),
            border: Border.all(color: color),
          ),
          child: Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
        if (support != null && version != null)
          Text(
            '当前版本 ${version.release}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
      ],
    );
  }

  /// 该模组在当前选中版本下是否可用；未选版本 / 版本号无法解析时返回 null
  ///
  /// 判定与版本列表一致：Java 模组用 java 门槛，其余用脚本门槛
  bool? _compatForSelectedVersion() {
    final version = selectedVersion;
    if (version == null) return null;
    final modMin = double.tryParse(modListMeta.minGameVersion);
    if (modMin == null) return null;

    final threshold = modListMeta.hasJava
        ? MinGameVersions.instance.java.resultOf(version.releaseDouble)
        : MinGameVersions.instance.mod.resultOf(version.releaseDouble);
    return modMin >= threshold && modMin <= version.releaseDouble;
  }

  /// release 中最大附件的体积（一般为模组本体）
  int _largestAssetSize(ModGithubMeta meta) =>
      meta.assets.fold(0, (max, asset) => asset.size > max ? asset.size : max);

  String _sizeText(int bytes) {
    if (bytes >= GB) return '${(bytes / GB).toStringAsFixed(2)} GB';
    if (bytes >= MB) return '${(bytes / MB).toStringAsFixed(1)} MB';
    if (bytes >= KB) return '${(bytes / KB).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

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
                          onTap: _showDetail,
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
                          icon: FontAwesomeIcons.github.data,
                          content: '作者主页',
                          onTap: () => _goToUrl(
                            'https://github.com/${modListMeta.repo.split('/').first}',
                          ),
                        ),
                        IconTextButton(
                          icon: Icons.download,
                          content: (modListMeta.hasJava && metas.isEmpty)
                              ? '下载源码'
                              : '最新版本',
                          onTap: () {
                            final latest = metas.firstOrNull;
                            // 非java：最新版本行为=下载最新源码（tag 常过时）；
                            // java 有 release → 版本详情选 asset；无 release → 源码下载
                            if (modListMeta.hasJava && latest != null) {
                              _buildDownloadPopup(latest);
                            } else {
                              _buildDownloadPopup(null, downloadSource: true);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Center(
          child: Text(
            '如果有条件，请到github给模组们sart!',
            style: theme.textTheme.labelMedium,
          ),
        ),

        _buildWarningBar(),
        FutureBuilder<bool>(
          future: _fetchFutureOfCurrentPage,
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
                      modListMeta.hasJava
                          ? '该模组没有发布任何版本，请等待作者正式发布版本'
                          : '该模组没有发布任何版本，可以点击最新版本下载源码',
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (!modListMeta.hasJava)
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

  /// 选中的候选项在其列表中的下标（默认 0 = 体积最大的 mod 本体）
  int _selectedAssetIndex = 0;

  /// 版本详情下载的同类型候选（.jar 或 .zip，按体积从大到小）；
  /// 下载源码时无候选，不展示。
  List<GithubApiReleaseAsset> get _assetCandidates {
    if (widget.downloadSource) return const <GithubApiReleaseAsset>[];
    final ext = modListMeta.hasJava ? '.jar' : '.zip';
    return modMeta?.assetsOfType(ext) ?? const <GithubApiReleaseAsset>[];
  }

  bool get _canDownload {
    if (version == null && otherSavePath == null) return false;
    if (widget.downloadSource) {
      return true;
    } else {
      if (modListMeta.hasJava && _assetCandidates.isEmpty) return false;
    }
    return true;
  }

  bool get javaDownloadBan =>
      modListMeta.hasJava && _assetCandidates.isEmpty && !widget.downloadSource;
  void _download() async {
    // 源码下载：走源码 task
    if (widget.downloadSource) {
      addTask(
        DownloadSourceModTask(
          modListMeta: modListMeta,
          modMeta: modMeta,
          savePath: version?.modsPath ?? otherSavePath!,
        ),
      );
      if (mounted) Navigator.pop(context);
      return;
    }

    // 无编译产物时跳转对应 tag 下载源码
    final candidates = _assetCandidates;
    if (candidates.isEmpty) {
      addTask(
        DownloadSourceModTask(
          modListMeta: modListMeta,
          modMeta: modMeta,
          savePath: version?.modsPath ?? otherSavePath!,
        ),
      );
      if (mounted) Navigator.pop(context);
      return;
    }
    final chosen = _selectedAssetIndex.clamp(0, candidates.length - 1);
    final mainAssetIndex = modMeta!.assets.indexOf(candidates[chosen]);

    if (modListMeta.hasJava) {
      addTask(
        DownloadJavaModTask(
          modListMeta: modListMeta,
          modMeta: modMeta!,
          savePath: version?.modsPath ?? otherSavePath!,
          mainAssetIndex: mainAssetIndex,
        ),
      );
    } else {
      // 非Java Mod
      addTask(
        DownloadZipModTask(
          modListMeta,
          modMeta!,
          version?.modsPath ?? otherSavePath!,
          mainAssetIndex: mainAssetIndex,
        ),
      );
    }

    if (mounted) Navigator.pop(context);
  }

  /// 页面内嵌的候选资源选择：多个同类型候选用下拉选择，
  /// 单个只读展示，没有则显示建议
  Widget _buildAssetSelection() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    // 源码下载：java 源码在下载弹窗内提醒玩家
    if (widget.downloadSource) {
      return modListMeta.hasJava
          ? Row(
              spacing: 4,
              children: [
                Icon(
                  Icons.warning_amber,
                  color: theme.colorScheme.error,
                  size: 20,
                ),
                Expanded(
                  child: Text(
                    '注意：未经编译的 java 源码无法直接载入',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            )
          : const SizedBox.shrink();
    }

    final candidates = _assetCandidates;
    if (candidates.isEmpty) {
      // 无编译产物：跳转对应 tag 下载源码

      // java，不允许下载
      if (modListMeta.hasJava) {
        return Row(
          spacing: 4,
          children: [
            const SizedBox(width: 12),
            Icon(Icons.warning_amber, color: theme.colorScheme.error, size: 28),
            Expanded(
              child: Text(
                '该版本未发布资源，请尝试下载其他版本',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        );
      }

      //非java，提醒
      return Row(
        spacing: 4,
        children: [
          Icon(Icons.info_outline, size: 20, color: colors.itemSecondary),
          Expanded(
            child: Text(
              '该版本未发布资源，将自动下载该版本的源码',
              style: theme.textTheme.bodySmall?.copyWith(),
            ),
          ),
        ],
      );
    }

    //有资源
    if (candidates.length == 1) {
      return Row(
        spacing: 4,
        children: [
          Icon(Icons.description_outlined, color: colors.itemSecondary),
          Expanded(
            child: Text(
              candidates.first.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _formatAssetSize(candidates.first.size),
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }

    // 多个候选：下拉选择，默认最大的在前（一般为 mod 本体）
    final value = _selectedAssetIndex < candidates.length
        ? _selectedAssetIndex
        : 0;
    return Column(
      spacing: 4,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('选择要下载的文件，体积最大一般为 mod 本体', style: theme.textTheme.bodySmall),
        DropdownLayer<int>(
          initialValue: value,
          onSelect: (v) => setState(() => _selectedAssetIndex = v),
          options: candidates
              .map(
                (it) => DropdownOption(
                  value: value,
                  leading: Icon(
                    Icons.description_outlined,
                    size: 18,
                    color: colors.itemSecondary,
                  ),
                  label: it.name,
                  labelWidget: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          it.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatAssetSize(it.size),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  String _formatAssetSize(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes < kb) return '$bytes B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / gb).toStringAsFixed(1)} GB';
  }

  Widget _buildInfoTile() {
    //javaDownloadBan 不呈现信息
    if (javaDownloadBan) return SizedBox();
    final theme = Theme.of(context);
    Widget buildPathTile() {
      final savePath = otherSavePath ?? version?.modsPath;

      if (savePath == null) {
        return Text('未选中任何版本，请先选择版本或自定义存储路径');
      }

      return Column(
        spacing: 4,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('存储路径', style: theme.textTheme.bodyMedium),
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

    if (otherSavePath != null || version == null) return buildPathTile();
    Widget buildGameVersionTile() {
      if (!_canDownload) return SizedBox();

      return Column(
        spacing: 4,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('将下载到当前选中的版本', style: theme.textTheme.bodyMedium),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.max,
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
                    Text(version!.release, style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      spacing: 4,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildGameVersionTile(),
        if (!(version?.isolation ?? false))
          Text(
            '当前版本未隔离，将下载至默认路径，建议到设置中开启隔离模式',
            style: theme.textTheme.labelMedium,
          ),
        buildPathTile(),
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
    final colors = AppColors.of(context);

    final title = Row(
      spacing: 8,
      children: [
        ReboundButton(
          child: Icon(Icons.arrow_back_ios_new, size: 18),
          onTap: () {
            Navigator.of(context).pop();
          },
        ),

        Expanded(
          child: javaDownloadBan
              ? Text(
                  '警告！',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.error,
                  ),
                )
              : Text(
                  '下载${widget.downloadSource ? '源码' : ''} :'
                  ' ${modListMeta.name}  ${modMeta?.tag ?? ''}',
                  style: theme.textTheme.titleMedium,
                  overflow: .ellipsis,
                  maxLines: 1,
                ),
        ),
        SizedBox(width: 8),
      ],
    );

    final info = Column(
      spacing: 4,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (javaDownloadBan) const SizedBox(),

        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: _buildAssetSelection(),
        ),

        Divider(thickness: 2, indent: 32, endIndent: 32, color: colors.border),

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
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: _buildInfoTile(),
              ),
            ),
          ),
        ),
        if (!javaDownloadBan)
          Center(
            child: IconTextButton(
              icon: Icons.file_open_outlined,
              content: '选择其他路径',
              onTap: () => _chooseOtherSavePath(),
            ),
          ),
      ],
    );

    final child = Column(
      mainAxisSize: .min,
      children: [
        title,
        const SizedBox(height: 8),
        CopperSingleChildScrollView(child: info),
      ],
    );

    final startButton = AnimatedOpacitySize(
      child: _canDownload
          ? ReboundButton(
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
            )
          : null,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Material(
          color: Colors.transparent,
          elevation: 4,
          shadowColor: Colors.black,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.6,
            padding: EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9 - 60,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: child,
          ),
        ),
        const SizedBox(height: 8),
        startButton,
      ],
    );
  }
}
