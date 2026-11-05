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
    this.cornerRadius = 0,
    this.showBarDivider = true,
    this.showContentBorder = false,
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

  /// 左上角圆角（页面与侧栏交界处）：0 = 直角，一般取 12~16
  final double cornerRadius;

  /// 顶栏下边框：去掉后靠底色 + 内容区圆角分隔（用户 2026-11-05 想试无边界线）
  final bool showBarDivider;

  /// 内容区描边：只画**左边 + 上边**两条 1px 线（左上角跟着圆角），右边和下边不画
  final bool showContentBorder;
  final Color? headerBackground;
  final Color? pageBackground;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    // 外壳底色 = 顶栏色：内容区圆角露出来的就是它，于是看起来是「顶栏 + 侧栏包住内容区」
    final chrome = headerBackground ?? skin.surface;
    final contentArea = ColoredBox(
      color: pageBackground ?? skin.page,
      child: scroll
          ? TemplateScrollView(skin: skin, showBackToTop: true, child: body)
          : body,
    );
    // 圆角只给内容区的**左上角**（不是整页）：顶栏保持直角横贯顶部，左下留直角
    final bodyArea = cornerRadius <= 0
        ? contentArea
        : ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(cornerRadius),
            ),
            child: showContentBorder
                // 描边只压左边与上边，跟着左上圆角走
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      contentArea,
                      IgnorePointer(
                        child: TemplateContentEdge(
                          skin: skin,
                          cornerRadius: cornerRadius,
                        ),
                      ),
                    ],
                  )
                : contentArea,
          );
    return ColoredBox(
      color: chrome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: barHeight,
            padding: const EdgeInsets.symmetric(horizontal: TemplateSpace.md),
            decoration: BoxDecoration(
              color: chrome,
              border: showBarDivider
                  ? Border(bottom: BorderSide(color: skin.border))
                  : null,
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
          Expanded(child: bodyArea),
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
    this.rotationTurns = 0.0,
  });

  final TemplateSkin skin;
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double iconSize;
  final double size;
  final bool selected;
  final bool enabled;

  /// 图标旋转圈数（收纳按钮用：展开 0 圈、收起 0.5 圈）
  final double rotationTurns;

  @override
  Widget build(BuildContext context) {
    final foreground = selected && enabled
        ? skin.accentText
        : (enabled ? skin.textSecondary : skin.textDisabled);
    Widget iconWidget = Icon(icon, size: iconSize, color: foreground);
    if (rotationTurns != 0) {
      iconWidget = AnimatedRotation(
        turns: rotationTurns,
        duration: const Duration(milliseconds: 250),
        curve: Curves.ease,
        child: iconWidget,
      );
    }
    final button = ReboundContainer(
      onTap: enabled ? (onTap ?? () {}) : null,
      pressedScale: 0.94,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      backgroundColor: selected ? skin.selected : Colors.transparent,
      hoverColor: enabled ? skin.hoverOn(skin.surface) : Colors.transparent,
      highlightColor: enabled ? skin.pressed : Colors.transparent,
      padding: EdgeInsets.all((size - iconSize) / 2),
      child: iconWidget,
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

/// 侧栏顶部：**软件 logo + 应用名**（展开显示文字、收起只剩 logo），仿照现有 App 的 `NavigationRail._buildLogo`
class TemplateRailBrand extends StatelessWidget {
  const TemplateRailBrand({
    super.key,
    required this.skin,
    this.logo,
    this.title = 'Copper',
    this.collapsed = false,
  });

  final TemplateSkin skin;
  final Widget? logo;
  final String title;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: TemplateSpace.md),
      alignment: Alignment.centerLeft,
      child: Row(
        spacing: TemplateSpace.sm,
        children: [
          logo ??
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: skin.accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 16,
                  color: skin.onAccent,
                ),
              ),
          if (!collapsed)
            Flexible(
              child: Text(
                title,
                style: TemplateType.page.copyWith(
                  color: skin.accentText,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// 侧栏顶部（子页面）：返回键 + 「返回」文字，与 logo 共用同一个位置
class TemplateRailBack extends StatelessWidget {
  const TemplateRailBack({
    super.key,
    required this.skin,
    this.label = '返回',
    this.collapsed = false,
    this.onTap,
  });

  final TemplateSkin skin;
  final String label;
  final bool collapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: TemplateSpace.md),
      alignment: Alignment.centerLeft,
      child: ReboundContainer(
        onTap: onTap,
        pressedScale: collapsed ? 0.8 : 0.94,
        borderRadius: BorderRadius.circular(TemplateRadius.control),
        hoverColor: skin.hoverOn(skin.surface),
        highlightColor: skin.pressed,
        child: Row(
          spacing: TemplateSpace.sm,
          children: [
            Icon(Icons.arrow_back, size: 20, color: skin.textSecondary),
            if (!collapsed)
              Flexible(
                child: Text(
                  label,
                  style: TemplateType.item.copyWith(color: skin.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏最左的**侧栏收纳/展开**按钮（仿现有 App 的 `Symbols.dock_to_right`：展开时高亮、收起时转 180°）
class TemplateNavigationToggle extends StatelessWidget {
  const TemplateNavigationToggle({
    super.key,
    required this.skin,
    required this.collapsed,
    this.onTap,
  });

  final TemplateSkin skin;
  final bool collapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TemplateIconButton(
      skin: skin,
      icon: Icons.keyboard_double_arrow_left,
      tooltip: collapsed ? '展开主菜单' : '收纳主菜单',
      size: 28,
      iconSize: 16,
      selected: !collapsed,
      rotationTurns: collapsed ? 0.5 : 0,
      onTap: onTap,
    );
  }
}

/// 侧边导航栏：顶部槽（**软件 logo / 返回键**）+ 导航格 + 底部槽（底部条目，如版本号 / 账户）
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
    // 展开：图标 + 名称的长条；收起：只剩图标
    this.width = 180,
    this.collapsedWidth = 56,
    this.showDivider = true,
  });

  final TemplateSkin skin;
  final List<TemplateRailEntry> entries;
  final int selectedIndex;
  final ValueChanged<int>? onSelect;

  /// 顶部槽：**软件 logo**；子页面时换成返回键（二选一，位置共用）
  final Widget? top;

  /// 底部槽：**折叠 / 展开按钮**放这里
  final Widget? bottom;

  /// 收起态：只剩图标（56 宽），名称走 tooltip
  final bool collapsed;
  final double width;
  final double collapsedWidth;

  /// 右侧分隔线：去掉后靠底色 + 内容区圆角分隔
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final railWidth = collapsed ? collapsedWidth : width;
    return Container(
      width: railWidth,
      decoration: BoxDecoration(
        color: skin.surface,
        border: showDivider
            ? Border(right: BorderSide(color: skin.border))
            : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: TemplateSpace.sm),
      child: Column(
        children: [
          if (top != null) ...[top!, const SizedBox(height: TemplateSpace.sm)],
          // 导航格可滚：窗口矮的时候先牺牲它们，底部折叠按钮不动
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++)
                    _TemplateRailTile(
                      skin: skin,
                      entry: entries[i],
                      selected: i == selectedIndex,
                      collapsed: collapsed,
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

/// 导航格：展开时是「图标 + 名称」的整条，收起时只剩图标（名称走 tooltip）
class _TemplateRailTile extends StatelessWidget {
  const _TemplateRailTile({
    required this.skin,
    required this.entry,
    required this.selected,
    required this.collapsed,
    this.onTap,
  });

  final TemplateSkin skin;
  final TemplateRailEntry entry;
  final bool selected;
  final bool collapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = Stack(
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
    );

    final tile = ReboundContainer(
      onTap: onTap,
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      backgroundColor: selected ? skin.selected : Colors.transparent,
      hoverColor: skin.hoverOn(skin.surface),
      highlightColor: skin.pressed,
      padding: collapsed
          ? const EdgeInsets.all(TemplateSpace.sm)
          : const EdgeInsets.symmetric(
              horizontal: TemplateSpace.md,
              vertical: TemplateSpace.sm,
            ),
      child: collapsed
          ? icon
          : Row(
              spacing: TemplateSpace.sm,
              children: [
                icon,
                Expanded(
                  child: Text(
                    entry.label,
                    style: TemplateType.item.copyWith(
                      color: selected ? skin.textPrimary : skin.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.xs,
        vertical: 2,
      ),
      child: collapsed
          ? TemplateTooltip(skin: skin, message: entry.label, child: tile)
          : tile,
    );
  }
}

/// 内容区描边：只画**左边 + 上边**两条 1px 线，左上角顺着圆角画弧；右边与下边不画
///
/// 用户 2026-11-05：「描边说的是内容页的左和上边加描边」
class TemplateContentEdge extends StatelessWidget {
  const TemplateContentEdge({
    super.key,
    required this.skin,
    required this.cornerRadius,
  });

  final TemplateSkin skin;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ContentEdgePainter(
        color: skin.border,
        cornerRadius: cornerRadius,
      ),
    );
  }
}

class _ContentEdgePainter extends CustomPainter {
  _ContentEdgePainter({required this.color, required this.cornerRadius});

  final Color color;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = cornerRadius;
    // 0.5 内缩让 1px 线落在像素上，不糊成两像素
    final path = Path()..moveTo(0.5, size.height);
    if (radius > 0) {
      path
        ..lineTo(0.5, radius + 0.5)
        ..arcToPoint(
          Offset(radius + 0.5, 0.5),
          radius: Radius.circular(radius),
          clockwise: true,
        );
    } else {
      path.lineTo(0.5, 0.5);
    }
    path.lineTo(size.width, 0.5);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ContentEdgePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}
