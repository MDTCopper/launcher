import 'package:copper_launcher/ui/components/core/cu_button.dart';
import 'package:copper_launcher/ui/components/core/cu_checkbox.dart';
import 'package:copper_launcher/ui/components/core/cu_content_panel.dart';
import 'package:copper_launcher/ui/components/core/cu_icon_button.dart';
import 'package:copper_launcher/ui/components/core/cu_list_tile.dart';
import 'package:copper_launcher/ui/components/core/cu_log_tile.dart';
import 'package:copper_launcher/ui/components/core/cu_notice.dart';
import 'package:copper_launcher/ui/components/core/cu_progress.dart';
import 'package:copper_launcher/ui/components/core/cu_segment.dart';
import 'package:copper_launcher/ui/components/core/cu_select.dart';
import 'package:copper_launcher/ui/components/rebound/cu_slider.dart';
import 'package:copper_launcher/ui/components/core/cu_setting_row.dart';
import 'package:copper_launcher/ui/components/core/cu_switch.dart';
import 'package:copper_launcher/ui/components/core/cu_text_field.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/ui/util/toast.dart';
import 'package:copper_launcher/ui/pages/design/template_widgets.dart';
import 'package:flutter/material.dart';

/// 内核组件（`lib/ui/components/core/`）样张：只吃 AppColors + 几何令牌
///
/// 这里同时是「旧组件 → 新内核」的对照：上面是内核，下面是等价旧组件
class CoreComponentDemo extends StatefulWidget {
  const CoreComponentDemo({super.key, required this.skin});

  final TemplateSkin skin;

  @override
  State<CoreComponentDemo> createState() => _CoreComponentDemoState();
}

class _CoreComponentDemoState extends State<CoreComponentDemo> {
  bool _switchOn = true;
  bool _switchOff = false;
  bool _checked = true;
  int _tab = 1;
  int _iconTab = 0;
  String _sort = '最新发布';
  double _scale = 0.5;
  final _search = TextEditingController(text: 'Mindustry');
  final _error = TextEditingController(text: 'v999');
  final _disabled = TextEditingController(text: '不可编辑');

  TemplateSkin get skin => widget.skin;

  @override
  void dispose() {
    _search.dispose();
    _error.dispose();
    _disabled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.lg,
      children: [
        _lead(),
        _note(
          'CuButton',
          '三档观感：solid（主行动，带 0.97 轻回弹）/ plain（次级）/ quiet（静音）；危险态换错误色',
        ),
        _group(
          Wrap(
            spacing: TemplateSpace.sm,
            runSpacing: TemplateSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CuButton(label: '主按钮', icon: Icons.play_arrow, onTap: () {}),
              CuButton(
                label: '次按钮',
                icon: Icons.folder_open,
                kind: CuButtonKind.plain,
                onTap: () {},
              ),
              CuButton(
                label: '静音',
                icon: Icons.copy,
                kind: CuButtonKind.quiet,
                onTap: () {},
              ),
              CuButton(
                label: '危险',
                icon: Icons.delete_outline,
                danger: true,
                onTap: () {},
              ),
              const CuButton(label: '禁用', icon: Icons.block, enabled: false),
              CuButton(
                label: '禁用次按钮',
                icon: Icons.block,
                kind: CuButtonKind.plain,
                enabled: false,
              ),
            ],
          ),
        ),
        _note('CuButton（撑满）', 'expanded 用于任务卡底部那排等宽按钮'),
        _group(
          Row(
            spacing: TemplateSpace.sm,
            children: [
              Expanded(
                child: CuButton(
                  label: '启动',
                  icon: Icons.play_arrow,
                  expanded: true,
                  onTap: () {},
                ),
              ),
              Expanded(
                child: CuButton(
                  label: '取消',
                  icon: Icons.close,
                  kind: CuButtonKind.plain,
                  expanded: true,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
        _note('CuIconButton', '方形热区 + 变色反馈；可带底色（plain）或纯静音；可选悬停提示'),
        _group(
          Wrap(
            spacing: TemplateSpace.sm,
            runSpacing: TemplateSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CuIconButton(icon: Icons.search, hint: '搜索', onTap: () {}),
              CuIconButton(icon: Icons.tune, plain: true, onTap: () {}),
              CuIconButton(icon: Icons.refresh, selected: true, onTap: () {}),
              const CuIconButton(icon: Icons.block, enabled: false),
              const CuIconButton(icon: Icons.more_horiz, size: 24),
            ],
          ),
        ),
        _note('CuSegment', '单选分段，单段可禁用；凹槽底 + 选中格，按压只变色'),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.sm,
            children: [
              CuSegment(
                options: const ['紧凑', '列表', '网格'],
                value: _tab,
                onChanged: (index) => setState(() => _tab = index),
              ),
              CuSegment(
                options: const ['全部', '已安装', '有更新'],
                icons: const [
                  Icons.apps,
                  Icons.download_done,
                  Icons.new_releases_outlined,
                ],
                value: _iconTab,
                disabled: const {2},
                onChanged: (index) => setState(() => _iconTab = index),
              ),
              CuSegment(
                options: const ['禁用', '状态'],
                value: 0,
                enabled: false,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
        _note('CuSwitch', '槽实色 / 圆球亮色、球内开=勾关=叉；只有圆球位置做位移，颜色瞬切'),
        _group(
          Row(
            spacing: TemplateSpace.xl,
            children: [
              CuSwitch(
                value: _switchOn,
                onChanged: (value) => setState(() => _switchOn = value),
              ),
              CuSwitch(
                value: _switchOff,
                onChanged: (value) => setState(() => _switchOff = value),
              ),
              const CuSwitch(value: false, enabled: false),
            ],
          ),
        ),
        _note('CuTextField', '单行 / 多行、标签、错误态、前后缀图标；聚焦直接换描边，不做颜色插值'),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.md,
            children: [
              CuTextField(
                controller: _search,
                hint: '搜索模组 / 版本',
                prefixIcon: Icons.search,
              ),
              CuTextField(
                controller: _error,
                label: '版本号',
                hint: '例如 v160.7',
                error: '这个版本号不存在',
              ),
              CuTextField(
                controller: _disabled,
                label: '禁用',
                hint: '不可编辑',
                enabled: false,
              ),
            ],
          ),
        ),
        _note('通知样式', '通知（会堆叠、要看清内容）：右上卡片 / 顶部横条 banner；轻提示 toast 已独立出去'),
        _group(
          Wrap(
            spacing: TemplateSpace.sm,
            runSpacing: TemplateSpace.sm,
            children: [
              CuButton(
                label: '卡片通知',
                icon: Icons.notifications_outlined,
                kind: CuButtonKind.plain,
                onTap: () => addNotice(
                  icon: Icons.check_circle_outline,
                  title: '已保存游戏内身份',
                  content: 'Cubik65536',
                ),
              ),
              CuButton(
                label: 'Banner',
                icon: Icons.campaign_outlined,
                kind: CuButtonKind.plain,
                onTap: () => addNotice(
                  icon: Icons.info_outline,
                  title: '有新版本可用',
                  content: '当前 v160.7，最新 v161.2',
                  style: NoticeStyle.banner,
                ),
              ),
            ],
          ),
        ),
        _note('Toast（轻提示）', '独立浮层，一次一条、底部居中、自动消失；不堆叠、不进通知列表'),
        _group(
          Wrap(
            spacing: TemplateSpace.sm,
            runSpacing: TemplateSpace.sm,
            children: [
              CuButton(
                label: '轻提示',
                icon: Icons.copy,
                kind: CuButtonKind.plain,
                onTap: () => showToast(icon: Icons.copy, text: '房间码已复制'),
              ),
              CuButton(
                label: '长一点',
                icon: Icons.info_outline,
                kind: CuButtonKind.plain,
                onTap: () => showToast(
                  icon: Icons.info_outline,
                  text: '已开始下载 Mindustry 6.0，可在任务里查看进度',
                  duration: const Duration(seconds: 4),
                ),
              ),
            ],
          ),
        ),
        _note(
          'CuContentPanel',
          '标准页面内容卡：CuCard 地基 + 标题行（标题 / 说明 / 右侧动作）+ 统一内衬；flush 用于整块列表',
        ),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.md,
            children: [
              CuContentPanel(
                title: '启动设置',
                subtitle: '修改后下次启动生效',
                trailing: CuButton(
                  label: '重置',
                  kind: CuButtonKind.quiet,
                  onTap: () {},
                ),
                children: [
                  CuSettingRow(
                    title: '自动更新',
                    control: Align(
                      alignment: Alignment.centerRight,
                      child: CuSwitch(
                        value: _switchOn,
                        onChanged: (v) => setState(() => _switchOn = v),
                      ),
                    ),
                  ),
                  CuSettingRow(
                    title: '窗口缩放',
                    control: CuSlider(
                      value: _scale,
                      label: '${(_scale * 100).round()}%',
                      divisions: 20,
                      onChanged: (v) => setState(() => _scale = v),
                    ),
                  ),
                ],
              ),
              CuContentPanel(
                title: '版本列表',
                subtitle: '共 3 个 · 整块列表用 flush',
                flush: true,
                headerDivider: true,
                child: Column(
                  children: [
                    CuListTile(
                      title: const Text('v160.7 Copper'),
                      subtitle: const Text('v160.7'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: skin.border)),
                      ),
                      onTap: () {},
                    ),
                    CuListTile(
                      title: const Text('6.0 Build 123'),
                      subtitle: const Text('v123'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _note('CuNotice', '五种语气；左侧一道语义色 + 淡底，可带标题 / 行内动作 / 关闭'),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.sm,
            children: [
              const CuNotice(
                text: '普通说明：这里有新的版本可以下载',
                icon: Icons.info_outline,
              ),
              const CuNotice(
                title: '下载完成',
                text: 'Mindustry 6.0 已就绪',
                tone: CuNoticeTone.success,
                icon: Icons.check_circle_outline,
              ),
              const CuNotice(
                title: '存储空间不足',
                text: '至少还需要 1.2 GB 空间',
                tone: CuNoticeTone.warning,
                icon: Icons.warning_amber_outlined,
              ),
              CuNotice(
                title: '启动失败',
                text: '游戏进程异常退出，查看日志',
                tone: CuNoticeTone.danger,
                icon: Icons.error_outline,
                onClose: () {},
                action: CuButton(
                  label: '日志',
                  icon: Icons.description_outlined,
                  kind: CuButtonKind.quiet,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
        _note(
          'CuSelect',
          '下拉选择：复用项目 DropdownLayer（展开面板 / 选中态 / 外点关闭都在它那），只套 AppColors 配色',
        ),
        _group(
          Row(
            spacing: TemplateSpace.md,
            children: [
              Expanded(
                child: CuSelect<String>(
                  expanded: true,
                  value: _sort,
                  hint: '排序方式',
                  options: const [
                    CuSelectOption(value: '最新发布', label: '最新发布'),
                    CuSelectOption(
                      value: '下载最多',
                      label: '下载最多',
                      icon: Icons.trending_down,
                    ),
                    CuSelectOption(
                      value: '最近更新',
                      label: '最近更新',
                      icon: Icons.update,
                    ),
                  ],
                  onChanged: (value) => setState(() => _sort = value),
                ),
              ),
              const SizedBox(
                width: 220,
                child: CuSelect<String>(
                  expanded: true,
                  enabled: false,
                  value: null,
                  hint: '禁用状态',
                  options: [],
                  onChanged: _noopString,
                ),
              ),
            ],
          ),
        ),
        _note(
          'CuListTile',
          'leading / 标题 / 副标题 / trailing；可选中、可禁用；分隔线用 decoration 透传',
        ),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CuListTile(
                leading: const Icon(Icons.view_in_ar, size: 20),
                title: const Text('Mindustry 6.0'),
                subtitle: const Text('build 123 · 78.4 MB'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: skin.border)),
                ),
                onTap: () {},
              ),
              CuListTile(
                leading: const Icon(Icons.push_pin_outlined, size: 20),
                title: const Text('选中行'),
                subtitle: const Text('selected 走强调色淡底'),
                trailing: const Icon(Icons.check, size: 18),
                selected: true,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: skin.border)),
                ),
                onTap: () {},
              ),
              const CuListTile(
                leading: Icon(Icons.block, size: 20),
                title: Text('禁用行'),
                subtitle: Text('enable = false'),
                enabled: false,
              ),
            ],
          ),
        ),
        _note('CuSettingRow', '标题固定宽 + 右侧控件；窄窗时标题被挤压，设置行之间标题对齐'),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.md,
            children: [
              CuSettingRow(
                title: '自动更新',
                control: Align(
                  alignment: Alignment.centerRight,
                  child: CuSwitch(
                    value: _switchOn,
                    onChanged: (v) => setState(() => _switchOn = v),
                  ),
                ),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: skin.border)),
                ),
              ),
              CuSettingRow(
                title: '窗口缩放',
                control: CuSlider(
                  value: _scale,
                  label: '${(_scale * 100).round()}%',
                  divisions: 20,
                  onChanged: (v) => setState(() => _scale = v),
                ),
              ),
              CuSettingRow(
                title: '备注',
                description: '仅本地生效',
                control: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '—',
                    style: TemplateType.caption.copyWith(
                      color: skin.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _note('CuLogTile', '日志多样化：四种等级（彩色图标）、可展开等宽详情（可复制）、过程进度、等宽命令输出'),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.xs,
            children: [
              const CuLogTile(
                text: '检查模组更新',
                level: CuLogLevel.info,
                time: '20:01:02',
              ),
              const CuLogTile(
                text: 'Java 运行时校验通过',
                level: CuLogLevel.success,
                time: '20:01:05',
              ),
              const CuLogTile(
                text: '镜像节点响应较慢，已切换到下一个',
                level: CuLogLevel.warning,
                time: '20:01:09',
              ),
              const CuLogTile(
                text: '启动失败：找不到游戏可执行文件',
                level: CuLogLevel.error,
                time: '20:01:12',
              ),
              const CuLogTile(
                text: '下载 Mindustry 6.0 (78.4 MB)',
                level: CuLogLevel.info,
                time: '20:01:20',
                progress: 0.42,
              ),
              CuLogTile(
                text: 'java -jar server.jar',
                level: CuLogLevel.info,
                time: '20:01:31',
                mono: true,
                onCopy: () {},
                detail:
                    '[20:01:31] [main/INFO]: Loading mindustry v160.7\n'
                    '[20:01:31] [main/INFO]: Java 17.0.9 (Eclipse Adoptium)\n'
                    '[20:01:32] [main/WARN]: Mod NewHorizon requires v146+\n'
                    '[20:01:33] [main/ERROR]: Failed to load texture atlas',
              ),
            ],
          ),
        ),
        _note('CuProgress', '确定进度（带百分比）与不确定进度；只动位置，颜色不插值'),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.md,
            children: [
              const CuProgress(value: 0.42, label: '42%'),
              const CuProgress(value: 0.78),
              const CuProgress(),
            ],
          ),
        ),
        _note('CuCheckbox', '方框 + 勾，可带文字 / 图标；整行可点'),
        _group(
          Wrap(
            spacing: TemplateSpace.lg,
            runSpacing: TemplateSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CuCheckbox(
                value: _checked,
                label: '带文字',
                onChanged: (value) => setState(() => _checked = value),
              ),
              CuCheckbox(
                value: !_checked,
                icon: Icons.star_outline,
                onChanged: (value) => setState(() => _checked = !value),
              ),
              const CuCheckbox(value: false, label: '禁用', enabled: false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lead() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TemplateSpace.xs,
      children: [
        Text(
          '内核组件（core）',
          style: TemplateType.page.copyWith(color: skin.textPrimary),
        ),
        Text(
          'lib/ui/components/core/ —— 只吃 AppColors + DesignSystem 几何，不引设计层皮肤；'
          '按压统一走 CuPressable（变色、不缩放）',
          style: TemplateType.caption.copyWith(
            color: skin.textTertiary,
            height: 18 / 12,
          ),
        ),
      ],
    );
  }

  static void _noopString(String _) {}

  Widget _note(String title, String desc) {
    return TemplateNotice(
      skin: skin,
      tone: TemplateNoticeTone.note,
      title: title,
      text: desc,
      icon: Icons.widgets_outlined,
    );
  }

  Widget _group(Widget child) {
    return TemplateCard(
      skin: skin,
      padding: const EdgeInsets.all(TemplateSpace.md),
      child: child,
    );
  }
}
