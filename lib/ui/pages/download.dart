import 'dart:convert';

import 'package:async/async.dart';
import 'package:copperlauncher_main/core/app_constant.dart';
import 'package:copperlauncher_main/data/net_asset.dart';
import 'package:copperlauncher_main/ui/feature/feature_color.dart';
import 'package:copperlauncher_main/ui/util/dialog/custom_animated_dialog.dart';
import 'package:copperlauncher_main/ui/util/framework/content_panel.dart';
import 'package:copperlauncher_main/ui/util/framework/menu_bar.dart';
import 'package:copperlauncher_main/ui/util/framework/page_skeleton.dart';
import 'package:copperlauncher_main/ui/util/widget/animated_dropdown_menu.dart';
import 'package:copperlauncher_main/ui/util/widget/animated_expansion.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_list_tile.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_text_field.dart';
import 'package:copperlauncher_main/ui/util/widget/rebound_checkbox.dart';
import 'package:copperlauncher_main/util/format/string_cleaner.dart';
import 'package:copperlauncher_main/util/format/time_since.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:line_icons/line_icons.dart';
import 'package:string_similarity/string_similarity.dart';

import '../../core/app_config.dart';
import '../../domain/task_manager.dart';
import '../../domain/tasks/download_mindustry.dart';
import '../../util/io/downloader.dart';
import '../../util/validate/windows_file_name_validator.dart';
import '../feature/images.dart';
import '../util/widget/future/mod_icon_loader.dart';
import '../util/widget/pager.dart';
import '../util/widget/rebound_container.dart';
import '../vars.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadState();
}

class _DownloadState extends State<DownloadPage> with TickerProviderStateMixin {
  static int index = 5;

  final List<Widget> pageList = [
    _VersionPage(),
    _ModPage(),
    Center(key: ValueKey('2'), child: Text('todo:PackagePage')),
    Center(key: ValueKey('3'), child: Text('todo:MapPage')),
    Center(key: ValueKey('4'), child: Text('todo:BluePrintPage')),
    _TextAssetPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PageSkeleton(
      body: pageList[index],
      menuBar: SideMenuBar(
        items: [
          MenuItem(
            leading: Icon(Icons.view_in_ar),
            title: Text('Mindustry'),
            selected: index == 0,
            onTap: () => setState(() => index = 0),
          ),
          Row(
            children: [
              Text(
                '社区资源',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Expanded(child: Divider(indent: 8)),
            ],
          ),

          MenuItem(
            leading: Icon(LineIcons.puzzlePiece, fontWeight: FontWeight.w500),
            title: Text('模组'),
            selected: index == 1,
            onTap: () => setState(() => index = 1),
          ),
          MenuItem(
            leading: Icon(Icons.token_outlined),
            title: Text('整合包'),
            selected: index == 2,
            onTap: () => setState(() => index = 2),
          ),
          MenuItem(
            leading: Icon(Icons.map_outlined),
            title: Text('地图'),
            selected: index == 3,
            onTap: () => setState(() => index = 3),
          ),
          MenuItem(
            leading: Icon(Icons.paste_outlined),
            title: Text('蓝图'),
            selected: index == 4,
            onTap: () => setState(() => index = 4),
          ),
          MenuItem(
            leading: Icon(Icons.terminal),
            title: Text('测试资源'),
            selected: index == 5,
            onTap: () => setState(() => index = 5),
          ),
        ],
      ),
    );
  }
}

class _TextAssetPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _TextAssetPageState();
}

class _TextAssetPageState extends State<_TextAssetPage> {
  final list = <MindustryGithubMeta>[
    MindustryGithubMeta(
      name: "v8 Build 152.2 - Beta",
      releaseNum: "v152.2",
      releaseDate: "2025-09-29T12:56:21Z",
      assets: [
        GithubApiReleaseAsset(
          url: "http://localhost/downloads/Mindustry152.2.jar",
          size: 0,
          downloadCount: 0,
          name: 'Mindustry.jar',
        ),
      ],
      describe: '',
    )..isBe = false,
    MindustryGithubMeta(
      name: "v8 Build 152 - Beta",
      releaseNum: "v152",
      releaseDate: "2025-09-29T12:56:21Z",
      assets: [
        GithubApiReleaseAsset(
          url: "http://localhost/downloads/Mindustry152.jar",
          size: 0,
          downloadCount: 0,
          name: 'Mindustry.jar',
        ),
      ],
      describe: '',
    )..isBe = false,
    MindustryGithubMeta(
      name: "7.0 Build 146 ",
      releaseNum: "v146",
      releaseDate: "2025-09-29T12:56:21Z",
      assets: [
        GithubApiReleaseAsset(
          url: "http://localhost/downloads/mindustry146.jar",
          size: 0,
          downloadCount: 0,
          name: 'mindustry.jar',
        ),
      ],
      describe: '',
    )..isBe = false,
    MindustryGithubMeta(
      name: "Build 26403",
      releaseNum: "26403",
      releaseDate: "2025-09-29T12:56:21Z",
      assets: [
        GithubApiReleaseAsset(
          url: "http://localhost/downloads/mindustry26403.jar",
          size: 0,
          downloadCount: 0,
          name: 'mindustry.jar',
        ),
      ],
      describe: '',
    )..isBe = true,
    for (int i = 0; i < 50; i++)
      MindustryGithubMeta(
        name: "Build 26403",
        releaseNum: "26403",
        releaseDate: "2025-09-29T12:56:21Z",
        assets: [
          GithubApiReleaseAsset(
            url: "http://localhost/downloads/mindustry26403.jar",
            size: 0,
            downloadCount: 0,
            name: 'mindustry.jar',
          ),
        ],
        describe: '',
      )..isBe = true,
  ];

  // final list = <String, String>{
  //   "http://localhost/downloads/Mindustry152.2.jar": 'v152.2',
  //   "http://localhost/downloads/mindustry152.jar": 'v152',
  //   "http://localhost/downloads/mindustry146.jar": 'v146',
  //   "http://localhost/downloads/mindustryv142.jar": '',
  //   "http://localhost/downloads/mindustryv126.2.jar": '',
  //   "http://localhost/downloads/mindustry26403.jar": '',
  //   "http://localhost/downloads/mindustry26398.jar": '',
  // };

  Widget _buildVersionList(
    String title,
    List<MindustryGithubMeta> versionList,
  ) {
    final List<Widget> versions = [];

    final theme = Theme.of(context);

    for (var version in versionList) {
      if (version.assets.isEmpty) continue;

      late Widget subtitle = Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          Row(
            spacing: 8,
            children: [
              Icon(Icons.date_range_outlined),
              Text(version.releaseDate.split('T').first),
            ],
          ),
        ],
      );

      final Widget widget = ReboundListTile(
        margin: EdgeInsets.all(8),
        borderRadius: BorderRadius.circular(4),
        leading: Image.asset('assets/images/logo.png', width: 48),
        title: Text(version.name, style: theme.textTheme.bodyLarge),
        subtitle: subtitle,
        onTap: () {
          _buildDownloadPopup(version);
        },
      );
      versions.add(widget);
    }
    title = '$title(${versions.length.toString()})';
    return AnimatedExpansion(title: Text(title), children: versions);
  }

  void _buildDownloadPopup(MindustryGithubMeta mindustry) {
    showAnimatedDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 350),
      animationType: DialogAnimation.leapOut,
      pageBuilder: (context, _, _) {
        return _DownloadMindustryPopupPage(mindustry);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(items: [_buildVersionList('mindustry', list)]);
  }
}

class _DownloadMindustryPopupPage extends StatefulWidget {
  final MindustryGithubMeta mindustryMeta;

  const _DownloadMindustryPopupPage(this.mindustryMeta);

  @override
  State<StatefulWidget> createState() => _DownloadMindustryPopupPageState();
}

class _DownloadMindustryPopupPageState
    extends State<_DownloadMindustryPopupPage> {
  late final MindustryGithubMeta mindustryMeta = widget.mindustryMeta;
  late String tag = mindustryMeta.name;
  String? copperVersion;

  String? error;

  late final TextEditingController textEditingController;

  late final ExpansibleController controller = ExpansibleController();

  @override
  void initState() {
    error = check(tag);
    textEditingController = TextEditingController(text: tag)..addListener(() {
      tag = textEditingController.text;
      final text = textEditingController.text;
      setState(() {
        error = check(text);
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    textEditingController.dispose();
    controller.dispose();
    super.dispose();
  }

  String? check(String? tag) {
    final error = WindowsFileNameValidator.tagValidate(tag);
    if (error != null) return error;

    final versionFolds = config.versionOptions.versionFolds;
    for (final versionFold in versionFolds) {
      for (final versions in versionFold.versions) {
        if (versions.tag == tag) {
          return '名称已存在';
        }
      }
    }
    return null;
  }

  void startDownload() {
    if (error != null) return;

    addTask(DownloadMindustryTask(mindustryMeta: mindustryMeta, tag: tag));
    Navigator.of(context).pop();
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
                    Text(
                      '下载 ${mindustryMeta.name}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),

                OutlinedTextField(
                  label: '游戏名称',
                  error: error,
                  controller: textEditingController,
                ),

                AnimatedExpansion(
                  controller: controller,
                  title: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      copperVersion ?? '可选 copper launcher 版本(5)',
                      key: ValueKey(
                        copperVersion ?? '可选 copper launcher 版本(5)',
                      ),
                    ),
                  ),
                  child: Container(
                    constraints: BoxConstraints(maxHeight: 175),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        spacing: 8,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 4; i > 0; i--)
                            ReboundListTile(
                              borderRadius: BorderRadius.circular(4),
                              leading: Image.asset(Images.copper),
                              title: Text('Copper v0.${i + 1}.0'),

                              subtitle: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 8,
                                children: [
                                  Icon(Icons.date_range_outlined, size: 18),
                                  Text(
                                    '2025.${i + 3}.15 ',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                              trailing: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child:
                                    copperVersion == 'Copper v0.${i + 1}.0'
                                        ? Icon(
                                          Icons.check_box_outlined,
                                          size: 28,
                                        )
                                        : null,
                              ),
                              onTap: () {
                                setState(() {
                                  controller.collapse();
                                  if (copperVersion == 'Copper v0.${i + 1}.0') {
                                    copperVersion = null;
                                  } else {
                                    copperVersion = 'Copper v0.${i + 1}.0';
                                  }
                                });
                              },
                            ),
                          SizedBox(),
                        ],
                      ),
                    ),
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
          onTap: startDownload,
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

//==================================

//            版本页面

//==================================

class _VersionPage extends StatefulWidget {
  const _VersionPage();

  @override
  State<StatefulWidget> createState() => _VersionPageState();
}

class _VersionPageState extends State<_VersionPage> {
  static final List<MindustryGithubMeta> _versionList = [];
  static final Map<double, int> _minModGameVersionMap = {};
  static final Map<double, int> _minJavaModGameVersionMap = {};
  static late MindustryGithubMeta _latestBeta;

  Future<bool> _fetchVersionAssets() async {
    if (_versionList.isNotEmpty) return true;

    final url = "https://api.github.com/repos/Anuken/Mindustry/releases";
    final betaUrl =
        "https://api.github.com/repos/Anuken/MindustryBuilds/releases";

    try {
      final List<MindustryGithubMeta> list = [];

      for (int i = 1; !((i - 1) * 100 > list.length); i++) {
        var response = await dio.get(
          '$url?page=$i&per_page=100',
          options: Options(headers: gameDownloadHeaders),
        );
        if (response.statusCode == 200) {
          List<dynamic> jsonList = response.data;
          //用jsonList生成Mindustry后组成MindustryList
          list.addAll(
            jsonList
                .map<MindustryGithubMeta>(
                  (json) => MindustryGithubMeta.fromJson(json),
                )
                .toList(),
          );
        } else {
          throw Exception("列表获取失败：${response.statusCode}");
        }
      }

      _versionList.clear();
      _versionList.addAll(list);
      list.clear();

      //只获取最新be，然后提供按版本号下载
      var response = await dio.get(
        '$betaUrl?per_page=1',
        options: Options(headers: gameDownloadHeaders),
      );
      if (response.statusCode == 200) {
        List<dynamic> jsonList = response.data;
        _latestBeta = MindustryGithubMeta.fromJson(jsonList.first);
      } else {
        throw Exception("列表获取失败：${response.statusCode}");
      }
      return true;
    } catch (e) {
      debugPrint(e.toString());
      return false;
    }
  }

  Widget _buildVersionList(
    String title,
    List<MindustryGithubMeta> versionList,
  ) {
    List<Widget> versions = [];

    for (var version in versionList) {
      if (version.assets.isEmpty) continue;
      final Widget subtitle = Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          Row(
            spacing: 8,
            children: [
              Icon(Icons.date_range_outlined, size: 18),
              Text(version.releaseDate.split('T').first),
            ],
          ),
        ],
      );

      final Widget widget = ReboundListTile(
        margin: EdgeInsets.all(8),
        borderRadius: BorderRadius.circular(4),
        leading: Image.asset('assets/images/logo.png', width: 48),
        title: Text(version.name),
        subtitle: subtitle,
        onTap: () {
          _buildDownloadPopup(version);
        },
      );
      versions.add(widget);
    }
    title = '$title(${versions.length.toString()})';

    return AnimatedExpansion(title: Text(title), children: versions);
  }

  void _buildDownloadPopup(MindustryGithubMeta mindustry) {
    showAnimatedDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 350),
      animationType: DialogAnimation.leapOut,
      pageBuilder: (context, _, _) {
        return _DownloadMindustryPopupPage(mindustry);
      },
    );
  }

  Widget _buildVersionView() {
    return ListContentPanel(
      items: [
        ContentPanelModule(
          title: '最新版本',
          child: Column(
            spacing: 8,
            children: [
              ReboundListTile(
                pressedScale: 0.98,
                margin: EdgeInsets.all(8),
                borderRadius: BorderRadius.circular(4),
                leading: Image.asset('assets/images/logo.png', width: 48),
                title: Text(_versionList.first.name),
                subtitle: Row(
                  spacing: 8,
                  children: [
                    Icon(Icons.date_range_outlined, size: 18),
                    Text(_versionList.first.releaseDate.split('T').first),
                  ],
                ),
                onTap: () {
                  _buildDownloadPopup(_versionList.first);
                },
              ),
              ReboundListTile(
                pressedScale: 0.98,
                margin: EdgeInsets.all(8),
                borderRadius: BorderRadius.circular(4),
                leading: Image.asset('assets/images/logo.png', width: 48),
                title: Text(_latestBeta.name),
                subtitle: Row(
                  spacing: 8,
                  children: [
                    Icon(Icons.date_range_outlined, size: 18),
                    Text(_latestBeta.releaseDate.split('T').first),
                  ],
                ),
                onTap: () {
                  _buildDownloadPopup(_latestBeta);
                },
              ),
            ],
          ),
        ),
        _buildVersionList('正式版', _versionList),
        SizedBox(height: 40),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = FutureBuilder<bool>(
      future: _fetchVersionAssets(),
      builder: (context, snapshot) {
        late Widget widget;

        if (snapshot.connectionState == ConnectionState.waiting) {
          widget = Center(
            key: ValueKey(snapshot.connectionState),
            child: CircularProgressIndicator(color: Colors.grey),
          );
        } else {
          if (snapshot.data ?? false) {
            widget = _buildVersionView();
          } else {
            widget = Card(
              color: FeatureColors.coolTonedWhite,
              child: Padding(
                padding: EdgeInsetsGeometry.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    Text(
                      '网络错误，请检查网络环境后再重试',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ReboundButton(
                      child: Icon(Icons.refresh, color: Colors.red, size: 40),
                      onTap: () {
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          }
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: widget,
        );
      },
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReboundButton(
          child: Icon(Icons.download, size: 40),
          onTap: () async {
            print('fetch minGameVersion');

            var depth = 0;
            for (final version in _versionList) {
              // depth++;
              // if (depth > 2) break;

              final num = double.parse(version.releaseNum.substring(1));

              if (num < 100) break;

              if (_minJavaModGameVersionMap.containsKey(num)) continue;
              if (_minModGameVersionMap.containsKey(num)) continue;

              print(version.releaseNum);
              dio
                  .get(
                    '$githubRAW/Anuken/Mindustry/${version.releaseNum}/core/src/mindustry/Vars.java',
                  )
                  .then((value) {
                    if (value.statusCode == 200) {
                      final str = value.data as String;
                      var index = str.lastIndexOf('minModGameVersion = ');
                      if (index != -1) {
                        final len = 'minModGameVersion = '.length;
                        final minGameVersion = str.substring(
                          index + len,
                          index + len + 3,
                        );
                        _minModGameVersionMap[double.parse(
                          version.releaseNum.substring(1),
                        )] = int.parse(minGameVersion);
                      }
                      index = str.lastIndexOf('minJavaModGameVersion = ');
                      if (index != -1) {
                        final len = 'minJavaModGameVersion = '.length;
                        final minGameVersion = str.substring(
                          index + len,
                          index + len + 3,
                        );
                        _minJavaModGameVersionMap[double.parse(
                          version.releaseNum.substring(1),
                        )] = int.parse(minGameVersion);
                      }
                    }
                  });
              await Future.delayed(const Duration(milliseconds: 400));
            }
          },
        ),
        ReboundButton(
          child: Icon(Icons.print, size: 40),
          onTap: () {
            print(_minModGameVersionMap);
            print('----------------');
            print(_minJavaModGameVersionMap);
          },
        ),
        Expanded(child: child),
      ],
    );

    return child;
  }
}

//==================================

//            模组页面

//==================================

class _ModPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _ModPageState();
}

class _ModPageState extends State<_ModPage> {
  static Map<String, ModOfficialListMeta> previousModMetaMap = {};
  static List<ModOfficialListMeta> modMetas = [];
  static int index = 1;
  static bool order = true;
  static String sort = 'default';

  late bool conditionChange;

  static String searchString = '';
  late final TextEditingController searchTextController;

  late final ScrollController _controller;

  static double version = 9999;

  static Set<double> versionSet = {};

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
    //todo 做一个列表，选择版本筛选就会筛掉不能运行的模组
    final minGameVersion = minModGameVersionMap[version] ?? 136;

    final minJavaGameVersion = minJavaModGameVersionMap[version] ?? 136;

    final l = modMetas.toList();
    return l.where((it) {
      final isJava = it.hasJava;
      final modMin = double.parse(it.minGameVersion);

      final bool support;

      if (isJava) {
        support = modMin >= minJavaGameVersion && modMin <= version;
      } else {
        support = modMin >= minGameVersion && modMin <= version;
      }

      final type =
          it.hasJava
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

      double hot =
          mod.starsDifferenceCache == null
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
          var jsons = jsonDecode(res.data);
          final List<ModOfficialListMeta> list =
              jsons
                  .map<ModOfficialListMeta>(
                    (it) => ModOfficialListMeta.fromJson(it),
                  )
                  .toList();
          previousModMetaMap = {for (final it in list) it.repo: it};
        }

        return true;
      } catch (e) {
        if (tryTime < 5) {
          print(tryTime);
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

    Widget buildResetButton() {
      final showResetButton =
          searchString.isNotEmpty ||
          sort != 'default' ||
          version != 9999 ||
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
          child:
              showResetButton
                  ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReboundIconButton(
                        icon: Icons.refresh,
                        content: '重置',
                        onTap: () {
                          setState(() {
                            searchTextController.clear();
                            sort = 'default';
                            version = 9999;
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

    var selectedVersion = double.tryParse(
      config.versionOptions.selectedVersion?.releaseNum.substring(1) ?? '',
    );

    Widget buildModTypeOptions() {
      return Row(
        children: [
          Text('模组类型'),
          SizedBox(width: 16),
          Container(
            padding: EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.fromBorderSide(
                theme.inputDecorationTheme.border?.borderSide ?? BorderSide(),
              ),
            ),
            child: Row(
              spacing: 4,
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
          ),
        ],
      );
    }

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
              SizedBox(width: 16),
              buildResetButton(),
              ReboundIconButton(
                icon: Icons.search,
                content: '搜索',
                onTap: () => setState(() {}),
              ),
            ],
          ),
          Row(
            spacing: 32,
            children: [
              SizedBox(
                width: 180,
                child: Row(
                  spacing: 16,
                  children: [
                    Text('游戏版本'),
                    Expanded(
                      child: AnimatedDropdownMenu<double>(
                        initialValue: version,
                        onSelect: (v) {
                          setState(() {
                            version = v;
                            conditionChange = true;
                          });
                        },
                        options: [
                          DropdownOption(value: 9999, label: '不限'),
                          if (selectedVersion != null)
                            DropdownOption(
                              value: selectedVersion,
                              label: '当前版本',
                            ),
                          DropdownOption(value: 157.4, label: 'v154+'),
                          DropdownOption(value: 154.0, label: 'v147+'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: Row(
                  spacing: 16,
                  children: [
                    Text('排序'),
                    Expanded(
                      child: AnimatedDropdownMenu(
                        initialValue: sort,
                        onSelect: (s) {
                          setState(() {
                            sort = s;
                            conditionChange = true;
                          });
                        },
                        options: [
                          DropdownOption(value: 'default', label: '默认'),
                          DropdownOption(value: 'stars', label: '星星'),
                          DropdownOption(value: 'updateTime', label: '更新时间'),
                          DropdownOption(value: 'hot', label: '热度'),
                        ],
                      ),
                    ),
                    ReboundButton(
                      child: AnimatedRotation(
                        turns: order ? 0.0 : 0.5,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOutBack,
                        child: Icon(Icons.arrow_downward),
                      ),
                      onTap: () => setState(() => order = !order),
                    ),
                  ],
                ),
              ),
            ],
          ),
          buildModTypeOptions(),
        ],
      ),
    );
  }

  Widget? _buildWarningBar() {
    final key = 'warning bar of mod page of download page enable';
    final setting = config.setting.getCustomSetting(key, true);
    if (setting == false) return null;
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
              '国内访问github受限，请优先选择国内镜像资源；'
              '如有条件，可以到设置中添加网络代理',
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
            onTap: () {
              config.setting.customSetting[key] = false;
              setState(() {});
              config.save();
            },
            child: Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildModTile(ModOfficialListMeta mod) {
    final theme = Theme.of(context);

    Widget buildOverview() {
      Widget buildIconText(IconData icon, String text) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon), Text(text)],
        );
      }

      var stars = '${mod.stars}';
      if (sort == 'hot') {
        if (mod.starsDifferenceCache != null) {
          stars +=
              '(${mod.starsDifferenceCache!.isNegative ? '' : '+'}${mod.starsDifferenceCache})';
        }
      }
      return Row(
        spacing: 12,
        children: [
          if (mod.hasJava) buildIconText(Icons.coffee_outlined, 'Java'),
          if (mod.hasScripts && !mod.hasJava)
            buildIconText(LineIcons.javascriptJsSquare, 'JavaScript'),
          if (!(mod.hasScripts || mod.hasJava))
            buildIconText(Icons.data_object, 'Json'),
          Expanded(child: SizedBox()),
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: 60, maxWidth: 100),
            child: buildIconText(
              Icons.source_outlined,
              'v${mod.minGameVersion}',
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: 80, maxWidth: 120),
            child: buildIconText(Icons.star_border, stars),
          ),
          SizedBox(
            width: 180,
            child: buildIconText(
              Icons.update,
              "${mod.lastUpdated.toIso8601String().split('T').first}"
              " (${timeSince(mod.lastUpdated)})",
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
          child: Row(
            spacing: 8,
            children: [
              Text(
                removeColorTags(mod.name),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              VerticalDivider(endIndent: 5, indent: 5),
              Expanded(
                child: Text(
                  removeColorTags(removeNewlines(mod.author)),
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
            '/download/mod_download',
            arguments: {'lead': '模组下载 ', 'title': mod.name, 'mod': mod},
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
              ReboundIconButton(
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
