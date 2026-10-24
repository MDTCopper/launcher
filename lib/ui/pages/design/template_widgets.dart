import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';

/// 参考模版的组件层：**皮肤（[TemplateSkin]）+ 这一层 = 要搬进 Copper 的东西**
///
/// 交互一律走项目的 rebound（[ReboundContainer] / [ReboundButton]），
/// 颜色全部由 [TemplateSkin] 显式传入 —— 不读 `AppColors`，因此可以脱离原皮肤试版

/// 按钮的四种量级：实心主行动 / 中性 / 安静 / 破坏性
enum TemplateButtonKind { solid, plain, quiet, danger }

/// 分组卡：标题**在卡外**（2026-10-05 用户先问「是否应该把标题再融入 card」、
/// 试过之后要求「标题还是移出去」⇒ 回到卡外，标题贴左 4、与卡相距 8）
///
/// 三条几何规则：
/// ① **卡默认占满宽度** —— 卡宽跟着内容走时，同一页的卡宽窄不一、左边缘参差
///    （用户 2026-10-05「内容板应该默认被撑大」）
/// ② **卡内衬统一 12**（原来是「行卡 8 / 内容卡 16」两种）—— 两种内衬会让同一页的
///    卡的边距不在同一条线上
/// ③ 标题在卡外**作为组标签**：它与卡的 8px 间距在表达「这个标题管住这张卡」，
///    行卡里行的文字比卡边再深 12（那是给行自己的圆角悬停块留的）
class TemplateSection extends StatelessWidget {
  const TemplateSection({
    super.key,
    required this.skin,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.all(TemplateSpace.md),
  });

  final TemplateSkin skin;
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // 卡间距：本组件只给 12，外面 `ListContentPanel` 默认还会再给 12
    // ⇒ 卡底到下一张卡合计 24（组间），这是规范里定下的组间距离。
    // **改一边要改另一边**，别只改这里让两组加起来变成 36（2026-10-05 用户指出过大）
    return Padding(
      padding: const EdgeInsets.only(bottom: TemplateSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: TemplateSpace.xs),
              child: Text(
                title!,
                style: TemplateType.section.copyWith(color: skin.textPrimary),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: skin.surface,
              borderRadius: BorderRadius.circular(TemplateRadius.card),
              border: Border.all(color: skin.border),
              boxShadow: [
                BoxShadow(
                  color: skin.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}

/// 卡内的一行：走 rebound 的回弹与悬停，底色按状态给
class TemplateRow extends StatelessWidget {
  const TemplateRow({
    super.key,
    required this.skin,
    required this.child,
    this.onTap,
    this.selected = false,
    this.enabled = true,
    this.padding,
  });

  final TemplateSkin skin;
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final background = selected ? skin.selected : Colors.transparent;
    return ReboundContainer(
      onTap: enabled ? onTap : null,
      pressedScale: 0.995,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      backgroundColor: background,
      // 禁用时连悬停都不回应；rebound 的悬停层与 onTap 无关，只看 hoverColor
      hoverColor: enabled ? skin.hoverOn(background) : Colors.transparent,
      highlightColor: enabled ? skin.pressedOn(background) : Colors.transparent,
      padding:
          padding ??
          const EdgeInsets.symmetric(
            horizontal: TemplateSpace.md,
            vertical: TemplateSpace.md,
          ),
      child: child,
    );
  }
}

/// 标题 + 说明两行：条目、槽位、快照都用它
class TemplateTwoLine extends StatelessWidget {
  const TemplateTwoLine({
    super.key,
    required this.skin,
    required this.title,
    this.desc,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final String title;
  final String? desc;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          title,
          style: TemplateType.item.copyWith(
            color: enabled ? skin.textPrimary : skin.textDisabled,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (desc != null)
          Text(
            desc!,
            style: TemplateType.caption.copyWith(
              color: enabled ? skin.textTertiary : skin.textDisabled,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

/// 只读的键值行：左标签、右值
class TemplateKeyRow extends StatelessWidget {
  const TemplateKeyRow({
    super.key,
    required this.skin,
    required this.title,
    required this.value,
  });

  final TemplateSkin skin;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      child: Row(
        children: [
          Expanded(
            child: TemplateTwoLine(skin: skin, title: title),
          ),
          const SizedBox(width: TemplateSpace.lg),
          Flexible(
            child: Text(
              value,
              style: TemplateType.item.copyWith(color: skin.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// 开关行：标题 + 说明 + 右侧开关
class TemplateSwitchRow extends StatelessWidget {
  const TemplateSwitchRow({
    super.key,
    required this.skin,
    required this.title,
    required this.desc,
    required this.value,
    required this.onTap,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final String title;
  final String desc;
  final bool value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      onTap: enabled ? onTap : null,
      enabled: enabled,
      child: Row(
        children: [
          Expanded(
            child: TemplateTwoLine(
              skin: skin,
              title: title,
              desc: desc,
              enabled: enabled,
            ),
          ),
          const SizedBox(width: TemplateSpace.lg),
          TemplateSwitch(
            skin: skin,
            value: value,
            onTap: onTap,
            enabled: enabled,
          ),
        ],
      ),
    );
  }
}

/// 四档的**面**：实心 = 主题色底 + 其上文字；标准 = 控件面；安静 = 无面；破坏 = 无面 + 危险文字。
/// **只有实心带主题色**（用户 2026-10-24 定）
///
/// 禁用态：实心留 12% 的主题色（[TemplateSkin.solidDisabledSurface]）、标准比控件面暗一档
/// （[TemplateSkin.standardDisabledSurface]）——两块要分得开，不然禁用的主行动和次级行动一模一样；
/// 安静 / 破坏禁用时只剩 38% 的字
class TemplateButton extends StatelessWidget {
  const TemplateButton({
    super.key,
    required this.skin,
    required this.label,
    required this.icon,
    required this.kind,
    this.onTap,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final String label;
  final IconData icon;
  final TemplateButtonKind kind;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (kind) {
      TemplateButtonKind.solid =>
        enabled
            ? (skin.accent, skin.onAccent)
            : (skin.solidDisabledSurface, skin.textDisabled),
      TemplateButtonKind.plain => (
        enabled ? skin.sunken : skin.standardDisabledSurface,
        enabled ? skin.textPrimary : skin.textDisabled,
      ),
      TemplateButtonKind.quiet => (
        Colors.transparent,
        enabled ? skin.textSecondary : skin.textDisabled,
      ),
      TemplateButtonKind.danger => (
        Colors.transparent,
        enabled ? skin.dangerText : skin.textDisabled,
      ),
    };
    // 实心上的状态要更明显，而且是「压暗」而不是按主题方向（见 solidHoverOn）
    final solid = kind == TemplateButtonKind.solid && enabled;

    final button = ReboundButton(
      onTap: enabled ? (onTap ?? () {}) : null,
      backgroundColor: background,
      hoverColor: !enabled
          ? Colors.transparent
          : solid
          ? skin.solidHoverOn(background)
          : skin.hoverOn(background),
      highlightColor: !enabled
          ? Colors.transparent
          : solid
          ? skin.solidPressedOn(background)
          : skin.pressedOn(background),
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.lg,
        vertical: TemplateSpace.sm + 1,
      ),
      // 文字样式走 Text.style 合并环境样式；整层换 DefaultTextStyle 会把字体族一起丢掉
      child: IconTheme(
        data: IconThemeData(color: foreground, size: 18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: TemplateSpace.sm,
          children: [
            Icon(icon),
            Text(
              label,
              style: TemplateType.item.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );

    return button;
  }
}

/// 开关：轨道带描边（关着的时候也要认得出来，1.4.11 那条 3:1）
class TemplateSwitch extends StatelessWidget {
  const TemplateSwitch({
    super.key,
    required this.skin,
    required this.value,
    required this.onTap,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final bool value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final track = enabled && value ? skin.accent : skin.sunken;
    return ReboundContainer(
      onTap: enabled ? onTap : null,
      pressedScale: 0.94,
      borderRadius: BorderRadius.circular(TemplateRadius.pill),
      backgroundColor: track,
      hoverColor: enabled ? skin.hoverOn(track) : Colors.transparent,
      highlightColor: enabled ? skin.pressedOn(track) : Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 40,
        height: 22,
        padding: const EdgeInsets.all(3),
        // 禁用时仍按值摆滑块：位置本身就是开关的状态，不能因为不可用把它抹掉
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TemplateRadius.pill),
          border: enabled && value
              ? null
              : Border.all(
                  color: enabled
                      ? skin.controlBorder
                      : skin.controlBorderDisabled,
                ),
        ),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: enabled
                ? (value ? skin.onAccent : skin.textTertiary)
                : skin.textDisabled,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// 单选分段：单选语义就用它，别拿复选框手拼
///
/// 选中格的**面是一道轻渐变**（上亮下暗 = 抬起），三个状态改变这道渐变而不是叠色：
/// 悬停整体深/浅一档、**按下把渐变反过来**（上暗下亮 = 压进去）。
/// 这样按下与悬停的区别是「光的方向」而不是明度差 —— 凹槽底与选中格本来只差 8 个 tone，
/// 继续靠压暗做按下就会撞上凹槽底，看着既糊又怪
class TemplateSegment extends StatelessWidget {
  const TemplateSegment({
    super.key,
    required this.skin,
    required this.options,
    required this.value,
    required this.onTap,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final List<String> options;
  final int value;
  final void Function(int index) onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(TemplateSpace.xs),
      decoration: BoxDecoration(
        color: skin.sunken,
        borderRadius: BorderRadius.circular(
          TemplateRadius.control + TemplateSpace.xs,
        ),
        border: Border.all(
          color: enabled ? skin.controlBorder : skin.controlBorderDisabled,
        ),
      ),
      child: Row(
        spacing: TemplateSpace.xs,
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: _SegmentPill(
                skin: skin,
                label: options[i],
                selected: value == i,
                enabled: enabled,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
  }
}

/// 分段的单格：自己跟踪悬停 / 按下，好让三态各自给一道渐变
class _SegmentPill extends StatefulWidget {
  const _SegmentPill({
    required this.skin,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final TemplateSkin skin;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_SegmentPill> createState() => _SegmentPillState();
}

class _SegmentPillState extends State<_SegmentPill> {
  bool _hover = false;

  /// 选中格的渐变两端（tone）：静止 / 悬停
  ///
  /// 取值的两条边界：**最暗的一档不能碰到凹槽底**（亮色底 tone 90 / 暗色底 20，
  /// 最暗只到 95 / 26，实测留 1.1:1 以上），又要看得出变化；
  /// 亮色下选中格已经贴着上限（tone 98），所以变化只能往下走
  ///
  /// **按下不改底色**：点击瞬间把渐变反过来会让整格底色翻个方向，看着像突变；
  /// 按下的反馈只留回弹缩放
  (double, double) get _stops {
    if (widget.skin.dark) return _hover ? (32, 27) : (29, 25);
    return _hover ? (97, 95) : (98, 96);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final selected = widget.selected;
    final enabled = widget.enabled;

    // 需要按悬停换渐变，而 rebound 的悬停是它自己的内部状态（没有回调可用）
    // ⇒ 这里自己监听指针：MouseRegion 是被动观察，不抢点击与回弹
    return MouseRegion(
      onEnter: (_) {
        if (enabled) setState(() => _hover = true);
      },
      onExit: (_) {
        if (enabled) setState(() => _hover = false);
      },
      child: ReboundContainer(
        onTap: enabled ? widget.onTap : null,
        pressedScale: 0.96,
        borderRadius: BorderRadius.circular(TemplateRadius.control),
        backgroundColor: Colors.transparent,
        // 状态由渐变表达，这里不再叠色（叠色正是「融合」的来源）；
        // 主题的水波（splash）也关掉，不然点击瞬间会闪过一层旧强调色
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        // 一律用渐变（未选中＝两端同色的透明/薄底）：同类型之间才插值得平滑，
        // 底色与渐变互换时会硬切
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            vertical: TemplateSpace.sm,
            horizontal: TemplateSpace.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TemplateRadius.control),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: selected
                  ? [skin.neutralTone(_stops.$1), skin.neutralTone(_stops.$2)]
                  : [
                      enabled && _hover
                          ? skin.hoverOn(Colors.transparent)
                          : Colors.transparent,
                      enabled && _hover
                          ? skin.hoverOn(Colors.transparent)
                          : Colors.transparent,
                    ],
            ),
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TemplateType.item.copyWith(
              color: !enabled
                  ? skin.textDisabled
                  : selected
                  ? skin.textPrimary
                  : skin.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// 提示条：靠底色与左边一道强调线，不靠描边把整条圈起来
class TemplateNotice extends StatelessWidget {
  const TemplateNotice({
    super.key,
    required this.skin,
    required this.text,
    this.icon = Icons.info_outline,
  });

  final TemplateSkin skin;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    // 外面不再自带边距：它是卡里的一项，间距由卡片自己（`TemplateSection.spacing`）管
    return DecoratedBox(
      decoration: BoxDecoration(
        color: skin.sunken,
        borderRadius: BorderRadius.circular(TemplateRadius.card),
        border: Border(left: BorderSide(color: skin.accent, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TemplateSpace.lg,
          vertical: TemplateSpace.md,
        ),
        child: Row(
          spacing: TemplateSpace.md,
          children: [
            Icon(icon, size: 18, color: skin.accentText),
            Expanded(
              child: Text(
                text,
                style: TemplateType.caption.copyWith(color: skin.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 快捷入口小方块：并列入口，中性重量
class TemplateShortcut extends StatelessWidget {
  const TemplateShortcut({
    super.key,
    required this.skin,
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? skin.textSecondary : skin.textDisabled;
    return ReboundContainer(
      onTap: enabled ? (onTap ?? () {}) : null,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      backgroundColor: skin.sunken,
      hoverColor: enabled ? skin.hoverOn(skin.sunken) : Colors.transparent,
      highlightColor: enabled
          ? skin.pressedOn(skin.sunken)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.lg,
        vertical: TemplateSpace.md,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: TemplateSpace.sm,
        children: [
          Icon(icon, size: 18, color: foreground),
          Text(label, style: TemplateType.item.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

/// 下拉行：左边标签、右边下拉框（值 + 箭头）
///
/// 模版还没有真正的下拉组件，这里先给它的样子；[onTap] 为空时就是个静态框
class TemplateSelectRow extends StatelessWidget {
  const TemplateSelectRow({
    super.key,
    required this.skin,
    required this.title,
    required this.value,
    this.onTap,
    this.enabled = true,
    this.labelWidth = 150,
  });

  final TemplateSkin skin;
  final String title;
  final String value;
  final VoidCallback? onTap;
  final bool enabled;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      onTap: onTap,
      enabled: enabled,
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              title,
              style: TemplateType.item.copyWith(
                color: enabled ? skin.textPrimary : skin.textDisabled,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: TemplateSpace.lg),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: TemplateSpace.md,
                vertical: TemplateSpace.sm,
              ),
              decoration: BoxDecoration(
                color: skin.sunken,
                borderRadius: BorderRadius.circular(TemplateRadius.control),
                border: Border.all(
                  color: enabled
                      ? skin.controlBorder
                      : skin.controlBorderDisabled,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: TemplateType.item.copyWith(
                        color: enabled ? skin.textPrimary : skin.textDisabled,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.expand_more,
                    size: 18,
                    color: enabled ? skin.textSecondary : skin.textDisabled,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 进度条：细轨 + 实心填充（列表行内与内存占用都用它）
class TemplateProgressBar extends StatelessWidget {
  const TemplateProgressBar({
    super.key,
    required this.skin,
    required this.value,
    this.height = 4,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final double value;
  final double height;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(TemplateRadius.pill),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            ColoredBox(color: skin.sunken, child: const SizedBox.expand()),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(
                color: enabled ? skin.accent : skin.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 滑条行：标题 + 实时值 + 可点可拖的轨道
class TemplateSliderRow extends StatelessWidget {
  const TemplateSliderRow({
    super.key,
    required this.skin,
    required this.title,
    required this.value,
    required this.label,
    this.onChanged,
    this.divisions = 20,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final String title;
  final double value;
  final String label;
  final ValueChanged<double>? onChanged;
  final int divisions;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      enabled: enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.md,
        children: [
          Row(
            children: [
              Expanded(
                child: TemplateTwoLine(
                  skin: skin,
                  title: title,
                  enabled: enabled,
                ),
              ),
              const SizedBox(width: TemplateSpace.lg),
              Text(
                label,
                style: TemplateType.item.copyWith(
                  color: enabled ? skin.textPrimary : skin.textDisabled,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          _buildTrack(),
        ],
      ),
    );
  }

  Widget _buildTrack() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        void update(double dx) {
          if (!enabled || onChanged == null || width <= 0) return;
          final raw = (dx / width).clamp(0.0, 1.0);
          final stepped = divisions <= 1
              ? raw
              : (raw * divisions).roundToDouble() / divisions;
          onChanged!(stepped);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled
              ? (detail) => update(detail.localPosition.dx)
              : null,
          onHorizontalDragUpdate: enabled
              ? (detail) => update(detail.localPosition.dx)
              : null,
          child: SizedBox(
            height: 24,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                TemplateProgressBar(
                  skin: skin,
                  value: value,
                  height: 6,
                  enabled: enabled,
                ),
                // 滑块：位置跟着值走
                Positioned(
                  left: (width - 16) * value.clamp(0.0, 1.0),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: skin.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: enabled
                            ? skin.accent
                            : skin.controlBorderDisabled,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 输入行：标题 + 输入框（聚焦时描边换强调色）
class TemplateInputRow extends StatelessWidget {
  const TemplateInputRow({
    super.key,
    required this.skin,
    required this.title,
    required this.controller,
    this.hint = '',
    this.enabled = true,
  });

  final TemplateSkin skin;
  final String title;
  final TextEditingController controller;
  final String hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      enabled: enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.sm,
        children: [
          Text(
            title,
            style: TemplateType.caption.copyWith(
              color: enabled ? skin.textTertiary : skin.textDisabled,
            ),
          ),
          TextField(
            controller: controller,
            enabled: enabled,
            style: TemplateType.item.copyWith(
              color: enabled ? skin.textPrimary : skin.textDisabled,
            ),
            cursorColor: skin.accent,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TemplateType.item.copyWith(color: skin.textTertiary),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: TemplateSpace.md,
                vertical: TemplateSpace.md,
              ),
              filled: true,
              fillColor: skin.sunken,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TemplateRadius.control),
                borderSide: BorderSide(color: skin.controlBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TemplateRadius.control),
                borderSide: BorderSide(color: skin.accent, width: 2),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TemplateRadius.control),
                borderSide: BorderSide(color: skin.controlBorderDisabled),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
