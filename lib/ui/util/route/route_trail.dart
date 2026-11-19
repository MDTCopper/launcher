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

/// 路由统一入场时间轴作用域
///
/// 由 [CuPageRoute] 注入页面树；页内元素（如 [AppearItem] / 看板卡 / 启动区）直接绑定
/// 路由自己的 [animation] 推进区间，避免各处自起 Timer 与路由转场脱节
class PageEntranceScope extends InheritedWidget {
  const PageEntranceScope({
    super.key,
    required this.animation,
    required this.transitionKind,
    required super.child,
  });

  final Animation<double> animation;
  final CuTransitionKind transitionKind;

  /// 页内元素入场的统一参数：与旧页 0.00~0.32 清场、舞台 0.25~0.62 浮现严密接力
  static const double slotStart = 0.30;
  static const double slotStep = 0.06;
  static const double slotSpan = 0.42;
  static const int maxStaggerSlots = 4;

  static PageEntranceScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PageEntranceScope>();
  }

  /// 计算第 [slot] 阶元素在路由 0~1 时间轴上的入场区间（最多错开前 5 阶，末尾不拖沓）
  static Interval intervalForSlot(
    int slot, {
    Curve curve = Curves.easeOutCubic,
  }) {
    final clamped = slot.clamp(0, maxStaggerSlots);
    final begin = (slotStart + clamped * slotStep).clamp(0.0, 0.72);
    final end = (begin + slotSpan).clamp(begin + 0.1, 1.0);
    return Interval(begin, end, curve: curve);
  }

  /// 按当前转场语义给出页内元素的默认入场位移方向
  Offset defaultSlideOffset({double magnitude = 0.025}) {
    return switch (transitionKind) {
      CuTransitionKind.rootSwitch => Offset(0, magnitude),
      CuTransitionKind.pushDrill => Offset(magnitude, 0),
    };
  }

  @override
  bool updateShouldNotify(covariant PageEntranceScope oldWidget) =>
      oldWidget.animation != animation ||
      oldWidget.transitionKind != transitionKind;
}

/// 内层导航栈用的页面路由：带一条顶栏回写通道与统一转场时间轴
class CuPageRoute extends PageRouteBuilder<dynamic> {
  CuPageRoute({
    required RouteSettings super.settings,
    required this.trailController,
    required super.pageBuilder,
    required super.transitionsBuilder,
    this.transitionKind = CuTransitionKind.pushDrill,
    super.transitionDuration = const Duration(milliseconds: 440),
    super.reverseTransitionDuration = const Duration(milliseconds: 320),
    super.opaque = false,
  });

  final PageTopBarController trailController;
  final CuTransitionKind transitionKind;
}
