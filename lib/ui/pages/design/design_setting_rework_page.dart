import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';
import 'template_widgets.dart';

const designSettingReworkPageRouteKey = '/design/example/setting';

/// 设计规范 · 实例页 · 设置页重做
///
/// 素材是 `ui/pages/overview/version_setting.dart` 的「设置」分项（启动选项 / 游戏内存 /
/// 高级选项）：原实现仍在原位跑，这一页**用参考模版的皮肤把同样的内容重做一遍**，
/// 用来对比同一批设置的观感
class DesignSettingReworkPage extends StatefulWidget {
  const DesignSettingReworkPage({super.key});

  @override
  State<DesignSettingReworkPage> createState() =>
      _DesignSettingReworkPageState();
}

class _DesignSettingReworkPageState extends State<DesignSettingReworkPage> {
  double _hue = TemplateHues.copper;

  // ── 演示状态 ──
  bool _isolation = true;
  int _memoryMode = 1;
  double _memory = 0.6;
  int _gpu = 0;

  final _jvmController = TextEditingController(text: '-XX:+UseG1GC');

  TemplateSkin get _skin => TemplateSkin.of(
    hue: _hue,
    dark: Theme.of(context).brightness == Brightness.dark,
  );

  @override
  void dispose() {
    _jvmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = _skin;

    return ListContentPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.xxl,
        vertical: TemplateSpace.xl,
      ),
      items: [
        _buildHueSwitch(skin),
        _buildLaunchOptions(skin),
        _buildMemory(skin),
        _buildAdvanced(skin),
      ],
    );
  }

  Widget _buildHueSwitch(TemplateSkin skin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TemplateSpace.xl),
      child: SizedBox(
        width: 320,
        child: TemplateSegment(
          skin: skin,
          options: [for (final item in TemplateHues.named) item.name],
          value: TemplateHues.named.indexWhere((item) => item.hue == _hue),
          onTap: (index) =>
              setState(() => _hue = TemplateHues.named[index].hue),
        ),
      ),
    );
  }

  // ════════ 启动选项 ════════

  Widget _buildLaunchOptions(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '启动选项',
      padding: const EdgeInsets.all(TemplateSpace.sm),
      child: Column(
        spacing: 2,
        children: [
          TemplateSwitchRow(
            skin: skin,
            title: '游戏存档隔离',
            desc: '存档与模组放在版本目录里，与别处那份分开',
            value: _isolation,
            onTap: () => setState(() => _isolation = !_isolation),
          ),
          TemplateSelectRow(
            skin: skin,
            title: '游戏Java',
            value: 'Java 17',
            onTap: () {},
          ),
        ],
      ),
    );
  }

  // ════════ 游戏内存 ════════

  Widget _buildMemory(TemplateSkin skin) {
    // 自定义才出现滑条；其余两种是自动值
    final isCustom = _memoryMode == 2;

    return TemplateSection(
      skin: skin,
      title: '游戏内存',
      padding: const EdgeInsets.all(TemplateSpace.sm),
      child: Column(
        spacing: 2,
        children: [
          TemplateRow(
            skin: skin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.md,
              children: [
                TemplateTwoLine(skin: skin, title: '内存分配'),
                TemplateSegment(
                  skin: skin,
                  options: const ['跟随全局', '自动分配', '自定义'],
                  value: _memoryMode,
                  onTap: (index) => setState(() => _memoryMode = index),
                ),
              ],
            ),
          ),
          if (isCustom)
            TemplateSliderRow(
              skin: skin,
              title: '内存上限',
              label: '${(_memory * 12).toStringAsFixed(1)} GB',
              value: _memory,
              onChanged: (value) => setState(() => _memory = value),
            ),
          TemplateRow(
            skin: skin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.md,
              children: [
                TemplateProgressBar(skin: skin, value: 0.37, height: 8),
                Row(
                  children: [
                    Text(
                      '当前占用',
                      style: TemplateType.caption.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '12.0 / 32.0 GB（37.5%）',
                      style: TemplateType.caption.copyWith(
                        color: skin.textSecondary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      '将为游戏分配',
                      style: TemplateType.caption.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      isCustom
                          ? '${(_memory * 12).toStringAsFixed(1)} GB'
                          : '6.0 GB',
                      style: TemplateType.caption.copyWith(
                        color: skin.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════ 高级选项 ════════

  Widget _buildAdvanced(TemplateSkin skin) {
    return TemplateSection(
      skin: skin,
      title: '高级选项',
      padding: const EdgeInsets.all(TemplateSpace.sm),
      child: Column(
        spacing: 2,
        children: [
          TemplateRow(
            skin: skin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.md,
              children: [
                TemplateTwoLine(skin: skin, title: '使用高性能显卡'),
                TemplateSegment(
                  skin: skin,
                  options: const ['跟随全局', '关闭', '开启'],
                  value: _gpu,
                  onTap: (index) => setState(() => _gpu = index),
                ),
              ],
            ),
          ),
          TemplateInputRow(
            skin: skin,
            title: 'jvm虚拟机参数',
            controller: _jvmController,
            hint: '-XX:+UseG1GC',
          ),
        ],
      ),
    );
  }
}
