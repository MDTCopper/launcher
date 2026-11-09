import 'package:copper_launcher/ui/components/core/app_button.dart';
import 'package:copper_launcher/ui/components/core/app_checkbox.dart';
import 'package:copper_launcher/ui/components/core/app_icon_button.dart';
import 'package:copper_launcher/ui/components/core/app_segment.dart';
import 'package:copper_launcher/ui/components/core/app_switch.dart';
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

  TemplateSkin get skin => widget.skin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TemplateSpace.lg,
      children: [
        _lead(),
        _note(
          'AppButton',
          '三档观感：solid（主行动，带 0.97 轻回弹）/ plain（次级）/ quiet（静音）；危险态换错误色',
        ),
        _group(
          Wrap(
            spacing: TemplateSpace.sm,
            runSpacing: TemplateSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppButton(label: '主按钮', icon: Icons.play_arrow, onTap: () {}),
              AppButton(
                label: '次按钮',
                icon: Icons.folder_open,
                kind: AppButtonKind.plain,
                onTap: () {},
              ),
              AppButton(
                label: '静音',
                icon: Icons.copy,
                kind: AppButtonKind.quiet,
                onTap: () {},
              ),
              AppButton(
                label: '危险',
                icon: Icons.delete_outline,
                danger: true,
                onTap: () {},
              ),
              const AppButton(label: '禁用', icon: Icons.block, enabled: false),
              AppButton(
                label: '禁用次按钮',
                icon: Icons.block,
                kind: AppButtonKind.plain,
                enabled: false,
              ),
            ],
          ),
        ),
        _note('AppButton（撑满）', 'expanded 用于任务卡底部那排等宽按钮'),
        _group(
          Row(
            spacing: TemplateSpace.sm,
            children: [
              Expanded(
                child: AppButton(
                  label: '启动',
                  icon: Icons.play_arrow,
                  expanded: true,
                  onTap: () {},
                ),
              ),
              Expanded(
                child: AppButton(
                  label: '取消',
                  icon: Icons.close,
                  kind: AppButtonKind.plain,
                  expanded: true,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
        _note('AppIconButton', '方形热区 + 变色反馈；可带底色（plain）或纯静音；可选悬停提示'),
        _group(
          Wrap(
            spacing: TemplateSpace.sm,
            runSpacing: TemplateSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppIconButton(icon: Icons.search, hint: '搜索', onTap: () {}),
              AppIconButton(icon: Icons.tune, plain: true, onTap: () {}),
              AppIconButton(icon: Icons.refresh, selected: true, onTap: () {}),
              const AppIconButton(icon: Icons.block, enabled: false),
              const AppIconButton(icon: Icons.more_horiz, size: 24),
            ],
          ),
        ),
        _note('AppSegment', '单选分段，单段可禁用；凹槽底 + 选中格，按压只变色'),
        _group(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TemplateSpace.sm,
            children: [
              AppSegment(
                options: const ['紧凑', '列表', '网格'],
                value: _tab,
                onChanged: (index) => setState(() => _tab = index),
              ),
              AppSegment(
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
              AppSegment(
                options: const ['禁用', '状态'],
                value: 0,
                enabled: false,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
        _note('AppSwitch', '槽实色 / 圆球亮色、球内开=勾关=叉；只有圆球位置做位移，颜色瞬切'),
        _group(
          Row(
            spacing: TemplateSpace.xl,
            children: [
              AppSwitch(
                value: _switchOn,
                onChanged: (value) => setState(() => _switchOn = value),
              ),
              AppSwitch(
                value: _switchOff,
                onChanged: (value) => setState(() => _switchOff = value),
              ),
              const AppSwitch(value: false, enabled: false),
            ],
          ),
        ),
        _note('AppCheckbox', '方框 + 勾，可带文字 / 图标；整行可点'),
        _group(
          Wrap(
            spacing: TemplateSpace.lg,
            runSpacing: TemplateSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppCheckbox(
                value: _checked,
                label: '带文字',
                onChanged: (value) => setState(() => _checked = value),
              ),
              AppCheckbox(
                value: !_checked,
                icon: Icons.star_outline,
                onChanged: (value) => setState(() => _checked = !value),
              ),
              const AppCheckbox(value: false, label: '禁用', enabled: false),
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
          '按压统一走 AppPressable（变色、不缩放）',
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
