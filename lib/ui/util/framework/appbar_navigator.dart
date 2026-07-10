import 'package:copperlauncher_main/ui/components/rebound/rebound_container.dart';
import 'package:copperlauncher_main/ui/util/route/page_route_observer.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class AppbarNavigationBar extends StatefulWidget
    implements PreferredSizeWidget {
  final String initialRoute;
  final List<String>? rootRoutes;
  final Widget? leading;
  final List<AppbarNavigatorOption>? options;
  final List<Widget>? action;
  final EdgeInsetsGeometry? padding;

  final PageRouteObserver routeObserver;
  //final Color? optionColor;
  //final Color? activeColor;

  const AppbarNavigationBar({
    super.key,
    required this.initialRoute,
    required this.routeObserver,
    this.rootRoutes,
    this.leading,
    this.options,
    this.action,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  State<StatefulWidget> createState() => AppbarNavigationBarState();
}

class AppbarNavigationBarState extends State<AppbarNavigationBar>
    with SingleTickerProviderStateMixin {
  late Color? backgroundColor = Theme.of(context).appBarTheme.backgroundColor;

  late String currentRootRoute;

  String pageName = 'null';

  late final List<String> _rootRoutes;

  late final AnimationController _controller;

  NavigatorState? get _navigator => widget.routeObserver.navigator;

  bool get _canPop => widget.routeObserver.navigator?.canPop() ?? false;

  void updateRoute(Route newRoute) {
    //允许外部主动控制状态
    setState(() {
      var arg = newRoute.settings.arguments;
      String? lead;
      String? title;
      if (arg is Map) {
        lead = arg['lead'];
        if (lead != null) pageName = lead;
        title = arg['title'];
        if (title != null) pageName = '$lead [$title]';
      } else {
        pageName = newRoute.settings.name ?? 'null';
      }
      if (_canPop) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
      if (newRoute.settings.name == null) return;
      _updateRootRoute(newRoute.settings.name!);
    });
  }

  bool _updateRootRoute(String newRoute) {
    if (newRoute == currentRootRoute) return false;
    final needUpdate = _rootRoutes.any((route) => newRoute == route);
    if (needUpdate || _rootRoutes.isEmpty) {
      setState(() {
        currentRootRoute = newRoute;
      });
    }
    return needUpdate;
  }

  @override
  void initState() {
    currentRootRoute = widget.initialRoute;
    _rootRoutes =
        widget.rootRoutes ??
        widget.options?.map<String>((option) => option.route).toList() ??
        [];

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    super.initState();
  }

  Widget _buildOption() {
    final scale = Tween<double>(begin: 1.0, end: 0.75).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeInBack,
      ),
    );

    final opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeInBack,
      ),
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        if (_controller.isCompleted) return SizedBox();

        return FadeTransition(
          opacity: opacity,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: widget.options!.map<AppbarNavigatorItem>((option) {
          return AppbarNavigatorItem(
            selected: currentRootRoute == option.route,
            name: option.name,
            icon: option.icon,
            onTap: () {
              setState(() {
                _navigator?.pushReplacementNamed(option.route);
                _updateRootRoute(option.route);
                option.onTap?.call();
              });
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLeading() {
    if (widget.leading == null) return Text('null');

    final leading = widget.leading!;

    final backButton = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        ReboundButton(
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          hoverElevation: 4.0,
          child: Icon(
            Icons.arrow_back,
            color: Theme.of(context).appBarTheme.iconTheme?.color,
          ),
          onTap: () {
            _navigator?.pop();
          },
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) {
            final opacity = CurvedAnimation(
              parent: animation,
              curve: Interval(0.4, 1.0, curve: Curves.easeOut),
              reverseCurve: Interval(0.4, 1.0, curve: Curves.easeIn),
            );
            final sizeFactor = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: Interval(0.4, 1.0, curve: Curves.easeOutBack),
                reverseCurve: Interval(0.4, 1.0, curve: Curves.easeIn),
              ),
            );

            return FadeTransition(
              opacity: opacity,
              child: SizeTransition(
                axisAlignment: -0.5,
                axis: Axis.horizontal,
                sizeFactor: sizeFactor,
                child: child,
              ),
            );
          },
          layoutBuilder: (newChild, oldChildren) {
            return Stack(
              alignment: AlignmentGeometry.centerLeft,
              children: [...oldChildren, if (newChild != null) newChild],
            );
          },
          child: Text(
            pageName,
            key: ValueKey(pageName),
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, animation) {
        final opacity = CurvedAnimation(
          parent: animation,
          curve: Interval(0.4, 1.0, curve: Curves.easeOut),
          reverseCurve: Interval(0.4, 1.0, curve: Curves.easeIn),
        );
        final position =
            Tween<Offset>(begin: Offset(-0.3, 0.0), end: Offset.zero).animate(
              CurvedAnimation(
                parent: animation,
                curve: Interval(0.4, 1.0, curve: Curves.easeOutBack),
                reverseCurve: Interval(0.4, 1.0, curve: Curves.easeIn),
              ),
            );
        return FadeTransition(
          opacity: opacity,
          child: SlideTransition(position: position, child: child),
        );
      },
      layoutBuilder: (newChild, oldChildren) {
        return Stack(
          alignment: AlignmentGeometry.centerLeft,
          children: [...oldChildren, if (newChild != null) newChild],
        );
      },
      child: _canPop ? backButton : leading,
    );
  }

  @override
  Widget build(BuildContext context) {
    //todo 到时候判断平台

    return Container(
      width: .infinity,
      height: widget.preferredSize.height,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: const [
          BoxShadow(color: Colors.red, offset: Offset(0.0, -20.0)),
        ],
      ),
      child: Stack(
        alignment: .center,
        fit: .passthrough,
        children: [
          GestureDetector(onPanStart: (_) => windowManager.startDragging()),
          Positioned(left: 0, child: _buildLeading()),
          if (widget.options != null) _buildOption(),
          if (widget.action != null)
            Positioned(
              right: 0,
              child: Row(
                mainAxisAlignment: .end,
                mainAxisSize: .min,
                children: widget.action!,
              ),
            ),
        ],
      ),
    );
  }
}

class AppbarNavigatorItem extends StatefulWidget {
  final bool selected;
  final IconData icon;
  final String name;
  final VoidCallback? onTap;

  const AppbarNavigatorItem({
    super.key,
    required this.selected,
    required this.name,
    required this.icon,
    this.onTap,
  });

  @override
  State<StatefulWidget> createState() => _AppbarNavigatorItemState();
}

class _AppbarNavigatorItemState extends State<AppbarNavigatorItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final AppBarThemeData theme = Theme.of(context).appBarTheme;

  late final Color _itemColor =
      theme.iconTheme?.color ?? Theme.of(context).colorScheme.onPrimary;
  late final Color _itemActiveColor =
      theme.toolbarTextStyle?.color ?? Theme.of(context).colorScheme.onPrimary;
  late final Color _backgroundColor =
      theme.backgroundColor ?? Theme.of(context).colorScheme.primary;
  late final Color _backgroundActiveColor = Theme.of(
    context,
  ).colorScheme.primaryContainer;

  //late final Animation<double> _sizeFactor;
  //late final Animation<Color?> _backgroundColor;
  //late final Animation<Color?> _itemColor;

  @override
  void initState() {
    _controller = AnimationController(
      duration: Duration(milliseconds: 350),
      vsync: this,
    );

    if (widget.selected) _controller.forward(from: 1.0);
    super.initState();
  }

  @override
  void didUpdateWidget(covariant AppbarNavigatorItem oldWidget) {
    if (widget.selected) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        const SizedBox(width: 110),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: 32),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, _) {
              final sizeFactor = Tween<double>(begin: 0.70, end: 0.95).animate(
                CurvedAnimation(
                  parent: _controller,
                  curve: Curves.easeOutBack,
                  reverseCurve: Curves.easeIn,
                ),
              );

              final backgroundColor =
                  ColorTween(
                    begin: _backgroundColor,
                    end: _backgroundActiveColor,
                  ).animate(
                    CurvedAnimation(
                      parent: _controller,
                      curve: Curves.easeOutBack,
                      reverseCurve: Curves.easeIn,
                    ),
                  );

              final itemColor =
                  ColorTween(begin: _itemColor, end: _itemActiveColor).animate(
                    CurvedAnimation(
                      parent: _controller,
                      curve: Curves.easeOutBack,
                      reverseCurve: Curves.easeIn,
                    ),
                  );

              return ReboundContainer(
                pressedScale: 0.75,
                shadowColor: Colors.black,
                hoverElevation: 2,
                borderRadius: BorderRadius.circular(16),
                backgroundColor: backgroundColor.value,
                onTap: () {
                  if (widget.selected) return;
                  widget.onTap?.call();
                  setState(() {});
                },
                child: SizeTransition(
                  sizeFactor: sizeFactor,
                  axis: Axis.horizontal,
                  child: Container(
                    width: 110,
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: const Offset(-2.0, 0.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 2,
                        children: [
                          Icon(widget.icon, color: itemColor.value),
                          Transform.translate(
                            offset: const Offset(0.0, -1.0),
                            child: Text(
                              widget.name,
                              style: TextStyle(
                                color: itemColor.value,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

//创建item模型
class AppbarNavigatorOption {
  final String route;
  final IconData icon;
  final String name;
  final VoidCallback? onTap;
  AppbarNavigatorOption({
    required this.route,
    required this.icon,
    required this.name,
    this.onTap,
  });
}
