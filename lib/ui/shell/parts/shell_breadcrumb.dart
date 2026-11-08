import 'package:flutter/material.dart';

import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';

/// 顶栏「路由线路」：从根到当前的整条路由栈
///
/// 从设计层的 `TemplateBreadcrumbBar` 落进正式代码，配色改吃 [AppColors]；
/// 行为不变：点名称跳回那层、页面内分项用框标出、栈长了自动滚到当前层。
class ShellBreadcrumb {
  const ShellBreadcrumb(
    this.label, {
    this.onTap,
    this.tag,
    this.boxed = false,
    this.icon,
    this.current = false,
  });

  final String label;

  /// 可点跳转；[boxed] 为 true 时忽略
  final VoidCallback? onTap;

  /// 跟在名称后面的小字，如版本 tag / 资源名
  final String? tag;

  /// 页面内路由：框起来、不可点
  final bool boxed;

  /// 可选前置图标
  final IconData? icon;

  /// 当前所在页；页面内分项跟在它后面，不能靠「最后一段」判断
  final bool current;
}

/// 面包屑变化类型：决定切换动画
enum _TrailChange {
  none,

  /// 压栈：新段从左往右小幅位移淡入
  add,

  /// 弹栈：旧段反向淡出 + 向左位移
  remove,

  /// 同层切换：纯淡入淡出
  switchOnly,
}

class ShellBreadcrumbBar extends StatefulWidget {
  const ShellBreadcrumbBar({
    super.key,
    required this.crumbs,
    this.fadeColor,
  });

  final List<ShellBreadcrumb> crumbs;

  /// 左侧渐隐用的底色（默认取卡面）
  final Color? fadeColor;

  @override
  State<ShellBreadcrumbBar> createState() => _ShellBreadcrumbBarState();
}

class _ShellBreadcrumbBarState extends State<ShellBreadcrumbBar> {
  final _controller = ScrollController();
  bool _moreLeft = false;
  bool _jumpedToEnd = false;
  _TrailChange _change = _TrailChange.none;

  static const _crumbStyle = TextStyle(fontSize: 14, height: 20 / 14);
  static const _tagStyle = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant ShellBreadcrumbBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldLabels = oldWidget.crumbs.map((crumb) => crumb.label).toList();
    final newLabels = widget.crumbs.map((crumb) => crumb.label).toList();
    if (oldLabels.length == newLabels.length &&
        oldLabels.join('>') == newLabels.join('>')) {
      return;
    }
    _change = _detectChange(oldLabels, newLabels);
    // 换栈后对齐到「当前层」那一头
    _jumpedToEnd = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  static _TrailChange _detectChange(
    List<String> oldLabels,
    List<String> newLabels,
  ) {
    if (newLabels.length > oldLabels.length) {
      final appended =
          newLabels.take(oldLabels.length).join('>') == oldLabels.join('>');
      return appended ? _TrailChange.add : _TrailChange.switchOnly;
    }
    if (newLabels.length < oldLabels.length) {
      final truncated =
          oldLabels.take(newLabels.length).join('>') == newLabels.join('>');
      return truncated ? _TrailChange.remove : _TrailChange.switchOnly;
    }
    return _TrailChange.switchOnly;
  }

  @override
  void dispose() {
    _controller.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    // 栈太长：首次进来先滚到最右（露出当前层），之后左边若有内容就贴渐隐
    if (!_jumpedToEnd && position.maxScrollExtent > 0.5) {
      _jumpedToEnd = true;
      _controller.jumpTo(position.maxScrollExtent);
    }
    final moreLeft = position.pixels > position.minScrollExtent + 0.5;
    if (moreLeft != _moreLeft) {
      setState(() => _moreLeft = moreLeft);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fadeColor = widget.fadeColor ?? colors.cardBackground;
    final crumbs = widget.crumbs;
    if (crumbs.isEmpty) return const SizedBox.shrink();
    final hasExplicitCurrent = crumbs.any((crumb) => crumb.current);
    bool isCurrent(int index) =>
        hasExplicitCurrent ? crumbs[index].current : index == crumbs.length - 1;

    Widget separator() =>
        Icon(Icons.chevron_right, size: 14, color: colors.itemHint);

    // 根路由不参与动画：切页 / 压栈时它保持不动
    final root = _BreadcrumbItem(
      item: crumbs.first,
      current: isCurrent(0),
      crumbStyle: _crumbStyle,
      tagStyle: _tagStyle,
    );

    final rest = crumbs.length <= 1
        ? const SizedBox.shrink()
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              // 同层切换只淡入淡出；压栈 / 弹栈加一点横向位移
              if (_change == _TrailChange.switchOnly) {
                return FadeTransition(opacity: animation, child: child);
              }
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(-0.04, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previousChildren, ?currentChild],
            ),
            child: Row(
              key: ValueKey(
                crumbs.skip(1).map((crumb) => crumb.label).join('>'),
              ),
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                for (var index = 1; index < crumbs.length; index++) ...[
                  separator(),
                  _BreadcrumbItem(
                    item: crumbs[index],
                    current: isCurrent(index),
                    crumbStyle: _crumbStyle,
                    tagStyle: _tagStyle,
                  ),
                ],
              ],
            ),
          );

    final row = SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [root, rest],
      ),
    );
    if (!_moreLeft) return row;
    // 左边还有内容：贴一条 20px 渐隐，暗示可以往回滚
    return Stack(
      children: [
        row,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 20,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [fadeColor, fadeColor.withAlpha(0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BreadcrumbItem extends StatelessWidget {
  const _BreadcrumbItem({
    required this.item,
    required this.current,
    required this.crumbStyle,
    required this.tagStyle,
  });

  final ShellBreadcrumb item;
  final bool current;
  final TextStyle crumbStyle;
  final TextStyle tagStyle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    // 页面内路由：框起来、不可点
    if (item.boxed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            if (item.icon != null)
              Icon(item.icon, size: 12, color: colors.itemHint),
            Text(
              item.label,
              style: tagStyle.copyWith(
                color: current ? colors.itemSecondary : colors.itemHint,
              ),
            ),
            if (item.tag != null)
              Text(item.tag!, style: tagStyle.copyWith(color: colors.itemHint)),
          ],
        ),
      );
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        if (item.icon != null)
          Icon(
            item.icon,
            size: 14,
            color: current ? colors.interactive : colors.itemHint,
          ),
        Text(
          item.label,
          style: crumbStyle.copyWith(
            color: current ? colors.itemPrimary : colors.itemSecondary,
            fontWeight: current ? FontWeight.w600 : FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (item.tag != null)
          Text(
            item.tag!,
            style: tagStyle.copyWith(
              color: current ? colors.itemSecondary : colors.itemHint,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );

    if (current || item.onTap == null) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ReboundContainer(
        onTap: item.onTap,
        pressedScale: 0.97,
        borderRadius: BorderRadius.circular(6),
        backgroundColor: Colors.transparent,
        hoverColor: colors.highBackgroundOnCard,
        highlightColor: colors.splash,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: content,
      ),
    );
  }
}
