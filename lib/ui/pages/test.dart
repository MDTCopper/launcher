import 'dart:io';

import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/ui/components/animation/animated_expansion.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';

import 'package:copper_launcher/ui/components/button/segment_button.dart';
import 'package:copper_launcher/ui/components/rebound/copper_slider.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_switch.dart';
import 'package:copper_launcher/ui/components/setting_bar/slider_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';

import 'package:copper_launcher/ui/components/selection/drag_select_list.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';

import 'package:copper_launcher/data/net_asset.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';

import 'package:copper_launcher/ui/components/overlay_layer/popup_overlay.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:hjson_dart/hjson_dart.dart';

/// 测试页
class Test extends StatefulWidget {
  const Test({super.key});

  @override
  State<StatefulWidget> createState() => TestState();
}

class TestState extends State<Test> {
  final PopupOverlayController customController = PopupOverlayController();
  final ScrollController listController = ScrollController();

  // ── 第 11 区演示状态 ──
  int _segSelected = 1; // SegmentedReboundButton 选中值
  bool _groupExpanded = false; // AnimatedExpansion 展开日志

  // ── 第 12 区演示状态 ──
  bool _switchOn = false; // ReboundSwitch 开关
  double _sliderValue = 0.4; // CopperSlider 值(0~1 比例)

  // ── 第 13 区演示状态（DragSelectList 拖动连续选择）──
  final Set<int> _dragSelectedIndexes = {}; // 已选中的演示项下标
  bool _dragSelectEnabled = true; // 是否允许拖动连续选择
  static const List<String> _demoModNames = [
    'Copper Core',
    'Endless',
    'Factorio Mod',
    'Frozen',
    'Infinite',
    'Pac-Man',
    'Skies',
    'Zero',
  ];

  // ── 第 14 区演示状态（ModGithubMeta 临时测试）──
  // 每个 mock：github release 元数据 + 是否 java（对应 ModOfficialListMeta.hasJava）
  late final List<({ModGithubMeta meta, bool hasJava})> _mockMods = [
    (
      meta: ModGithubMeta(
        name: 'JavaMultiMod',
        tag: 'v1.2.0',
        releaseDate: '2024-01-01T00:00:00Z',
        assets: [
          GithubApiReleaseAsset(
            name: 'readme.txt',
            url:
                'https://github.com/mock/JavaMultiMod/releases/download/v1.2.0/readme.txt',
            size: 1 * 1024,
            downloadCount: 0,
          ),
          GithubApiReleaseAsset(
            name: 'JavaMultiMod-0.8.jar',
            url:
                'https://github.com/mock/JavaMultiMod/releases/download/v1.2.0/JavaMultiMod-0.8.jar',
            size: 2 * mb,
            downloadCount: 12,
          ),
          GithubApiReleaseAsset(
            name: 'JavaMultiMod-1.2.jar',
            url:
                'https://github.com/mock/JavaMultiMod/releases/download/v1.2.0/JavaMultiMod-1.2.jar',
            size: 5 * mb,
            downloadCount: 88, // 体积最大 = mod 本体，应排最前
          ),
        ],
        describe: 'java 多 jar 候选测试',
      ),
      hasJava: true,
    ),
    (
      meta: ModGithubMeta(
        name: 'ScriptMultiMod',
        tag: 'v0.3.0',
        releaseDate: '2024-02-05T00:00:00Z',
        assets: [
          GithubApiReleaseAsset(
            name: 'ScriptMultiMod-0.3.zip',
            url:
                'https://github.com/mock/ScriptMultiMod/releases/download/v0.3.0/a.zip',
            size: 1 * mb,
            downloadCount: 30,
          ),
          GithubApiReleaseAsset(
            name: 'ScriptMultiMod-0.2.zip',
            url:
                'https://github.com/mock/ScriptMultiMod/releases/download/v0.3.0/b.zip',
            size: 512 * kb,
            downloadCount: 5,
          ),
        ],
        describe: '非java 多 zip 候选测试',
      ),
      hasJava: false,
    ),
    (
      meta: ModGithubMeta(
        name: 'JavaNoAssetMod',
        tag: 'v0.9.0',
        releaseDate: '2024-03-10T00:00:00Z',
        assets: [
          GithubApiReleaseAsset(
            name: 'README.md',
            url:
                'https://github.com/mock/JavaNoAssetMod/releases/download/v0.9.0/README.md',
            size: 2 * kb,
            downloadCount: 0,
          ),
        ],
        describe: 'java 无 jar 产物 → 弹窗提示跳转 tag 源码',
      ),
      hasJava: true,
    ),
    (
      meta: ModGithubMeta(
        name: 'ScriptSingleMod',
        tag: 'v1.0.0',
        releaseDate: '2024-04-01T00:00:00Z',
        assets: [
          GithubApiReleaseAsset(
            name: 'ScriptSingleMod-1.0.zip',
            url:
                'https://github.com/mock/ScriptSingleMod/releases/download/v1.0.0/single.zip',
            size: 3 * mb,
            downloadCount: 66,
          ),
        ],
        describe: '非java 单个 zip → 只读展示',
      ),
      hasJava: false,
    ),
  ];

  /// 每个 mock 当前选中的候选下标（默认 0 = 体积最大）
  late final List<int> _mockSelectedAssetIndexes = List.filled(
    _mockMods.length,
    0,
  );

  @override
  void dispose() {
    listController.dispose();

    super.dispose();
  }

  Widget _card({
    required String title,
    required String desc,
    required Widget child,
  }) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return CopperSingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IconTextButton(icon: Icons.add, content: '666', onTap: () async {}),
          _segmentExpansionSection(),
          _switchSliderSection(),
          _dragSelectSection(),
          _modMetaSection(),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  // ════════ 11. 分段按钮 + 展开/收起容器（copper 风格翻新件） ════════
  Widget _segmentExpansionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('11. SegmentedReboundButton / AnimatedExpansion'),
        _card(
          title: 'SegmentedReboundButton（copper 双模式选中态）',
          desc: '分段按钮：点击切换选中段，选中段背景/前景有过渡动画（暗色玻璃、浅色云母片）。当前选中：$_segSelected。',
          child: SegmentedReboundButton<int>(
            selected: {_segSelected},
            segments: [
              ReboundButtonSegment(
                value: 0,
                icon: Icon(Icons.dark_mode),
                label: Text('暗色'),
              ),
              ReboundButtonSegment(
                value: 1,
                icon: Icon(Icons.auto_mode),
                label: Text('跟随系统'),
              ),
              ReboundButtonSegment(
                value: 2,
                icon: Icon(Icons.light_mode),
                label: Text('浅色'),
              ),
            ],
            onChange: (set) => setState(() => _segSelected = set.first),
          ),
        ),
        _card(
          title: 'AnimatedExpansion（基于 Flutter Expansible，收起后卸载子树）',
          desc:
              '点击标题展开/收起；收起动画完成后内容从树上移除（maintainState:false 性能改进）。最近切换日志：${_groupExpanded ? '展开' : '收起'}。',
          child: AnimatedExpansion(
            title: Text('展开一个分组（点我）'),
            onChange: () => setState(() => _groupExpanded = !_groupExpanded),
            children: [
              for (int i = 0; i < 30; i++)
                Container(
                  height: 32,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('收起后这 30 行不再参与构建 - 第 $i 项'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════ 12. copper 风格开关 / 滑条（ReboundSwitch / CopperSlider） ════════
  Widget _switchSliderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('12. ReboundSwitch / CopperSlider'),
        _card(
          title: 'ReboundSwitch(copper 风格开关)',
          desc: '轨道 + 滑块，选中/未选中平滑过渡；选中轨道变主题色。当前：${_switchOn ? '开' : '关'}。',
          child: ReboundSwitch(
            value: _switchOn,
            onChanged: (v) => setState(() {
              _switchOn = v;
            }),
          ),
        ),
        _card(
          title: 'CopperSlider(点击 / 拖动 / 刻度吸附)',
          desc:
              '轨道 + 填充 + 滑块，点击定位、拖动调整、拖拽时显示浮标；divisions 非空时吸附刻度。当前：${(_sliderValue * 100).round()}。',
          child: CopperSlider(
            value: _sliderValue,
            divisions: 10,
            label: '${(_sliderValue * 100).round()}',
            onChanged: (v) => setState(() => _sliderValue = v),
          ),
        ),
        _card(
          title: 'SwitchSettingBar / SliderSettingBar(弹性标题列)',
          desc: '标题列自适应：空间足时 150 固定宽，空间不足自动收缩 + 省略号。缩窗口即可观察。',
          child: Column(
            spacing: 12,
            children: [
              const SwitchSettingBar(title: '某个开关设置很长', value: true),
              SliderSettingBar(title: '某个滑条设置很长', value: 0.6),
            ],
          ),
        ),
        _card(
          title: '竖排方案试验：描述在上、开关在下',
          desc: '把具体控件放在描述下方（描述居左、控件右对齐独立成行），而非横排右侧。窗口缩窄时描述行仍可完整显示。',
          child: Column(
            spacing: 12,
            children: [
              // 横排对照：描述 + 右侧控件
              SwitchSettingBar(
                title: '横排对照开关',
                value: _switchOn,
                onChanged: (v) => setState(() => _switchOn = v),
              ),
              // 竖排试验：描述一行、开关下一行贴右
              Row(
                children: [
                  const Expanded(child: Text('开启某项高级功能')),
                  ReboundSwitch(
                    value: _switchOn,
                    onChanged: (v) => setState(() => _switchOn = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 竖排变体：描述 + 副说明 + 控件贴右
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('开启自动更新'),
                        Text(
                          '更新到最新版本',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        ReboundSwitch(
                          value: _switchOn,
                          onChanged: (v) => setState(() => _switchOn = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════ 13. DragSelectList 拖动连续选择 ════════
  Widget _dragSelectSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('13. DragSelectList（点击 + 拖动连续选择）'),
        _card(
          title: 'DragSelectList：点击切换选中，按住拖动连续清除/选中',
          desc:
              '点击某行切换选中；桌面/短列表按住直接拖动，移动端长按后拖动，可整段连续选中/清除'
              '（起点未选→整段选中，起点已选→整段清除）。列表放在固定高度容器内（自身可滚动）；'
              '列表可滚动时上下滑动仍滚动，长按再拖动才进入多选。可切换「允许拖动选择」对比开关效果。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              // 微调控件：拖动开关 + 选中数 + 清空
              Row(
                spacing: 12,
                children: [
                  const Text('允许拖动选择'),
                  ReboundSwitch(
                    value: _dragSelectEnabled,
                    onChanged: (v) => setState(() => _dragSelectEnabled = v),
                  ),
                  const Spacer(),
                  Text('已选 ${_dragSelectedIndexes.length} 项'),
                  ReboundMenuButton(
                    label: '清空',
                    onTap: () => setState(_dragSelectedIndexes.clear),
                  ),
                ],
              ),
              // 固定高度，给内部 SingleChildScrollView 一个有界视口；
              // 项数超高时可滚动，同时保留拖动连续选择
              SizedBox(
                height: 260,
                child: DragSelectList(
                  itemCount: _demoModNames.length,
                  dragSelect: _dragSelectEnabled,
                  itemSpacing: 4,
                  selected: _dragSelectedIndexes,
                  onToggle: (index, selected) => setState(() {
                    if (selected) {
                      _dragSelectedIndexes.add(index);
                    } else {
                      _dragSelectedIndexes.remove(index);
                    }
                  }),
                  itemBuilder: (context, index, isSelected) =>
                      _demoDragTile(index, isSelected),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 演示项：ReboundListTile 自带选中态/按压反馈，onTap 负责点击切换。
  /// 拖动连续选择的 pan 由外层 DragSelectList 处理，与条目 onTap 互不干扰。
  Widget _demoDragTile(int index, bool selected) {
    return ReboundListTile(
      itemSpacing: 10,
      leading: Icon(
        selected ? Icons.check_box : Icons.check_box_outline_blank,
        size: 20,
      ),
      title: Text(_demoModNames[index]),
      subtitle: Text(selected ? '已选中（起点已选→整段清除）' : '未选中（起点未选→整段选中）'),
      selected: selected,
      onTap: () => setState(() {
        if (selected) {
          _dragSelectedIndexes.remove(index);
        } else {
          _dragSelectedIndexes.add(index);
        }
      }),
    );
  }

  // ════════ 14. ModGithubMeta 临时测试（模拟资源候选选择逻辑） ════════
  Widget _modMetaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('14. ModGithubMeta 临时测试'),
        for (var i = 0; i < _mockMods.length; i++)
          _card(
            title:
                '${_mockMods[i].meta.name}（${_mockMods[i].hasJava ? 'java' : '非java'}）',
            desc: 'tag=${_mockMods[i].meta.tag}，${_mockMods[i].meta.describe}',
            child: _mockAssetSelection(i),
          ),
      ],
    );
  }

  /// 每个 mock 模拟下载弹窗里的资源候选展示：多个 → 下拉、单个 → 只读、无 → 提示。
  Widget _mockAssetSelection(int mockIndex) {
    final theme = Theme.of(context);
    final mock = _mockMods[mockIndex];
    final candidates = mock.meta.assetsOfType(mock.hasJava ? '.jar' : '.zip');

    if (candidates.isEmpty) {
      final hint = mock.hasJava
          ? '该版本未提供编译产物，将跳转到对应 tag 下载源码'
          : '该版本未发布编译产物，将自动下载该版本的源码';
      return Row(
        spacing: 4,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.error, size: 20),
          Expanded(
            child: Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      );
    }

    if (candidates.length == 1) {
      return Row(
        spacing: 4,
        children: [
          Icon(Icons.description_outlined, size: 18),
          Expanded(
            child: Text(
              candidates.first.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _formatSize(candidates.first.size),
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }

    // 多个候选：下拉选择，默认体积最大在前
    final value = _mockSelectedAssetIndexes[mockIndex].clamp(
      0,
      candidates.length - 1,
    );
    return Column(
      spacing: 4,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('选择要下载的文件，体积最大一般为 mod 本体', style: theme.textTheme.bodySmall),
        DropdownButton<int>(
          value: value,
          isExpanded: true,
          items: [
            for (var i = 0; i < candidates.length; i++)
              DropdownMenuItem<int>(
                value: i,
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        candidates[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _formatSize(candidates[i].size),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (v) =>
              setState(() => _mockSelectedAssetIndexes[mockIndex] = v ?? 0),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes < kb) return '$bytes B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / gb).toStringAsFixed(1)} GB';
  }
}

/// 简易菜单项按钮（本测试页专用）。
///
/// 注意：不要用 `Container(alignment: Alignment.center)`——
/// 内部会包 Align，松约束下会撑满父宽度。用 Row(mainAxisSize: min)
/// 保持自适应宽度，四角测试才能正确显示。
class ReboundMenuButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const ReboundMenuButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.interactive.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.interactive.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(label, style: TextStyle(color: colors.itemPrimary))],
        ),
      ),
    );
  }
}
