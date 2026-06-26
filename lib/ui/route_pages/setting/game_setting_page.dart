import 'dart:io';

import 'package:copperlauncher_main/ui/components/rebound/rebound_checkbox.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:copperlauncher_main/ui/util/widget/setting_bar/switch_setting_bar.dart';
import 'package:flutter/material.dart';

import '../../../core/app_config.dart';
import '../../../data/mindustry_settings.dart';
import '../../util/framework/content_panel.dart';

class GameSettingPage extends StatefulWidget {
  const GameSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _GameSettingPageState();
}

class _GameSettingPageState extends State<GameSettingPage> {
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
