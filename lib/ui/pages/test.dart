import 'package:copper_launcher/ui/components/animation/reveal_grid_view.dart';
import 'package:copper_launcher/ui/components/animation/reveal_list_view.dart';
import 'package:copper_launcher/ui/components/overlay_layer/back_to_top_layer.dart';
import 'package:copper_launcher/ui/components/panel/content_list_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/scroll/list_view.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:flutter/material.dart';

/// 测试页：临时测试实例集中地。
class Test extends StatefulWidget {
  const Test({super.key});

  @override
  State<StatefulWidget> createState() => TestState();
}

class TestState extends State<Test> {
  late final ScrollController lazyController;
  late final ScrollController backToTopController;

  Widget _tile(String label) => Container(
    height: 44,
    margin: const EdgeInsets.only(bottom: 8),
    alignment: Alignment.center,
    color: Colors.primaries[label.hashCode % Colors.primaries.length].withAlpha(
      140,
    ),
    child: Text(label),
  );

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );

  @override
  void initState() {
    super.initState();
    lazyController = ScrollController();
    backToTopController = ScrollController();
  }

  @override
  void dispose() {
    lazyController.dispose();
    backToTopController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CopperSingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. RevealListView 错位入场（重进页面看动画）──
          _sectionTitle('RevealListView 错位入场（默认构造）'),
          Padding(
            padding: const EdgeInsets.only(right: 64),
            child: SizedBox(height: 220, child: _revealListEntry()),
          ),
          // ── 2. RevealGridView 生长式入场 ──
          _sectionTitle('RevealGridView 生长式入场'),
          Padding(
            padding: const EdgeInsets.only(right: 64),
            child: SizedBox(height: 220, child: _revealGrid()),
          ),
          // ── 3. BackToTopLayer 回顶 ──
          _sectionTitle('BackToTopLayer（滚超 1200 浮现回顶）'),
          Padding(
            padding: const EdgeInsets.only(right: 64),
            child: SizedBox(height: 280, child: _backToTop()),
          ),
          // ── 4. 预测滚动条（惰性模块）──
          _sectionTitle('预测滚动条（惰性模块 + 预测总长）'),
          Padding(
            padding: const EdgeInsets.only(right: 64),
            child: SizedBox(height: 380, child: _lazyPanel()),
          ),
          const SizedBox(height: 240),
        ],
      ),
    );
  }

  // ── RevealListView 错位入场 ──
  Widget _revealListEntry() {
    return RevealListView(
      items: [
        for (int i = 0; i < 12; i++)
          Container(
            height: 44,
            margin: const EdgeInsets.only(bottom: 8),
            alignment: Alignment.center,
            color: Colors.primaries[i % Colors.primaries.length].withAlpha(180),
            child: Text('入场 $i'),
          ),
      ],
      delay: 200,
      interval: 0.3,
      offset: const Offset(0, 0.3),
    );
  }

  // ── RevealGridView 生长式 ──
  Widget _revealGrid() {
    return RevealGridView(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      items: [
        for (int i = 0; i < 20; i++)
          Container(
            alignment: Alignment.center,
            color: Colors.primaries[i % Colors.primaries.length].withAlpha(160),
            child: Text('生长 $i'),
          ),
      ],
      delay: 100,
      interval: 0.15,
    );
  }

  // ── BackToTopLayer ──
  Widget _backToTop() {
    return BackToTopLayer(
      controller: backToTopController,
      child: CopperListView(
        controller: backToTopController,
        children: [
          for (int i = 0; i < 60; i++)
            Container(
              height: 44,
              margin: const EdgeInsets.only(bottom: 8),
              alignment: Alignment.center,
              color: Colors.primaries[i % Colors.primaries.length].withAlpha(
                150,
              ),
              child: Text('回顶测试 $i'),
            ),
        ],
      ),
    );
  }

  // ── 预测滚动条（惰性模块）──
  Widget _lazyPanel() {
    const double estimatedMax = 4696; // 预测总长 ≈ Σ 模块高度
    return ListContentPanel(
      controller: lazyController,
      estimatedMaxScrollExtent: estimatedMax,
      items: [
        ContentPanelModule(
          title: '小模块 A',
          child: Column(children: [for (int i = 0; i < 3; i++) _tile('A$i')]),
        ),
        ContentPanelModule(
          title: '小模块 B',
          child: Column(children: [for (int i = 0; i < 3; i++) _tile('B$i')]),
        ),
        ContentListPanelModule(
          title: '大模块（80 项）',
          children: [for (int i = 0; i < 80; i++) _tile('大$i')],
        ),
        ContentPanelModule(
          title: '小模块 C',
          child: Column(children: [for (int i = 0; i < 3; i++) _tile('C$i')]),
        ),
        ContentPanelModule(
          title: '小模块 D',
          child: Column(children: [for (int i = 0; i < 3; i++) _tile('D$i')]),
        ),
      ],
    );
  }
}
