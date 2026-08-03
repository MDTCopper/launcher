import 'package:copper_launcher/ui/components/scroll/scroll_fade_mask.dart';
import 'package:copper_launcher/ui/util/widget/desktop_scroll_view.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/material.dart';

///Copper单子滚动视图，带有桌面端滚动条和顶部底部渐变遮罩
///
///本质就是多套了DesktopScrollViewContainer和ScrollFadeMask
class CopperSingleChildScrollView extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;

  const CopperSingleChildScrollView({
    super.key,
    required this.child,
    this.padding,
    this.controller,
  });

  @override
  State<StatefulWidget> createState() => _CopperSingleChildScrollViewState();
}

class _CopperSingleChildScrollViewState
    extends State<CopperSingleChildScrollView> {
  late final ScrollController _scrollController;

  @override
  initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
  }

  @override
  dispose() {
    if (widget.controller == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  bool showTopFade = false;
  bool showBottomFade = false;

  @override
  Widget build(BuildContext context) {
    Widget child = SingleChildScrollView(
      controller: _scrollController,
      padding: widget.padding,
      child: widget.child,
    );
    if (isDesktop) {
      child = DesktopScrollViewContainer(
        controller: _scrollController,
        child: child,
      );
    }
    child = ScrollFadeMask(controller: _scrollController, child: child);

    return child;
  }
}
