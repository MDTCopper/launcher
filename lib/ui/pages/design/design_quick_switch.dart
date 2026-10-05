import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/app_theme.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

/// 设计审视用的悬浮开关：左下角一颗胶囊，随手切亮 / 暗、循环换主题色
///
/// 走的是与设置页同一条 [themeSwitchTo]，切完整个应用即时换；
/// 它只在设计页面挂（规范页与实例页容器）
class DesignQuickSwitch extends StatelessWidget {
  const DesignQuickSwitch({super.key});

  static const _themeLabels = <ThemeColor, String>{
    ThemeColor.copper: '铜',
    ThemeColor.titanium: '钛',
    ThemeColor.thorium: '钍',
    ThemeColor.plastanium: '塑钢',
  };

  void _toggleBrightness() {
    final setting = config.setting.personalizationOptions;
    final next = setting.themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    themeSwitchTo(next, setting.themeColor);
  }

  void _nextThemeColor() {
    final setting = config.setting.personalizationOptions;
    final all = ThemeColor.values;
    final next = all[(all.indexOf(setting.themeColor) + 1) % all.length];
    themeSwitchTo(setting.themeMode, next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final setting = config.setting.personalizationOptions;
    final isDark = setting.themeMode == ThemeMode.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.tight),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: AppRadius.panelShape,
        border: Border.all(
          color: colors.border,
          width: AppBorderWidth.hairline,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.tight,
        children: [
          HintLayer(
            hint: '切换亮 / 暗',
            preferPosition: .top,
            child: IconTextButton(
              icon: isDark ? Icons.light_mode : Icons.dark_mode,
              content: isDark ? '当前暗色' : '当前亮色',
              onTap: _toggleBrightness,
            ),
          ),
          HintLayer(
            hint: '循环换主题色',
            preferPosition: .top,
            child: IconTextButton(
              icon: Icons.palette_outlined,
              content: _themeLabels[setting.themeColor] ?? '主题色',
              onTap: _nextThemeColor,
            ),
          ),
        ],
      ),
    );
  }
}
