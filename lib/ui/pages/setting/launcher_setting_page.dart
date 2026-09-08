import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/app_theme.dart';
import 'package:copper_launcher/ui/components/button/segment_button.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/vars.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:copper_launcher/ui/components/setting_bar/segment_setting_bar.dart';
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
              Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: _ThemeModeOptionWidget(
                      selected: themeMode == .dark,
                      mode: ThemeMode.dark,
                      onTap: () =>
                          setState(() => themeSwitchTo(.dark, themeColor)),
                      icon: Icons.dark_mode,
                      label: '深色模式',
                    ),
                  ),
                  Expanded(child: SizedBox()),
                  Expanded(
                    flex: 10,
                    child: _ThemeModeOptionWidget(
                      selected: themeMode == .system,
                      mode: ThemeMode.system,
                      onTap: () =>
                          setState(() => themeSwitchTo(.system, themeColor)),
                      icon: Symbols.routine,
                      label: '跟随系统',
                    ),
                  ),
                  Expanded(child: SizedBox()),
                  Expanded(
                    flex: 10,
                    child: _ThemeModeOptionWidget(
                      selected: themeMode == .light,
                      mode: ThemeMode.light,
                      onTap: () =>
                          setState(() => themeSwitchTo(.light, themeColor)),
                      icon: Icons.light_mode,
                      label: '浅色模式',
                    ),
                  ),
                ],
              ),
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

class _ThemeModeOptionWidget extends StatefulWidget {
  const _ThemeModeOptionWidget({
    required this.selected,
    required this.mode,
    required this.onTap,
    required this.icon,
    required this.label,
  });

  final bool selected;
  final ThemeMode mode;
  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  State<StatefulWidget> createState() => _ThemeModeOptionWidgetState();
}

class _ThemeModeOptionWidgetState extends State<_ThemeModeOptionWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: animationDuration);
    if (widget.selected) controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant _ThemeModeOptionWidget oldWidget) {
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
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(widget.icon, size: 32, color: itemColorA.value),
                  const SizedBox(height: 8),
                  Text(
                    widget.label,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: itemColorA.value,
                    ),
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
