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
    this.padding,
  });

  final TemplateSkin skin;
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final background = selected ? skin.selected : Colors.transparent;
    return ReboundContainer(
      onTap: onTap,
      pressedScale: 0.995,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      backgroundColor: background,
      hoverColor: skin.hoverOn(background),
      highlightColor: skin.pressedOn(background),
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
  });

  final TemplateSkin skin;
  final String title;
  final String? desc;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          title,
          style: TemplateType.item.copyWith(color: skin.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (desc != null)
          Text(
            desc!,
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
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
  });

  final TemplateSkin skin;
  final String title;
  final String desc;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: TemplateTwoLine(skin: skin, title: title, desc: desc),
          ),
          const SizedBox(width: TemplateSpace.lg),
          TemplateSwitch(skin: skin, value: value, onTap: onTap),
        ],
      ),
    );
  }
}

/// 按钮：几何完全一样，只差底色与前景
class TemplateButton extends StatelessWidget {
  const TemplateButton({
    super.key,
    required this.skin,
    required this.label,
    required this.icon,
    required this.kind,
    this.onTap,
  });

  final TemplateSkin skin;
  final String label;
  final IconData icon;
  final TemplateButtonKind kind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (kind) {
      TemplateButtonKind.solid => (skin.accent, skin.onAccent),
      TemplateButtonKind.plain => (skin.raised, skin.textPrimary),
      TemplateButtonKind.quiet => (Colors.transparent, skin.textSecondary),
      TemplateButtonKind.danger => (Colors.transparent, skin.dangerText),
    };
    // 实心上的状态要更明显，而且是「压暗」而不是按主题方向（见 solidHoverOn）
    final solid = kind == TemplateButtonKind.solid;

    return ReboundButton(
      onTap: onTap ?? () {},
      backgroundColor: background,
      hoverColor: solid
          ? skin.solidHoverOn(background)
          : skin.hoverOn(background),
      highlightColor: solid
          ? skin.solidPressedOn(background)
          : skin.pressedOn(background),
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.lg,
        vertical: TemplateSpace.sm + 1,
      ),
      child: DefaultTextStyle(
        style: TemplateType.item.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
        child: IconTheme(
          data: IconThemeData(color: foreground, size: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: TemplateSpace.sm,
            children: [Icon(icon), Text(label)],
          ),
        ),
      ),
    );
  }
}

/// 开关：轨道带描边（关着的时候也要认得出来，1.4.11 那条 3:1）
class TemplateSwitch extends StatelessWidget {
  const TemplateSwitch({
    super.key,
    required this.skin,
    required this.value,
    required this.onTap,
  });

  final TemplateSkin skin;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ReboundContainer(
      onTap: onTap,
      pressedScale: 0.94,
      borderRadius: BorderRadius.circular(TemplateRadius.pill),
      backgroundColor: value ? skin.accent : skin.sunken,
      hoverColor: skin.hoverOn(value ? skin.accent : skin.sunken),
      highlightColor: skin.pressedOn(value ? skin.accent : skin.sunken),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 40,
        height: 22,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TemplateRadius.pill),
          border: value ? null : Border.all(color: skin.controlBorder),
        ),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: value ? skin.onAccent : skin.textTertiary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// 分段选择：单选语义就用它，别拿复选框手拼
class TemplateSegment extends StatelessWidget {
  const TemplateSegment({
    super.key,
    required this.skin,
    required this.options,
    required this.value,
    required this.onTap,
  });

  final TemplateSkin skin;
  final List<String> options;
  final int value;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(TemplateSpace.xs),
      decoration: BoxDecoration(
        color: skin.sunken,
        borderRadius: BorderRadius.circular(
          TemplateRadius.control + TemplateSpace.xs,
        ),
        border: Border.all(color: skin.controlBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: ReboundContainer(
                onTap: () => onTap(i),
                borderRadius: BorderRadius.circular(TemplateRadius.control),
                // 选中的那一格用抬升档：暗色里控件面（凹槽档）比卡面亮，选中要更亮一层
                backgroundColor: value == i ? skin.raised : Colors.transparent,
                hoverColor: skin.hoverOn(
                  value == i ? skin.raised : Colors.transparent,
                ),
                highlightColor: skin.pressedOn(
                  value == i ? skin.raised : Colors.transparent,
                ),
                padding: const EdgeInsets.symmetric(vertical: TemplateSpace.sm),
                child: Text(
                  options[i],
                  textAlign: TextAlign.center,
                  style: TemplateType.item.copyWith(
                    color: value == i ? skin.textPrimary : skin.textSecondary,
                    fontWeight: value == i ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
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
  });

  final TemplateSkin skin;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ReboundContainer(
      onTap: onTap ?? () {},
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      backgroundColor: skin.sunken,
      hoverColor: skin.hoverOn(skin.sunken),
      highlightColor: skin.pressedOn(skin.sunken),
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.lg,
        vertical: TemplateSpace.md,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: TemplateSpace.sm,
        children: [
          Icon(icon, size: 18, color: skin.textSecondary),
          Text(
            label,
            style: TemplateType.item.copyWith(color: skin.textSecondary),
          ),
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
    this.labelWidth = 150,
  });

  final TemplateSkin skin;
  final String title;
  final String value;
  final VoidCallback? onTap;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              title,
              style: TemplateType.item.copyWith(color: skin.textPrimary),
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
                border: Border.all(color: skin.controlBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: TemplateType.item.copyWith(
                        color: skin.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.expand_more, size: 18, color: skin.textSecondary),
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
  });

  final TemplateSkin skin;
  final double value;
  final double height;

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
              child: ColoredBox(color: skin.accent),
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
  });

  final TemplateSkin skin;
  final String title;
  final double value;
  final String label;
  final ValueChanged<double>? onChanged;
  final int divisions;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.md,
        children: [
          Row(
            children: [
              Expanded(
                child: TemplateTwoLine(skin: skin, title: title),
              ),
              const SizedBox(width: TemplateSpace.lg),
              Text(
                label,
                style: TemplateType.item.copyWith(
                  color: skin.textPrimary,
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
          if (onChanged == null || width <= 0) return;
          final raw = (dx / width).clamp(0.0, 1.0);
          final stepped = divisions <= 1
              ? raw
              : (raw * divisions).roundToDouble() / divisions;
          onChanged!(stepped);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (detail) => update(detail.localPosition.dx),
          onHorizontalDragUpdate: (detail) => update(detail.localPosition.dx),
          child: SizedBox(
            height: 24,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                TemplateProgressBar(skin: skin, value: value, height: 6),
                // 滑块：位置跟着值走
                Positioned(
                  left: (width - 16) * value.clamp(0.0, 1.0),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: skin.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: skin.accent, width: 2),
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
  });

  final TemplateSkin skin;
  final String title;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.sm,
        children: [
          Text(
            title,
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
          TextField(
            controller: controller,
            style: TemplateType.item.copyWith(color: skin.textPrimary),
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
            ),
          ),
        ],
      ),
    );
  }
}
