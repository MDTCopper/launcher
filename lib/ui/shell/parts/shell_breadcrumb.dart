import 'dart:async';

import 'package:copper_launcher/ui/components/core/cu_stable_text.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';

/// 顶栏「路由线路」：从根到当前的整条路由栈

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

class ShellBreadcrumbBar extends StatefulWidget {
  const ShellBreadcrumbBar({super.key, required this.crumbs, this.fadeColor});

  final List<ShellBreadcrumb> crumbs;

  /// 左侧渐隐用的底色（默认取卡面）
  final Color? fadeColor;

  @override
  State<ShellBreadcrumbBar> createState() => _ShellBreadcrumbBarState();
}

class _ShellBreadcrumbBarState extends State<ShellBreadcrumbBar> {
  final _controller = ScrollController();
  bool _moreLeft = false;
  bool _moreRight = false;

  /// 实际渲染的面包屑：缩回时先把旧的宽内容滚回最左，再换成新内容，
  /// 否则内容一变窄，滚动偏移会被框架立刻夹到 0，看起来就是「跳变」
  late List<ShellBreadcrumb> _renderCrumbs;

  /// 上一帧的段名：用来判断哪一段是这次新压进来的、哪一段换了内容
  List<String> _previousLabels = const [];

  /// 本次更新里新压进来的段 / 内容变了的段（按下标）
  Set<int> _enteringSlots = const {};
  Set<int> _changedSlots = const {};

  /// 渲染中的段槽数；弹栈时先留着槽位，等这一段的淡出走完再移除
  int _restSlots = 0;
  Timer? _trimSlotsTimer;

  /// 新压进来的段先空一帧再上内容，AnimatedSwitcher 才会播入场
  bool _holdNewSegments = false;

  /// 与设计层 TemplateBreadcrumbBar 的节奏一致
  static const _segmentDuration = Duration(milliseconds: 180);
  static const _scrollDuration = Duration(milliseconds: 200);

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
    _renderCrumbs = widget.crumbs;
    _previousLabels = _labelsOf(widget.crumbs);
    _restSlots = _renderCrumbs.length <= 1 ? 0 : _renderCrumbs.length - 1;
    _controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      // 首次进来直接贴右，不播动画
      _controller.jumpTo(_controller.position.maxScrollExtent);
      _sync();
    });
  }

  static List<String> _labelsOf(List<ShellBreadcrumb> crumbs) =>
      crumbs.map((crumb) => crumb.label).toList();

  @override
  void didUpdateWidget(covariant ShellBreadcrumbBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newLabels = _labelsOf(widget.crumbs);
    if (listEquals(_previousLabels, newLabels)) return;

    final entering = <int>{};
    final changed = <int>{};
    for (var index = 1; index < newLabels.length; index++) {
      if (index >= _previousLabels.length) {
        entering.add(index);
      } else if (_previousLabels[index] != newLabels[index]) {
        changed.add(index);
      }
    }
    final shrinking = newLabels.length < _previousLabels.length;
    _previousLabels = newLabels;
    _enteringSlots = entering;
    _changedSlots = changed;
    _holdNewSegments = entering.isNotEmpty;

    if (shrinking) {
      // 先保留旧内容，等滚回最左再换成新内容
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollBackThenApply();
      });
      return;
    }

    _applyCrumbs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_holdNewSegments) setState(() => _holdNewSegments = false);
      _alignToEnd();
      _sync();
    });
  }

  /// 换成新内容并同步槽位；fadeOutExtraSlots 时多留一会儿让旧段淡出
  void _applyCrumbs({bool fadeOutExtraSlots = false}) {
    _trimSlotsTimer?.cancel();
    _renderCrumbs = widget.crumbs;
    final restCount = _renderCrumbs.length <= 1 ? 0 : _renderCrumbs.length - 1;
    if (restCount >= _restSlots) {
      _restSlots = restCount;
      return;
    }
    if (!fadeOutExtraSlots) {
      _restSlots = restCount;
      return;
    }
    _trimSlotsTimer = Timer(_segmentDuration, () {
      if (!mounted) return;
      setState(() => _restSlots = restCount);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _alignToEnd();
        _sync();
      });
    });
  }

  Future<void> _scrollBackThenApply() async {
    if (!mounted) return;
    if (_controller.hasClients) {
      final position = _controller.position;
      if (position.pixels > position.minScrollExtent + 0.5) {
        await _controller.animateTo(
          position.minScrollExtent,
          duration: _scrollDuration,
          curve: Curves.easeOutCubic,
        );
        if (!mounted) return;
      }
    }
    setState(() => _applyCrumbs(fadeOutExtraSlots: true));
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  /// 滚到最右（当前层）；新内容可能晚一帧才完成布局，重试几次
  void _alignToEnd({int retry = 4}) {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (position.maxScrollExtent > position.minScrollExtent + 0.5) {
      _controller.animateTo(
        position.maxScrollExtent,
        duration: _scrollDuration,
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (retry > 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _alignToEnd(retry: retry - 1),
      );
    }
  }

  @override
  void dispose() {
    _trimSlotsTimer?.cancel();
    _controller.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final moreLeft = position.pixels > position.minScrollExtent + 0.5;
    final moreRight = position.pixels < position.maxScrollExtent - 0.5;
    if (moreLeft != _moreLeft || moreRight != _moreRight) {
      setState(() {
        _moreLeft = moreLeft;
        _moreRight = moreRight;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fadeColor = widget.fadeColor ?? colors.cardBackground;
    final crumbs = _renderCrumbs;
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

    // 除根段外每段各占一个槽：只有新压进来 / 内容变了的那一段自己播动画
    final segments = <Widget>[];
    for (var index = 1; index <= _restSlots; index++) {
      final hasCrumb = index < crumbs.length;
      final entering = _enteringSlots.contains(index);
      final fadeOnly = _changedSlots.contains(index);
      final showContent = hasCrumb && !(entering && _holdNewSegments);
      segments.add(
        AnimatedSwitcher(
          key: ValueKey(index),
          duration: _segmentDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            // 同层切换只淡入淡出；压栈 / 弹栈加一点横向位移
            if (fadeOnly) {
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
          child: showContent
              ? Row(
                  key: ValueKey(crumbs[index].label),
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    separator(),
                    _BreadcrumbItem(
                      item: crumbs[index],
                      current: isCurrent(index),
                      crumbStyle: _crumbStyle,
                      tagStyle: _tagStyle,
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      );
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [root, ...segments],
    );

    final row = CuSingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      // 顶栏只有 40 高：横向滚动条会压在文字上，两侧遮罩由下面自绘
      showScrollbar: false,
      fadeMask: false,
      child: content,
    );

    // 遮罩：左右两侧按「还能往那边滚」显示；缩回动画期间左侧常亮
    // 遮罩：左右两侧按「还能往那边滚」显示
    return Stack(
      children: [
        row,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 20,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _moreLeft ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [fadeColor, fadeColor.withAlpha(0)],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 20,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _moreRight ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [fadeColor.withAlpha(0), fadeColor],
                  ),
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
        CuStableText(
          item.label,
          style: crumbStyle.copyWith(
            color: current ? colors.itemPrimary : colors.itemSecondary,
            fontWeight: current ? FontWeight.w600 : FontWeight.w500,
          ),
          maxLines: 1,
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

    // 可点段的内边距在不可点（当前页）时也要占位：压栈后加粗段变普通段，
    // 只给可点态加内边距会让整行文字向右跳一段
    const itemPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 2);
    if (current || item.onTap == null) {
      return Padding(padding: itemPadding, child: content);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ReboundContainer(
        onTap: item.onTap,
        pressedScale: 0.97,
        borderRadius: BorderRadius.circular(6),
        backgroundColor: Colors.transparent,
        hoverColor: colors.highBackgroundOnCard,
        highlightColor: colors.splash,
        padding: itemPadding,
        child: content,
      ),
    );
  }
}
