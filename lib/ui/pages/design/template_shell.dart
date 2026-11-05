import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:flutter/material.dart';

import 'template_skin.dart';

/// 面包屑的一段：越靠右越「当前」；给了 [onTap] 才能点（像文件管理器那样跳级）
class TemplateBreadcrumb {
  const TemplateBreadcrumb(this.label, {this.onTap});

  final String label;
  final VoidCallback? onTap;
}

/// 页面骨架：**40 高的一行顶栏** + 内容区（默认带滚动）
///
/// 用户 2026-11-04 的反馈：顶栏要贴近现有设计、别把信息堆成三层（面包屑 / 标题 / 副标题），
/// 一层就够；面包屑本身就是标题，越靠右越当前。
///
/// 覆盖度审计（2026-11-04）里排 P0-1：现有 App 的顶栏是自绘的
/// （拖拽区 / 折叠 / 面包屑 / 窗控），设计层原先一行都没有。
/// 这里只做**内容页**的骨架；窗口拖拽、窗控按钮属于外壳，用 [leading] / [trailing] 注入
///
/// 2026-11-04 定稿的外壳规则（用户澄清后）：**软件 logo 在左侧边栏顶部，返回键与 logo 共用那个位置**
/// ——子页面时侧栏顶部显示返回、隐藏 logo；顶栏左边是账户（左抽屉）、右边是任务（右抽屉）。
/// 所以本组件不再管返回键，[leading] 放账户，[trailing] 放任务/窗控
class TemplatePageFrame extends StatelessWidget {
  const TemplatePageFrame({
    super.key,
    required this.skin,
    required this.breadcrumb,
    required this.child,
    this.actions = const <Widget>[],
    this.leading,
    this.trailing,
    this.scroll = true,
    this.padding = const EdgeInsets.all(TemplateSpace.xl),
    this.barHeight = 40,
    this.headerBackground,
    this.pageBackground,
  });

  final TemplateSkin skin;

  /// 从根到当前的路径（至少一段）；最后一段是当前页、不可点
  final List<TemplateBreadcrumb> breadcrumb;
  final List<Widget> actions;

  /// 顶栏左侧：账户头像（左抽屉入口）
  final Widget? leading;
  final Widget? trailing;
  final bool scroll;
  final EdgeInsetsGeometry padding;
  final Widget child;
  final double barHeight;
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
            height: barHeight,
            padding: const EdgeInsets.symmetric(horizontal: TemplateSpace.md),
            decoration: BoxDecoration(
              color: headerBackground ?? skin.surface,
              border: Border(bottom: BorderSide(color: skin.border)),
            ),
            child: Row(
              spacing: TemplateSpace.xs,
              children: [
                // 顶栏左侧只放账户（返回键在上一条规则里由侧栏顶部承担）
                if (leading != null) leading!,
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      spacing: 2,
                      children: [
                        for (var i = 0; i < breadcrumb.length; i++) ...[
                          if (i > 0)
                            Icon(
                              Icons.chevron_right,
                              size: 14,
                              color: skin.textTertiary,
                            ),
                          _BreadcrumbItem(
                            skin: skin,
                            item: breadcrumb[i],
                            current: i == breadcrumb.length - 1,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: TemplateSpace.xs),
                  Row(spacing: 2, children: actions),
                ],
                if (trailing != null) trailing!,
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

class _BreadcrumbItem extends StatelessWidget {
  const _BreadcrumbItem({
    required this.skin,
    required this.item,
    required this.current,
  });

  final TemplateSkin skin;
  final TemplateBreadcrumb item;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      item.label,
      style: TemplateType.item.copyWith(
        color: current ? skin.textPrimary : skin.textTertiary,
        fontWeight: current ? FontWeight.w600 : FontWeight.w400,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (current || item.onTap == null) return text;
    return ReboundContainer(
      onTap: item.onTap,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      hoverColor: skin.hoverOn(skin.surface),
      highlightColor: skin.pressed,
      padding: const EdgeInsets.symmetric(horizontal: TemplateSpace.xs),
      child: text,
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

/// 侧边栏的一格：图标 + 名称（收起时只剩图标，名称走 tooltip）
class TemplateRailEntry {
  const TemplateRailEntry({
    required this.icon,
    required this.label,
    this.onTap,
    this.showDot = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// 右上角小圆点：未读 / 有更新这类
  final bool showDot;
}

/// 侧边导航栏：顶部槽（**软件 logo / 返回键**）+ 导航格 + 底部槽（**折叠按钮**）
///
/// 2026-11-04 定稿的摆放：**折叠按钮在侧栏底部**、账户在顶栏**左上**、任务在顶栏**右上**（左右侧抽屉）；
/// 顶部那个位置是**软件 logo**，子页面时换成返回键（两者共享同一位置）
class TemplateSideRail extends StatelessWidget {
  const TemplateSideRail({
    super.key,
    required this.skin,
    required this.entries,
    this.selectedIndex = 0,
    this.onSelect,
    this.top,
    this.bottom,
    this.collapsed = false,
    this.width = 56,
    this.collapsedWidth = 24,
  });

  final TemplateSkin skin;
  final List<TemplateRailEntry> entries;
  final int selectedIndex;
  final ValueChanged<int>? onSelect;

  /// 顶部槽：**软件 logo**；子页面时换成返回键（二选一，位置共用）
  final Widget? top;

  /// 底部槽：**折叠 / 展开按钮**放这里
  final Widget? bottom;

  /// 收起态：只剩一条 24 宽的窄条 + 底部展开按钮
  final bool collapsed;
  final double width;
  final double collapsedWidth;

  @override
  Widget build(BuildContext context) {
    final railWidth = collapsed ? collapsedWidth : width;
    return Container(
      width: railWidth,
      decoration: BoxDecoration(
        color: skin.surface,
        border: Border(right: BorderSide(color: skin.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: TemplateSpace.sm),
      child: Column(
        children: [
          if (top != null) ...[top!, const SizedBox(height: TemplateSpace.sm)],
          // 导航格可滚：窗口矮的时候先牺牲它们，底部折叠按钮不动
          Expanded(
            child: collapsed
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var i = 0; i < entries.length; i++)
                          _TemplateRailTile(
                            skin: skin,
                            entry: entries[i],
                            selected: i == selectedIndex,
                            onTap:
                                entries[i].onTap ??
                                (onSelect == null ? null : () => onSelect!(i)),
                          ),
                      ],
                    ),
                  ),
          ),
          if (bottom != null) ...[
            const SizedBox(height: TemplateSpace.sm),
            bottom!,
          ],
        ],
      ),
    );
  }
}

class _TemplateRailTile extends StatelessWidget {
  const _TemplateRailTile({
    required this.skin,
    required this.entry,
    required this.selected,
    this.onTap,
  });

  final TemplateSkin skin;
  final TemplateRailEntry entry;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.xs,
        vertical: 2,
      ),
      child: TemplateTooltip(
        skin: skin,
        message: entry.label,
        child: ReboundContainer(
          onTap: onTap,
          pressedScale: 0.94,
          borderRadius: BorderRadius.circular(TemplateRadius.control),
          backgroundColor: selected ? skin.selected : Colors.transparent,
          hoverColor: skin.hoverOn(skin.surface),
          highlightColor: skin.pressed,
          padding: const EdgeInsets.all(TemplateSpace.sm),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                entry.icon,
                size: 20,
                color: selected ? skin.accentText : skin.textSecondary,
              ),
              if (entry.showDot)
                Positioned(
                  right: -3,
                  top: -2,
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
          ),
        ),
      ),
    );
  }
}
