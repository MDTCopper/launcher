import 'package:copperlauncher_main/core/app_constant.dart';
import 'package:copperlauncher_main/data/net_asset.dart';
import 'package:copperlauncher_main/ui/util/dialog/custom_animated_dialog.dart';
import 'package:copperlauncher_main/ui/util/framework/content_panel.dart';
import 'package:copperlauncher_main/ui/util/widget/animated_expansion.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_list_tile.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_text_field.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/app_config.dart';
import '../../../domain/task_manager.dart';
import '../../../domain/tasks/download_mindustry.dart';
import '../../../util/io/downloader.dart';
import '../../../util/validate/windows_file_name_validator.dart';
import '../../feature/images.dart';
import '../../vars.dart';

class MindustryDownloadPage extends StatefulWidget {
  const MindustryDownloadPage({super.key});

  @override
  State<StatefulWidget> createState() => _MindustryDownloadPageState();
}

class _MindustryDownloadPageState extends State<MindustryDownloadPage> {
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

  Widget _buildVersionList(String title,
      List<MindustryGithubMeta> versionList,) {
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

//            测试页面

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

