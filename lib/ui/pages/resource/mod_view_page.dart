import 'dart:convert';

import 'package:async/async.dart';
import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/data/net_asset.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_checkbox.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/format/time_since.dart';
import 'package:flutter/material.dart';
import 'package:line_icons/line_icons.dart';
import 'package:string_similarity/string_similarity.dart';

import '../../../core/app_config.dart';
import '../../../util/io/downloader.dart';
import '../../components/future/mod_icon_loader.dart';
import '../../components/pager.dart';
import '../../components/row/priority_row.dart';
import '../../components/tips/warning_bar.dart';
import '../../vars.dart';

///模组浏览页面
class ModViewPage extends StatefulWidget {
  const ModViewPage({super.key});

  @override
  State<StatefulWidget> createState() => _ModViewPageState();
}

class _ModViewPageState extends State<ModViewPage> {
  static Map<String, ModOfficialListMeta> previousModMetaMap = {};
  static List<ModOfficialListMeta> modMetas = [];
  static int index = 1;
  static bool order = true;
  static String sort = 'default';

  /// 版本(180) + 排序(200) + 两处间距(24*2) 的并排预算，取整 420
  static const double _kVersionSortBlockWidth = 420;

  /// 选项区并排阈值：预留基准(420) + 版本排序块(420)
  static const double _kInlineMoreOptionsMinWidth =
      420 + _kVersionSortBlockWidth;

  late bool conditionChange;

  static String searchString = '';
  late final TextEditingController searchTextController;

  late final ScrollController _controller;

  ///不限版本 = -1 , 当前所选版本 = -2
  static int version = -1;

  static Set<String> modTypeSet = {};

  @override
  void initState() {
    super.initState();
    conditionChange = true;
    searchTextController = TextEditingController(text: searchString)
      ..addListener(() {
        searchString = searchTextController.text;
        conditionChange = true;
      });
    _controller = ScrollController();

    if (version == -2 && config.versionOptions.selectedVersion == null) {
      version = -1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _fetchModMetasOperation?.cancel();
    super.dispose();
  }

  var headers = modDownloadHeaders;

  void _move(int to) async {
    _controller.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
    await Future.delayed(const Duration(milliseconds: 250));
    setState(() {
      index = to;
    });
  }

  List<ModOfficialListMeta> get filteredMods {
    final int v;

    if (version == -2) {
      v = int.parse(
        config.versionOptions.selectedVersion!.releaseNum
            .substring(1)
            .split('.')
            .first,
      );
    } else {
      v = version;
    }

    final minGameVersion = minModGameVersionModifier.resultOf(v);

    final minJavaGameVersion = minJavaModGameVersionModifier.resultOf(v);

    final l = modMetas.toList();
    return l.where((it) {
      final isJava = it.hasJava;
      final modMin = double.parse(it.minGameVersion);

      bool support;

      //不限版本，不过滤
      if (version == -1) {
        support = true;
      } else {
        if (isJava) {
          support = modMin >= minJavaGameVersion && modMin <= v;
        } else {
          support = modMin >= minGameVersion && modMin <= v;
        }
      }

      final type = it.hasJava
          ? 'java'
          : it.hasScripts
          ? 'js'
          : 'json';

      final typeFilter = modTypeSet.isEmpty || modTypeSet.contains(type);

      return support && typeFilter;
    }).toList();
  }

  //相似算法耗时较长
  List<ModOfficialListMeta> sortedModCache = [];

  Future<List<ModOfficialListMeta>> get sortedMods async {
    if (!conditionChange) {
      if (!order) return sortedModCache;
      return sortedModCache.reversed.toList();
    }

    final l = filteredMods;

    var starsWeight = 0.06;
    var matchWeight = 0.7;
    var updateWeight = 0.10;
    var randomWeight = 0.14;
    var hotWeight = 0.0;

    switch (sort) {
      case 'stars':
        starsWeight = 0.299;
        updateWeight = 0.001;
        randomWeight = 0.0;
        break;
      case 'updateTime':
        starsWeight = 0.001;
        updateWeight = 0.299;
        randomWeight = 0.0;
        break;
      case 'hot':
        starsWeight = 0.005;
        updateWeight = 0.035;
        randomWeight = 0.0;
        hotWeight = 0.26;
        break;
    }
    double scoreOf(ModOfficialListMeta mod) {
      final stars = mod.stars / (mod.stars + 200);

      final timeD = DateTime.now().difference(mod.lastUpdated).inHours;
      final updateTime = 1 - (timeD / (timeD + 24 * 7));

      double match = 0;
      if (searchString.isNotEmpty) {
        final name =
            mod.name.toLowerCase().similarityTo(searchString.toLowerCase()) *
            0.8;
        if (name < 0.2) {
          match +=
              removeColorTags(
                mod.author.toLowerCase(),
              ).similarityTo(searchString.toLowerCase()) *
              0.8;
        } else {
          match += name;
        }
        match +=
            generalizeText(
              mod.name.toLowerCase(),
            ).similarityTo(searchString.toLowerCase()) *
            0.2;
      }

      final random = randomWeight == 0 ? 0 : mod.hashCode % 10 / 10;

      double hot = mod.starsDifferenceCache == null
          ? 0.0
          : mod.starsDifferenceCache! / (mod.starsDifferenceCache! + 10);
      if (hotWeight != 0.0 && hot == 0.0) {
        final previousMeta = previousModMetaMap[mod.repo];
        if (previousMeta != null) {
          final starsD = mod.stars - previousMeta.stars;
          hot = starsD / (starsD + 20);
          mod.starsDifferenceCache = starsD;
        } else {
          //新模组奖励算法(?)
          if (timeD < 24 * 94) {
            hot = mod.stars / (mod.stars + 10);
            mod.starsDifferenceCache = mod.stars;
          } else {
            //长期(不更新+star不涨)惩罚
            hot = 0;
            mod.starsDifferenceCache = 0;
          }
        }
      }

      return stars * starsWeight +
          updateTime * updateWeight +
          match * matchWeight +
          random * randomWeight +
          hot * hotWeight;
    }

    l.sort((a, b) => scoreOf(a).compareTo(scoreOf(b)));
    sortedModCache = l;
    if (!order) return l;
    return l.reversed.toList();
  }

  CancelableOperation<bool>? _fetchModMetasOperation;
  var _refreshModMetas = true;

  Future<bool> _fetchModMetas() async {
    // await Future.delayed(const Duration(seconds: 1));
    if (!_refreshModMetas && _fetchModMetasOperation != null) {
      return await _fetchModMetasOperation!.value;
    }
    _refreshModMetas = false;
    _fetchModMetasOperation?.cancel();

    Future<bool> fetch({int tryTime = 0}) async {
      try {
        if (modMetas.isEmpty) {
          var res = await dio.get(githubModMetaUrl);
          if (res.statusCode != 200) throw Exception('链接失败');
          List<dynamic> jsons = jsonDecode(res.data);
          modMetas.addAll(
            jsons
                .map<ModOfficialListMeta>(
                  (it) => ModOfficialListMeta.fromJson(it),
                )
                .toList(),
          );
        }
        if (previousModMetaMap.isEmpty) {
          var res = await dio.get(github3MonthsModMetaUrl);
          if (res.statusCode != 200) throw Exception('链接失败');
          List<dynamic> jsons = jsonDecode(res.data);
          final List<ModOfficialListMeta> list = jsons
              .map<ModOfficialListMeta>(
                (it) => ModOfficialListMeta.fromJson(it),
              )
              .toList();
          previousModMetaMap = {for (final it in list) it.repo: it};
        }

        return true;
      } catch (e) {
        if (tryTime < 5) {
          tryTime++;
          await Future.delayed(const Duration(seconds: 1));
          return await fetch(tryTime: tryTime);
        }
        rethrow;
      }
    }

    _fetchModMetasOperation = CancelableOperation<bool>.fromFuture(fetch());
    return await _fetchModMetasOperation!.value;
  }

  // ===========================
  //            UI
  // ===========================

  Widget _buildHeadBar() {
    final theme = Theme.of(context);
    var selectedVersion = double.tryParse(
      config.versionOptions.selectedVersion?.releaseNum.substring(1) ?? '',
    );
    Widget buildResetButton() {
      final showResetButton =
          searchString.isNotEmpty ||
          sort != 'default' ||
          version != -1 ||
          modTypeSet.isNotEmpty;

      return AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.ease,
          switchOutCurve: Curves.ease,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            );
          },
          child: showResetButton
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconTextButton(
                      icon: Icons.refresh,
                      content: '重置',
                      onTap: () {
                        setState(() {
                          searchTextController.clear();
                          sort = 'default';
                          version = -1;
                          modTypeSet.clear();
                        });
                      },
                    ),
                    SizedBox(width: 8),
                  ],
                )
              : null,
        ),
      );
    }

    /// 模组类型紧凑多选下拉：窄窗与宽窗并排时共用
    Widget buildModTypeDropdown() => LayoutBuilder(
      builder: (_, c) => DropdownLayer<String>.multiSelect(
        hintText: '不限',
        width: c.maxWidth.clamp(0.0, 280),
        initialValues: modTypeSet,
        onMultiSelect: (set) {
          setState(() {
            modTypeSet
              ..clear()
              ..addAll(set);
          });
        },
        options: [
          DropdownOption(value: 'copper', label: 'Copper'),
          DropdownOption(value: 'java', label: 'Java'),
          DropdownOption(value: 'js', label: 'JavaScript'),
          DropdownOption(value: 'json', label: 'Json'),
        ],
        // 场景自建“全选 / 重置”工具栏，位于菜单顶部
        topWidget: (context, controller) {
          final colors = AppColors.of(context);
          return Row(
            children: [
              Expanded(child: Divider(height: 6, color: colors.border)),
              ReboundButton(
                pressedScale: 0.9,
                borderRadius: BorderRadius.circular(4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                onTap: controller.isAllSelected
                    ? controller.reset
                    : controller.selectAll,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      controller.isAllSelected
                          ? Icons.restart_alt
                          : Icons.select_all,
                      size: 14,
                      color: colors.itemSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      controller.isAllSelected ? '重置' : '全选',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.itemSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    Widget buildModTypeOptions() {
      Widget buildOptions() => LayoutBuilder(
        builder: (_, c) {
          // 窄窗：切换为多选下拉
          if (c.maxWidth < 330) return buildModTypeDropdown();

          return Container(
            padding: EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.fromBorderSide(
                theme.inputDecorationTheme.border?.borderSide ?? BorderSide(),
              ),
            ),
            child: Row(
              spacing: 4,
              mainAxisSize: .min,
              children: [
                ReboundCheckbox(
                  label: '不限',
                  value: modTypeSet.isEmpty,
                  onChange: (v) {
                    if (modTypeSet.isEmpty) return;
                    setState(() {
                      modTypeSet.clear();
                    });
                  },
                ),
                SizedBox(),
                SizedBox(
                  width: 1,
                  height: 18,
                  child: ColoredBox(color: theme.colorScheme.primary),
                ),
                SizedBox(),
                ReboundCheckbox(
                  label: 'Copper',
                  value: modTypeSet.contains('copper'),
                  onChange: (v) {
                    setState(() {
                      if (v == true) {
                        modTypeSet.add('copper');
                      } else {
                        modTypeSet.remove('copper');
                      }
                    });
                  },
                ),
                ReboundCheckbox(
                  label: 'Java',
                  value: modTypeSet.contains('java'),
                  onChange: (v) {
                    setState(() {
                      if (v == true) {
                        modTypeSet.add('java');
                      } else {
                        modTypeSet.remove('java');
                      }
                    });
                  },
                ),
                ReboundCheckbox(
                  label: 'JavaScript',
                  value: modTypeSet.contains('js'),
                  onChange: (v) {
                    setState(() {
                      if (v == true) {
                        modTypeSet.add('js');
                      } else {
                        modTypeSet.remove('js');
                      }
                    });
                  },
                ),
                ReboundCheckbox(
                  label: 'Json',
                  value: modTypeSet.contains('json'),
                  onChange: (v) {
                    setState(() {
                      if (v == true) {
                        modTypeSet.add('json');
                      } else {
                        modTypeSet.remove('json');
                      }
                    });
                  },
                ),
              ],
            ),
          );
        },
      );

      return Row(
        children: [
          Text('模组类型'),
          SizedBox(width: 16),
          Flexible(child: buildOptions()),
        ],
      );
    }

    Widget buildVersionOptions() {
      return SizedBox(
        width: 180,
        child: Row(
          spacing: 16,
          children: [
            Text('游戏版本'),
            Expanded(
              child: DropdownLayer<int>(
                initialValue: version,
                onSelect: (v) {
                  setState(() {
                    version = v;
                    conditionChange = true;
                  });
                },
                options: [
                  DropdownOption(value: -1, label: '不限'),
                  if (selectedVersion != null)
                    DropdownOption(value: -2, label: '当前版本'),
                  DropdownOption(value: 154, label: 'v154+'),
                  DropdownOption(value: 147, label: 'v147+'),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget buildSortOptions() => LayoutBuilder(
      builder: (_, c) {
        // 长度不足 200：排序二字并入无选项占位文本，递增递减符号并入菜单头部
        final soSmall = c.maxWidth < 200;

        return SizedBox(
          width: c.maxWidth.clamp(0, 200),
          child: Row(
            children: [
              if (!soSmall) ...[Text('排序'), const SizedBox(width: 16)],
              Expanded(
                child: DropdownLayer(
                  initialValue: sort,
                  onSelect: (s) {
                    setState(() {
                      sort = s;
                      conditionChange = true;
                    });
                  },
                  options: [
                    DropdownOption(
                      value: 'default',
                      label: soSmall ? '默认排序' : '默认',
                    ),
                    DropdownOption(value: 'stars', label: '星星'),
                    DropdownOption(value: 'updateTime', label: '更新时间'),
                    DropdownOption(value: 'hot', label: '热度'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ReboundButton(
                child: AnimatedRotation(
                  turns: order ? 0.0 : 0.5,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutBack,
                  child: Icon(Icons.arrow_downward, size: 18),
                ),
                onTap: () => setState(() => order = !order),
              ),
            ],
          ),
        );
      },
    );

    /// 选项区：宽窗时模组类型与版本 / 排序并排一行，窄窗回退为分行
    Widget buildFilterOptionsRow() => LayoutBuilder(
      builder: (_, c) {
        if (c.maxWidth >= _kInlineMoreOptionsMinWidth) {
          return Row(
            children: [
              Flexible(child: buildModTypeOptions()),
              const SizedBox(width: 24),
              buildVersionOptions(),
              const SizedBox(width: 24),
              buildSortOptions(),
            ],
          );
        }
        return Column(
          spacing: 8,
          children: [
            buildModTypeOptions(),
            Row(
              spacing: 16,
              children: [
                buildVersionOptions(),
                Flexible(child: buildSortOptions()),
              ],
            ),
          ],
        );
      },
    );

    return ContentPanelModule(
      title: '搜索',
      child: Column(
        spacing: 8,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedTextField(
                  label: '模组名称',
                  controller: searchTextController,
                ),
              ),
              const SizedBox(width: 8),
              buildResetButton(),
              IconTextButton(
                icon: Icons.search,
                content: '搜索',
                onTap: () => setState(() {}),
              ),
            ],
          ),
          buildFilterOptionsRow(),
        ],
      ),
    );
  }

  Widget? _buildWarningBar() {
    return buildWarningBar(
      context,
      'warning bar of mod page of download page enable',
      '国内访问github受限，请优先选择国内镜像资源；'
          '如有条件，可以到设置中添加网络代理',
      onTap: () => setState(() {}),
    );
  }

  Widget _buildModTile(ModOfficialListMeta mod) {
    final theme = Theme.of(context);

    Widget buildOverview() {
      String modTypeText() {
        if (mod.hasJava) return 'Java';
        if (mod.hasScripts && !mod.hasJava) return 'JavaScript';
        return 'Json';
      }

      IconData modTypeIcon() {
        if (mod.hasJava) return Icons.coffee_outlined;
        if (mod.hasScripts && !mod.hasJava) return LineIcons.javascriptJsSquare;
        return Icons.data_object;
      }

      var stars = '${mod.stars}';
      if (sort == 'hot') {
        if (mod.starsDifferenceCache != null) {
          stars +=
              '(${mod.starsDifferenceCache!.isNegative ? '' : '+'}${mod.starsDifferenceCache})';
        }
      }

      return Row(
        children: [
          SizedBox(
            width: 70,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.source_outlined, size: 18),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'v${mod.minGameVersion}',

                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: PriorityRow(
              items: [
                PriorityRowItem.text(
                  text: modTypeText(),
                  icon: modTypeIcon(),
                  priority: 3,
                  width: 100,
                ),
                PriorityRowItem.text(
                  text: stars,
                  icon: Icons.star_border,
                  priority: 2,
                  width: 90,
                ),
                PriorityRowItem.text(
                  text:
                      "${mod.lastUpdated.toIso8601String().split('T').first}"
                      " (${timeSince(mod.lastUpdated)})",
                  icon: Icons.update,
                  priority: 1,
                  width: 160,
                ),
              ],
            ),
          ),
        ],
      );
    }

    //_iconFuturesCache[mod.repo] ??= _fetchModIcon(mod);

    return SizedBox(
      height: 84,
      child: ReboundListTile(
        itemSpacing: 8,
        leading: SizedBox(
          height: 64,
          width: 64,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ModNetworkIcon(modMeta: mod),
          ),
        ),
        title: SizedBox(
          height: 24,
          child: LayoutBuilder(
            builder: (_, c) {
              final painter = TextPainter(
                textDirection: Directionality.of(context),
                text: TextSpan(
                  text: removeColorTags(mod.name),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )..layout();
              const authorMinWidth = 120;
              final nameSoLong = c.maxWidth - painter.width < authorMinWidth;

              Widget name = Text(
                generalizeText(mod.name),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );

              Widget author = Text(
                generalizeText(mod.author),
                style: theme.textTheme.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );

              if (nameSoLong) {
                author = SizedBox(width: 100, child: author);
                name = Flexible(child: name);
              } else {
                author = Expanded(child: author);
              }

              return Row(
                spacing: 8,
                children: [
                  name,
                  VerticalDivider(endIndent: 5, indent: 5, width: 1),
                  author,
                ],
              );
            },
          ),
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              removeColorTags(removeNewlines(mod.description)),
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            buildOverview(),
          ],
        ),
        borderRadius: BorderRadius.circular(4),
        onTap: () {
          Navigator.pushNamed(
            context,
            '/mod_view/download',
            arguments: {'lead': '模组下载', 'title': mod.name, 'mod': mod},
          );
        },
      ),
    );
  }

  Widget _buildList() {
    final theme = Theme.of(context);

    Widget buildFetchFailed() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('模组列表获取失败，请检查网络后重试'),
              IconTextButton(
                icon: Icons.refresh,
                content: '重试',
                onTap: () => setState(() => _refreshModMetas = true),
              ),
            ],
          ),
        ],
      );
    }

    Widget buildLoading() {
      return CircularProgressIndicator();
    }

    return FutureBuilder<bool>(
      future: _fetchModMetas(),
      builder: (context, snapshot) {
        Widget child;

        final state = snapshot.connectionState;
        if (snapshot.hasError) child = buildFetchFailed();
        if (state == ConnectionState.waiting) {
          child = buildLoading();
        } else if (modMetas.isEmpty) {
          child = buildFetchFailed();
        } else {
          child = ContentPanelModule(
            child: FutureBuilder(
              future: sortedMods,
              builder: (_, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return SizedBox();
                }

                final length = s.data!.length;

                if (length == 0) {
                  return Column(
                    spacing: 8,
                    children: [
                      Text('( ´ﾟДﾟ`)', style: theme.textTheme.titleLarge),
                      Text('没有找到任何模组...'),
                    ],
                  );
                }

                final int perPage = 25;
                int begin = (index - 1) * perPage;
                int end;
                if (length < index * perPage) {
                  end = length;
                } else {
                  end = index * perPage;
                }

                int endIndex =
                    length ~/ perPage + (length % perPage == 0 ? 0 : 1);
                return Column(
                  spacing: 8,
                  children: [
                    for (int i = begin; i < end; i++) _buildModTile(s.data![i]),
                    Pager(
                      index,
                      endPage: index == endIndex,
                      endIndex: endIndex,
                      onDown: () => _move(--index),
                      onUp: () => _move(++index),
                      goHome: () => _move(1),
                      goEnd: () => _move(endIndex),
                    ),
                  ],
                );
              },
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

            final scale = Tween(begin: 0.6, end: 1.0).animate(animation);

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
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      controller: _controller,
      items: [_buildHeadBar(), _buildWarningBar(), _buildList()],
    );
  }
}
