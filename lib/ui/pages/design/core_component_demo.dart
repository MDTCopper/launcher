import 'package:copper_launcher/ui/components/core/copper_button.dart';
import 'package:copper_launcher/ui/components/core/copper_checkbox.dart';
import 'package:copper_launcher/ui/components/core/copper_icon_button.dart';
import 'package:copper_launcher/ui/components/core/copper_notice.dart';
import 'package:copper_launcher/ui/components/core/copper_progress.dart';
import 'package:copper_launcher/ui/components/core/copper_segment.dart';
import 'package:copper_launcher/ui/components/core/copper_switch.dart';
import 'package:copper_launcher/ui/components/core/copper_text_field.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
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
          'CopperButton',
          '三档观感：solid（主行动，带 0.97 轻回弹）/ plain（次级）/ quiet（静音）；危险态换错误色',
        ),
        _group(
          Wrap(
            spacing: TemplateSpace.sm,
            runSpacing: TemplateSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CopperButton(label: '主按钮', icon: Icons.play_arrow, onTap: () {}),
              CopperButton(
                label: '次按钮',
                icon: Icons.folder_open,
                kind: CopperButtonKind.plain,
                onTap: () {},
              ),
              CopperButton(
                label: '静音',
                icon: Icons.copy,
                kind: CopperButtonKind.quiet,
                onTap: () {},
              ),
              CopperButton(
                label: '危险',
                icon: Icons.delete_outline,
                danger: true,
                onTap: () {},
              ),
              const CopperButton(
                label: '禁用',
                icon: Icons.block,
                enabled: false,
              ),
              CopperButton(
                label: '禁用次按钮',
                icon: Icons.block,
                kind: CopperButtonKind.plain,
                enabled: false,
              ),
            ],
          ),
        ),
        _note('CopperButton（撑满）', 'expanded 用于任务卡底部那排等宽按钮'),
        _group(
          Row(
            spacing: TemplateSpace.sm,
            children: [
              Expanded(
                child: CopperButton(
                  label: '启动',
                  icon: Icons.play_arrow,
                  expanded: true,
                  onTap: () {},
                ),
              ),
              Expanded(
                child: CopperButton(
                  label: '取消',
                  icon: Icons.close,
                  kind: CopperButtonKind.plain,
                  expanded: true,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
        _note('CopperIconButton', '方形热区 + 变色反馈；可带底色（plain）或纯静音；可选悬停提示'),
        _group(
          Wrap(
            spacing: TemplateSpace.sm,
            runSpacing: TemplateSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CopperIconButton(icon: Icons.search, hint: '搜索', onTap: () {}),
              CopperIconButton(icon: Icons.tune, plain: true, onTap: () {}),
              CopperIconButton(
                icon: Icons.refresh,
                selected: true,
                onTap: () {},
              ),
              const CopperIconButton(icon: Icons.block, enabled: false),
              const CopperIconButton(icon: Icons.more_horiz, size: 24),
            ],
          ),
        ),
        _note('CopperSegment', '单选分段，单段可禁用；凹槽底 + 选中格，按压只变色'),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.sm,
            children: [
              CopperSegment(
                options: const ['紧凑', '列表', '网格'],
                value: _tab,
                onChanged: (index) => setState(() => _tab = index),
              ),
              CopperSegment(
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
              CopperSegment(
                options: const ['禁用', '状态'],
                value: 0,
                enabled: false,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
        _note('CopperSwitch', '槽实色 / 圆球亮色、球内开=勾关=叉；只有圆球位置做位移，颜色瞬切'),
        _group(
          Row(
            spacing: TemplateSpace.xl,
            children: [
              CopperSwitch(
                value: _switchOn,
                onChanged: (value) => setState(() => _switchOn = value),
              ),
              CopperSwitch(
                value: _switchOff,
                onChanged: (value) => setState(() => _switchOff = value),
              ),
              const CopperSwitch(value: false, enabled: false),
            ],
          ),
        ),
        _note('CopperTextField', '单行 / 多行、标签、错误态、前后缀图标；聚焦直接换描边，不做颜色插值'),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.md,
            children: [
              CopperTextField(
                controller: _search,
                hint: '搜索模组 / 版本',
                prefixIcon: Icons.search,
              ),
              CopperTextField(
                controller: _error,
                label: '版本号',
                hint: '例如 v160.7',
                error: '这个版本号不存在',
              ),
              CopperTextField(
                controller: _disabled,
                label: '禁用',
                hint: '不可编辑',
                enabled: false,
              ),
            ],
          ),
        ),
        _note('CopperNotice', '五种语气；左侧一道语义色 + 淡底，可带标题 / 行内动作 / 关闭'),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.sm,
            children: [
              const CopperNotice(
                text: '普通说明：这里有新的版本可以下载',
                icon: Icons.info_outline,
              ),
              const CopperNotice(
                title: '下载完成',
                text: 'Mindustry 6.0 已就绪',
                tone: CopperNoticeTone.success,
                icon: Icons.check_circle_outline,
              ),
              const CopperNotice(
                title: '存储空间不足',
                text: '至少还需要 1.2 GB 空间',
                tone: CopperNoticeTone.warning,
                icon: Icons.warning_amber_outlined,
              ),
              CopperNotice(
                title: '启动失败',
                text: '游戏进程异常退出，查看日志',
                tone: CopperNoticeTone.danger,
                icon: Icons.error_outline,
                onClose: () {},
                action: CopperButton(
                  label: '日志',
                  icon: Icons.description_outlined,
                  kind: CopperButtonKind.quiet,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
        _note('CopperProgress', '确定进度（带百分比）与不确定进度；只动位置，颜色不插值'),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.md,
            children: [
              const CopperProgress(value: 0.42, label: '42%'),
              const CopperProgress(value: 0.78),
              const CopperProgress(),
            ],
          ),
        ),
        _note('CopperCheckbox', '方框 + 勾，可带文字 / 图标；整行可点'),
        _group(
          Wrap(
            spacing: TemplateSpace.lg,
            runSpacing: TemplateSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CopperCheckbox(
                value: _checked,
                label: '带文字',
                onChanged: (value) => setState(() => _checked = value),
              ),
              CopperCheckbox(
                value: !_checked,
                icon: Icons.star_outline,
                onChanged: (value) => setState(() => _checked = !value),
              ),
              const CopperCheckbox(value: false, label: '禁用', enabled: false),
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
          '按压统一走 CopperPressable（变色、不缩放）',
          style: TemplateType.caption.copyWith(
            color: skin.textTertiary,
            height: 18 / 12,
          ),
        ),
      ],
    );
  }

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
