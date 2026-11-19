import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 页面回写到顶栏的那部分内容
///
/// [suffix] 拼在本页路由段后面，[sections] 是页内分项，按顺序追加在本页路由段之后；
/// 都不是路由，页内分项只做展示
@immutable
class PageTopBarTrail {
  const PageTopBarTrail({this.suffix, this.sections = const []});

  final String? suffix;
  final List<String> sections;

  @override
  bool operator ==(Object other) {
    return other is PageTopBarTrail &&
        other.suffix == suffix &&
        listEquals(other.sections, sections);
  }

  @override
  int get hashCode => Object.hash(suffix, Object.hashAll(sections));
}

/// 单个路由的顶栏回写通道
///
/// 由壳在 pageBuilder 里按路由创建，页面通过 [PageTopBar] 写；壳监听变化重建顶栏
class PageTopBarController extends ValueNotifier<PageTopBarTrail> {
  PageTopBarController() : super(const PageTopBarTrail());

  void setSuffix(String? suffix) {
    if (value.suffix == suffix) return;
    value = PageTopBarTrail(suffix: suffix, sections: value.sections);
  }

  void setSections(List<String> sections) {
    if (listEquals(value.sections, sections)) return;
    value = PageTopBarTrail(suffix: value.suffix, sections: sections);
  }
}

/// 把单个路由的回写通道挂到页面树上
class PageTopBarScope extends InheritedWidget {
  const PageTopBarScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final PageTopBarController controller;

  @override
  bool updateShouldNotify(covariant PageTopBarScope oldWidget) =>
      oldWidget.controller != controller;
}

/// 页面改顶栏的入口
///
/// 页面只能改自己那一段：后缀与页内分项；改不了前面的路由层级，也不能越权修改别页
class PageTopBar {
  const PageTopBar._(this._controller);

  final PageTopBarController _controller;

  static PageTopBar of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PageTopBarScope>();
    assert(scope != null, '当前页面不在可回写顶栏的路由里');
    return PageTopBar._(scope!.controller);
  }

  /// 本页路由段的后缀，如版本 tag / 模组名；传 null 清掉
  void setSuffix(String? suffix) => _controller.setSuffix(suffix);

  /// 本页路由段之后追加的页内分项，只展示、不参与路由跳转
  void setSections(List<String> sections) => _controller.setSections(sections);
}

/// 栈里一条路由的展示信息
@immutable
class RouteTrailEntry {
  const RouteTrailEntry({
    required this.route,
    required this.label,
    this.suffix,
    this.sections = const [],
  });

  final PageRoute<dynamic> route;

  /// 路由表里的段名
  final String label;

  /// 动态后缀，页面回写优先，push 时 arguments 里的 title 兜底
  final String? suffix;

  /// 页内分项
  final List<String> sections;

  /// 顶栏里显示的整段文字
  String get displayLabel =>
      suffix == null || suffix!.isEmpty ? label : '$label - $suffix';
}

/// 面包屑的一段
sealed class BreadcrumbSegment {
  const BreadcrumbSegment(this.label);

  final String label;
}

/// 路由段：对应栈里的一条路由，可以点回那一层
class RouteBreadcrumb extends BreadcrumbSegment {
  const RouteBreadcrumb(
    super.label, {
    required this.route,
    required this.isCurrent,
  });

  final PageRoute<dynamic> route;
  final bool isCurrent;
}

/// 页内分项：用方框标出来，不可点
class InPageBreadcrumb extends BreadcrumbSegment {
  const InPageBreadcrumb(super.label);
}

/// 把路由栈展开成面包屑：每条路由一个路由段，后面跟它自己的页内分项
List<BreadcrumbSegment> buildBreadcrumb(List<RouteTrailEntry> entries) {
  final segments = <BreadcrumbSegment>[];
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    segments.add(
      RouteBreadcrumb(
        entry.displayLabel,
        route: entry.route,
        isCurrent: index == entries.length - 1,
      ),
    );
    for (final section in entry.sections) {
      segments.add(InPageBreadcrumb(section));
    }
  }
  return segments;
}

/// 路由转场语义：平级入口切换走纵向轻景深，子页下钻走横向克制视差
enum CuTransitionKind { rootSwitch, pushDrill }

/// 路由统一入场 / 退场时间轴作用域
///
/// 由 [CuPageRoute] 注入页面树；页内元素（如 [AppearItem] / 看板卡 / 启动区）同时绑定
/// 路由的 [animation]（入场 & 弹出退场）与 [secondaryAnimation]（被覆盖退场 & 返回回露），
/// 让整页与页内元素共享同一根时钟、绝不脱节也不闪烁
class PageEntranceScope extends InheritedWidget {
  const PageEntranceScope({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.transitionKind,
    required super.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final CuTransitionKind transitionKind;

  /// 页内元素入场的统一参数：与旧页 0.00~0.36 清场、舞台 0.28~0.62 浮现严密接力
  static const double slotStart = 0.32;
  static const double slotStep = 0.055;
  static const double slotSpan = 0.42;
  static const int maxStaggerSlots = 4;

  static PageEntranceScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PageEntranceScope>();
  }

  /// 前进入场（animation: 0 → 1）：第 [slot] 阶在路由时间轴上的区间（最多错开前 5 阶）
  static Interval enterIntervalForSlot(
    int slot, {
    Curve curve = Curves.easeOutCubic,
  }) {
    final clamped = slot.clamp(0, maxStaggerSlots);
    final begin = (slotStart + clamped * slotStep).clamp(0.0, 0.58);
    final end = (begin + slotSpan).clamp(begin + 0.1, 1.0);
    return Interval(begin, end, curve: curve);
  }

  /// 弹出退场（animation: 1 → 0）：前 40% 内按槽位轻阶梯顺滑退清（easeOutCubic 倒放 = 渐加速离场）
  static Interval popExitIntervalForSlot(
    int slot, {
    Curve curve = Curves.easeOutCubic,
  }) {
    final clamped = slot.clamp(0, maxStaggerSlots);
    final end = (1.0 - clamped * 0.03).clamp(0.72, 1.0);
    final begin = (end - 0.28).clamp(0.56, end - 0.1);
    return Interval(begin, end, curve: curve);
  }

  /// 被新页覆盖退场（secondaryAnimation: 0 → 1）：前 36% 内按槽位退清，给新页让出画布
  static Interval coverExitIntervalForSlot(
    int slot, {
    Curve curve = Curves.easeInCubic,
  }) {
    final clamped = slot.clamp(0, maxStaggerSlots);
    final begin = (clamped * 0.03).clamp(0.0, 0.12);
    final end = (begin + 0.24).clamp(begin + 0.1, 0.36);
    return Interval(begin, end, curve: curve);
  }

  /// 下层页返回回露（secondaryAnimation: 1 → 0）：等顶层退清后（0.66 → 0.0）按槽位柔和落回
  static Interval revealIntervalForSlot(
    int slot, {
    Curve curve = Curves.easeInCubic,
  }) {
    final clamped = slot.clamp(0, maxStaggerSlots);
    final end = (0.66 - clamped * 0.055).clamp(0.42, 0.66);
    final begin = (end - 0.42).clamp(0.0, end - 0.1);
    return Interval(begin, end, curve: curve);
  }

  /// 兼容旧名：等价于 [enterIntervalForSlot]
  static Interval intervalForSlot(
    int slot, {
    Curve curve = Curves.easeOutCubic,
  }) => enterIntervalForSlot(slot, curve: curve);

  /// 按当前转场语义给出页内元素的默认入场位移方向
  Offset defaultSlideOffset({double magnitude = 0.028}) {
    return switch (transitionKind) {
      CuTransitionKind.rootSwitch => Offset(0, magnitude),
      CuTransitionKind.pushDrill => Offset(magnitude, 0),
    };
  }

  /// 按当前转场语义给出页内元素被覆盖退场时的默认位移方向（与入场方向相反，形成推进感）
  Offset defaultCoverExitOffset({double magnitude = 0.024}) {
    return switch (transitionKind) {
      CuTransitionKind.rootSwitch => Offset(0, -magnitude),
      CuTransitionKind.pushDrill => Offset(-magnitude, 0),
    };
  }

  @override
  bool updateShouldNotify(covariant PageEntranceScope oldWidget) =>
      oldWidget.animation != animation ||
      oldWidget.secondaryAnimation != secondaryAnimation ||
      oldWidget.transitionKind != transitionKind;
}

/// 内层导航栈用的页面路由：带一条顶栏回写通道与统一转场时间轴
///
/// 保持 `opaque: true`：转场期间双页同台完成清场与浮现，结束后立即把下层旧页 offstage，
/// 既防止旧页内容残留压在底下，也避免下层继续消耗渲染资源；常驻流光与网格背景位于外层壳中不受影响
class CuPageRoute extends PageRouteBuilder<dynamic> {
  CuPageRoute({
    required RouteSettings super.settings,
    required this.trailController,
    required super.pageBuilder,
    required super.transitionsBuilder,
    this.transitionKind = CuTransitionKind.pushDrill,
    super.transitionDuration = const Duration(milliseconds: 440),
    super.reverseTransitionDuration = const Duration(milliseconds: 380),
    super.opaque = true,
  });

  final PageTopBarController trailController;
  final CuTransitionKind transitionKind;
}
