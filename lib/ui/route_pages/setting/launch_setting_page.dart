import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:copperlauncher_main/ui/components/rebound/rebound_checkbox.dart';
import 'package:copperlauncher_main/ui/util/info/notification.dart';
import 'package:copperlauncher_main/ui/util/widget/animated_dropdown_menu.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_text_field.dart';
import 'package:copperlauncher_main/ui/util/widget/percent_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/checkbox_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/input_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/option_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/switch_setting_bar.dart';
import 'package:copperlauncher_main/util/format/byte_unit.dart';
import 'package:copperlauncher_main/util/io/java_finder.dart';
import 'package:copperlauncher_main/util/io/path_selector.dart';
import 'package:copperlauncher_main/util/system_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:line_icons/line_icons.dart';

import '../../../core/app_config.dart';
import '../../../util/format/ram_rank_list.dart';
import '../../util/framework/content_panel.dart';
import '../../util/widget/setting_bar/slider_setting_bar.dart';

class LaunchSettingPage extends StatefulWidget {
  const LaunchSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _LaunchSettingPageState();
}

class _LaunchSettingPageState extends State<LaunchSettingPage> {
  LaunchOptions get launchOptions => config.setting.launchOptions;

  Set<VersionIsolation> get versionIsolationSet =>
      launchOptions.versionIsolationSet;

  GameWindowSizeSet get gameWindowSizeSet => launchOptions.gameWindowSizeSet;

  WindowSize get customWindowSize => launchOptions.customWindowSize;

  JavaOptions get javaOptions => launchOptions.javaOptions;

  String get javaSelect => javaOptions.selectedJava;

  List<JavaInfo> get javas => javaOptions.javas;

  Memory get memory => launchOptions.memory;

  bool get autoMemory => launchOptions.autoMemory;

  bool get useGoodGPU => launchOptions.javaOptions.useBetterGPU;

  String get jvmParameter => javaOptions.jvmParameter;

  late final TextEditingController widthController;
  late final TextEditingController heightController;
  static Memory freeMemory = Memory(gb: 128);
  static Memory totalMemory = Memory(gb: 128);

  late Timer _getMemoryTimer;

  void _getRam() async {
    final free = await SysInfo.getFreePhysicalMemory();
    freeMemory = Memory(bytes: free);
    final total = await SysInfo.getTotalPhysicalMemory();
    totalMemory = Memory(bytes: total);
    if (mounted) setState(() {});
    _getMemoryTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final free = await SysInfo.getFreePhysicalMemory();
      freeMemory = Memory(bytes: free);
      if (mounted) setState(() {});
    });
  }

  String _formatRam(double ram) {
    return (ram).toStringAsFixed(1);
  }

  void _routeToVersionSetting() {
    Navigator.pushNamed(
      context,
      '/version_setting',
      arguments: {
        'lead': '版本设置',
        'version': config.versionOptions.selectedVersion,
        'title': config.versionOptions.selectedVersion?.tag ?? 'null',
      },
    );
  }

  bool searching = false;

  void _searchJava() async {
    if (searching) return;
    searching = true;

    addNotice(icon: Icons.search, title: '搜索Java');

    final Set<JavaInfo> list = {};
    final javas = await JavaFinder.getJavaInstallationsInfo(deepScan: true);
    //测试原有的java是否可用,重复版本会被覆盖
    list.addAll(javaOptions.javas);
    list.addAll(javas);

    javaOptions.javas = list.toList();
    config.save();

    if (list.isEmpty) {
      addNotice(
        icon: Icons.close,
        title: '搜索Java',
        content: '没有找到任何可用Java，可以尝试手动添加Java',
      );
    } else {
      addNotice(
        icon: Icons.info_outline,
        title: '搜索Java',
        content: '共找到了${list.length}个可用Java版本',
      );
    }

    searching = false;
    if (mounted) setState(() {});
  }

  void _addJava() async {
    final javaPath = await PathSelector.selectFile();
    if (javaPath == null) return;
    final version = await JavaFinder.getJavaVersion(javaPath);
    if (version == null) {
      addNotice(icon: Icons.close, title: '添加失败', content: '该文件不是Java');
      return;
    } else {
      javaOptions.javas.add(JavaInfo(path: javaPath, version: version));
      await config.save();
      addNotice(
        icon: Icons.check,
        title: '添加成功',
        content: '添加成功Java $version\n (路径 $javaPath) ',
      );
      if (mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _getRam();
    final size = launchOptions.customWindowSize;
    widthController = TextEditingController(text: '${size.width}')
      ..addListener(() => setState(() {}));
    heightController = TextEditingController(text: '${size.height}')
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _getMemoryTimer.cancel();
    widthController.dispose();
    heightController.dispose();
    super.dispose();
  }

  Widget _buildDefaultVersionIsolationSettingBar() {
    final theme = Theme.of(context);
    return CheckboxSettingBar(
      title: '游戏默认隔离设置',
      options: [
        ReboundCheckbox(
          value: versionIsolationSet.isEmpty,
          label: '无隔离',
          onChange: (value) {
            setState(() {
              if (value) {
                launchOptions.versionIsolationSet.clear();
              } else {
                launchOptions.versionIsolationSet.addAll(
                  VersionIsolation.values,
                );
              }
              config.save();
            });
          },
        ),
        SizedBox(
          width: 1,
          height: 16,
          child: ColoredBox(color: theme.colorScheme.secondary),
        ),
        ReboundCheckbox(
          value: versionIsolationSet.contains(VersionIsolation.be),
          label: '测试版',
          onChange: (value) {
            setState(() {
              if (value) {
                launchOptions.versionIsolationSet.add(VersionIsolation.be);
              } else {
                launchOptions.versionIsolationSet.remove(VersionIsolation.be);
              }
              config.save();
            });
          },
        ),
        ReboundCheckbox(
          value: launchOptions.versionIsolationSet.contains(
            VersionIsolation.mindustry,
          ),
          label: '正式版',
          onChange: (value) {
            setState(() {
              if (value) {
                launchOptions.versionIsolationSet.add(
                  VersionIsolation.mindustry,
                );
              } else {
                launchOptions.versionIsolationSet.remove(
                  VersionIsolation.mindustry,
                );
              }
              config.save();
            });
          },
        ),
        ReboundCheckbox(
          value: launchOptions.versionIsolationSet.contains(
            VersionIsolation.copper,
          ),
          label: 'Copper',
          onChange: (value) {
            setState(() {
              if (value) {
                launchOptions.versionIsolationSet.add(VersionIsolation.copper);
              } else {
                launchOptions.versionIsolationSet.remove(
                  VersionIsolation.copper,
                );
              }
              config.save();
            });
          },
        ),
      ],
    );
  }

  var animating = false;

  Widget _buildGameWindowSizeSettingBar() {
    Widget buildCustomWinSizeSetting() {
      if (gameWindowSizeSet != GameWindowSizeSet.custom) {
        return SizedBox();
      }
      final width = int.tryParse(widthController.text) ?? 0;
      final height = int.tryParse(heightController.text) ?? 0;
      final size = customWindowSize;
      final showB = width != size.width || height != size.height;

      Widget buildButton() {
        final Widget child;
        if (!animating && !showB) {
          child = SizedBox();
        } else {
          animating = true;
          child = Row(
            spacing: 8,
            children: [
              SizedBox(width: 8),
              ReboundIconButton(
                icon: Icons.check,
                margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                content: '保存',
                onTap: () {
                  setState(() {
                    if (width <= 320 || height <= 160) {
                      return; //todo 窗口过小警告
                    }
                    final winSize = WindowSize(width, height);
                    launchOptions.customWindowSize = winSize;
                    config.save();
                  });
                },
              ),
              ReboundIconButton(
                icon: Icons.close,
                margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                content: '取消',
                onTap: () {
                  setState(() {
                    widthController.text = size.width.toString();
                    heightController.text = size.height.toString();
                  });
                },
              ),
            ],
          );
        }
        return AnimatedOpacity(
          opacity: showB ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          onEnd: () => setState(() => animating = false),
          child: AnimatedScale(
            scale: showB ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 300),
            curve: Curves.ease,
            child: child,
          ),
        );
      }

      return Column(
        children: [
          SizedBox(height: 8),
          Row(
            children: [
              SizedBox(width: 150, child: Text('自定义窗口大小')),
              Expanded(
                child: Row(
                  spacing: 4,
                  children: [
                    Expanded(
                      child: OutlinedTextField(
                        controller: widthController,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(5),
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    Icon(
                      Icons.close,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    Expanded(
                      child: OutlinedTextField(
                        controller: heightController,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(5),
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.ease,
                child: buildButton(),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        OptionSettingBar<GameWindowSizeSet>(
          title: '游戏窗口大小',
          initialValue: gameWindowSizeSet,
          onSelect: (value) {
            setState(() {
              launchOptions.gameWindowSizeSet = value;
              config.save();
            });
          },
          options: [
            DropdownOption<GameWindowSizeSet>(
              value: GameWindowSizeSet.gameDefault,
              label: '游戏默认',
            ),
            DropdownOption<GameWindowSizeSet>(
              value: GameWindowSizeSet.maximize,
              label: '最大化',
            ),
            DropdownOption<GameWindowSizeSet>(
              value: GameWindowSizeSet.fullScreen,
              label: '全屏',
            ),
            DropdownOption<GameWindowSizeSet>(
              value: GameWindowSizeSet.custom,
              label: '自定义',
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.ease,
          alignment: Alignment.topCenter,
          child: buildCustomWinSizeSetting(),
        ),
      ],
    );
  }

  Widget _buildJavaSettingBar() {
    final list = [];

    final js =
        javas.toList()..sort((a, b) {
          if (a.version == null || b.version == null) return 0;
          return (b.version ?? 0) - (a.version ?? 0);
        });

    for (var it in js) {
      if (!it.isValid) continue;

      final label = it.version == null ? '未知版本' : 'Java ${it.version}';

      list.add(
        DropdownOption<String>(
          value: it.path,
          label: '$label ( "${it.path}" )',
        ),
      );
    }

    return Column(
      spacing: 8,
      children: [
        OptionSettingBar<String>(
          title: '游戏Java',
          initialValue: javaSelect,
          onSelect: (value) {
            setState(() {
              launchOptions.javaOptions.selectedJava = value;
              config.save();
            });
          },
          options: [
            DropdownOption<String>(value: 'auto', label: '自动选择合适的Java'),
            ...list,
          ],
        ),

        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: 16,
          children: [
            if (javaOptions.javas.isEmpty)
              ReboundIconButton(
                icon: LineIcons.java,
                content: '下载Java',
                onTap: () {},
              ),
            ReboundIconButton(
              icon: Icons.folder_copy_outlined,
              content: '手动添加',
              onTap: _addJava,
            ),
            ReboundIconButton(
              icon: Icons.search,
              content: '自动搜索',
              onTap: _searchJava,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAutoMemorySettingBar() {
    return SwitchSettingBar(
      title: '内存自动分配',
      value: autoMemory,
      onChanged: (value) {
        setState(() {
          launchOptions.autoMemory = value;
          config.save();
        });
      },
    );
  }

  Widget _buildMemorySettingBar() {
    var divisions =
        memoryRankList.indexWhere((element) => element >= totalMemory.inGB) - 1;

    if (divisions < 0) divisions = memoryRankList.length;

    final memoryRank = memoryRankList.indexWhere(
      (element) => element >= memory.inGB,
    );

    final memoryValue = memoryRank / divisions;

    return SliderSettingBar(
      title: '内存 ${(memory.inGB).toStringAsFixed(1)}GB',
      label: '${(memory.inGB).toStringAsFixed(1)}GB',
      divisions: divisions,
      onChanged: (value) {
        setState(() {
          final rank = (value * divisions).round();
          launchOptions.memory = Memory(
            bytes: (memoryRankList[rank] * gb).toInt(),
          );
          config.save();
        });
      },
      value: memoryValue,
    );
  }

  Widget _buildMemoryInfo() {
    final free = _formatRam(freeMemory.inGB);
    final total = _formatRam(totalMemory.inGB);
    final used = _formatRam((totalMemory - freeMemory).inGB);
    final allocation = _formatRam(memory.inGB);
    final occupy = ((1 - freeMemory.bytes / totalMemory.bytes) * 100)
        .toStringAsFixed(1);

    return Column(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PercentBar(
          total: totalMemory.bytes.toDouble(),
          dataList: [
            PercentBarData(value: (totalMemory - freeMemory).bytes.toDouble()),
            PercentBarData(
              value: min(memory.bytes.toDouble(), freeMemory.bytes.toDouble()),
            ),
          ],
        ),

        Row(
          children: [
            Text('当前占用  $used / $total GB ($occupy%)'),
            Expanded(child: SizedBox()),
            AnimatedOpacity(
              opacity: memory > freeMemory ? 1 : 0,
              curve: Curves.ease,
              duration: const Duration(milliseconds: 200),
              child: Text('( 当前可用内存仅 $free GB )'),
            ),
          ],
        ),
        Text('将为游戏分配   $allocation GB '),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return ListContentPanel(
      items: [
        ContentPanelModule(
          title: '启动选项',
          child: Column(
            spacing: 8,
            children: [
              _buildDefaultVersionIsolationSettingBar(),

              if (isDesktop) _buildGameWindowSizeSettingBar(),

              _buildJavaSettingBar(),
              //if (gameWindowSizeSet == GameWindowSizeSet.custom)
            ],
          ),
        ),
        ContentPanelModule(
          title: '游戏内存',
          child: Column(
            spacing: 8,
            children: [
              _buildAutoMemorySettingBar(),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.fastOutSlowIn,
                alignment: Alignment.topCenter,
                child: autoMemory ? SizedBox() : _buildMemorySettingBar(),
              ),
              _buildMemoryInfo(),
            ],
          ),
        ),
        ContentPanelModule(
          title: '高级选项',
          child: Column(
            spacing: 8,
            children: [
              SwitchSettingBar(
                title: '使用高性能显卡',
                value: useGoodGPU,
                onChanged: (value) {
                  setState(() {
                    launchOptions.javaOptions.useBetterGPU = value;
                    config.save();
                  });
                },
              ),
              InputSettingBar(title: 'jvm虚拟机参数'),
            ],
          ),
        ),
        SizedBox(height: 8),
        if (config.versionOptions.selectedVersion != null)
          ReboundButton(
            margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            borderRadius: BorderRadius.circular(16),
            pressedScale: 0.9,
            elevation: 2,
            hoverElevation: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Icon(Icons.swap_vert, size: 48),
                Text(
                  '转到单独版本设置',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
              ],
            ),
            onTap: () {
              _routeToVersionSetting();
            },
          ),
        SizedBox(height: 8),
      ],
    );
  }
}
