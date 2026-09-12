import 'package:copper_launcher/core/app_config.dart';

import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/feature/images.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/app_theme.dart';

import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/vars.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:copper_launcher/util/launcher_tray.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

class LauncherSettingPage extends StatefulWidget {
  const LauncherSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _LauncherSettingPageState();
}

class _LauncherSettingPageState extends State<LauncherSettingPage> {
  PersonalizationOptions get personalizationOptions =>
      config.setting.personalizationOptions;

  ThemeMode get themeMode => personalizationOptions.themeMode;
  ThemeColor get themeColor => personalizationOptions.themeColor;

  void _setPostLaunchBehavior(LauncherPostLaunchBehavior behavior) {
    setState(() {
      personalizationOptions.launcherPostLaunchBehavior = behavior;
    });
    config.save();
    //实时应用托盘模式（创建/销毁托盘、开关「关闭进托盘」）
    LauncherTray.instance.applyMode();
  }

  Widget _buildPostLaunchOption({
    required bool selected,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Expanded(
      child: ReboundContainer(
        pressedScale: 0.95,
        borderRadius: BorderRadius.circular(12),
        backgroundColor: selected ? colors.interactive.withAlpha(40) : null,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: selected ? colors.interactive : colors.itemSecondary,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: selected ? colors.interactive : colors.itemPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostLaunchModule() {
    final behavior = personalizationOptions.launcherPostLaunchBehavior;
    final isTray = behavior == LauncherPostLaunchBehavior.tray;
    return ContentPanelModule(
      title: '游戏启动后',
      child: Column(
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              _buildPostLaunchOption(
                selected: !isTray,
                label: '无行为',
                icon: Icons.do_not_disturb_on_outlined,
                onTap: () =>
                    _setPostLaunchBehavior(LauncherPostLaunchBehavior.none),
              ),
              _buildPostLaunchOption(
                selected: isTray,
                label: '系统托盘',
                icon: Icons.minimize_outlined,
                onTap: () =>
                    _setPostLaunchBehavior(LauncherPostLaunchBehavior.tray),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.ease,
            alignment: Alignment.topCenter,
            child: isTray
                ? SwitchSettingBar(
                    title: '游戏退出后恢复窗口',
                    value: personalizationOptions.restoreWindowOnGameExit,
                    onChanged: (value) {
                      setState(() {
                        personalizationOptions.restoreWindowOnGameExit = value;
                      });
                      config.save();
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeColorOptions() {
    final style = Theme.of(context).textTheme.bodyLarge;
    return Row(
      children: [
        Expanded(
          flex: 10,
          child: _ThemeOptionWidget<ThemeColor>(
            spacing: 4,
            padding: const EdgeInsets.all(8),
            selected: themeColor == .copper,
            mode: .copper,
            onTap: () => setState(() => themeSwitchTo(themeMode, .copper)),
            icon: Image.asset(Images.copper, height: 24),
            label: '黄铜',
            style: style,
          ),
        ),
        Expanded(child: SizedBox()),
        Expanded(
          flex: 10,
          child: _ThemeOptionWidget<ThemeColor>(
            spacing: 4,
            padding: const EdgeInsets.all(8),
            selected: themeColor == .titanium,
            mode: .titanium,
            onTap: () => setState(() => themeSwitchTo(themeMode, .titanium)),
            icon: Image.asset(Images.titanium, height: 24),
            label: '钛蓝',
            style: style,
          ),
        ),
        Expanded(child: SizedBox()),
        Expanded(
          flex: 10,
          child: _ThemeOptionWidget<ThemeColor>(
            spacing: 4,
            padding: const EdgeInsets.all(8),
            selected: themeColor == .thorium,
            mode: .thorium,
            onTap: () => setState(() => themeSwitchTo(themeMode, .thorium)),
            icon: Image.asset(Images.thorium, height: 24),
            label: '钍粉',
            style: style,
          ),
        ),
        Expanded(child: SizedBox()),
        Expanded(
          flex: 10,
          child: _ThemeOptionWidget<ThemeColor>(
            spacing: 4,
            padding: const EdgeInsets.all(8),
            selected: themeColor == .plastanium,
            mode: .plastanium,
            onTap: () => setState(() => themeSwitchTo(themeMode, .plastanium)),
            icon: Image.asset(Images.plastanium, height: 24),
            label: '塑钢绿',
            style: style,
          ),
        ),
      ],
    );
  }

  Widget _buildThemeModeOptions() {
    return Row(
      children: [
        Expanded(
          flex: 10,
          child: _ThemeOptionWidget(
            spacing: 8,
            padding: const EdgeInsets.all(20),
            selected: themeMode == .dark,
            mode: ThemeMode.dark,
            onTap: () => setState(() => themeSwitchTo(.dark, themeColor)),
            icon: Icon(Icons.dark_mode),
            label: '深色模式',
          ),
        ),
        Expanded(child: SizedBox()),
        Expanded(
          flex: 10,
          child: _ThemeOptionWidget(
            spacing: 8,
            padding: const EdgeInsets.all(20),
            selected: themeMode == .system,
            mode: ThemeMode.system,
            onTap: () => setState(() => themeSwitchTo(.system, themeColor)),
            icon: Icon(Symbols.routine),
            label: '跟随系统',
          ),
        ),
        Expanded(child: SizedBox()),
        Expanded(
          flex: 10,
          child: _ThemeOptionWidget(
            spacing: 8,
            padding: const EdgeInsets.all(20),
            selected: themeMode == .light,
            mode: ThemeMode.light,
            onTap: () => setState(() => themeSwitchTo(.light, themeColor)),
            icon: Icon(Icons.light_mode),
            label: '浅色模式',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        if (isDesktop) _buildPostLaunchModule(),
        ContentPanelModule(
          title: '主题',
          child: Column(
            spacing: 8,
            children: [
              _buildThemeColorOptions(),
              Divider(indent: 40, endIndent: 40),
              _buildThemeModeOptions(),
              if (kDebugMode)
                SwitchSettingBar(
                  title: '特殊主题',
                  value: false,
                  onChanged: (_) {},
                ),
            ],
          ),
        ),
        if (kDebugMode)
          ContentPanelModule(
            title: '背景',
            child: Column(children: [Text('todo背景图片预设与自定义'), Text('背景图片不透明度')]),
          ),
        if (kDebugMode)
          ContentPanelModule(
            title: '布局',
            child: Column(children: [Text('todo 软件UI显示'), Text('主页小工具布局设置')]),
          ),
      ],
    );
  }
}

class _ThemeOptionWidget<T> extends StatefulWidget {
  const _ThemeOptionWidget({
    required this.selected,
    required this.mode,
    required this.onTap,
    required this.icon,
    required this.label,
    required this.padding,
    required this.spacing,
    this.style,
  });

  final bool selected;
  final T mode;
  final VoidCallback onTap;
  final Widget icon;
  final double spacing;
  final String label;
  final EdgeInsets padding;
  final TextStyle? style;

  @override
  State<StatefulWidget> createState() => _ThemeOptionWidgetState();
}

class _ThemeOptionWidgetState extends State<_ThemeOptionWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: animationDuration);
    if (widget.selected) controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant _ThemeOptionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    final style = widget.style ?? theme.textTheme.headlineMedium;

    Widget child;

    final backgroundColorA = ColorTween(
      begin: colors.interactive.withAlpha(0),
      end: colors.interactive.withAlpha(40),
    ).animate(controller);
    final itemColorA = ColorTween(
      begin: colors.itemPrimary,
      end: colors.interactive,
    ).animate(controller);

    child = AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        return ReboundContainer(
          pressedScale: 0.95,
          backgroundColor: backgroundColorA.value,
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.all(0),
          onTap: widget.onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Padding(
              padding: widget.padding,
              child: Column(
                children: [
                  IconTheme(
                    data: IconTheme.of(
                      context,
                    ).copyWith(size: 32, color: itemColorA.value),
                    child: widget.icon,
                  ),
                  SizedBox(height: widget.spacing),
                  Text(
                    widget.label,
                    style: style?.copyWith(color: itemColorA.value),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return child;
  }
}
