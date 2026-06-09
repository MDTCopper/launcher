import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:copperlauncher_main/ui/util/framework/page_skeleton.dart';
import 'package:copperlauncher_main/ui/util/info/notification.dart';
import 'package:copperlauncher_main/ui/util/widget/animated_dropdown_menu.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_text_field.dart';
import 'package:copperlauncher_main/ui/util/widget/percent_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/rebound_checkbox.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/checkbox_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/input_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/option_setting_bar.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/switch_setting_bar.dart';
import 'package:copperlauncher_main/util/format/byte_unit.dart';
import 'package:copperlauncher_main/util/io/file_reader.dart';
import 'package:copperlauncher_main/util/io/java_finder.dart';
import 'package:copperlauncher_main/util/system_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_config.dart';
import '../../data/mindustry_settings.dart';
import '../../util/format/ram_rank_list.dart';
import '../util/framework/content_panel.dart';
import '../util/framework/menu_bar.dart';
import '../util/widget/setting_bar/segment_setting_bar.dart';
import '../util/widget/setting_bar/slider_setting_bar.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingState();
}

class _SettingState extends State<SettingPage> {
  static int index = 0;

  final List<Widget> pageList = [
    LaunchSettingPage(),
    InnerSettingPage(),
    PersonalizationSettingPage(),
    OtherSettingPage(),
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return PageSkeleton(
      body: pageList[index],
      menuBar: SideMenuBar(
        items: [
          MenuItem(
            selected: index == 0,
            onTap: () {
              setState(() {
                index = 0;
              });
            },
            leading: Icon(Icons.play_arrow_outlined),
            title: Text('启动'),
          ),
          MenuItem(
            selected: index == 1,
            onTap:
                () => setState(() {
                  index = 1;
                }),
            leading: Icon(Icons.gamepad),
            title: Text('游戏内'),
          ),
          MenuItem(
            selected: index == 2,
            onTap: () {
              setState(() {
                index = 2;
              });
            },
            leading: Icon(Icons.format_paint_outlined),
            title: Text('个性化'),
          ),
          MenuItem(
            selected: index == 3,
            onTap: () {
              setState(() {
                index = 3;
              });
            },
            leading: Icon(Icons.menu),
            title: Text('其他'),
          ),
        ],
      ),
    );
  }
}

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
    final javaPath = await FileReader.selectFile();
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
            //todo 游戏内设置参数
            // DropdownOption<GameWindowSizeSet>(
            //   value: GameWindowSizeSet.fullScreen,
            //   label: '全屏',
            // ),
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

  Timer? saveTimer;
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
          saveTimer?.cancel();
          saveTimer = Timer(const Duration(seconds: 1), () {
            config.save();
          });
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

class InnerSettingPage extends StatefulWidget {
  const InnerSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _InnerSettingPageState();
}

class _InnerSettingPageState extends State<InnerSettingPage> {
  MindustrySettingsPatch get settings => config.setting.mindustrySettings;

  bool get settingsOverride => config.setting.mindustrySettingsOverride;

  // ── 缓存 ── 在 patch 字段为 null 时仍保留上次显示值
  static int _saveInterval = 60;
  static int _uiScale = 100;
  static int _fpsCap = 240;
  static int _screenShake = 4;
  static int _bloomIntensity = 6;
  static int _bloomBlur = 2;
  static int _musicVol = 100;
  static int _sfxVol = 100;
  static int _ambientVol = 100;
  static int _chatOpacity = 100;
  static int _lasersOpacity = 100;
  static int _unitLaserOpacity = 100;
  static int _bridgeOpacity = 100;
  static int _maxMagnification = 100;
  static int _minMagnification = 100;

  // ── 通用控件 ──

  Widget _buildOverrideIcon(bool value, void Function(bool)? onChange) {
    final itemColor = Theme.of(context).colorScheme.primary;
    return ReboundCheckbox(
      value: value,
      itemColor: itemColor,
      icon: Icons.settings,
      onChange: onChange,
    );
  }

  Widget _buildBoolSettingBar(
    String title,
    bool? value,
    void Function(bool?) onChanged,
  ) {
    final theme = Theme.of(context);
    final itemColor = theme.colorScheme.primary;
    return Row(
      spacing: 8,
      children: [
        Text(title),
        Expanded(child: SizedBox()),
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
                itemColor: itemColor,
                icon: Icons.close,
                value: value == false,
                onChange: (_) => onChanged(false),
              ),
              ReboundCheckbox(
                itemColor: itemColor,
                icon: Icons.check,
                value: value == true,
                onChange: (_) => onChanged(true),
              ),
              ReboundCheckbox(
                itemColor: itemColor,
                icon: Icons.settings,
                value: value == null,
                onChange: (_) => onChanged(null),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 通用整数滑块 + 覆盖切换。
  ///
  /// [cache] 为 static 变量引用，在 patch 字段为 null 时回退。
  /// [unit] 显示在标题后缀。
  Widget _buildIntSliderBar({
    required String title,
    required int max,
    required int Function() getCache,
    required void Function(int) setCache,
    required int? Function() getField,
    required void Function(int?) setField,
    String unit = '',
    int min = 0,
    int step = 1,
    String Function(int)? format,
  }) {
    final currentCache = getCache();
    final field = getField();
    if (field != null) setCache(field);

    final override = field != null;
    final displayValue = field ?? currentCache;
    final sliderValue = ((displayValue - min) / (max - min)).clamp(0.0, 1.0);
    final divisions = (max - min) ~/ step;
    final label = format != null ? format(displayValue) : '$displayValue $unit';

    return Row(
      children: [
        SizedBox(width: 160, child: Text(title)),
        SizedBox(
          width: 60,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.ease,
            switchOutCurve: Curves.ease,
            child: Text(key: ValueKey(override), override ? label : '不变'),
            transitionBuilder: (child, animation) {
              final opacity = CurvedAnimation(
                parent: animation,
                curve: Interval(0.7, 1.0),
                reverseCurve: Interval(0.7, 1.0),
              );

              return FadeTransition(
                opacity: opacity,
                child: ScaleTransition(scale: animation, child: child),
              );
            },
          ),
        ),

        Expanded(
          child: Slider(
            padding: EdgeInsets.symmetric(vertical: 8),
            value: sliderValue,
            divisions: divisions,
            min: 0.0,
            label: label,
            onChanged:
                override
                    ? (v) => setState(() {
                      final raw = v * (max - min) + min;
                      final stepped = ((raw - min) / step).round() * step + min;
                      final newVal = stepped.clamp(min, max);
                      setField(newVal);
                      setCache(newVal);
                      config.save();
                    })
                    : null,
          ),
        ),
        SizedBox(width: 8),
        _buildOverrideIcon(
          !override,
          (v) => setState(() {
            if (v) {
              setField(null);
            } else {
              setField(currentCache);
            }
            config.save();
          }),
        ),
        SizedBox(width: 5),
      ],
    );
  }

  // ── 游戏 ──

  Widget _buildSaveIntervalBar() {
    return _buildIntSliderBar(
      title: '自动保存时间',
      max: 600,
      min: 10,
      step: 10,
      getCache: () => _saveInterval,
      setCache: (v) => _saveInterval = v,
      getField: () => settings.saveInterval,
      setField: (v) => settings.saveInterval = v,
      unit: '秒',
    );
  }

  Widget _buildHintsBar() {
    return _buildBoolSettingBar('游戏提示', settings.hints, (v) {
      setState(() {
        settings.hints = v;
        config.save();
      });
    });
  }

  Widget _buildAutoTargetBar() {
    return _buildBoolSettingBar('自动瞄准（移动端）', settings.autoTarget, (v) {
      setState(() {
        settings.autoTarget = v;
        config.save();
      });
    });
  }

  Widget _buildDoubleTapMineBar() {
    return _buildBoolSettingBar('双击采矿', settings.doubleTapMine, (v) {
      setState(() {
        settings.doubleTapMine = v;
        config.save();
      });
    });
  }

  Widget _buildDistinctControlGroupsBar() {
    return _buildBoolSettingBar('每单位限制一个编队', settings.distinctControlGroups, (
      v,
    ) {
      setState(() {
        settings.distinctControlGroups = v;
        config.save();
      });
    });
  }

  Widget _buildCommandModeHoldBar() {
    return _buildBoolSettingBar('长按保持指挥模式', settings.commandModeHold, (v) {
      setState(() {
        settings.commandModeHold = v;
        config.save();
      });
    });
  }

  Widget _buildBlockReplaceBar() {
    return _buildBoolSettingBar('自动选择合适的建筑', settings.blockReplace, (v) {
      setState(() {
        settings.blockReplace = v;
        config.save();
      });
    });
  }

  Widget _buildConveyorPathfindingBar() {
    return _buildBoolSettingBar('传送带寻路', settings.conveyorPathfinding, (v) {
      setState(() {
        settings.conveyorPathfinding = v;
        config.save();
      });
    });
  }

  Widget _buildBackgroundPauseBar() {
    return _buildBoolSettingBar('后台暂停', settings.backgroundPause, (v) {
      setState(() {
        settings.backgroundPause = v;
        config.save();
      });
    });
  }

  Widget _buildBuildAutoPauseBar() {
    return _buildBoolSettingBar('建造自动暂停', settings.buildAutoPause, (v) {
      setState(() {
        settings.buildAutoPause = v;
        config.save();
      });
    });
  }

  Widget _buildCrashReportBar() {
    return _buildBoolSettingBar('发送崩溃报告', settings.crashReport, (v) {
      setState(() {
        settings.crashReport = v;
        config.save();
      });
    });
  }

  Widget _buildLogicHintsBar() {
    return _buildBoolSettingBar('逻辑处理器提示', settings.logicHints, (v) {
      setState(() {
        settings.logicHints = v;
        config.save();
      });
    });
  }

  // ── 图像 ──

  //todo 新版本：ui内边距

  Widget _buildUiScaleBar() {
    return _buildIntSliderBar(
      title: '界面缩放比例',
      max: 300,
      min: 25,
      step: 5,
      format: (v) => '$v%',
      getCache: () => _uiScale,
      setCache: (v) => _uiScale = v,
      getField: () => settings.uiScale,
      setField: (v) => settings.uiScale = v,
      unit: '%',
    );
  }

  Widget _buildFpsCapBar() {
    return _buildIntSliderBar(
      title: '最大帧数',
      max: 245,
      min: 10,
      step: 5,
      format: (v) => v >= 245 ? '无限制' : '$v fps',
      getCache: () => _fpsCap,
      setCache: (v) => _fpsCap = v,
      getField: () => settings.fpsCap,
      setField: (v) => settings.fpsCap = v,
      unit: 'fps',
    );
  }

  Widget _buildScreenShakeBar() {
    return _buildIntSliderBar(
      title: '屏幕抖动',
      max: 8,
      format: (v) => '${(v / 4).toStringAsFixed(2)}x',
      getCache: () => _screenShake,
      setCache: (v) => _screenShake = v,
      getField: () => settings.screenShake,
      setField: (v) => settings.screenShake = v,
    );
  }

  Widget _buildBloomIntensityBar() {
    return _buildIntSliderBar(
      title: '光效强度',
      max: 16,
      format: (v) => '${(v * 100 ~/ 4)}%',
      getCache: () => _bloomIntensity,
      setCache: (v) => _bloomIntensity = v,
      getField: () => settings.bloomIntensity,
      setField: (v) => settings.bloomIntensity = v,
    );
  }

  Widget _buildBloomBlurBar() {
    return _buildIntSliderBar(
      title: '光效模糊',
      max: 16,
      min: 1,
      format: (v) => '${v}x',
      getCache: () => _bloomBlur,
      setCache: (v) => _bloomBlur = v,
      getField: () => settings.bloomBlur,
      setField: (v) => settings.bloomBlur = v,
    );
  }

  Widget _buildVsyncBar() {
    return _buildBoolSettingBar('垂直同步', settings.vsync, (v) {
      setState(() {
        settings.vsync = v;
        config.save();
      });
    });
  }

  Widget _buildBloomBar() {
    return _buildBoolSettingBar('光效', settings.bloom, (v) {
      setState(() {
        settings.bloom = v;
        config.save();
      });
    });
  }

  Widget _buildEffectsBar() {
    return _buildBoolSettingBar('建筑特效', settings.effects, (v) {
      setState(() {
        settings.effects = v;
        config.save();
      });
    });
  }

  Widget _buildAtmosphereBar() {
    return _buildBoolSettingBar('显示行星大气层', settings.atmosphere, (v) {
      setState(() {
        settings.atmosphere = v;
        config.save();
      });
    });
  }

  Widget _buildDrawLightBar() {
    return _buildBoolSettingBar('绘制阴影/光照', settings.drawLight, (v) {
      setState(() {
        settings.drawLight = v;
        config.save();
      });
    });
  }

  Widget _buildDestroyedBlocksBar() {
    return _buildBoolSettingBar('显示已摧毁的建筑', settings.destroyedBlocks, (v) {
      setState(() {
        settings.destroyedBlocks = v;
        config.save();
      });
    });
  }

  Widget _buildSmoothCameraBar() {
    return _buildBoolSettingBar('平滑镜头', settings.smoothCamera, (v) {
      setState(() {
        settings.smoothCamera = v;
        config.save();
      });
    });
  }

  Widget _buildMinimapBar() {
    return _buildBoolSettingBar('显示小地图', settings.minimap, (v) {
      setState(() {
        settings.minimap = v;
        config.save();
      });
    });
  }

  Widget _buildAnimatedWaterBar() {
    return _buildBoolSettingBar('动态液体', settings.animatedWater, (v) {
      setState(() {
        settings.animatedWater = v;
        config.save();
      });
    });
  }

  Widget _buildAnimatedShieldsBar() {
    return _buildBoolSettingBar('动态力场', settings.animatedShields, (v) {
      setState(() {
        settings.animatedShields = v;
        config.save();
      });
    });
  }

  Widget _buildPixelateBar() {
    return _buildBoolSettingBar('像素画面', settings.pixelate, (v) {
      setState(() {
        settings.pixelate = v;
        config.save();
      });
    });
  }

  Widget _buildLinearBar() {
    return _buildBoolSettingBar('抗锯齿', settings.linear, (v) {
      setState(() {
        settings.linear = v;
        config.save();
      });
    });
  }

  Widget _buildPlayerIndicatorsBar() {
    return _buildBoolSettingBar('玩家指示器', settings.playerIndicators, (v) {
      setState(() {
        settings.playerIndicators = v;
        config.save();
      });
    });
  }

  Widget _buildShowWeatherBar() {
    return _buildBoolSettingBar('显示天气效果', settings.showWeather, (v) {
      setState(() {
        settings.showWeather = v;
        config.save();
      });
    });
  }

  Widget _buildPlayerChatBar() {
    return _buildBoolSettingBar('显示玩家聊天气泡', settings.playerChat, (v) {
      setState(() {
        settings.playerChat = v;
        config.save();
      });
    });
  }

  Widget _buildCoreItemsBar() {
    return _buildBoolSettingBar('显示核心物资', settings.coreItems, (v) {
      setState(() {
        settings.coreItems = v;
        config.save();
      });
    });
  }

  Widget _buildBlockStatusBar() {
    return _buildBoolSettingBar('显示建筑状态', settings.blockStatus, (v) {
      setState(() {
        settings.blockStatus = v;
        config.save();
      });
    });
  }

  Widget _buildIndicatorsBar() {
    return _buildBoolSettingBar('显示标记', settings.indicators, (v) {
      setState(() {
        settings.indicators = v;
        config.save();
      });
    });
  }

  Widget _buildPositionBar() {
    return _buildBoolSettingBar('显示玩家坐标', settings.position, (v) {
      setState(() {
        settings.position = v;
        config.save();
      });
    });
  }

  Widget _buildMousePositionBar() {
    return _buildBoolSettingBar('显示鼠标坐标', settings.mousePosition, (v) {
      setState(() {
        settings.mousePosition = v;
        config.save();
      });
    });
  }

  Widget _buildFpsCounterBar() {
    return _buildBoolSettingBar('显示帧数和网络延迟', settings.fps, (v) {
      setState(() {
        settings.fps = v;
        config.save();
      });
    });
  }

  Widget _buildDetachCameraBar() {
    return _buildBoolSettingBar('自由视角', settings.detachCamera, (v) {
      setState(() {
        settings.detachCamera = v;
        config.save();
      });
    });
  }

  Widget _buildSkipCoreAnimationBar() {
    return _buildBoolSettingBar('跳过核心发射/着陆动画', settings.skipCoreAnimation, (v) {
      setState(() {
        settings.skipCoreAnimation = v;
        config.save();
      });
    });
  }

  Widget _buildHideDisplaysBar() {
    return _buildBoolSettingBar('不显示逻辑绘图', settings.hideDisplays, (v) {
      setState(() {
        settings.hideDisplays = v;
        config.save();
      });
    });
  }

  Widget _buildMacNotchBar() {
    return _buildBoolSettingBar('Mac 刘海屏适配', settings.macNotch, (v) {
      setState(() {
        settings.macNotch = v;
        config.save();
      });
    });
  }

  // ── 不透明度 ──

  Widget _buildChatOpacityBar() {
    return _buildIntSliderBar(
      title: '聊天界面不透明度',
      max: 100,
      step: 5,
      format: (v) => '$v%',
      getCache: () => _chatOpacity,
      setCache: (v) => _chatOpacity = v,
      getField: () => settings.chatOpacity,
      setField: (v) => settings.chatOpacity = v,
    );
  }

  Widget _buildLasersOpacityBar() {
    return _buildIntSliderBar(
      title: '电力连接线不透明度',
      max: 100,
      step: 5,
      format: (v) => '$v%',
      getCache: () => _lasersOpacity,
      setCache: (v) => _lasersOpacity = v,
      getField: () => settings.lasersOpacity,
      setField: (v) => settings.lasersOpacity = v,
    );
  }

  Widget _buildUnitLaserOpacityBar() {
    return _buildIntSliderBar(
      title: '单位采矿光束不透明度',
      max: 100,
      step: 5,
      format: (v) => '$v%',
      getCache: () => _unitLaserOpacity,
      setCache: (v) => _unitLaserOpacity = v,
      getField: () => settings.unitLaserOpacity,
      setField: (v) => settings.unitLaserOpacity = v,
    );
  }

  Widget _buildBridgeOpacityBar() {
    return _buildIntSliderBar(
      title: '桥梁不透明度',
      max: 100,
      step: 5,
      format: (v) => '$v%',
      getCache: () => _bridgeOpacity,
      setCache: (v) => _bridgeOpacity = v,
      getField: () => settings.bridgeOpacity,
      setField: (v) => settings.bridgeOpacity = v,
    );
  }

  // ── 缩放 ──

  Widget _buildMaxMagnificationBar() {
    return _buildIntSliderBar(
      title: '最小视距（最大缩放）',
      max: 200,
      min: 100,
      step: 25,
      format: (v) => '$v%',
      getCache: () => _maxMagnification,
      setCache: (v) => _maxMagnification = v,
      getField: () => settings.maxMagnificationMultiplierPercent,
      setField: (v) => settings.maxMagnificationMultiplierPercent = v,
    );
  }

  Widget _buildMinMagnificationBar() {
    return _buildIntSliderBar(
      title: '最大视距（最小缩放）',
      max: 300,
      min: 100,
      step: 25,
      format: (v) => '$v%',
      getCache: () => _minMagnification,
      setCache: (v) => _minMagnification = v,
      getField: () => settings.minMagnificationMultiplierPercent,
      setField: (v) => settings.minMagnificationMultiplierPercent = v,
    );
  }

  // ── 音频 ──

  Widget _buildMusicVolBar() {
    return _buildIntSliderBar(
      title: '音乐音量',
      max: 100,
      getCache: () => _musicVol,
      setCache: (v) => _musicVol = v,
      getField: () => settings.musicVol,
      setField: (v) => settings.musicVol = v,
      unit: '%',
    );
  }

  Widget _buildSfxVolBar() {
    return _buildIntSliderBar(
      title: '音效音量',
      max: 100,
      getCache: () => _sfxVol,
      setCache: (v) => _sfxVol = v,
      getField: () => settings.sfxVol,
      setField: (v) => settings.sfxVol = v,
      unit: '%',
    );
  }

  Widget _buildAmbientVolBar() {
    return _buildIntSliderBar(
      title: '环境音量',
      max: 100,
      getCache: () => _ambientVol,
      setCache: (v) => _ambientVol = v,
      getField: () => settings.ambientVol,
      setField: (v) => settings.ambientVol = v,
      unit: '%',
    );
  }

  Widget _buildAlwaysMusicBar() {
    return _buildBoolSettingBar('始终播放音乐', settings.alwaysMusic, (v) {
      setState(() {
        settings.alwaysMusic = v;
        config.save();
      });
    });
  }

  // ── 系统 ──

  Widget _buildLocaleBar() {
    final val = settings.locale;
    final override = val != null;

    return Row(
      spacing: 8,
      children: [
        Text('语言'),
        Expanded(child: SizedBox()),
        DropdownButton<String>(
          value: val ?? 'default',
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'default', child: Text('游戏默认')),
            DropdownMenuItem(value: 'zh_CN', child: Text('简体中文')),
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'ja', child: Text('日本語')),
            DropdownMenuItem(value: 'ko', child: Text('한국어')),
          ],
          onChanged:
              override
                  ? (v) => setState(() {
                    settings.locale = v;
                    config.save();
                  })
                  : null,
        ),
        SizedBox(width: 8),
        _buildOverrideIcon(
          !override,
          (v) => setState(() {
            if (v) {
              settings.locale = null;
            } else {
              settings.locale = 'default';
            }
            config.save();
          }),
        ),
        SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBlockSyncBar() {
    return _buildBoolSettingBar('方块同步', settings.blockSync, (v) {
      setState(() {
        settings.blockSync = v;
        config.save();
      });
    });
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(
          title: '覆盖',
          child: Column(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchSettingBar(
                wide: 200,
                title: '启动时覆盖游戏内部设置',
                value: settingsOverride,
                onChanged:
                    (v) => setState(() {
                      config.setting.mindustrySettingsOverride = v;
                      config.save();
                    }),
              ),
              Row(
                spacing: 8,
                children: [
                  ReboundIconButton(
                    icon: Icons.data_object,
                    content: '同步选中版本设置',
                    onTap: () {},
                  ),
                  ReboundIconButton(
                    icon: Icons.cancel_outlined,
                    content: '取消',
                    onTap: () {},
                  ),
                  Expanded(child: SizedBox()),
                  ReboundIconButton(
                    icon: Icons.refresh,
                    content: '恢复默认',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── 游戏 ──
        ContentPanelModule(
          title: '游戏',
          child: Column(
            spacing: 8,
            children: [
              _buildSaveIntervalBar(),
              if (Platform.isAndroid) _buildAutoTargetBar(),
              _buildBlockReplaceBar(),
              _buildConveyorPathfindingBar(),
              _buildHintsBar(),
              _buildLogicHintsBar(),
              _buildBackgroundPauseBar(),
              _buildBuildAutoPauseBar(),
              _buildDistinctControlGroupsBar(),
              _buildDoubleTapMineBar(),
              _buildCommandModeHoldBar(),
              _buildCrashReportBar(),
            ],
          ),
        ),

        // ── 图像 ──
        ContentPanelModule(
          title: '图像',
          child: Column(
            spacing: 8,
            children: [
              // _buildUiPaddingBar(), // TODO UI 内边距 — 暂无此设置项
              _buildUiScaleBar(),
              _buildScreenShakeBar(),
              _buildBloomIntensityBar(),
              _buildBloomBlurBar(),
              _buildFpsCapBar(),
              _buildChatOpacityBar(),
              _buildLasersOpacityBar(),
              _buildUnitLaserOpacityBar(),
              _buildBridgeOpacityBar(),
              _buildMaxMagnificationBar(),
              _buildMinMagnificationBar(),

              _buildVsyncBar(),
              _buildEffectsBar(),
              _buildAtmosphereBar(),
              _buildDrawLightBar(),
              _buildDestroyedBlocksBar(),
              _buildBlockStatusBar(),
              _buildPlayerChatBar(),
              _buildCoreItemsBar(),
              _buildMinimapBar(),
              _buildSmoothCameraBar(),
              _buildDetachCameraBar(),
              _buildPositionBar(),
              _buildMousePositionBar(),
              _buildFpsCounterBar(),
              _buildPlayerIndicatorsBar(),
              _buildIndicatorsBar(),
              // _buildOtherPlayerPlansBar(), // TODO 显示其他玩家的建筑规划 — 暂无此设置项
              // _buildEnemyIndicatorsBar(), // TODO 敌人指示器 — 暂无此设置项
              _buildShowWeatherBar(),
              _buildAnimatedWaterBar(),
              _buildAnimatedShieldsBar(),
              _buildBloomBar(),
              _buildPixelateBar(),
              _buildLinearBar(),
              _buildSkipCoreAnimationBar(),
              _buildHideDisplaysBar(),
              _buildMacNotchBar(),
            ],
          ),
        ),

        // ── 音频 ──
        ContentPanelModule(
          title: '音频',
          child: Column(
            spacing: 8,
            children: [
              _buildAlwaysMusicBar(),
              _buildMusicVolBar(),
              _buildSfxVolBar(),
              _buildAmbientVolBar(),
            ],
          ),
        ),

        // ── 系统 ──
        ContentPanelModule(
          title: '系统',
          child: Column(
            spacing: 8,
            children: [_buildLocaleBar(), _buildBlockSyncBar()],
          ),
        ),
      ],
    );
  }
}

class PersonalizationSettingPage extends StatefulWidget {
  const PersonalizationSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _PersonalizationSettingPageState();
}

class _PersonalizationSettingPageState
    extends State<PersonalizationSettingPage> {
  static Set<String> selected = {'选项1'};

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(
          title: '主题',
          child: Column(
            spacing: 8,
            children: [
              Text('todo 主题色'),
              SizedBox(height: 20),
              SegmentSettingBar<String>(
                title: '主题模式',
                segments: [
                  ReboundButtonSegment(
                    value: '选项1',
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('深色模式'),
                  ),
                  ReboundButtonSegment(
                    value: '选项2',
                    icon: Icon(Icons.settings),
                    label: Text('跟随系统'),
                  ),
                  ReboundButtonSegment(
                    value: '选项3',
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('浅色模式'),
                  ),
                ],
                //multiSelectionEnabled: true,
                onChange: (s) {
                  setState(() {
                    selected = s;
                  });
                },
                selected: selected,
              ),
              SwitchSettingBar(title: '特殊主题', value: false, onChanged: (_) {}),
            ],
          ),
        ),
        ContentPanelModule(
          title: '背景',
          child: Column(children: [Text('todo背景图片预设与自定义'), Text('背景图片不透明度')]),
        ),
        ContentPanelModule(
          title: '布局',
          child: Column(children: [Text('todo 软件UI显示'), Text('主页小工具布局设置')]),
        ),
      ],
    );
  }
}

class OtherSettingPage extends StatefulWidget {
  const OtherSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _OtherSettingPage();
}

class _OtherSettingPage extends State<OtherSettingPage> {
  static double maxDownloadSpeed = 0.5;
  static double maxThread = 8;

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        ContentPanelModule(
          title: '下载',
          child: Column(
            spacing: 8,
            children: [
              SliderSettingBar(title: '最大下载速度', value: maxDownloadSpeed),
              SliderSettingBar(
                title: '最大线程数',
                label: maxThread.toStringAsFixed(0),
                value: maxThread,
                onChanged: (value) {
                  setState(() {
                    maxThread = value;
                  });
                },
                min: 1.0,
                max: 16.0,
                divisions: 15,
              ),
              // InputSettingBar(title: '自定义系统代理'),
              InputSettingBar(title: 'github访问Token'),
              OptionSettingBar(title: '资源获取优先级', options: []),
            ],
          ),
        ),
        ContentPanelModule(
          title: '存储',
          child: Column(
            children: [Text('todo 存储'), InputSettingBar(title: '默认存储路径')],
          ),
        ),
        ContentPanelModule(
          title: 'HTTP 代理',
          child: Column(children: [Text('todo 网络代理')]),
        ),
      ],
    );
  }
}
