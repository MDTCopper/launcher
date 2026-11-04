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

/// 内层导航栈用的页面路由：带一条顶栏回写通道
class CopperPageRoute extends PageRouteBuilder<dynamic> {
  CopperPageRoute({
    required RouteSettings settings,
    required this.trailController,
    required Widget Function(BuildContext, Animation<double>, Animation<double>)
    pageBuilder,
    required Widget Function(
      BuildContext,
      Animation<double>,
      Animation<double>,
      Widget,
    )
    transitionsBuilder,
  }) : super(
         settings: settings,
         pageBuilder: pageBuilder,
         transitionsBuilder: transitionsBuilder,
         transitionDuration: const Duration(milliseconds: 350),
         reverseTransitionDuration: const Duration(milliseconds: 350),
       );

  final PageTopBarController trailController;
}
