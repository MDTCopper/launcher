import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 滚动回顶浮层：监听 [ScrollController]，滚动超过 [showThreshold] 时浮现
/// 回顶按钮，低于 [hideThreshold] 时隐藏；点击滚动到顶部。
///
/// 需要时再套（如 `BackToTopLayer(controller: c, child: list)`），
/// 滚动视图本身不内嵌。
class BackToTopLayer extends StatefulWidget {
  final ScrollController controller;
  final Widget child;
  final double showThreshold; // 滚动超过此值显示按钮
  final double hideThreshold; // 滚动低于此值隐藏按钮
  final Alignment alignment; // 按钮位置

  const BackToTopLayer({
    super.key,
    required this.controller,
    required this.child,
    this.showThreshold = 1200,
    this.hideThreshold = 600,
    this.alignment = const Alignment(0, 0.9), // 底部中央偏左
  });

  @override
  State<StatefulWidget> createState() => _BackToTopLayerState();
}

class _BackToTopLayerState extends State<BackToTopLayer> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final offset = widget.controller.offset;
    final show = offset > widget.showThreshold;
    final hide = offset < widget.hideThreshold;
    if (show && !_show) {
      setState(() => _show = true);
    } else if (hide && _show) {
      setState(() => _show = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.of(context);
    return Stack(
      children: [
        widget.child,
        Align(
          alignment: widget.alignment,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: AnimatedOpacity(
              opacity: _show ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeIn,
              child: AnimatedScale(
                scale: _show ? 1.0 : 0.0,
                curve: Curves.easeOutBack,
                duration: const Duration(milliseconds: 200),
                child: ReboundButton(
                  hoverElevation: 4.0,
                  elevation: 1.0,
                  borderRadius: const BorderRadius.all(Radius.circular(50)),
                  baseColor: color.cardBackground,
                  onTap: () {
                    widget.controller.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: const Icon(Icons.arrow_upward),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
