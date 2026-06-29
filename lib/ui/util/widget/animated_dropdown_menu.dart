import 'package:flutter/material.dart';

//todo 自定义组件接口
typedef AnimatedDropdownHeadBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Widget? child,
    );
typedef AnimatedDropdownMenuBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Widget child,
    );

class AnimatedDropdownMenu<T> extends StatefulWidget {
  final List<DropdownOption<T>> options;
  final Widget? child;
  final T? initialValue;
  final String hintText;
  final void Function(T value)? onSelect;
  final double width;
  final double menuHeight;
  final Color? color;
  final Color? hoverColor;
  final Border? border;
  final Border? hoverBorder;
  // final Widget? innerWidget;

  const AnimatedDropdownMenu({
    super.key,
    this.initialValue,
    required this.options,
    this.hintText = 'null',
    this.onSelect,
    this.menuHeight = 200,
    this.child,
    this.width = double.infinity,
    this.color,
    this.hoverColor,
    this.border,
    this.hoverBorder,
  });

  @override
  State<StatefulWidget> createState() => _AnimatedDropdownMenuState<T>();
}

class DropdownOption<T> {
  final T value;
  final Widget? leading;

  final String label;
  final Widget? labelWidget;
  final VoidCallback? onTap;
  final T? selectValue;
  DropdownOption({
    required this.value,
    required this.label,
    this.leading,
    this.onTap,
    this.selectValue,
    this.labelWidget,
  });
}

class _AnimatedDropdownMenuState<T> extends State<AnimatedDropdownMenu<T>>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool onHover = false;
  bool expanded = false;

  T? selectValue;
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlayEntry; // 顶层覆盖菜单
  Size? _menuSize;

  late final AnimationController expandedController;
  late final Animation<double> opacity;
  late final Animation<double> sizeFactor;
  late final Animation<double> turns;

  late final AnimationController selectController;

  @override
  void didUpdateWidget(covariant AnimatedDropdownMenu<T> oldWidget) {
    if (oldWidget.initialValue != widget.initialValue) {
      selectValue = widget.initialValue;
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    selectValue = widget.initialValue;

    expandedController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 200),
    )..addStatusListener((status) {
      if (!expanded && status.isDismissed && _overlayEntry!.mounted) {
        _overlayEntry?.remove();
        _overlayEntry = null;
      }
    });
    sizeFactor = CurvedAnimation(
      parent: expandedController,
      curve: Curves.fastOutSlowIn,
    );
    opacity = CurvedAnimation(
      parent: expandedController,
      curve: Interval(0.0, 0.5),
      reverseCurve: Interval(0.1, 0.6),
    );
    turns = Tween(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(
        parent: expandedController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInBack,
      ),
    );

    selectController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 100),
    );

    super.initState();
  }

  @override
  void dispose() {
    selectController.dispose();
    expandedController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (expanded) {
      expanded = false;
      if (!expandedController.isDismissed) {
        _closeMenu();
      }
      if (selectController.isDismissed) {
        _hoverChange();
      }
    }
    super.didChangeMetrics();
  }

  void _toggle() {
    expanded = !expanded;
    setState(() {
      if (expanded) {
        _openMenu();
      } else {
        _closeMenu();
      }
      _hoverChange();
    });
  }

  void _select(T value) {
    selectValue = value;
    _toggle();
    widget.onSelect?.call(value);
  }

  String get label {
    if (selectValue == null) return widget.hintText;
    final DropdownOption<T> o = widget.options.firstWhere(
      (o) => selectValue == o.value,
      orElse:
          () => DropdownOption<T>(
            value: selectValue as T,
            label: widget.hintText,
          ),
    );
    return o.label;
  }

  void _hoverChange() {
    if (onHover || expanded) {
      selectController.forward();
    } else {
      selectController.reverse();
    }
  }

  Widget _buildMenu(bool getSize) {
    final theme = Theme.of(context);

    final colorScheme = theme.colorScheme;

    Widget menu = Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(4),
        child: Column(
          children:
              widget.options.map((item) {
                if (getSize) {
                  return ListTile(
                    dense: true,
                    leading: item.leading,
                    title: Text(item.label),
                  );
                }
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  selected: item.value == widget.initialValue,
                  dense: true,
                  hoverColor: colorScheme.primary.withAlpha(50),
                  tileColor: colorScheme.primaryContainer,
                  selectedTileColor: colorScheme.primary.withAlpha(185),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      color:
                          item.value == widget.initialValue
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                      fontWeight:
                          item.value == widget.initialValue
                              ? FontWeight.bold
                              : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    _select(item.value);
                  },
                );
              }).toList(),
        ),
      ),
    );

    return menu;
  }

  Future<Size> get menuSize async {
    final size = context.size ?? Size.zero;
    //简单构建测高度
    final globalKey = GlobalKey();
    final measureEntry = OverlayEntry(
      builder: (_) {
        return Offstage(
          child: UnconstrainedBox(
            child: Container(
              key: globalKey,
              constraints: BoxConstraints(
                maxHeight: widget.menuHeight,
                maxWidth: size.width, //这里因为没有外部容器限制，
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: _buildMenu(true),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(measureEntry);
    Size menuSize = Size(0.0, 0.0);
    await WidgetsBinding.instance.endOfFrame;
    menuSize = globalKey.currentContext!.size!;
    measureEntry.remove();
    return menuSize;
  }

  void _openMenu() async {
    _menuSize ??= await menuSize; //获取菜单高度,并防止反复构建测高组件

    if (mounted) {
      final menuHeight = _menuSize!.height;
      final size = context.size ?? Size.zero;
      final renderBox = context.findRenderObject() as RenderBox;

      final topLeft = renderBox.localToGlobal(Offset.zero);
      final screenHeight = MediaQuery.of(context).size.height;
      final available = screenHeight - topLeft.dy - size.height - 16;

      Offset menuOffset = Offset.zero;
      if (available < menuHeight) {
        menuOffset = Offset(0.0, available - menuHeight); //超过可用高度
      }

      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;

      if (_overlayEntry == null) {
        _overlayEntry = OverlayEntry(
          builder: (context) {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                setState(() {
                  expanded = false;
                  _closeMenu();
                  _hoverChange();
                });
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CompositedTransformFollower(
                      link: _link,
                      showWhenUnlinked: false,
                      offset: menuOffset,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Column(
                          children: [
                            SizedBox(
                              height: size.height + 8,
                              width: size.height,
                              child: GestureDetector(
                                //在按钮位置上生成一个一样的检测
                                onTap: _toggle,
                              ),
                            ),
                            FadeTransition(
                              opacity: opacity,
                              child: Container(
                                width: size.width,
                                constraints: BoxConstraints(
                                  maxHeight: widget.menuHeight,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  border: Border.all(
                                    color: colorScheme.onSurface,
                                    strokeAlign: BorderSide.strokeAlignOutside,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: SizeTransition(
                                  axisAlignment: -0.75,
                                  sizeFactor: sizeFactor,
                                  child: _buildMenu(false),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
        Overlay.of(context).insert(_overlayEntry!);
      }
      expandedController.forward();
    }
  }

  void _closeMenu() {
    expandedController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onExit: (_) {
          setState(() {
            onHover = false;
            _hoverChange();
          });
        },
        onEnter: (_) {
          setState(() {
            onHover = true;
            _hoverChange();
          });
        },
        child: GestureDetector(
          onTap: _toggle,
          child: AnimatedBuilder(
            animation: selectController,
            builder: (context, child) {
              final Animation<Border?> border = BorderTween(
                begin:
                    widget.border ??
                    Border.all(
                      color: colorScheme.onSurface,
                      width: 0.9,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                end:
                    widget.hoverBorder ??
                    Border.all(
                      color: colorScheme.secondary,
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
              ).animate(selectController);

              final Animation<Color?> backgroundColor = ColorTween(
                begin: widget.color ?? colorScheme.secondary.withAlpha(0),
                end: widget.hoverColor ?? colorScheme.secondary.withAlpha(30),
              ).animate(selectController);

              return Container(
                padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                width: widget.width,
                decoration: BoxDecoration(
                  border: border.value,
                  borderRadius: BorderRadius.circular(4),
                  color: backgroundColor.value,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        switchInCurve: Interval(0.5, 1.0),
                        switchOutCurve: Interval(0.5, 1.0),
                        duration: const Duration(milliseconds: 300),
                        layoutBuilder: (oldChild, children) {
                          return Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              if (oldChild != null) oldChild,
                              ...children,
                            ],
                          );
                        },
                        child: Text(
                          label,
                          key: ValueKey(label),
                          style:
                              selectValue != null
                                  ? TextStyle()
                                  : theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.textTheme.bodyMedium?.color
                                        ?.withAlpha(185),
                                  ),
                        ),
                      ),
                    ),
                    RotationTransition(
                      turns: turns,
                      child: Icon(Icons.keyboard_arrow_down),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
