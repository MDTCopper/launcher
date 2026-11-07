import 'package:copper_launcher/ui/components/animation/loop/drill_loading.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu_entry.dart';
import 'package:copper_launcher/ui/pages/design/template_color.dart';
import 'package:copper_launcher/ui/pages/design/template_drawer.dart';
import 'package:copper_launcher/ui/pages/design/template_drop.dart';
import 'package:copper_launcher/ui/pages/design/template_keys.dart';
import 'package:copper_launcher/ui/pages/design/template_loading.dart';
import 'package:copper_launcher/ui/pages/design/template_markdown.dart';
import 'package:copper_launcher/ui/pages/design/template_media.dart';
import 'package:copper_launcher/ui/pages/design/template_motion.dart';
import 'package:copper_launcher/ui/pages/design/template_menu.dart';
import 'package:copper_launcher/ui/pages/design/template_overlay.dart';
import 'package:copper_launcher/ui/pages/design/template_shell.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_table.dart';
import 'package:copper_launcher/ui/pages/design/template_state.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 组件目录：一次把所有组件与它们的常见状态摆出来
///
/// 既是设计样张的来源（`test/design_render_test.dart` 渲染它），
/// 也是 App 里可以打开的「组件目录」调试页（`/template_catalog`，仅 debug 可见）
class TemplateCatalogPage extends StatefulWidget {
  const TemplateCatalogPage({super.key, required this.skin, this.onlySection});

  final TemplateSkin skin;

  /// 只渲染某一节（出单节样张 / 截图用）；null = 全量
  final String? onlySection;

  @override
  State<TemplateCatalogPage> createState() => _TemplateCatalogPageState();
}

class _TemplateCatalogPageState extends State<TemplateCatalogPage> {
  bool _switchA = true;
  bool _switchB = false;
  bool _tileSwitch = true;
  int _segment = 0;
  int _tab = 0;
  Set<String> _multi = {'Java 17'};
  int _pagerPage = 2;
  int _segmentWide = 2;
  double _slider = 0.55;
  String _java = 'Java 17';
  List<String> _hotkey = const ['Ctrl', 'Shift', 'K'];
  Set<int> _multiSeg = {0};
  Color _color = templatePresetColors[1];
  bool _dropActive = false;
  final _input = TextEditingController(text: '-XX:+UseG1GC');

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.lg,
      children: [
        _buildButtons(skin),
        _buildRows(skin),
        _buildTiles(skin),
        _buildControls(skin),
        _buildTabs(skin),
        _buildPickers(skin),
        _buildSliders(skin),
        _buildFeedback(skin),
        _buildMotion(skin),
        _buildDotMatrix(skin),
        _buildDotMatrixLive(skin),
        _buildDotMatrixFrames(skin),
        _buildLoaders(skin),
        _buildChrome(skin),
        _buildRailPlacements(skin),
        _buildRouteStacks(skin),
        _buildMenus(skin),
        _buildCards(skin),
        _buildTable(skin),
        _buildMarkdown(skin),
        _buildDrawerParts(skin),
        _buildPageParts(skin),
        _buildScene(skin),
      ],
    );
  }

  Widget _section(TemplateSkin skin, String title, Widget child) {
    if (widget.onlySection != null && widget.onlySection != title) {
      return const SizedBox.shrink();
    }
    return TemplateSection(skin: skin, title: title, child: child);
  }

  /// 批 1 新增：页面骨架 / 浮层 / 三态 / 图标按钮 / 复选 / 徽标
  Widget _buildChrome(TemplateSkin skin) {
    Widget caption(String text) => Text(
      text,
      style: TemplateType.caption.copyWith(color: skin.textTertiary),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.lg,
      children: [
        _section(
          skin,
          '页面骨架（顶部栏 + 滚动区）',
          SizedBox(
            height: 420,
            child: TemplatePageFrame(
              skin: skin,
              breadcrumb: const [
                TemplateBreadcrumb('设置', onTap: _noop),
                TemplateBreadcrumb('启动'),
                TemplateBreadcrumb('启动设置'),
              ],
              // 顶栏左上是账户（左抽屉入口），返回键在侧栏顶部与 logo 共用位置
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: skin.accentTint,
                  shape: BoxShape.circle,
                  border: Border.all(color: skin.border),
                ),
                child: Icon(Icons.person, size: 14, color: skin.onAccentTint),
              ),
              actions: [
                TemplateIconButton(
                  skin: skin,
                  icon: Icons.refresh,
                  tooltip: '刷新',
                  onTap: () {},
                ),
                TemplateIconButton(
                  skin: skin,
                  icon: Icons.more_horiz,
                  tooltip: '更多',
                  onTap: () {},
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TemplateSection(
                    skin: skin,
                    title: '启动项',
                    child: Column(
                      spacing: 2,
                      children: [
                        TemplateSwitchRow(
                          skin: skin,
                          title: '游戏存档隔离',
                          desc: '存档与模组放在版本目录里',
                          value: true,
                          onTap: () {},
                        ),
                        TemplateSwitchRow(
                          skin: skin,
                          title: '启动前自动同步云存档',
                          desc: '退出游戏后上传',
                          value: false,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                  TemplateSection(
                    skin: skin,
                    title: '操作',
                    child: Wrap(
                      spacing: TemplateSpace.md,
                      runSpacing: TemplateSpace.md,
                      children: [
                        TemplateButton(
                          skin: skin,
                          label: '启动游戏',
                          icon: Icons.play_arrow,
                          kind: TemplateButtonKind.solid,
                          onTap: () {},
                        ),
                        TemplateButton(
                          skin: skin,
                          label: '打开文件夹',
                          icon: Icons.folder_open,
                          kind: TemplateButtonKind.plain,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _section(
          skin,
          '浮层（对话框 / Toast）',
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.lg,
            children: [
              SizedBox(
                width: 380,
                child: TemplateDialog(
                  skin: skin,
                  icon: Icons.delete_outline,
                  title: '删除这个版本？',
                  message: '版本文件与模组会被一并移除，存档目录不动。',
                  actions: [
                    TemplateButton(
                      skin: skin,
                      label: '取消',
                      icon: Icons.close,
                      kind: TemplateButtonKind.plain,
                      onTap: () {},
                    ),
                    TemplateButton(
                      skin: skin,
                      label: '删除',
                      icon: Icons.delete_outline,
                      kind: TemplateButtonKind.plain,
                      danger: true,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TemplateSpace.sm,
                  children: [
                    caption('Toast（右上堆叠，5s 自消）'),
                    TemplateToast(skin: skin, message: '已复制到剪贴板'),
                    TemplateToast(
                      skin: skin,
                      message: '版本列表已刷新',
                      icon: Icons.check_circle_outline,
                      tone: TemplateToastTone.success,
                    ),
                    TemplateToast(
                      skin: skin,
                      message: '下载失败，已写入日志',
                      icon: Icons.error_outline,
                      tone: TemplateToastTone.danger,
                    ),
                    const SizedBox(height: TemplateSpace.sm),
                    caption('图标按钮 / 复选 / 徽标'),
                    // Wrap：标准宽度 760 下这一排放不下，允许换行
                    Wrap(
                      spacing: TemplateSpace.sm,
                      runSpacing: TemplateSpace.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TemplateIconButton(
                          skin: skin,
                          icon: Icons.refresh,
                          tooltip: '刷新',
                          onTap: () {},
                        ),
                        TemplateIconButton(
                          skin: skin,
                          icon: Icons.more_horiz,
                          onTap: () {},
                        ),
                        TemplateIconButton(
                          skin: skin,
                          icon: Icons.settings,
                          selected: true,
                          onTap: () {},
                        ),
                        TemplateIconButton(
                          skin: skin,
                          icon: Icons.block,
                          enabled: false,
                          onTap: () {},
                        ),
                        const SizedBox(width: TemplateSpace.md),
                        TemplateCheckbox(skin: skin, value: true, onTap: () {}),
                        TemplateCheckbox(
                          skin: skin,
                          value: false,
                          onTap: () {},
                        ),
                        TemplateCheckbox(skin: skin, value: null, onTap: () {}),
                        TemplateCheckbox(
                          skin: skin,
                          value: true,
                          enabled: false,
                          onTap: () {},
                        ),
                        const SizedBox(width: TemplateSpace.md),
                        // 窗控：关闭悬停会铺危险色底
                        TemplateWindowControls(
                          skin: skin,
                          onMinimize: () {},
                          onMaximize: () {},
                          onClose: () {},
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: TemplateSpace.sm,
                      runSpacing: TemplateSpace.sm,
                      children: [
                        TemplateBadge(skin: skin, label: '已就绪'),
                        TemplateBadge(
                          skin: skin,
                          label: '推荐',
                          tone: TemplateBadgeTone.accent,
                        ),
                        TemplateBadge(
                          skin: skin,
                          label: '已同步',
                          tone: TemplateBadgeTone.success,
                          icon: Icons.cloud_done_outlined,
                        ),
                        TemplateBadge(
                          skin: skin,
                          label: '有更新',
                          tone: TemplateBadgeTone.warning,
                        ),
                        TemplateBadge(
                          skin: skin,
                          label: '不兼容',
                          tone: TemplateBadgeTone.danger,
                        ),
                        // 第四个语义色：提示 / 说明（蓝调，用户 2026-11-06 要的）
                        TemplateBadge(
                          skin: skin,
                          label: '提示',
                          tone: TemplateBadgeTone.note,
                          icon: Icons.lightbulb_outline,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _section(
          skin,
          '空 / 错 / 载三态',
          Wrap(
            spacing: TemplateSpace.md,
            runSpacing: TemplateSpace.md,
            children: [
              SizedBox(
                width: 240,
                height: 180,
                child: TemplateEmptyState(
                  skin: skin,
                  title: '还没有存档',
                  message: '启动一次游戏后，这里会出现可同步的存档',
                ),
              ),
              SizedBox(
                width: 240,
                height: 180,
                child: TemplateErrorState(
                  skin: skin,
                  title: '加载失败',
                  message: '无法连接到版本服务，检查网络后重试',
                ),
              ),
              SizedBox(
                width: 240,
                height: 180,
                // 转圈是无限动画，样张里关掉 ticker，否则 pumpAndSettle 永远等不到静止
                child: TickerMode(
                  enabled: false,
                  child: TemplateLoadingState(skin: skin, message: '正在读取版本…'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 账户 / 任务 / 折叠按钮放哪：三种摆法对照（2026-11-04 待用户选）
  Widget _buildRailPlacements(TemplateSkin skin) {
    Widget avatar(double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: skin.accentTint,
        shape: BoxShape.circle,
        border: Border.all(color: skin.border),
      ),
      child: Icon(Icons.person, size: size * 0.6, color: skin.onAccentTint),
    );

    Widget tasksIcon() => Stack(
      clipBehavior: Clip.none,
      children: [
        TemplateIconButton(
          skin: skin,
          icon: Icons.assignment_outlined,
          tooltip: '任务',
          size: 28,
          iconSize: 18,
          onTap: () {},
        ),
        Positioned(
          right: 2,
          top: 2,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: skin.danger,
              shape: BoxShape.circle,
              border: Border.all(color: skin.surface, width: 1),
            ),
          ),
        ),
      ],
    );

    const entries = [
      TemplateRailEntry(icon: Icons.play_circle_outline, label: '概览'),
      TemplateRailEntry(icon: Icons.storage_outlined, label: '资源'),
      TemplateRailEntry(icon: Icons.public, label: '联机'),
      TemplateRailEntry(icon: Icons.settings_outlined, label: '设置'),
    ];

    Widget mock({
      required String title,
      required String note,
      required bool collapsed,
      required bool isSubPage,
      List<Widget> barTrailing = const [],
      double corner = 14,
    }) {
      final brand = isSubPage
          ? TemplateRailBack(skin: skin, collapsed: collapsed)
          : TemplateRailBrand(skin: skin, collapsed: collapsed);
      return SizedBox(
        width: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: TemplateSpace.xs,
          children: [
            Text(
              title,
              style: TemplateType.item.copyWith(color: skin.textPrimary),
            ),
            Text(
              note,
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
            Container(
              height: 250,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                // 外壳底色 = 顶栏色：内容区圆角露出来的就是它（顶栏 + 侧栏包住内容区）
                color: skin.surface,
                border: Border.all(color: skin.border),
                borderRadius: BorderRadius.circular(TemplateRadius.card),
              ),
              child: Row(
                children: [
                  TemplateSideRail(
                    skin: skin,
                    entries: entries,
                    collapsed: collapsed,
                    showDivider: false,
                    top: brand,
                    // 底部：收纳 / 展开按钮
                    bottom: TemplateRailCollapse(
                      skin: skin,
                      collapsed: collapsed,
                      onTap: () {},
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(
                            horizontal: TemplateSpace.sm,
                          ),
                          // 无边界线：顶栏与内容区只靠底色 + 圆角分隔
                          decoration: BoxDecoration(color: skin.surface),
                          child: Row(
                            spacing: TemplateSpace.xs,
                            children: [
                              // 顶栏左侧只有账户（收纳按钮在侧栏底部）
                              avatar(24),
                              Expanded(
                                child: Text(
                                  '概览 › 启动',
                                  style: TemplateType.item.copyWith(
                                    color: skin.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ...barTrailing,
                            ],
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(corner),
                            ),
                            // 描边只压左边 + 上边（左上跟着圆角），右边 / 下边不画
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(
                                  color: skin.page,
                                  padding: const EdgeInsets.all(
                                    TemplateSpace.md,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    spacing: TemplateSpace.sm,
                                    children: [
                                      Container(
                                        height: 56,
                                        decoration: BoxDecoration(
                                          color: skin.surface,
                                          borderRadius: BorderRadius.circular(
                                            TemplateRadius.card,
                                          ),
                                          border: Border.all(
                                            color: skin.border,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        height: 96,
                                        decoration: BoxDecoration(
                                          color: skin.surface,
                                          borderRadius: BorderRadius.circular(
                                            TemplateRadius.card,
                                          ),
                                          border: Border.all(
                                            color: skin.border,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IgnorePointer(
                                  child: TemplateContentEdge(
                                    skin: skin,
                                    cornerRadius: corner,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return _section(
      skin,
      '外壳：logo + 应用名 / 收纳按钮在侧栏底部 / 页面左上圆角',
      Wrap(
        spacing: TemplateSpace.lg,
        runSpacing: TemplateSpace.lg,
        children: [
          mock(
            title: '展开：侧栏顶部 logo + Copper',
            note: '收纳按钮在侧栏底部；账户在顶栏左上、任务在右上',
            collapsed: false,
            isSubPage: false,
            barTrailing: [tasksIcon()],
          ),
          mock(
            title: '折叠：侧栏只剩 logo（56 宽）',
            note: '导航格只剩图标、名称走 tooltip；侧栏底部只剩旋转后的展开图标',
            collapsed: true,
            isSubPage: false,
            barTrailing: [tasksIcon()],
          ),
          mock(
            title: '子页面：返回键 + 「返回」占 logo 位',
            note: '返回键与软件 logo 共用同一位置——有返回就显示返回，logo 让位',
            collapsed: false,
            isSubPage: true,
            barTrailing: [tasksIcon()],
          ),
        ],
      ),
    );
  }

  /// 顶栏「路由线路」：整条栈 + 页面内路由（框起来）+ 名称后的 tag
  Widget _buildRouteStacks(TemplateSkin skin) {
    Widget bar(List<TemplateBreadcrumb> crumbs) => Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: TemplateSpace.md),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(TemplateRadius.control),
        border: Border.all(color: skin.border),
      ),
      child: TemplateBreadcrumbBar(skin: skin, crumbs: crumbs),
    );

    void noop() {}

    return _section(
      skin,
      '顶栏路由线路（整条栈 / 页面内路由用框 / 名称带 tag）',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          _hint(skin, '从「主页」进来：版本设置 → 页面内「设置」（框起来，不可点）'),
          bar([
            TemplateBreadcrumb('主页', onTap: noop),
            TemplateBreadcrumb('版本选择', onTap: noop),
            TemplateBreadcrumb('版本设置', tag: 'build 146', onTap: noop),
            const TemplateBreadcrumb('设置', boxed: true),
          ]),
          _hint(skin, '同一页，但从「设置」进来：栈不一样（入口不同 = 分类不同）'),
          bar([
            TemplateBreadcrumb('设置', onTap: noop),
            TemplateBreadcrumb('版本设置', tag: 'build 146', onTap: noop),
            const TemplateBreadcrumb('资源', boxed: true),
          ]),
          _hint(skin, '当前层是普通路由：最深且加粗（不可点）'),
          bar([
            TemplateBreadcrumb('主页', onTap: noop),
            TemplateBreadcrumb('版本选择', onTap: noop),
            TemplateBreadcrumb('版本设置', tag: 'build 146'),
          ]),
          _hint(skin, '页面内路由后面还能再接外部路由（资源下载）'),
          bar([
            TemplateBreadcrumb('社区资源', onTap: noop),
            const TemplateBreadcrumb('模组', boxed: true),
            TemplateBreadcrumb(
              '模组下载',
              tag: 'New Horizon',
              icon: Icons.extension_outlined,
              onTap: noop,
            ),
          ]),
        ],
      ),
    );
  }

  /// 滑块可选的几种形态：自绘 / 原生 M3 两代 / 刻度 / 数值气泡
  /// 标签页：一级分类切换（下划线式）
  Widget _buildTabs(TemplateSkin skin) {
    return _section(
      skin,
      '标签页（下划线式）',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          TemplateTabBar(
            skin: skin,
            tabs: const ['版本列表', '模组介绍', 'Readme'],
            value: _tab,
            onTap: (index) => setState(() => _tab = index),
            trailing: Text(
              '共 3 个版本',
              style: TemplateType.caption.copyWith(color: skin.textTertiary),
            ),
          ),
          Text(
            '当前选中：${const ['版本列表', '模组介绍', 'Readme'][_tab]}',
            style: TemplateType.caption.copyWith(color: skin.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 键位 / 颜色 / 拖放
  Widget _buildPickers(TemplateSkin skin) {
    Widget caption(String text) => Text(
      text,
      style: TemplateType.caption.copyWith(color: skin.textTertiary),
    );

    return _section(
      skin,
      '键位 / 颜色 / 拖放',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          caption('键位组合 + 捕获面板（点「开始捕获」后按键；Esc 取消）'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.lg,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TemplateSpace.sm,
                  children: [
                    TemplateKeyCombo(skin: skin, keys: _hotkey, size: 30),
                    Text(
                      '捕获到：${_hotkey.join(' + ')}',
                      style: TemplateType.micro.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TemplateKeyCapture(
                  skin: skin,
                  initial: _hotkey,
                  onCaptured: (keys) {
                    if (keys != null && keys.isNotEmpty) {
                      setState(() => _hotkey = keys);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: TemplateSpace.sm),
          caption('颜色：SV 面板 + 色相条 + 16 个预置色点'),
          TemplateColorPicker(
            skin: skin,
            color: _color,
            onChanged: (color) => setState(() => _color = color),
          ),
          const SizedBox(height: TemplateSpace.sm),
          caption('拖放区：常态虚线，悬停实线 + 主题色底（点一下切换演示）'),
          TemplateDropZone(
            skin: skin,
            title: '把资源拖进来',
            hint: 'zip / jar / 游戏本体',
            active: _dropActive,
            onTap: () => setState(() => _dropActive = !_dropActive),
          ),
          const SizedBox(height: TemplateSpace.sm),
          caption('窗口级拖放遮罩'),
          SizedBox(
            height: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(TemplateRadius.card),
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: skin.sunken)),
                  TemplateDropOverlay(skin: skin),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliders(TemplateSkin skin) {
    Widget row(String title, Widget slider) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.xs,
        children: [
          Text(
            title,
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
          slider,
        ],
      );
    }

    Widget native({required bool year2023, int? divisions, String? label}) {
      return SliderTheme(
        data: SliderThemeData(
          year2023: year2023,
          trackHeight: 12,
          activeTrackColor: skin.accent,
          inactiveTrackColor: skin.sunken,
          thumbColor: skin.accent,
          overlayColor: skin.accent.withAlpha(0x1F),
          valueIndicatorColor: skin.accent,
          valueIndicatorTextStyle: TemplateType.caption.copyWith(
            color: skin.onAccent,
          ),
          showValueIndicator: label == null
              ? ShowValueIndicator.never
              : ShowValueIndicator.alwaysVisible,
          activeTickMarkColor: skin.onAccent,
          inactiveTickMarkColor: skin.textTertiary,
          thumbShape: year2023
              ? const RoundSliderThumbShape(enabledThumbRadius: 10)
              : null,
        ),
        child: Slider(
          value: 0.55,
          divisions: divisions,
          label: label,
          onChanged: (_) {},
        ),
      );
    }

    return _section(
      skin,
      '滑块类型',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.lg,
        children: [
          row(
            '现状：自绘（轨道 16 + 圆滑块 24）',
            TemplateSliderRow(
              skin: skin,
              title: '内存上限',
              label: '6.6 GB',
              value: _slider,
              onChanged: (value) => setState(() => _slider = value),
            ),
          ),
          row('原生 M3 · 2024 样式', native(year2023: false)),
          row('原生 + 刻度（10 档）', native(year2023: false, divisions: 10)),
        ],
      ),
    );
  }

  /// 一条独立设置 = 一行，高度与原生开关一致
  Widget _buildTiles(TemplateSkin skin) {
    return _section(
      skin,
      '独立设置 tile（高度 = 原生开关默认高度）',
      Column(
        spacing: 2,
        children: [
          TemplateSettingTile(
            skin: skin,
            title: '自动检查启动器更新',
            onTap: () {},
            trailing: TemplateSwitch(
              skin: skin,
              value: _tileSwitch,
              onTap: () => setState(() => _tileSwitch = !_tileSwitch),
            ),
          ),
          TemplateSettingTile(
            skin: skin,
            title: '启动时恢复上次版本',
            trailing: TemplateSwitch(
              skin: skin,
              value: true,
              onTap: () {},
              enabled: false,
            ),
          ),
          TemplateSettingTile(
            skin: skin,
            title: '临时文件',
            onTap: () {},
            trailing: Icon(
              Icons.chevron_right,
              size: 20,
              color: skin.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(TemplateSkin skin) {
    return _section(
      skin,
      '按钮',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.md,
        children: [
          Wrap(
            spacing: TemplateSpace.md,
            runSpacing: TemplateSpace.md,
            children: [
              TemplateButton(
                skin: skin,
                label: '启动游戏',
                icon: Icons.play_arrow,
                kind: TemplateButtonKind.solid,
                onTap: () {},
              ),
              TemplateButton(
                skin: skin,
                label: '打开文件夹',
                icon: Icons.folder_open,
                kind: TemplateButtonKind.plain,
                onTap: () {},
              ),
              TemplateButton(
                skin: skin,
                label: '取消',
                icon: Icons.close,
                kind: TemplateButtonKind.quiet,
                onTap: () {},
              ),
              TemplateButton(
                skin: skin,
                label: '删除',
                icon: Icons.delete_outline,
                kind: TemplateButtonKind.plain,
                danger: true,
                onTap: () {},
              ),
              TemplateButton(
                skin: skin,
                label: '清空',
                icon: Icons.delete_sweep_outlined,
                kind: TemplateButtonKind.quiet,
                danger: true,
                onTap: () {},
              ),
            ],
          ),
          Wrap(
            spacing: TemplateSpace.md,
            runSpacing: TemplateSpace.md,
            children: [
              for (final (kind, danger, label) in const [
                (TemplateButtonKind.solid, false, '启动游戏'),
                (TemplateButtonKind.plain, false, '打开文件夹'),
                (TemplateButtonKind.quiet, false, '取消'),
                (TemplateButtonKind.plain, true, '删除'),
                (TemplateButtonKind.solid, true, '重置'),
              ])
                TemplateButton(
                  skin: skin,
                  label: label,
                  icon: Icons.block,
                  kind: kind,
                  danger: danger,
                  enabled: false,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRows(TemplateSkin skin) {
    return _section(
      skin,
      '行',
      Column(
        spacing: 2,
        children: [
          TemplateSwitchRow(
            skin: skin,
            title: '游戏存档隔离',
            desc: '存档与模组放在版本目录里',
            value: _switchA,
            onTap: () => setState(() => _switchA = !_switchA),
          ),
          TemplateSwitchRow(
            skin: skin,
            title: '启动前自动同步云存档',
            desc: '退出游戏后上传',
            value: _switchB,
            onTap: () => setState(() => _switchB = !_switchB),
          ),
          TemplateSwitchRow(
            skin: skin,
            title: '仅已同步时可用',
            desc: '禁用时整行与开关一起退掉',
            value: true,
            onTap: () {},
            enabled: false,
          ),
          TemplateSelectRow(
            skin: skin,
            title: '游戏Java',
            value: 'Java 17',
            onTap: () {},
          ),
          TemplateSelectRow(
            skin: skin,
            title: '版本通道',
            value: '未检测到本体',
            enabled: false,
          ),
          TemplateRow(
            skin: skin,
            onTap: () {},
            child: Row(
              children: [
                Expanded(
                  child: TemplateTwoLine(
                    skin: skin,
                    title: 'NewHorizon',
                    desc: 'v2.1.4 · 大型模组 · 12.8 MB',
                  ),
                ),
                Icon(
                  Icons.toggle_on_outlined,
                  size: 20,
                  color: skin.textSecondary,
                ),
              ],
            ),
          ),
          TemplateRow(
            skin: skin,
            selected: true,
            onTap: () {},
            child: Row(
              children: [
                Expanded(
                  child: TemplateTwoLine(
                    skin: skin,
                    title: '已选中的条目',
                    desc: '选中态用主题色的一层薄底',
                  ),
                ),
              ],
            ),
          ),
          TemplateKeyRow(
            skin: skin,
            title: '模组加载器',
            value: 'Copper Loader 0.2.0',
          ),
          TemplateKeyRow(
            skin: skin,
            title: '数据目录',
            value: r'E:\Mindustry\Copper',
          ),
        ],
      ),
    );
  }

  Widget _buildControls(TemplateSkin skin) {
    return _section(
      skin,
      '控件',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.lg,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.sm,
            children: [
              _hint(skin, '分段：三个选项'),
              TemplateSegment(
                skin: skin,
                options: const ['跟随全局', '自动分配', '自定义'],
                value: _segment,
                onTap: (index) => setState(() => _segment = index),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.sm,
            children: [
              _hint(skin, '分段：五个选项（挤的边界）'),
              TemplateSegment(
                skin: skin,
                options: const ['跟随全局', '自动分配', '自定义', '极简', '省电'],
                value: _segmentWide,
                onTap: (index) => setState(() => _segmentWide = index),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.sm,
            children: [
              _hint(skin, '分段：禁用'),
              TemplateSegment(
                skin: skin,
                options: const ['Java 17', 'Java 21'],
                value: 1,
                onTap: (_) {},
                enabled: false,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.sm,
            children: [
              _hint(skin, '分段：带图标 / 多选'),
              TemplateSegment(
                skin: skin,
                icons: const [
                  Icons.grid_view_outlined,
                  Icons.dashboard_outlined,
                  Icons.view_list_outlined,
                ],
                options: const ['网格', '卡片', '列表'],
                value: _segment,
                onTap: (index) => setState(() => _segment = index),
              ),
              TemplateMultiSegment(
                skin: skin,
                options: const ['已安装', '有更新', '已收藏'],
                selectedValues: _multiSeg,
                onTap: (index) => setState(() {
                  if (!_multiSeg.remove(index)) _multiSeg.add(index);
                }),
              ),
            ],
          ),
          _hint(skin, '开关：开 / 关 / 禁用'),
          Wrap(
            spacing: TemplateSpace.xl,
            runSpacing: TemplateSpace.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TemplateSwitch(
                skin: skin,
                value: true,
                onTap: () => setState(() => _switchA = true),
              ),
              TemplateSwitch(
                skin: skin,
                value: false,
                onTap: () => setState(() => _switchB = false),
              ),
              TemplateSwitch(
                skin: skin,
                value: true,
                onTap: () {},
                enabled: false,
              ),
              TemplateSwitch(
                skin: skin,
                value: false,
                onTap: () {},
                enabled: false,
              ),
            ],
          ),
          TemplateSliderRow(
            skin: skin,
            title: '内存上限',
            label: '${(_slider * 12).toStringAsFixed(1)} GB',
            value: _slider,
            divisions: 24,
            showTicks: true,
            minLabel: '0 GB',
            maxLabel: '12 GB',
            onChanged: (value) => setState(() => _slider = value),
          ),
          TemplateSliderRow(
            skin: skin,
            title: '交换空间',
            label: '不可调',
            value: 0.4,
            enabled: false,
          ),
          TemplateInputRow(
            skin: skin,
            title: 'jvm虚拟机参数',
            controller: _input,
            hint: '-XX:+UseG1GC',
          ),
          TemplateInputRow(
            skin: skin,
            title: '启动参数',
            controller: TextEditingController(text: '由启动器自动决定'),
            enabled: false,
          ),
          // 输入族：多行 / 错误 / 字数上限 / 密码显隐 / 后缀
          TemplateInputRow(
            skin: skin,
            title: '备注（多行）',
            controller: TextEditingController(text: ''),
            hint: '给这个版本写点什么…',
            multiline: true,
            maxLength: 200,
          ),
          TemplateInputRow(
            skin: skin,
            title: '端口（错误态）',
            controller: TextEditingController(text: '70000'),
            error: '端口要在 1 ~ 65535 之间',
            suffix: Text(
              '端口',
              style: TemplateType.micro.copyWith(color: skin.textTertiary),
            ),
          ),
          TemplateInputRow(
            skin: skin,
            title: '访问令牌（密码）',
            controller: TextEditingController(text: 'ghp_xxxxxxxxxxxx'),
            obscure: true,
          ),
        ],
      ),
    );
  }

  /// 动效：交错入场 / 品牌加载 / 描边进度 / 数字滚动 / 转场约定
  Widget _buildMotion(TemplateSkin skin) {
    Widget demo(String label, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TemplateSpace.xs,
      children: [_hint(skin, label), child],
    );

    return _section(
      skin,
      '动效',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          _hint(skin, '交错入场（AppearItem：淡入 + 上移 10，延迟按 index × 40ms）'),
          Row(
            spacing: TemplateSpace.md,
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: TemplateAppear(
                    index: i,
                    child: TemplateCard(
                      skin: skin,
                      padding: const EdgeInsets.all(TemplateSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: TemplateSpace.xs,
                        children: [
                          Text(
                            '卡片 ${i + 1}',
                            style: TemplateType.item.copyWith(
                              color: skin.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '进场延迟 ${i * 40}ms',
                            style: TemplateType.micro.copyWith(
                              color: skin.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          _hint(skin, '品牌加载：铜钻头（循环 / 完成 / 错误）'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.xl,
            children: [
              demo('循环', TemplateDrillLoading(skin: skin, size: 64)),
              demo(
                '完成',
                TemplateDrillLoading(
                  skin: skin,
                  size: 44,
                  state: DrillLoadingState.completing,
                ),
              ),
              demo(
                '错误',
                TemplateDrillLoading(
                  skin: skin,
                  size: 44,
                  state: DrillLoadingState.error,
                ),
              ),
            ],
          ),
          _hint(skin, '描边进度（按钮 / 卡片外沿；null = 不确定态）'),
          Row(
            spacing: TemplateSpace.md,
            children: [
              Expanded(
                child: TemplateBorderProgress(
                  skin: skin,
                  progress: 0.42,
                  child: TemplateButton(
                    skin: skin,
                    label: '下载中 42%',
                    icon: Icons.download,
                    kind: TemplateButtonKind.plain,
                    onTap: () {},
                  ),
                ),
              ),
              Expanded(
                child: TemplateBorderProgress(
                  skin: skin,
                  progress: null,
                  child: TemplateButton(
                    skin: skin,
                    label: '刷新中…',
                    icon: Icons.refresh,
                    kind: TemplateButtonKind.quiet,
                    onTap: () {},
                  ),
                ),
              ),
            ],
          ),
          _hint(skin, '数字滚动（从 0 滚到目标值，600ms easeOutCubic；≥1 万显示「万」）'),
          Row(
            spacing: TemplateSpace.xl,
            children: [
              demo(
                '126,900 次下载',
                TemplateAnimatedCounter(skin: skin, value: 126900),
              ),
              demo(
                '1,200 星标',
                TemplateAnimatedCounter(skin: skin, value: 1200, suffix: ' ★'),
              ),
              demo(
                '860 次（不带万）',
                TemplateAnimatedCounter(skin: skin, value: 860),
              ),
            ],
          ),
          _hint(
            skin,
            '页面转场：templatePageRoute（淡入 + 上移 2%，200ms easeOutCubic；返回 160ms）',
          ),
        ],
      ),
    );
  }

  /// 圆点矩阵动效（全动画）：不传 phase，几种图案同时在跑，App 里看真实节奏
  Widget _buildDotMatrixLive(TemplateSkin skin) {
    Widget item(String label, TemplateDotPattern pattern, {double size = 72}) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: TemplateSpace.xs,
          children: [
            SizedBox(
              width: size + 8,
              height: size + 8,
              child: Center(
                child: TemplateDotMatrix(
                  skin: skin,
                  size: size,
                  dots: size >= 56 ? 16 : 12,
                  pattern: pattern,
                  // 随机闪烁是「长循环的固定序列」：整圈 24s，单次呼吸 12~24s
                  duration: pattern == TemplateDotPattern.randomBlink
                      ? const Duration(milliseconds: 24000)
                      : const Duration(milliseconds: 1600),
                ),
              ),
            ),
            _hint(skin, label),
          ],
        );

    return _section(
      skin,
      '圆点矩阵动效（全动画）',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.lg,
        children: [
          _hint(skin, '五种图案都在跑（不传 phase 时自循环；这一节是给 App 里看真机的）'),
          Row(
            spacing: TemplateSpace.lg,
            children: [
              item('径向波纹', TemplateDotPattern.radialRipple),
              item('双螺旋', TemplateDotPattern.dualSpiral),
              item('环闪', TemplateDotPattern.ringFlash),
              item('菱形波', TemplateDotPattern.diamondWave),
              item('轨道光点', TemplateDotPattern.orbit),
              item('随机闪烁', TemplateDotPattern.randomBlink),
            ],
          ),
          _hint(skin, '同一图案（径向波纹）三种尺寸：56 / 40 / 28 都在转'),
          Row(
            spacing: TemplateSpace.lg,
            children: [
              for (final size in const [56.0, 40.0, 28.0])
                item(
                  '${size.toInt()}',
                  TemplateDotPattern.radialRipple,
                  size: size,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 圆点矩阵帧序列：每种图案 8 帧静帧，样张里看「运动轨迹」
  Widget _buildDotMatrixFrames(TemplateSkin skin) {
    Widget row(String label, TemplateDotPattern pattern) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TemplateSpace.xs,
      children: [
        _hint(skin, label),
        Row(
          spacing: TemplateSpace.sm,
          children: [
            for (var i = 0; i < 8; i++)
              SizedBox(
                width: 72,
                height: 72,
                child: Center(
                  child: TemplateDotMatrix(
                    skin: skin,
                    size: 62,
                    dots: 16,
                    pattern: pattern,
                    phase: i / 8,
                  ),
                ),
              ),
          ],
        ),
      ],
    );

    return _section(
      skin,
      '圆点矩阵动效（帧序列）',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          _hint(skin, '每种图案 8 帧（0 → 7/8），静帧拼起来就是运动轨迹；App 里看「全动画」那节'),
          row('① 径向波纹', TemplateDotPattern.radialRipple),
          row('② 双螺旋', TemplateDotPattern.dualSpiral),
          row('③ 环闪', TemplateDotPattern.ringFlash),
          row('④ 菱形波', TemplateDotPattern.diamondWave),
          row('⑤ 轨道光点', TemplateDotPattern.orbit),
          row('⑥ 随机闪烁（几颗光点随机亮灭）', TemplateDotPattern.randomBlink),
        ],
      ),
    );
  }

  /// 加载动效候选：每个候选给 4 帧（0 / 25 / 50 / 75%），挑一个再接到真实页面
  Widget _buildLoaders(TemplateSkin skin) {
    Widget frames(Widget Function(double phase) build) => Row(
      spacing: TemplateSpace.lg,
      children: [
        for (var i = 0; i < 4; i++)
          SizedBox(width: 56, height: 56, child: Center(child: build(i / 4))),
      ],
    );

    Widget block(String label, Widget Function(double phase) build) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TemplateSpace.xs,
      children: [_hint(skin, label), frames(build)],
    );

    return _section(
      skin,
      '加载动效（候选）',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.lg,
        children: [
          _hint(skin, '铜钻头那版不好看，这里给六个新候选；每行 4 帧是同一动画的不同相位（App 里是连续循环）'),
          block(
            '① 弧线环：一根带渐隐尾巴的铜色圆弧（最稳，任意尺寸都清楚）',
            (phase) => TemplateArcSpinner(skin: skin, size: 32, phase: phase),
          ),
          block(
            '② 铜粒轨道：三颗铜粒追尾旋转，头亮尾淡（最像「铜」）',
            (phase) => TemplateOrbitDots(skin: skin, size: 32, phase: phase),
          ),
          block(
            '③ 熔炉脉冲：三圈波纹从中心荡开 + 中心铜点呼吸（静态也好看）',
            (phase) => TemplateFurnacePulse(skin: skin, size: 32, phase: phase),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.xl,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TemplateSpace.xs,
                children: [
                  _hint(skin, '④ 进度环（确定进度，环里带百分比）'),
                  Row(
                    spacing: TemplateSpace.lg,
                    children: [
                      TemplateRingProgress(
                        skin: skin,
                        size: 44,
                        value: 0.28,
                        label: '28%',
                      ),
                      TemplateRingProgress(
                        skin: skin,
                        size: 44,
                        value: 0.62,
                        label: '62%',
                      ),
                      TemplateRingProgress(skin: skin, size: 44, value: null),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TemplateSpace.xs,
                children: [
                  _hint(skin, '⑤ 行内传送带（列表行 / 按钮里用）'),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: TemplateSpace.sm,
                    children: [
                      for (var i = 0; i < 2; i++)
                        TemplateBeltLoader(skin: skin, width: 92, phase: i / 2),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // ⑥ 圆点阵列钻头：用户点名要的「点阵叶片」，定子正八边形、叶片绕它转
          _hint(skin, '⑥ 圆点阵列钻头：圆盘点阵当盘面、四片螺旋刃在盘里转，中心定子（正八边形）不转'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: TemplateSpace.xl,
            children: [
              SizedBox(
                width: 116,
                height: 116,
                child: Center(
                  child: TemplateDotDrill(skin: skin, size: 108, dots: 20),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TemplateSpace.xs,
                children: [
                  _hint(skin, '转起来（4 帧，每帧差 30°；App 里连续转）'),
                  Row(
                    spacing: TemplateSpace.md,
                    children: [
                      for (var i = 0; i < 4; i++)
                        SizedBox(
                          width: 84,
                          height: 84,
                          child: Center(
                            child: TemplateDotDrill(
                              skin: skin,
                              size: 76,
                              dots: 18,
                              phase: i / 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          _hint(skin, '尺寸对照：56 / 44 / 32（整页 / 列表 / 行内）'),
          Row(
            spacing: TemplateSpace.lg,
            children: [
              for (final size in const [56.0, 44.0, 32.0])
                SizedBox(
                  width: 72,
                  height: 72,
                  child: Center(
                    child: TemplateDotDrill(
                      skin: skin,
                      size: size,
                      dots: size >= 50 ? 18 : 14,
                      phase: 0.05,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 圆点矩阵动效候选：统一网格，只让点的亮度 / 大小变化
  Widget _buildDotMatrix(TemplateSkin skin) {
    Widget frames(TemplateDotPattern pattern) => Row(
      spacing: TemplateSpace.lg,
      children: [
        for (var i = 0; i < 4; i++)
          SizedBox(
            width: 84,
            height: 84,
            child: Center(
              child: TemplateDotMatrix(
                skin: skin,
                size: 72,
                dots: 16,
                pattern: pattern,
                phase: i / 4,
              ),
            ),
          ),
      ],
    );

    Widget block(String title, TemplateDotPattern pattern) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TemplateSpace.xs,
      children: [_hint(skin, title), frames(pattern)],
    );

    return _section(
      skin,
      '圆点矩阵动效（候选）',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.lg,
        children: [
          _hint(
            skin,
            '一堆点、一套网格，只让亮度 / 点径动：参考 flutter_dot_loader 的 MatrixPattern（radial ripple / dual spiral / ring flash / manhattan pulse）',
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: TemplateSpace.xl,
            children: [
              SizedBox(
                width: 132,
                height: 132,
                child: Center(
                  child: TemplateDotMatrix(
                    skin: skin,
                    size: 124,
                    dots: 20,
                    pattern: TemplateDotPattern.radialRipple,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TemplateSpace.xs,
                children: [
                  _hint(skin, '尺寸：整页 56~72 / 行内 20~28（同一网格密度）'),
                  _hint(skin, '下面每个给 4 帧（0 / 25 / 50 / 75%）'),
                ],
              ),
            ],
          ),
          block('① 径向波纹：一圈圈从中心荡出去（最耐看）', TemplateDotPattern.radialRipple),
          block('② 双螺旋：两道光臂绕中心扫（最「科技」）', TemplateDotPattern.dualSpiral),
          block('③ 环闪：一道亮环往外扫 + 两条拖影（最「扫描」）', TemplateDotPattern.ringFlash),
          block('④ 菱形波：曼哈顿距离上的波，菱形向外扩（最「棋盘」）', TemplateDotPattern.diamondWave),
          block('⑤ 轨道光点：一颗光点在轨道上跑，附近点被照亮（最克制）', TemplateDotPattern.orbit),
          block('⑥ 随机闪烁：几颗光点在限定范围内随机亮灭（用户的想法）', TemplateDotPattern.randomBlink),
        ],
      ),
    );
  }

  Widget _buildFeedback(TemplateSkin skin) {
    return _section(
      skin,
      '反馈与入口',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.md,
        children: [
          TemplateNotice(skin: skin, text: '可以把资源或游戏本体拖进 Copper 直接导入'),
          // 主题色别堆：三条粗细并排成一排看差别，再补一条禁用态就够
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.md,
            children: [
              for (final (height, label) in const [
                (8.0, '8'),
                (12.0, '12'),
                (16.0, '16'),
              ])
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: TemplateSpace.xs,
                    children: [
                      _hint(skin, '粗 $label'),
                      TemplateProgressBar(
                        skin: skin,
                        value: 0.62,
                        height: height,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          TemplateProgressBar(
            skin: skin,
            value: 0.72,
            height: 12,
            enabled: false,
          ),
          // 双段进度：已分配（淡）＋ 已用（实心）——内存 / 磁盘这类「底量 + 用量」
          Row(
            spacing: TemplateSpace.md,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TemplateSpace.xs,
                  children: [
                    _hint(skin, '双段：已用 4.2 / 已分配 6.0 GB'),
                    TemplateProgressBar(
                      skin: skin,
                      value: 0.52,
                      secondary: 0.74,
                      height: 12,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TemplateSpace.xs,
                  children: [
                    _hint(skin, '双段：接近上限'),
                    TemplateProgressBar(
                      skin: skin,
                      value: 0.93,
                      secondary: 0.97,
                      height: 12,
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 状态点 / 数字徽章 / 胶囊标签
          Wrap(
            spacing: TemplateSpace.lg,
            runSpacing: TemplateSpace.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TemplateStatusDot(
                skin: skin,
                tone: TemplateStatusTone.online,
                label: '在线',
              ),
              TemplateStatusDot(
                skin: skin,
                tone: TemplateStatusTone.busy,
                label: '忙碌',
              ),
              TemplateStatusDot(
                skin: skin,
                tone: TemplateStatusTone.away,
                label: '离开',
              ),
              TemplateStatusDot(
                skin: skin,
                tone: TemplateStatusTone.offline,
                label: '离线',
              ),
            ],
          ),
          Wrap(
            spacing: TemplateSpace.sm,
            runSpacing: TemplateSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TemplateCountBadge(skin: skin, count: 3),
              TemplateCountBadge(
                skin: skin,
                count: 128,
                tone: TemplateBadgeTone.danger,
              ),
              TemplateCountBadge(
                skin: skin,
                count: 9,
                tone: TemplateBadgeTone.neutral,
              ),
              TemplateCountBadge(skin: skin, dotOnly: true),
              TemplateChip(
                skin: skin,
                icon: Icons.tag,
                label: 'v146',
                selected: true,
                onTap: () {},
              ),
              TemplateChip(
                skin: skin,
                icon: Icons.tag,
                label: 'v153',
                onTap: () {},
              ),
              TemplateChip(skin: skin, label: 'Java 模组', onClose: () {}),
            ],
          ),
          Wrap(
            spacing: TemplateSpace.md,
            runSpacing: TemplateSpace.md,
            children: [
              TemplateShortcut(
                skin: skin,
                icon: Icons.save,
                label: '存档文件夹',
                onTap: () {},
              ),
              TemplateShortcut(
                skin: skin,
                icon: Icons.map_outlined,
                label: '地图文件夹',
                onTap: () {},
              ),
              TemplateShortcut(
                skin: skin,
                icon: Icons.folder_off_outlined,
                label: '未安装',
                enabled: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 右键菜单：这里刻意用**当前项目里的** `ContextMenu`（用户 2026-11-06：
  /// 「右键菜单我说的是当前项目里用的」），设计层只负责在页面里接上它
  void _showContextMenu(BuildContext context, Offset globalPosition) {
    ContextMenu.show(
      context: context,
      position: globalPosition,
      entries: [
        ContextMenuAction(
          icon: Icons.play_arrow,
          label: '启动',
          onSelected: () {},
        ),
        ContextMenuAction(
          icon: Icons.folder_open,
          label: '打开文件夹',
          onSelected: () {},
        ),
        const ContextMenuDivider(),
        ContextMenuAction(
          icon: Icons.visibility_outlined,
          label: '只显示已安装',
          checked: true,
          onSelected: () {},
        ),
        ContextMenuAction(icon: Icons.copy, label: '复制版本名', onSelected: () {}),
        const ContextMenuDivider(),
        ContextMenuAction(
          icon: Icons.delete_outline,
          label: '删除版本',
          danger: true,
          onSelected: () {},
        ),
      ],
    );
  }

  /// 表格：表头 + 固定列 + 行分隔（模组页版本列表的抽出版）
  Widget _buildTable(TemplateSkin skin) {
    Widget cell(String text, {bool accent = false}) => Text(
      text,
      style: accent
          ? TemplateType.item.copyWith(
              color: skin.textPrimary,
              fontWeight: FontWeight.w600,
            )
          : TemplateType.caption.copyWith(color: skin.textTertiary),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return _section(
      skin,
      '表格',
      TemplateTable(
        skin: skin,
        onRowTap: (_) {},
        columns: const [
          TemplateTableColumn('版本', width: 90, icon: Icons.info_outline),
          TemplateTableColumn('发布时间', width: 110, icon: Icons.calendar_today),
          TemplateTableColumn(
            '支持版本',
            width: 150,
            icon: Icons.check_circle_outline,
          ),
          TemplateTableColumn('体积', width: 80, icon: Icons.storage),
          TemplateTableColumn('下载量', width: 70, icon: Icons.download),
          TemplateTableColumn('备注', flex: 1),
        ],
        rows: [
          [
            cell('v2.1.4', accent: true),
            cell('2026-11-04'),
            cell('v146-v153'),
            cell('12.4 MB'),
            cell('10.2k'),
            cell('当前主推版本'),
          ],
          [
            cell('v2.1.3', accent: true),
            cell('2026-10-21'),
            cell('v146-v153'),
            cell('12.1 MB'),
            cell('1499'),
            cell(''),
          ],
          [
            cell('v2.1.0', accent: true),
            cell('2026-09-30'),
            cell('v146-v153'),
            cell('11.8 MB'),
            cell('25.4k'),
            cell('已知与部分整合包冲突'),
          ],
        ],
      ),
    );
  }

  /// 右侧抽屉里的任务卡 / 日志卡
  Widget _buildDrawerParts(TemplateSkin skin) {
    Widget quiet(String label, IconData icon) => TemplateButton(
      skin: skin,
      label: label,
      icon: icon,
      kind: TemplateButtonKind.quiet,
      onTap: () {},
    );

    return _section(
      skin,
      '任务卡 / 日志卡（右侧抽屉）',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          TemplateTaskCard(
            skin: skin,
            icon: Icons.rocket_launch,
            title: 'Mindustry 146',
            statusLabel: '运行中',
            statusTone: TemplateBadgeTone.accent,
            phaseText: '游戏已启动 · 已运行 12 分钟',
            timeText: '18:20',
            detailText: '内存 4.0 / 8.0 GB · Java 17',
            actions: [
              quiet('结束进程', Icons.pause),
              quiet('进程日志', Icons.terminal),
            ],
          ),
          TemplateTaskCard(
            skin: skin,
            icon: Icons.downloading,
            title: 'Mindustry 146',
            statusLabel: '下载中',
            phaseText: '正在下载本体分块',
            progress: 0.42,
            progressText: '5.2 MB / 12.4 MB',
            sizeText: '1.8 MB/s',
            detailText: '分块 3 / 8 · 已校验 2 块',
            timeText: '18:19',
            actions: [quiet('取消', Icons.close)],
          ),
          TemplateTaskCard(
            skin: skin,
            icon: Icons.link,
            title: '拉取云存档',
            statusLabel: '进行中',
            phaseText: '正在获取大小…',
            timeText: '18:18',
            actions: [quiet('取消', Icons.close)],
          ),
          TemplateTaskCard(
            skin: skin,
            icon: Icons.error_outline,
            title: 'Copper Loader 0.2.1',
            statusLabel: '失败',
            statusTone: TemplateBadgeTone.danger,
            phaseText: '下载失败：连接超时',
            progress: 0.21,
            progressText: '2.6 MB / 12.4 MB',
            detailText: '重试会自动续传',
            timeText: '18:05',
            actions: [quiet('重试', Icons.refresh), quiet('日志', Icons.terminal)],
          ),
          const SizedBox(height: TemplateSpace.xs),
          TemplateLogCard(
            skin: skin,
            message: '已启动 Mindustry 146',
            timeText: '18:20:31',
          ),
          TemplateLogCard(
            skin: skin,
            message: '云存档同步完成（3 个文件）',
            timeText: '18:19:40',
            tone: TemplateLogTone.success,
          ),
          TemplateLogCard(
            skin: skin,
            message: 'GitHub 接口接近限流阈值',
            timeText: '18:18:02',
            tone: TemplateLogTone.warning,
          ),
          TemplateLogCard(
            skin: skin,
            message: '下载失败：连接超时',
            timeText: '18:05:12',
            tone: TemplateLogTone.error,
          ),
        ],
      ),
    );
  }

  /// 分页 / 折叠 / 图片与头像
  Widget _buildPageParts(TemplateSkin skin) {
    Widget caption(String text) => Text(
      text,
      style: TemplateType.caption.copyWith(color: skin.textTertiary),
    );

    return _section(
      skin,
      '分页 / 折叠 / 图片位',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          caption('分页器（第 x / y 页，可带首末页）'),
          TemplatePager(
            skin: skin,
            page: _pagerPage,
            pageCount: 6,
            firstLast: true,
            onPage: (page) => setState(() => _pagerPage = page),
          ),
          const SizedBox(height: TemplateSpace.sm),
          caption('折叠面板（整行可点，内容由调用方给）'),
          TemplateCollapse(
            skin: skin,
            title: '高级选项',
            subtitle: 'JVM 参数 / 启动参数 / 键位',
            initiallyExpanded: true,
            trailing: Text(
              '3 项',
              style: TemplateType.micro.copyWith(color: skin.textTertiary),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: TemplateSpace.sm,
              children: [
                TemplateKeyRow(
                  skin: skin,
                  title: 'JVM 参数',
                  value: '-XX:+UseG1GC',
                ),
                TemplateKeyRow(skin: skin, title: '启动参数', value: '自动'),
                TemplateKeyRow(skin: skin, title: '键位', value: '默认'),
              ],
            ),
          ),
          const SizedBox(height: TemplateSpace.sm),
          caption('图片位 / 头像（有图用图，没图退回图标或首字）'),
          Row(
            spacing: TemplateSpace.md,
            children: [
              TemplateImageBox(
                skin: skin,
                size: 72,
                icon: Icons.extension_outlined,
              ),
              TemplateImageBox(
                skin: skin,
                size: 72,
                icon: Icons.map_outlined,
                radius: TemplateRadius.control,
              ),
              TemplateAvatar(skin: skin, size: 48, name: 'Copper'),
              TemplateAvatar(skin: skin, size: 48, name: 'Alex'),
              TemplateAvatar(skin: skin, size: 48),
            ],
          ),
        ],
      ),
    );
  }

  /// Markdown（README 渲染）
  Widget _buildMarkdown(TemplateSkin skin) {
    return _section(
      skin,
      'Markdown（README）',
      TemplateMarkdown(
        skin: skin,
        data: '''
# New Horizon

一个把 Mindustry 往「大后期」推的内容模组：新增科技层级、单位与建筑。

> 装之前先看「已知问题」，与部分整合包冲突。

## 安装

1. 选一个 **v146 ~ v153** 的版本
2. 点「下载」，启动器自动挑兼容版本
3. 启动游戏

- 建议搭配 Copper Loader `0.2.1` 及以上
- 冲突时先禁用对方再重启

---

```json
"minGameVersion": "146",
"java": true
```

![Java 模组](https://img.shields.io/badge/java-mod-orange)

更多见 [GitHub 仓库](https://github.com/)。
''',
        onLinkTap: (_) {},
      ),
    );
  }

  Widget _buildScene(TemplateSkin skin) {
    return _section(
      skin,
      '页面片段：启动前设置',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          TemplateTwoLine(
            skin: skin,
            title: 'Mindustry 146 · 已就绪',
            desc: '上次启动 2 小时前',
          ),
          TemplateProgressBar(skin: skin, value: 0.62, height: 12),
          const SizedBox(height: TemplateSpace.xs),
          TemplateKeyRow(skin: skin, title: 'Java', value: 'Zulu 17.0.9'),
          TemplateKeyRow(skin: skin, title: '内存', value: '4.0 GB / 8.0 GB'),
          const SizedBox(height: TemplateSpace.sm),
          Wrap(
            spacing: TemplateSpace.md,
            runSpacing: TemplateSpace.md,
            children: [
              TemplateButton(
                skin: skin,
                label: '启动游戏',
                icon: Icons.play_arrow,
                kind: TemplateButtonKind.solid,
                onTap: () {},
              ),
              TemplateButton(
                skin: skin,
                label: '版本设置',
                icon: Icons.tune,
                kind: TemplateButtonKind.plain,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 菜单 / 下拉 / 提示条语气
  Widget _buildMenus(TemplateSkin skin) {
    Widget caption(String text) => Text(
      text,
      style: TemplateType.caption.copyWith(color: skin.textTertiary),
    );

    return _section(
      skin,
      '菜单 / 下拉 / 提示条语气',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.md,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TemplateSpace.lg,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TemplateSpace.sm,
                children: [
                  caption('下拉（真菜单，单选）'),
                  TemplateDropdown<String>(
                    skin: skin,
                    width: 200,
                    value: _java,
                    items: const [
                      TemplateDropdownItem(value: 'Java 17', label: 'Java 17'),
                      TemplateDropdownItem(value: 'Java 21', label: 'Java 21'),
                      TemplateDropdownItem(value: 'Java 8', label: 'Java 8'),
                    ],
                    onSelected: (value) => setState(() => _java = value),
                  ),
                  const SizedBox(height: TemplateSpace.sm),
                  caption('下拉（多选，面板可连续勾选）'),
                  TemplateMultiDropdown<String>(
                    skin: skin,
                    width: 200,
                    values: _multi,
                    items: const [
                      TemplateDropdownItem(value: 'Java 17', label: 'Java 17'),
                      TemplateDropdownItem(value: 'Java 21', label: 'Java 21'),
                      TemplateDropdownItem(value: 'Java 8', label: 'Java 8'),
                      TemplateDropdownItem(value: 'Java 25', label: 'Java 25'),
                    ],
                    onChanged: (values) => setState(() => _multi = values),
                  ),
                  const SizedBox(height: TemplateSpace.sm),
                  caption('右键菜单（含复选 / 危险项 / 快捷键）'),
                ],
              ),
              TemplateMenuPanel(
                skin: skin,
                items: [
                  const TemplateMenuItem(
                    label: '启动',
                    icon: Icons.play_arrow,
                    shortcut: 'Enter',
                  ),
                  const TemplateMenuItem(
                    label: '打开文件夹',
                    icon: Icons.folder_open,
                  ),
                  const TemplateMenuItem(
                    label: '复制版本名',
                    icon: Icons.copy,
                    shortcut: 'Ctrl+C',
                  ),
                  const TemplateMenuItem(label: '只显示已安装', checked: true),
                  TemplateMenuItem(
                    label: '删除版本',
                    icon: Icons.delete_outline,
                    danger: true,
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: TemplateSpace.sm),
          caption('右键 / 长按下面这块，弹出真菜单（点外部关闭、Esc 关闭）'),
          GestureDetector(
            onSecondaryTapDown: (details) =>
                _showContextMenu(context, details.globalPosition),
            onLongPressStart: (details) =>
                _showContextMenu(context, details.globalPosition),
            child: Container(
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: skin.sunken,
                borderRadius: BorderRadius.circular(TemplateRadius.card),
                border: Border.all(color: skin.border),
              ),
              child: Text(
                '右键这里',
                style: TemplateType.caption.copyWith(color: skin.textTertiary),
              ),
            ),
          ),
          const SizedBox(height: TemplateSpace.sm),
          caption('提示条：五种语气 / 可关闭 / 行内动作'),
          TemplateNotice(skin: skin, text: '把资源或游戏本体拖进 Copper 直接导入'),
          TemplateNotice(
            skin: skin,
            tone: TemplateNoticeTone.success,
            text: '版本列表已刷新',
          ),
          TemplateNotice(
            skin: skin,
            tone: TemplateNoticeTone.note,
            text: '选「仅兼容」只会列出支持当前版本的那些版本',
          ),
          TemplateNotice(
            skin: skin,
            tone: TemplateNoticeTone.warning,
            title: '有可用更新',
            text: 'Copper Loader 0.2.1 已发布，重启后生效',
            action: TemplateButton(
              skin: skin,
              label: '查看',
              icon: Icons.arrow_forward,
              kind: TemplateButtonKind.quiet,
              onTap: () {},
            ),
            onClose: () {},
          ),
          TemplateNotice(
            skin: skin,
            tone: TemplateNoticeTone.danger,
            text: '下载失败，已写入日志',
          ),
        ],
      ),
    );
  }

  /// 列表卡 / 网格卡
  Widget _buildCards(TemplateSkin skin) {
    return _section(
      skin,
      '列表卡 / 网格卡',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.md,
        children: [
          TemplateListCard(
            skin: skin,
            title: 'Mindustry 146',
            subtitle: 'v146 · 已安装 · 2 小时前启动',
            icon: Icons.gamepad_outlined,
            badge: TemplateBadge(
              skin: skin,
              label: '已同步',
              tone: TemplateBadgeTone.success,
            ),
            trailing: TemplateIconButton(
              skin: skin,
              icon: Icons.play_arrow,
              tooltip: '启动',
              onTap: () {},
            ),
            onTap: () {},
          ),
          TemplateListCard(
            skin: skin,
            title: 'NewHorizon',
            subtitle: 'v2.1.4 · 大型模组 · 12.8 MB',
            icon: Icons.extension_outlined,
            selected: true,
            trailing: TemplateIconButton(
              skin: skin,
              icon: Icons.more_horiz,
              onTap: () {},
            ),
            onTap: () {},
          ),
          SizedBox(
            height: 236,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.md,
              children: [
                SizedBox(
                  width: 220,
                  child: TemplateGridCard(
                    skin: skin,
                    title: 'Mindustry 146',
                    subtitle: '已安装 · 2 小时前',
                    icon: Icons.gamepad_outlined,
                    badge: TemplateBadge(
                      skin: skin,
                      label: '推荐',
                      tone: TemplateBadgeTone.accent,
                    ),
                    onTap: () {},
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TemplateGridCard(
                    skin: skin,
                    title: '地图合集',
                    subtitle: '32 张地图 · 14.2 MB',
                    icon: Icons.map_outlined,
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint(TemplateSkin skin, String text) {
    return Text(
      text,
      style: TemplateType.caption.copyWith(color: skin.textTertiary),
    );
  }
}

/// 面包屑演示用：常量上下文里只能挂顶层函数引用
void _noop() {}
