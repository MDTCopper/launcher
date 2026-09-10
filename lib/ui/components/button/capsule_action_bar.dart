import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 胶囊里的一个动作入口
class CapsuleAction {
  const CapsuleAction({
    required this.icon,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;

  /// 按钮只有图标，作用交给 [HintLayer] 提示
  final String hint;

  final VoidCallback onTap;
}

/// 胶囊操作栏：图标按钮竖着装在一颗胶囊里
///
/// - 收纳：只留顶部切换键，其余按钮用 [AnimatedSize] + `heightFactor` 压到 0
/// - 展开：向下长出按钮，胶囊随之变长（[StadiumBorder] 圆角跟着自适应）
/// - 按钮是胶囊内的圆形热区（透明底、不叠阴影），作用经 [HintLayer] 提示
class CapsuleActionBar extends StatefulWidget {
  const CapsuleActionBar({
    super.key,
    required this.actions,
    this.initExpanded = true,
    this.expandIcon = Icons.tune,
    this.collapseIcon = Icons.close,
    this.expandHint = '展开',
    this.collapseHint = '收纳',
    this.buttonSize = 40,
  });

  final List<CapsuleAction> actions;

  /// 初始是否展开
  final bool initExpanded;

  /// 切换键的图标与提示（按展开状态二选一）
  final IconData expandIcon;
  final IconData collapseIcon;
  final String expandHint;
  final String collapseHint;

  /// 单个按钮的边长，也是胶囊宽度
  final double buttonSize;

  @override
  State<CapsuleActionBar> createState() => _CapsuleActionBarState();
}

class _CapsuleActionBarState extends State<CapsuleActionBar> {
  late bool _isExpanded = widget.initExpanded;

  void _toggle() {
    setState(() => _isExpanded = !_isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isExpanded = _isExpanded;

    return Material(
      color: colors.cardBackground,
      elevation: 4,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(
            hint: isExpanded ? widget.collapseHint : widget.expandHint,
            onTap: _toggle,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => RotationTransition(
                turns: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                isExpanded ? widget.collapseIcon : widget.expandIcon,
                key: ValueKey(isExpanded),
                size: 20,
              ),
            ),
          ),

          // 收纳：高度压到 0，AnimatedSize 负责动画、ClipRect 负责裁切
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: ClipRect(
              child: AnimatedOpacity(
                opacity: isExpanded ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Align(
                  alignment: Alignment.topCenter,
                  // widthFactor 必须给 1：为 null 时 Align 会按父级最大宽度撑满，
                  // 外层 Column 的 crossSize 跟着变宽，胶囊就被横向拉成一条
                  widthFactor: 1,
                  heightFactor: isExpanded ? 1 : 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final action in widget.actions)
                        _buildButton(
                          hint: action.hint,
                          onTap: action.onTap,
                          child: Icon(action.icon, size: 20),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 胶囊内的按钮：透明底（不叠阴影）、圆形热区、提示默认显示在左侧
  Widget _buildButton({
    required Widget child,
    required String hint,
    required VoidCallback onTap,
  }) {
    return HintLayer(
      hint: hint,
      preferPosition: HintPosition.left,
      child: ReboundContainer(
        backgroundColor: Colors.transparent,
        borderRadius: BorderRadius.circular(widget.buttonSize / 2),
        onTap: onTap,
        child: SizedBox(
          width: widget.buttonSize,
          height: widget.buttonSize,
          child: Center(child: child),
        ),
      ),
    );
  }
}
