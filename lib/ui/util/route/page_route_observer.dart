import 'package:flutter/cupertino.dart';

class PageRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  late Route currentRoute;

  late final void Function(Route route)? onRouteChange;

  PageRouteObserver({this.onRouteChange});

  @override
  void didPop(Route route, Route? previousRoute) {
    currentRoute = previousRoute!;
    debugPrint(
      'route pop: route [${route.settings}], previousRoute [${previousRoute.settings}]',
    );
    super.didPop(route, previousRoute);
    onRouteChange?.call(currentRoute);
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    currentRoute = route;
    debugPrint(
      'route push: route [${route.settings}], previousRoute [${previousRoute?.settings}]',
    );
    super.didPush(route, previousRoute);
    if (previousRoute == null) return;
    onRouteChange?.call(currentRoute);
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    if (previousRoute != null) {
      currentRoute = previousRoute;
      debugPrint(
        'route remove: route [${route.settings}], previousRoute [${previousRoute.settings}]',
      );
      onRouteChange?.call(currentRoute);
    }
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    currentRoute = newRoute!;
    debugPrint(
      'route replace: newRoute [${newRoute.settings}], oldRoute [${oldRoute?.settings}]',
    );
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    onRouteChange?.call(currentRoute);
  }
}
