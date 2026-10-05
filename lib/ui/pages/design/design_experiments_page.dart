import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/copper_card.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/theme/design_system.dart';
import 'package:flutter/material.dart';

const designExperimentsPageRouteKey = '/design/example/experiments';

/// 设计规范 · 实例页 · 试验对照
///
/// 五个「反例 / 正例」对照，每个都附桌面 UI 规范的原文结论；
/// 出处链接在 `.project_status/components.md` 的规范节
class DesignExperimentsPage extends StatefulWidget {
  const DesignExperimentsPage({super.key});

  @override
  State<DesignExperimentsPage> createState() => _DesignExperimentsPageState();
}

class _DesignExperimentsPageState extends State<DesignExperimentsPage> {
  /// 依据表的出处列宽
  static const double _labelWidth = 120;

  /// 桌面 UI 规范的原文结论（2026-10-05 查，出处见 components.md 的规范节）
  static const _typographyEvidence = <({String source, String finding})>[
    (
      source: 'Apple HIG',
      finding:
          'macOS 默认字号 13pt、最小 10pt；Headline 与 Body 同为 13pt，只靠字重区分 —— 层级靠字重，不靠把尺寸吹大',
    ),
    (
      source: 'IBM Carbon',
      finding:
          '桌面 productive 档基准 14px：body 14/20、heading-compact 14/18 Semibold，标题与正文同尺寸；label 与 helper 12/16',
    ),
    (
      source: 'Windows / Fluent 2',
      finding:
          'Windows 档位少而步长大：Caption 12、Body 14、Subtitle 20、Title 28；标题一律 Semibold、正文 Regular',
    ),
    (
      source: 'Fluent 2 对比度',
      finding: '正文 ≥ 4.5:1，大字号（加粗 >18.5 或常规 >24）可放宽到 3:1 —— 铜色标题在浅色卡上约 2:1，不合规',
    ),
    (
      source: 'GNOME HIG',
      finding: '尽量减少字号与字重的种类；次要信息「更小 + 更浅」、重要信息「更粗 + 更深」；禁止全大写',
    ),
    (
      source: 'WCAG 2.2',
      finding:
          '可点目标至少 24×24（桌面底线 2.5.8），触控达 44×44（2.5.5）—— 现有 iconButton 24 / item 48 正好卡住',
    ),
  ];

  /// 视觉重心的依据（2026-10-05 查，出处见 components.md 的规范节）
  static const _focusRules = <({String source, String finding})>[
    (
      source: 'Apple HIG 布局',
      finding: '按重要度摆位置：人按「自上而下、从起始侧到末尾侧」看，最重要的放顶部与起始侧；别让不重要的细节把它挤住',
    ),
    (
      source: 'Apple HIG 分组',
      finding: '用留白、底色、色块或分隔线把相关内容圈在一起，无关内容分开 —— 分组本身就是层级',
    ),
    (source: 'Apple HIG 对齐', finding: '组件互相对齐能让界面好扫，也在表达组织与层级；缩进同样表达层级'),
    (source: 'Apple HIG（macOS）', finding: '不要把控件或关键信息放在窗口底部 —— 用户常把窗口下沿拖到屏幕外'),
    (
      source: 'Windows 内容布局',
      finding: '空间紧时用 Body Strong（14 w600）当标题且不加间距 —— 抬层级靠字重，不靠放大字号',
    ),
    (
      source: 'Windows 内容布局',
      finding: '间距在表达关系：控件之间 8、控件与标签 12、内容块之间 12、卡片边缘到文字 16',
    ),
    (source: 'Windows 命令设计', finding: '常用命令才放在内容区；命令放太多会占掉版面并淹没用户，不常用的收进别的命令面'),
    (source: 'NN/g 眯眼测试', finding: '把界面缩到 25% 或眯眼看：应该只剩一个跳出来的焦点；到处都在跳说明没有重心'),
  ];

  /// 分组与留白的依据（2026-10-05 查）
  static const _groupingRules = <({String source, String finding})>[
    (
      source: 'Carbon 间距',
      finding: '挨得近的元素被看成有关系，间距越大关系越弱 ⇒ 分组只用间距就够，不必画线或加卡片；重要的元素周围多留白，它就自然更显眼',
    ),
    (source: 'Fluent 布局', finding: '同一套间距模式里的元素被看成等重的一组；间距用对了就形成逻辑分区，不需要分隔线'),
    (
      source: 'Fluent 布局 · 网格',
      finding: '网格由列 / 槽 / 边距组成，12 列是常用框架；最重要的一块占最大的那份；基线网格定出垂直节奏，人扫起来更顺',
    ),
    (
      source: 'Apple HIG 布局',
      finding: '用留白、底色、色块或分隔线把相关内容圈在一起，同时保证内容与控件彼此可辨；无关的控件别挤在一起',
    ),
    (
      source: 'GNOME 框选列表',
      finding: '成组比零散好扫：一行通常只放一个控件、最多两个；行内多个文本靠大小 / 字重 / 颜色区分；图标用符号风格，别抢列表的视觉',
    ),
    (
      source: 'Windows 内容布局',
      finding: '间距就在表达关系：控件之间 8、控件与标签 12、内容块之间 12、卡片边缘到文字 16',
    ),
  ];

  /// 密度与节奏的依据（2026-10-05 查）
  static const _densityRules = <({String source, String finding})>[
    (
      source: 'Fluent 间距梯度',
      finding:
          '基准单位 4px：0 / 2 / 4 / 6 / 8 / 10 / 12 / 16 / 20 / 24 / 32 / 40 / 48 …；其中 2 / 6 / 10 是给图标对齐留的例外',
    ),
    (
      source: 'Carbon 间距刻度',
      finding:
          '2 / 4 / 8 / 12 / 16 / 24 / 32 / 40 / 48 / 64 …；小档管元素内部关系、大档控制整页密度；刻度外的值尽量别用',
    ),
    (source: 'Carbon 留白', finding: '局部可以密，整页不能挤：密集的信息区是允许的，但整页要留出让眼睛休息的空白'),
    (source: 'Carbon 响应式', finding: '间距可以随断点跳档（窄屏退一到两档），不必一格一格连续变化'),
    (
      source: 'Windows 内容布局',
      finding: '空间紧时不要靠压缩间距解决，改用更轻的排版：Body Strong 当标题、Caption 当按钮文字',
    ),
  ];

  /// 空态与状态设计的依据（2026-10-05 查）
  static const _statusRules = <({String source, String finding})>[
    (
      source: 'Carbon 空态 · 结构',
      finding:
          '图（可选）/ 标题（短，尽量写成正面表述）/ 正文（说清下一步、为什么空、这么做有什么好处）/ 主行动 / 次行动（可选，正文下方的链接）',
    ),
    (
      source: 'Carbon 空态 · 取舍',
      finding: '一个空态只讲一件事，多个选择就只留最重要的那个；别用用户还不懂的产品术语；别把用户带进死胡同',
    ),
    (
      source: 'Carbon 空态 · 布局',
      finding: '空态元素左对齐成一块（小瓦片例外：图居中、文字与动作仍左对齐）；空间小就只用文字，不给图',
    ),
    (source: 'Carbon 空态 · 多个同现', finding: '同一屏可能出现多个空态时，动作用三级按钮 —— 避免一屏多个主按钮'),
    (
      source: 'Carbon 空态 · 语义',
      finding: '空态要顶掉原本要显示的那个元素（表格空态就别再画表头），屏幕阅读器才不会先读一遍空表',
    ),
    (
      source: 'Windows 命令设计',
      finding: '错误与破坏性动作：不可逆的才用确认弹窗，可撤销的给撤销就够了；别把确认弹窗用成习惯',
    ),
  ];

  /// 其余状态的写法要点
  static const _stateNotes = [
    '加载：用骨架或进度条占住位置，别让布局跳一下；进度要能看出还剩多少',
    '错误：说清发生了什么 + 用户能做什么，并给一个重试入口；不可逆的才弹确认',
    '禁用：走 enable: false，不要靠改颜色冒充；顺手给一句为什么不能点',
    '部分失败：能用的部分照常显示，别整页变成错误页',
  ];

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.block,
        vertical: AppSpacing.related,
      ),
      items: [
        _buildCompareModule(),
        _buildFocusModule(),
        _buildGroupingModule(),
        _buildDensityModule(),
        _buildStatusModule(),
      ],
    );
  }

  // ════════ 试验一：文字层级（桌面密度模型） ════════

  Widget _buildCompareModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '试验一：文字层级（现状 / 桌面密度改法）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.section,
        children: [
          Text(
            '两边的结构与内容完全一样，差别只在「用哪一档文字角色 + 用哪个语义色」，'
            '所以下面的对照不会掺进布局变量',
            style: theme.textTheme.bodySmall,
          ),
          _buildSpecimen(
            caption:
                '现状：卡片标题 headlineSmall 16 bold + 主题色；条目 headlineMedium 18 bold；正文 bodyMedium + itemSecondary',
            tuned: false,
          ),
          _buildSpecimen(
            caption:
                '改法：卡片标题 titleMedium 14 w600 + itemPrimary；条目 bodyMedium 14 + itemPrimary；'
                '说明 bodySmall 12 + itemSecondary；主题色只留给交互与图标',
            tuned: true,
          ),
          Text('依据：桌面 UI 规范的原文结论', style: theme.textTheme.titleSmall),
          for (final item in _typographyEvidence)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.group,
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Text(item.source, style: theme.textTheme.titleSmall),
                ),
                Expanded(
                  child: Text(item.finding, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          Text(
            '注：这一块是试验田，样式写在页面里、没有动公共组件；定稿后再落到 textTheme 与 ContentPanelModule',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 同一组内容渲染两遍；tuned 为 true 走桌面密度改法
  Widget _buildSpecimen({required String caption, required bool tuned}) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final textTheme = theme.textTheme;

    // 改法只做三件事：换 textTheme 的档位、标题去主题色、正文提到 itemPrimary
    final titleStyle = tuned
        ? textTheme.titleMedium?.copyWith(color: colors.itemPrimary)
        : textTheme.headlineSmall?.copyWith(color: colors.interactive);
    final itemStyle = tuned
        ? textTheme.bodyMedium?.copyWith(color: colors.itemPrimary)
        : textTheme.headlineMedium;
    final bodyStyle = tuned
        ? textTheme.bodyMedium?.copyWith(color: colors.itemPrimary)
        : textTheme.bodyMedium;
    final hintStyle = textTheme.bodySmall?.copyWith(
      color: tuned ? colors.itemSecondary : colors.itemHint,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.related,
      children: [
        Text(
          caption,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.itemSecondary,
          ),
        ),
        CopperCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(AppSpacing.section),
          borderRadius: AppRadius.itemShape,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.related,
            children: [
              Text('运行环境', style: titleStyle),
              Text('下面这些是启动游戏要用到的东西', style: hintStyle),
              Row(
                spacing: AppSpacing.group,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Java 运行环境', style: itemStyle),
                        Text('已安装 · JDK 25', style: hintStyle),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: AppIconSize.item,
                    color: colors.itemHint,
                  ),
                ],
              ),
              Text('正文示例：把这份 Java 拉起来、摆好参数，再把游戏画面接到设备上。', style: bodyStyle),
            ],
          ),
        ),
      ],
    );
  }

  // ════════ 试验二：视觉重心 ════════

  Widget _buildFocusModule() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return ContentPanelModule(
      title: '试验二：视觉重心（一个视图只留一个焦点）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.section,
        children: [
          Text(
            '重心不是「哪里加粗」，而是「眼睛先落在哪」：一个视图只该有一个最重的东西，'
            '其余动作按 primary / secondary / tertiary 往下排',
            style: theme.textTheme.bodySmall,
          ),
          _buildFocusSpecimen(
            caption: '反例：三个动作一样重，眼睛没有落点 —— 现在的 IconTextButton 全是这一种',
            actions: [
              IconTextButton(
                icon: Icons.play_arrow,
                content: '启动游戏',
                onTap: () {},
              ),
              IconTextButton(
                icon: Icons.settings,
                content: '版本设置',
                onTap: () {},
              ),
              IconTextButton(
                icon: Icons.folder_open,
                content: '打开目录',
                onTap: () {},
              ),
            ],
          ),
          _buildFocusSpecimen(
            caption: '正例：启动是唯一的 primary（实心主题色），设置次之，打开目录降为三级',
            actions: [
              IconTextButton(
                icon: Icons.play_arrow,
                content: '启动游戏',
                weight: ActionWeight.primary,
                onTap: () {},
              ),
              IconTextButton(
                icon: Icons.settings,
                content: '版本设置',
                weight: ActionWeight.secondary,
                onTap: () {},
              ),
              IconTextButton(
                icon: Icons.folder_open,
                content: '打开目录',
                weight: ActionWeight.tertiary,
                onTap: () {},
              ),
            ],
          ),
          _buildFocusSpecimen(
            caption: '主行动的取法（浅色下；括号里是文字与它自己底色的对比度）',
            actions: [
              _buildTintedAction(
                background: colors.interactive,
                foreground: colors.itemOnInteractive,
                label: '现在用的 copper700（2.95:1）',
              ),
              _buildTintedAction(
                background: colors.interactiveHigh,
                foreground: colors.itemOnInteractive,
                label: '试过的 copper900（7.1:1，发闷）',
              ),
              _buildTintedAction(
                // 候选值：Palette.copper800，#9E6B30 —— 现在 AppColors 里取不到，要加 token
                background: const Color(0xFF9E6B30),
                foreground: colors.itemOnInteractive,
                label: '候选 copper800（4.6:1）',
              ),
              _buildTintedAction(
                background: colors.indicatorBackground,
                foreground: colors.interactiveHigh,
                label: '软底 copper300 + copper900 字（5.9:1）',
              ),
            ],
          ),
          Text(
            '用户 2026-10-05 拍板：回到旧观感 copper700 —— copper900 虽然对比达标（7.1:1）但发闷，'
            '宁可接受 2.95:1 的对比不达标。铜色要到 copper800 那档才能两头兼顾，'
            '而它现在取不到（只存在于 Palette，AppColors 里没有），要走 B 类加一对'
            '「实心强调 / 其上文字」token 才用得上',
            style: theme.textTheme.bodySmall,
          ),
          Text('依据', style: theme.textTheme.titleSmall),
          for (final item in _focusRules)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.group,
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Text(item.source, style: theme.textTheme.titleSmall),
                ),
                Expanded(
                  child: Text(item.finding, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          Text(
            '自查手法：把窗口缩到 25% 或眯起眼看，应该只剩一个东西跳出来；到处都在跳就是没有重心',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.itemSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 反例 / 正例共用的一行动作
  Widget _buildFocusSpecimen({
    required String caption,
    required List<Widget> actions,
  }) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.related,
      children: [
        Text(
          caption,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.itemSecondary,
          ),
        ),
        CopperCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(AppSpacing.section),
          borderRadius: AppRadius.itemShape,
          child: Wrap(
            spacing: AppSpacing.related,
            runSpacing: AppSpacing.related,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ),
      ],
    );
  }

  // ════════ 试验三：分组与留白 ════════

  Widget _buildGroupingModule() {
    final theme = Theme.of(context);

    return ContentPanelModule(
      title: '试验三：分组与留白（用间距分组，不靠画线）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.section,
        children: [
          Text(
            '同组 8、组间 24 就够了：挨得近的被看成一组、离得远的自然分开，'
            '所以分组不必加卡片，也不必每条都画分隔线',
            style: theme.textTheme.bodySmall,
          ),
          _buildGroupingSpecimen(
            caption: '反例：所有项等距 + 每条都画分隔线，看不出哪儿是一组',
            grouped: false,
          ),
          _buildGroupingSpecimen(
            caption: '正例：同组 8、组间 24、无分隔线；组标题只占一行小字',
            grouped: true,
          ),
          _buildRuleRows(_groupingRules),
        ],
      ),
    );
  }

  /// 同一份内容按「等距 + 分隔线」与「分组间距」两种方式排
  Widget _buildGroupingSpecimen({
    required String caption,
    required bool grouped,
  }) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final rowStyle = theme.textTheme.bodyMedium;
    final before = ['当前版本', '数据目录', '日志目录'];
    final after = ['启动时检查更新', '下载镜像', '内存上限'];

    List<Widget> plainRows() => [
      for (final name in [...before, ...after]) ...[
        Text(name, style: rowStyle),
        Divider(
          height: AppSpacing.section,
          thickness: AppBorderWidth.hairline,
          color: colors.border,
        ),
      ],
    ];

    List<Widget> groupedRows(List<String> names) => [
      for (var i = 0; i < names.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpacing.related),
        Text(names[i], style: rowStyle),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.related,
      children: [
        Text(
          caption,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.itemSecondary,
          ),
        ),
        CopperCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(AppSpacing.section),
          borderRadius: AppRadius.itemShape,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: grouped
                ? [
                    Text('位置', style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.related),
                    ...groupedRows(before),
                    const SizedBox(height: AppSpacing.block),
                    Text('行为', style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.related),
                    ...groupedRows(after),
                  ]
                : plainRows(),
          ),
        ),
      ],
    );
  }

  // ════════ 试验四：密度与节奏 ════════

  Widget _buildDensityModule() {
    final theme = Theme.of(context);

    return ContentPanelModule(
      title: '试验四：密度与节奏（局部可密，整页不能挤）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.section,
        children: [
          Text(
            '节奏不是「处处均匀」，而是「同一种关系用同一档」：'
            '标题到内容 8、行与行 8、块与块 24，这样重复下去才是节奏',
            style: theme.textTheme.bodySmall,
          ),
          _buildDensitySpecimen(
            caption: '反例：全程 8，块与块的边界看不出来，整页也没有能喘气的地方',
            leveled: false,
          ),
          _buildDensitySpecimen(
            caption: '正例：块内 8、块间 24、卡片内衬 16；密集的部分照旧，块之间留白',
            leveled: true,
          ),
          _buildRuleRows(_densityRules),
        ],
      ),
    );
  }

  Widget _buildDensitySpecimen({
    required String caption,
    required bool leveled,
  }) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final blockGap = leveled ? AppSpacing.block : AppSpacing.related;
    final blocks = [
      (title: '位置', rows: ['当前版本', '数据目录']),
      (title: '行为', rows: ['启动时检查更新', '下载镜像']),
      (title: '内存', rows: ['上限 4 GB', '自动分配']),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.related,
      children: [
        Text(
          caption,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.itemSecondary,
          ),
        ),
        CopperCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(AppSpacing.section),
          borderRadius: AppRadius.itemShape,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0) SizedBox(height: blockGap),
                Text(blocks[i].title, style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.related),
                for (final row in blocks[i].rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.related),
                    child: Text(row, style: theme.textTheme.bodyMedium),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ════════ 试验五：空态与状态设计 ════════

  Widget _buildStatusModule() {
    final theme = Theme.of(context);

    return ContentPanelModule(
      title: '试验五：空态与状态设计',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.section,
        children: [
          Text(
            '空态不是「暂无数据」四个字：它要说清这是什么、怎么才会有、以及现在就能做的那一步；'
            '元素左对齐成一块，动作用三级重量里的一个 primary',
            style: theme.textTheme.bodySmall,
          ),
          _buildStatusSpecimen(
            caption: '反例：居中大图 + 「暂无数据」，既没说怎么办也没给出路',
            correct: false,
          ),
          _buildStatusSpecimen(
            caption: '正例：标题写正面表述、正文说清下一步、主行动唯一、次行动降到三级',
            correct: true,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.related,
            children: [
              Text('其余状态的要点', style: theme.textTheme.titleSmall),
              for (final line in _stateNotes)
                Text('· $line', style: theme.textTheme.bodySmall),
            ],
          ),
          _buildRuleRows(_statusRules),
        ],
      ),
    );
  }

  Widget _buildStatusSpecimen({
    required String caption,
    required bool correct,
  }) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.related,
      children: [
        Text(
          caption,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.itemSecondary,
          ),
        ),
        CopperCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(AppSpacing.section),
          borderRadius: AppRadius.itemShape,
          child: correct
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.related,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: AppIconSize.large,
                      color: colors.itemHint,
                    ),
                    Text('还没有添加任何版本', style: theme.textTheme.titleMedium),
                    Text(
                      '从官方仓库下载一个版本，或导入你已有的本体；装好就能直接启动，'
                      '存档与模组都在版本目录里',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.itemSecondary,
                      ),
                    ),
                    Wrap(
                      spacing: AppSpacing.related,
                      runSpacing: AppSpacing.related,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconTextButton(
                          icon: Icons.download,
                          content: '下载版本',
                          weight: ActionWeight.primary,
                          onTap: () {},
                        ),
                        IconTextButton(
                          icon: Icons.folder_open,
                          content: '导入本地本体',
                          weight: ActionWeight.tertiary,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    spacing: AppSpacing.related,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: AppIconSize.hero,
                        color: colors.itemHint,
                      ),
                      Text('暂无数据', style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// 只用于对照的实验按钮：可指定底与字，用来比较主行动在浅色下的几种取法
  Widget _buildTintedAction({
    required Color background,
    required Color foreground,
    required String label,
  }) {
    final theme = Theme.of(context);

    return ReboundButton(
      backgroundColor: background,
      borderRadius: AppRadius.controlShape,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.section,
        vertical: AppSpacing.related,
      ),
      onTap: () {},
      child: DefaultTextStyle(
        style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
          color: foreground,
        ),
        child: IconTheme(
          data: IconTheme.of(
            context,
          ).copyWith(color: foreground, size: AppIconSize.item),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpacing.related,
            children: [const Icon(Icons.play_arrow), Text(label)],
          ),
        ),
      ),
    );
  }

  /// 规则行：左边出处、右边原文结论
  Widget _buildRuleRows(List<({String source, String finding})> rules) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.group,
      children: [
        Text('依据', style: theme.textTheme.titleSmall),
        for (final item in rules)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.group,
            children: [
              SizedBox(
                width: _labelWidth,
                child: Text(item.source, style: theme.textTheme.titleSmall),
              ),
              Expanded(
                child: Text(item.finding, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
      ],
    );
  }
}
