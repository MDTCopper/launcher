import 'package:copper_launcher/ui/components/animation/loop/drill_loading.dart';
import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;

import 'package:flutter/material.dart';

/// 测试页
class Test extends StatefulWidget {
  const Test({super.key});

  @override
  State<StatefulWidget> createState() => TestState();
}

class TestState extends State<Test> {
  // ── 第 19 区演示状态（DrillLoading 铜钻头循环）──
  DrillLoadingState _drillState = DrillLoadingState.spinning;
  int _drillCycles = 0; // onCycleFinished 计数

  // ── 第 20 区演示状态（ContextMenu 右键菜单）──
  bool _menuRelocate = true; // 同级菜单替换：同一个面板移动过去
  bool _menuMobilePosition = false; // 强制用移动端定位策略
  bool _menuPinned = true; // 菜单里那条「固定」的勾选态
  int _menuHits = 0; // 菜单动作被点的次数
  String _menuLastAction = '（还没点过菜单条目）';

  /// 当前状态在做什么，配合演示说清三种状态的差别
  String get _drillStateHint => switch (_drillState) {
    DrillLoadingState.spinning => '旋转态：不停转，每转一次闪一下灯；不出铜',
    DrillLoadingState.completing => '结束态：只转一次，转到头弹一粒铜就停住',
    DrillLoadingState.error => '错误态：只转一次，转到头后中心转红、金属泛红，停住',
  };

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
          _drillLoadingSection(),
          _contextMenuSection(),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  // ════════ 19. 铜钻头循环（DrillLoading） ════════

  void _onDrillCycle() => setState(() => _drillCycles++);

  /// 一块底色牌子，模拟真实等待场景（等待动画基本都出现在卡片/对话框里）
  Widget _buildDrillPlate({required String label, required Widget child}) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          child,
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: colors.itemPrimary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _drillLoadingSection() {
    final colors = AppColors.of(context);
    final labelStyle = TextStyle(color: colors.itemPrimary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('19. DrillLoading（铜钻头循环）'),
        _card(
          title: '线条化的 Mindustry 机械钻头：转一次、闪一下、弹一粒铜',
          desc:
              '层次是底座 → 四片钻臂 → 顶盖 → 中心亮点 → 铜粒。'
              '一个周期走一步：钻臂转到下一个 90 度 → 中心亮点闪到最亮（就是"钻到了"那一下）'
              '→ 从中心弹出一粒铜。下面四块是不停转的尺寸对照。',
          child: Wrap(
            spacing: 24,
            runSpacing: 24,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildDrillPlate(
                label: '16',
                child: const DrillLoading(size: 16),
              ),
              _buildDrillPlate(
                label: '28',
                child: const DrillLoading(size: 28),
              ),
              _buildDrillPlate(label: '56（默认）', child: const DrillLoading()),
              _buildDrillPlate(
                label: '96',
                child: const DrillLoading(size: 96),
              ),
            ],
          ),
        ),
        _card(
          title: '三种状态：旋转 / 结束 / 错误（点哪颗切哪个）',
          desc:
              '旋转态不停转、只闪灯不出铜；结束态只转一次、转到头弹一粒铜就停住；'
              '错误态只转一次、转到头后中心亮点转红、结构线条略微变红，不出铜。'
              '切状态会**等当前这一步走完**（转完那 90 度再进新状态），所以看不到半路被打断的钻头 —— '
              '可以趁它转的时候连点几下，看它是走完才切。右边那块实时记 onCycleFinished 的次数。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 24,
                runSpacing: 24,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildDrillPlate(
                    label: '三种状态共用这一块',
                    child: DrillLoading(size: 96, state: _drillState),
                  ),
                  _buildDrillPlate(
                    label: '回调已计 $_drillCycles 步',
                    child: DrillLoading(
                      size: 64,
                      state: _drillState,
                      onCycleFinished: _onDrillCycle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(_drillStateHint, style: labelStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final state in DrillLoadingState.values)
                    IconTextButton(
                      icon: switch (state) {
                        DrillLoadingState.spinning => Icons.rotate_right,
                        DrillLoadingState.completing =>
                          Icons.check_circle_outline,
                        DrillLoadingState.error => Icons.error_outline,
                      },
                      content: switch (state) {
                        DrillLoadingState.spinning => '旋转态',
                        DrillLoadingState.completing => '结束态（转一次弹铜）',
                        DrillLoadingState.error => '错误态（转一次转红）',
                      },
                      onTap: () => setState(() => _drillState = state),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════ 20. 右键菜单（ContextMenu） ════════

  void _noteMenuAction(String action) {
    setState(() {
      _menuHits++;
      _menuLastAction = action;
      if (action == '固定 / 取消固定') _menuPinned = !_menuPinned;
    });
  }

  /// 演示菜单：分组标题 / 勾选 / 分隔线 / 两级子菜单 / 禁用项 / 危险动作都有
  ///
  /// [spot] 是右键落在触发区的哪个方位，内容与条目数按它变 —— 换位置右键时
  /// 面板要既移动又换内容还得改尺寸，这一条才好看出效果
  List<ContextMenuEntry> _buildDemoMenuEntries({String spot = ''}) {
    return [
      ContextMenuHeader(spot.isEmpty ? '版本操作' : '点在$spot'),
      ContextMenuAction(
        icon: Icons.play_arrow,
        label: '启动游戏',
        onSelected: () => _noteMenuAction('启动游戏'),
      ),
      ContextMenuAction(
        icon: Icons.push_pin_outlined,
        label: _menuPinned ? '取消固定' : '固定到首页',
        checked: _menuPinned,
        onSelected: () => _noteMenuAction('固定 / 取消固定'),
      ),
      if (spot.contains('左')) ...[
        const ContextMenuDivider(),
        ContextMenuAction(
          icon: Icons.file_copy_outlined,
          label: '复制到左侧版本目录',
          onSelected: () => _noteMenuAction('复制到左侧目录'),
        ),
      ],
      if (spot.contains('下')) ...[
        const ContextMenuDivider(),
        ContextMenuAction(
          icon: Icons.history,
          label: '查看这次启动的完整日志与崩溃堆栈',
          onSelected: () => _noteMenuAction('查看完整日志'),
        ),
        ContextMenuAction(
          icon: Icons.terminal,
          label: '在终端里打开',
          onSelected: () => _noteMenuAction('在终端里打开'),
        ),
      ],
      const ContextMenuDivider(),
      // 条目可以自带颜色，不必只有普通 / 错误两档
      ContextMenuAction(
        icon: Icons.star_border,
        label: '标记为收藏',
        color: Colors.amber,
        onSelected: () => _noteMenuAction('标记为收藏'),
      ),
      ContextMenuSubmenu(
        icon: Icons.more_horiz,
        label: '更多操作',
        entries: [
          ContextMenuAction(
            icon: Icons.folder_open,
            label: '打开目录',
            onSelected: () => _noteMenuAction('打开目录'),
          ),
          ContextMenuSubmenu(
            icon: Icons.save_alt,
            label: '导出',
            entries: [
              ContextMenuAction(
                label: '导出为 PNG',
                onSelected: () => _noteMenuAction('导出为 PNG'),
              ),
              ContextMenuAction(
                label: '导出为 SVG',
                onSelected: () => _noteMenuAction('导出为 SVG'),
              ),
            ],
          ),
          const ContextMenuDivider(),
          ContextMenuAction(
            icon: Icons.delete_outline,
            label: '删除版本',
            danger: true,
            onSelected: () => _noteMenuAction('删除版本'),
          ),
        ],
      ),
      const ContextMenuAction(
        icon: Icons.block,
        label: '这条不可点',
        enabled: false,
      ),
    ];
  }

  /// 为空表示按平台取默认策略
  ContextMenuPositionDelegate? get _demoPositionDelegate =>
      _menuMobilePosition ? const ContextMenuMobilePosition() : null;

  /// 把触发区按上下左右切成四块，说出右键点在哪一块
  String _spotName(Offset local, Size size) {
    final horizontal = local.dx < size.width / 2 ? '左' : '右';
    final vertical = local.dy < size.height / 2 ? '上' : '下';
    return '$horizontal$vertical';
  }

  Widget _buildMenuTriggerArea(String hint) {
    final colors = AppColors.of(context);
    // 高度放在 LayoutBuilder 外面给：外面的 Column 高度无界，
    // 直接读 constraints.biggest 会拿到 Infinity，四分之一的判断就永远命中上半
    return SizedBox(
      height: 120,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              if ((event.buttons & kSecondaryButton) == 0) return;
              ContextMenu.show(
                context: context,
                position: event.position,
                entries: _buildDemoMenuEntries(
                  spot: _spotName(event.localPosition, size),
                ),
                relocateOnReopen: _menuRelocate,
                positionDelegate: _demoPositionDelegate,
              );
            },
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.lowBackgroundOnCard,
                borderRadius: AppRadius.itemShape,
                border: Border.all(color: colors.border),
              ),
              child: Text(hint, style: TextStyle(color: colors.itemSecondary)),
            ),
          );
        },
      ),
    );
  }

  /// 全局控制器是 Listenable，菜单开合 / 层级变化时这里会自动重建
  Widget _buildMenuStatusRow() {
    final colors = AppColors.of(context);
    return ListenableBuilder(
      listenable: ContextMenu.controller,
      builder: (context, child) {
        final depth = ContextMenu.depth;
        return Row(
          children: [
            Expanded(
              child: Text(
                depth == 0 ? '菜单已收起' : '菜单展开中：当前第 $depth 级',
                style: TextStyle(color: colors.itemSecondary),
              ),
            ),
            IconTextButton(
              icon: Icons.close,
              content: '收起',
              weight: ActionWeight.tertiary,
              onTap: depth == 0 ? null : () => ContextMenu.dismiss(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuListTile(String name) {
    final colors = AppColors.of(context);
    return ContextMenuField(
      menuBuilder: (context) => [
        ContextMenuHeader(name),
        ContextMenuAction(
          icon: Icons.play_arrow,
          label: '启动',
          onSelected: () => _noteMenuAction('启动 $name'),
        ),
        ContextMenuAction(
          icon: Icons.drive_file_rename_outline,
          label: '重命名',
          onSelected: () => _noteMenuAction('重命名 $name'),
        ),
        const ContextMenuDivider(),
        ContextMenuSubmenu(
          icon: Icons.more_horiz,
          label: '更多操作',
          entries: [
            ContextMenuAction(
              icon: Icons.copy_all,
              label: '复制版本数据',
              onSelected: () => _noteMenuAction('复制 $name 的数据'),
            ),
            ContextMenuAction(
              icon: Icons.delete_outline,
              label: '删除',
              danger: true,
              onSelected: () => _noteMenuAction('删除 $name'),
            ),
          ],
        ),
      ],
      relocateOnReopen: _menuRelocate,
      positionDelegate: _demoPositionDelegate,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.section),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: colors.lowBackgroundOnCard,
          borderRadius: AppRadius.itemShape,
          border: Border.all(color: colors.border),
        ),
        child: Text(name, style: TextStyle(color: colors.itemPrimary)),
      ),
    );
  }

  Widget _contextMenuSection() {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('20. ContextMenu（右键菜单）'),
        _card(
          title: '右键 / 长按弹出：一个全局控制器管住所有菜单实例',
          desc:
              '面板先量出自己的尺寸再定位，所以四向翻转、贴边、避让都准。'
              '桌面跟随鼠标；移动端摆在触点上方（手指和手掌都在触点下方，菜单压在下面会被挡），'
              '水平按触点在哪半屏定方向 —— 右半屏贴着触点往左铺、左半屏往右铺，上下不额外限制。'
              '子菜单点父条目展开（桌面悬停 400ms 也会展开），能一直往下挂。'
              '下面这块按上下左右切成四份，每份的条目数与文案都不一样：换位置右键时，'
              '开着「同级菜单移动过去」就是同一个面板一边滑过去一边换内容、尺寸跟着变。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionButton(
                    icon: const Icon(Icons.smartphone),
                    content: const Text('移动端定位'),
                    selected: _menuMobilePosition,
                    onTap: () => setState(
                      () => _menuMobilePosition = !_menuMobilePosition,
                    ),
                    hint: '移动端：摆在触点上方并居中，让开手指；桌面：跟随鼠标四向翻转',
                  ),
                  ActionButton(
                    icon: const Icon(Icons.open_with),
                    content: const Text('同级菜单移动过去'),
                    selected: _menuRelocate,
                    onTap: () => setState(() => _menuRelocate = !_menuRelocate),
                    hint: '开：同一个面板平移到新位置并换内容；关：旧面板原地播退场，新面板在新位置入场',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildMenuTriggerArea('在这四块里分别右键（触屏长按），看面板怎么移动与换内容'),
              const SizedBox(height: 12),
              _buildMenuStatusRow(),
              const SizedBox(height: 8),
              Text(
                '最近一次动作：$_menuLastAction（共 $_menuHits 次）',
                style: TextStyle(color: colors.itemSecondary),
              ),
              const SizedBox(height: 12),
              IconTextButton(
                icon: Icons.open_in_new,
                content: '在屏幕中间弹一个（全局 ContextMenu.show）',
                onTap: () {
                  final size = MediaQuery.sizeOf(context);
                  ContextMenu.show(
                    context: context,
                    position: Offset(size.width / 2, size.height / 2),
                    entries: _buildDemoMenuEntries(),
                    relocateOnReopen: _menuRelocate,
                    positionDelegate: _demoPositionDelegate,
                  );
                },
              ),
            ],
          ),
        ),
        _card(
          title: '列表里的用法：条目各包一层 ContextMenuField',
          desc:
              '每一条都有自己的菜单，内容按当时的页面状态算（这里带上了版本名）。'
              '右键另一条时，旧菜单要么平移过去换内容，要么原地退场、新菜单在新位置入场 —— '
              '同一个全局控制器下同时最多只有一个活跃菜单链，退场中的旧实例只为把动画播完。',
          child: Column(
            children: [
              for (final name in const ['阿尔法版本', '贝塔版本', '伽马版本'])
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.related),
                  child: _buildMenuListTile(name),
                ),
            ],
          ),
        ),
      ],
    );
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
