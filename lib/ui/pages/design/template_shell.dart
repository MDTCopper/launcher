import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';

/// 页面骨架：顶栏（面包屑 / 标题 / 右侧动作）+ 内容区（默认带滚动）
///
/// 覆盖度审计（2026-11-04）里排 P0-1：现有 App 的顶栏是自绘的
/// （拖拽区 / 折叠 / 面包屑 / 窗控），设计层原先一行都没有。
/// 这里只做**内容页**的骨架；窗口拖拽、窗控按钮属于外壳，不进模板
class TemplatePageFrame extends StatelessWidget {
  const TemplatePageFrame({
    super.key,
    required this.skin,
    required this.title,
    required this.child,
    this.subtitle,
    this.breadcrumb,
    this.actions = const <Widget>[],
    this.onBack,
    this.scroll = true,
    this.padding = const EdgeInsets.all(TemplateSpace.xl),
    this.headerBackground,
    this.pageBackground,
  });

  final TemplateSkin skin;
  final String title;

  /// 标题上方的细字，一般是「概览 / 设置」这类层级
  final String? breadcrumb;
  final String? subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;

  /// 内容是否套滚动容器（表格式页面可以关掉自己控制）
  final bool scroll;
  final EdgeInsetsGeometry padding;
  final Widget child;
  final Color? headerBackground;
  final Color? pageBackground;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return ColoredBox(
      color: pageBackground ?? skin.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            // 至少 56；带面包屑 + 副标题时按内容长（否则三行会溢出）
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: TemplateSpace.lg,
              vertical: TemplateSpace.sm,
            ),
            decoration: BoxDecoration(
              color: headerBackground ?? skin.page,
              border: Border(bottom: BorderSide(color: skin.border)),
            ),
            child: Row(
              spacing: TemplateSpace.sm,
              children: [
                if (onBack != null)
                  TemplateIconButton(
                    skin: skin,
                    icon: Icons.arrow_back,
                    tooltip: '返回',
                    onTap: onBack,
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      if (breadcrumb != null)
                        Text(
                          breadcrumb!,
                          style: TemplateType.micro.copyWith(
                            color: skin.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        title,
                        style: TemplateType.page.copyWith(
                          color: skin.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TemplateType.caption.copyWith(
                            color: skin.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: TemplateSpace.sm),
                  Row(spacing: TemplateSpace.sm, children: actions),
                ],
              ],
            ),
          ),
          Expanded(
            child: scroll
                ? TemplateScrollView(
                    skin: skin,
                    showBackToTop: true,
                    child: body,
                  )
                : body,
          ),
        ],
      ),
    );
  }
}

/// 带皮肤滚动条 + 回顶按钮的滚动容器
///
/// 滚动条：槽 = 凹槽面，拇指 = 强边界，悬停提到三级字色（三个 token 是这次审出来的缺口）
class TemplateScrollView extends StatefulWidget {
  const TemplateScrollView({
    super.key,
    required this.skin,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.showBackToTop = false,
    this.controller,
  });

  final TemplateSkin skin;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool showBackToTop;
  final ScrollController? controller;

  @override
  State<TemplateScrollView> createState() => _TemplateScrollViewState();
}

class _TemplateScrollViewState extends State<TemplateScrollView> {
  late final ScrollController _controller =
      widget.controller ?? ScrollController();
  bool _showTop = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _controller.hasClients && _controller.offset > 240;
    if (show != _showTop) setState(() => _showTop = show);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return Stack(
      children: [
        ScrollbarTheme(
          data: ScrollbarThemeData(
            thickness: const WidgetStatePropertyAll(8),
            radius: const Radius.circular(4),
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return skin.scrollbarThumbHover;
              }
              return skin.scrollbarThumb;
            }),
            trackColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          child: Scrollbar(
            controller: _controller,
            child: SingleChildScrollView(
              controller: _controller,
              padding: widget.padding,
              child: widget.child,
            ),
          ),
        ),
        if (widget.showBackToTop && _showTop)
          Positioned(
            right: TemplateSpace.lg,
            bottom: TemplateSpace.lg,
            child: TemplateIconButton(
              skin: skin,
              icon: Icons.arrow_upward,
              tooltip: '回到顶部',
              onTap: () => _controller.animateTo(
                0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              ),
            ),
          ),
      ],
    );
  }
}

/// 纯图标按钮：设置项右侧、工具栏、对话框右上角都用它
///
/// `TemplateButton` 强制带文字，图标按钮单独一支；[tooltip] 为空就不挂提示
class TemplateIconButton extends StatelessWidget {
  const TemplateIconButton({
    super.key,
    required this.skin,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.iconSize = 18,
    this.size = 32,
    this.selected = false,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double iconSize;
  final double size;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? skin.textSecondary : skin.textDisabled;
    final button = ReboundContainer(
      onTap: enabled ? (onTap ?? () {}) : null,
      pressedScale: 0.94,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      backgroundColor: selected ? skin.selected : Colors.transparent,
      hoverColor: enabled ? skin.hoverOn(skin.surface) : Colors.transparent,
      highlightColor: enabled ? skin.pressed : Colors.transparent,
      padding: EdgeInsets.all((size - iconSize) / 2),
      child: Icon(icon, size: iconSize, color: foreground),
    );
    if (tooltip == null) return button;
    return TemplateTooltip(skin: skin, message: tooltip!, child: button);
  }
}

/// 悬停提示：样式跟卡一致（卡面 + 1px 边 + 阴影），不用系统默认的黑底
class TemplateTooltip extends StatelessWidget {
  const TemplateTooltip({
    super.key,
    required this.skin,
    required this.message,
    required this.child,
  });

  final TemplateSkin skin;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.sm,
        vertical: TemplateSpace.xs,
      ),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(TemplateRadius.control),
        border: Border.all(color: skin.border),
        boxShadow: [
          BoxShadow(
            color: skin.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      textStyle: TemplateType.caption.copyWith(color: skin.textPrimary),
      child: child,
    );
  }
}

/// 徽标 / 状态签：列表项右侧、列表卡角标、状态点后面的文字都用它
enum TemplateBadgeTone { neutral, accent, success, warning, danger }

class TemplateBadge extends StatelessWidget {
  const TemplateBadge({
    super.key,
    required this.skin,
    required this.label,
    this.tone = TemplateBadgeTone.neutral,
    this.icon,
  });

  final TemplateSkin skin;
  final String label;
  final TemplateBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (color, textColor) = switch (tone) {
      TemplateBadgeTone.neutral => (skin.textTertiary, skin.textSecondary),
      TemplateBadgeTone.accent => (skin.accent, skin.accentText),
      TemplateBadgeTone.success => (skin.success, skin.success),
      TemplateBadgeTone.warning => (skin.warning, skin.warning),
      TemplateBadgeTone.danger => (skin.danger, skin.dangerText),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withAlpha((0.14 * 255).round()),
          skin.surface,
        ),
        borderRadius: BorderRadius.circular(TemplateRadius.control),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: TemplateSpace.xs,
          children: [
            if (icon != null) Icon(icon, size: 12, color: textColor),
            Text(label, style: TemplateType.micro.copyWith(color: textColor)),
          ],
        ),
      ),
    );
  }
}

/// 复选：`value == null` 就是第三态「不变」（项目里三处设置页都用它）
class TemplateCheckbox extends StatelessWidget {
  const TemplateCheckbox({
    super.key,
    required this.skin,
    required this.value,
    this.onTap,
    this.enabled = true,
    this.size = 18,
  });

  final TemplateSkin skin;

  /// true 勾选 / false 未选 / null 「不变」
  final bool? value;
  final VoidCallback? onTap;
  final bool enabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color border;
    if (!enabled) {
      fill = value == false ? Colors.transparent : skin.standardDisabledSurface;
      border = skin.controlBorderDisabled;
    } else if (value == null) {
      fill = skin.accentTint;
      border = skin.accent;
    } else if (value!) {
      fill = skin.accent;
      border = Colors.transparent;
    } else {
      fill = Colors.transparent;
      border = skin.controlBorder;
    }
    return ReboundContainer(
      onTap: enabled ? (onTap ?? () {}) : null,
      pressedScale: 0.9,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border, width: value == null ? 2 : 1.5),
          ),
          child: value == null
              ? Icon(Icons.remove, size: size * 0.66, color: skin.onAccentTint)
              : value!
              ? Icon(Icons.check, size: size * 0.72, color: skin.onAccent)
              : null,
        ),
      ),
    );
  }
}

/// 带文字的复选行：左侧两行说明，右侧勾选框（整行可点）
class TemplateCheckRow extends StatelessWidget {
  const TemplateCheckRow({
    super.key,
    required this.skin,
    required this.title,
    required this.value,
    required this.onTap,
    this.desc,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final String title;
  final String? desc;
  final bool? value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final titleColor = enabled ? skin.textPrimary : skin.textDisabled;
    final descColor = enabled ? skin.textTertiary : skin.textDisabled;
    return ReboundContainer(
      onTap: enabled ? onTap : null,
      pressedScale: 0.995,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      hoverColor: enabled ? skin.hoverOn(skin.surface) : Colors.transparent,
      highlightColor: enabled ? skin.pressed : Colors.transparent,
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.md,
        vertical: TemplateSpace.sm,
      ),
      child: Row(
        spacing: TemplateSpace.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title,
                  style: TemplateType.item.copyWith(color: titleColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (desc != null)
                  Text(
                    desc!,
                    style: TemplateType.caption.copyWith(color: descColor),
                  ),
              ],
            ),
          ),
          TemplateCheckbox(
            skin: skin,
            value: value,
            enabled: enabled,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}
