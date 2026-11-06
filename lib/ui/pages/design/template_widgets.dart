import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'template_shell.dart';
import 'template_skin.dart';

/// 参考模版的组件层：**皮肤（[TemplateSkin]）+ 这一层 = 要搬进 Copper 的东西**
///
/// 交互一律走项目的 rebound（[ReboundContainer] / [ReboundButton]），
/// 颜色全部由 [TemplateSkin] 显式传入 —— 不读 `AppColors`，因此可以脱离原皮肤试版

/// 按钮的三种**面**：实心主行动 / 标准（控件面）/ 安静（无面）
///
/// 危险**不再是第四档面**，而是一个标识（`danger: true`）——面还是那三种，只是字 / 底变红
/// （用户 2026-11-04：「danger 改为一个标识吧，有就变红；不然对话框里取消有底衬、删除没有，看着怪」）
enum TemplateButtonKind { solid, plain, quiet }

/// 分组卡：标题**在卡外**（2026-10-05 用户先问「是否应该把标题再融入 card」、
/// 试过之后要求「标题还是移出去」⇒ 回到卡外，标题贴左 4、与卡相距 8）
///
/// 三条几何规则：
/// ① **卡默认占满宽度** —— 卡宽跟着内容走时，同一页的卡宽窄不一、左边缘参差
///    （用户 2026-10-05「内容板应该默认被撑大」）
/// ② **卡内衬统一 12**（原来是「行卡 8 / 内容卡 16」两种）—— 两种内衬会让同一页的
///    卡的边距不在同一条线上
/// ③ 标题在卡外**作为组标签**：它与卡的 8px 间距在表达「这个标题管住这张卡」，
///    行卡里行的文字比卡边再深 12（那是给行自己的圆角悬停块留的）
class TemplateSection extends StatelessWidget {
  const TemplateSection({
    super.key,
    required this.skin,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.all(TemplateSpace.md),
  });

  final TemplateSkin skin;
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // 卡间距：本组件只给 12，外面 `ListContentPanel` 默认还会再给 12
    // ⇒ 卡底到下一张卡合计 24（组间），这是规范里定下的组间距离。
    // **改一边要改另一边**，别只改这里让两组加起来变成 36（2026-10-05 用户指出过大）
    return Padding(
      padding: const EdgeInsets.only(bottom: TemplateSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.sm,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: TemplateSpace.xs),
              child: Text(
                title!,
                style: TemplateType.section.copyWith(color: skin.textPrimary),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: skin.surface,
              borderRadius: BorderRadius.circular(TemplateRadius.card),
              border: Border.all(color: skin.border),
              boxShadow: [
                BoxShadow(
                  color: skin.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}

/// 卡内的一行：走 rebound 的回弹与悬停，底色按状态给
class TemplateRow extends StatelessWidget {
  const TemplateRow({
    super.key,
    required this.skin,
    required this.child,
    this.onTap,
    this.selected = false,
    this.enabled = true,
    this.padding,
  });

  final TemplateSkin skin;
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final background = selected ? skin.selected : Colors.transparent;
    return ReboundContainer(
      onTap: enabled ? onTap : null,
      pressedScale: 0.995,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      backgroundColor: background,
      // 禁用时连悬停都不回应；rebound 的悬停层与 onTap 无关，只看 hoverColor
      hoverColor: enabled ? skin.hoverOn(background) : Colors.transparent,
      highlightColor: enabled ? skin.pressedOn(background) : Colors.transparent,
      padding:
          padding ??
          const EdgeInsets.symmetric(
            horizontal: TemplateSpace.md,
            vertical: TemplateSpace.md,
          ),
      child: child,
    );
  }
}

/// 标题 + 说明两行：条目、槽位、快照都用它
class TemplateTwoLine extends StatelessWidget {
  const TemplateTwoLine({
    super.key,
    required this.skin,
    required this.title,
    this.desc,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final String title;
  final String? desc;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          title,
          style: TemplateType.item.copyWith(
            color: enabled ? skin.textPrimary : skin.textDisabled,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (desc != null)
          Text(
            desc!,
            style: TemplateType.caption.copyWith(
              color: enabled ? skin.textTertiary : skin.textDisabled,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

/// 只读的键值行：左标签、右值
class TemplateKeyRow extends StatelessWidget {
  const TemplateKeyRow({
    super.key,
    required this.skin,
    required this.title,
    required this.value,
  });

  final TemplateSkin skin;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      child: Row(
        children: [
          Expanded(
            child: TemplateTwoLine(skin: skin, title: title),
          ),
          const SizedBox(width: TemplateSpace.lg),
          // Flexible 给的是「最多一半」，Text 自己按内容宽度排 ⇒ 光设 textAlign 贴不到行尾，
          // 得让这一格自己撑满再右对齐（2026-10-24 渲染样张里值停在了中间）
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: TemplateType.item.copyWith(color: skin.textTertiary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用卡片：卡面色 + 1px 边 + 卡圆角
///
/// `TemplateSection` 是「标题 + 卡」；这块是不带标题的卡，给版本头这类自成一块的内容用
class TemplateCard extends StatelessWidget {
  const TemplateCard({
    super.key,
    required this.skin,
    required this.child,
    this.padding = const EdgeInsets.all(TemplateSpace.lg),
    this.selected = false,
    this.onTap,
  });

  final TemplateSkin skin;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected ? skin.selected : skin.surface;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(TemplateRadius.card),
        border: Border.all(color: skin.border),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return ReboundContainer(
      onTap: onTap,
      pressedScale: 0.995,
      borderRadius: BorderRadius.circular(TemplateRadius.card),
      backgroundColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      padding: EdgeInsets.zero,
      child: card,
    );
  }
}

/// 竖排字段块：**标题在上、解释在下、控件再往下**（铺满整行）
///
/// 用户 2026-11-05：「内存分配在上 / 下面是解释 / 再下面是选项」——
/// 分段 / 多选这类控件比单行控件宽，挤在右边会跟别的行对不齐，干脆单独占一块
class TemplateFieldBlock extends StatelessWidget {
  const TemplateFieldBlock({
    super.key,
    required this.skin,
    required this.title,
    required this.child,
    this.desc,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final String title;
  final String? desc;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // 横向 12：和 TemplateRow 的内边距一致，卡里混排时才不会左右错位
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TemplateSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TemplateSpace.xs,
        children: [
          Text(
            title,
            style: TemplateType.item.copyWith(
              color: enabled ? skin.textPrimary : skin.textDisabled,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (desc != null)
            Text(
              desc!,
              style: TemplateType.caption.copyWith(
                color: enabled ? skin.textSecondary : skin.textDisabled,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: TemplateSpace.xs),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// 开关行：标题 + 说明 + 右侧开关
class TemplateSwitchRow extends StatelessWidget {
  const TemplateSwitchRow({
    super.key,
    required this.skin,
    required this.title,
    required this.desc,
    required this.value,
    required this.onTap,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final String title;
  final String desc;
  final bool value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      onTap: enabled ? onTap : null,
      enabled: enabled,
      child: Row(
        children: [
          Expanded(
            child: TemplateTwoLine(
              skin: skin,
              title: title,
              desc: desc,
              enabled: enabled,
            ),
          ),
          const SizedBox(width: TemplateSpace.lg),
          TemplateSwitch(
            skin: skin,
            value: value,
            onTap: onTap,
            enabled: enabled,
          ),
        ],
      ),
    );
  }
}

/// 按钮的面：实心 = 主题色底 + 其上文字；标准 = 控件面；安静 = 无面。
/// **只有实心带主题色**（用户 2026-10-24 定）；`danger` 只换颜色不改面
///
/// 禁用态：实心留 12% 的主题色（[TemplateSkin.solidDisabledSurface]）、标准比控件面暗一档
/// （[TemplateSkin.standardDisabledSurface]）——两块要分得开，不然禁用的主行动和次级行动一模一样；
/// 安静禁用时只剩 38% 的字
class TemplateButton extends StatelessWidget {
  const TemplateButton({
    super.key,
    required this.skin,
    required this.label,
    required this.icon,
    required this.kind,
    this.danger = false,
    this.onTap,
    this.enabled = true,
    this.expanded = false,
  });

  final TemplateSkin skin;
  final String label;
  final IconData icon;
  final TemplateButtonKind kind;

  /// 危险标识：面不变，底 / 字换成危险的语义色
  final bool danger;
  final VoidCallback? onTap;
  final bool enabled;

  /// 撑满可用宽度、内容居中（任务卡底部那排等宽按钮用）
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (kind) {
      TemplateButtonKind.solid =>
        enabled
            ? (
                danger ? skin.danger : skin.accent,
                danger ? skin.onDanger : skin.onAccent,
              )
            : (
                danger
                    ? skin.danger.withAlpha((0.12 * 255).round())
                    : skin.solidDisabledSurface,
                skin.textDisabled,
              ),
      TemplateButtonKind.plain => (
        enabled ? skin.sunken : skin.standardDisabledSurface,
        enabled
            ? (danger ? skin.dangerText : skin.textPrimary)
            : skin.textDisabled,
      ),
      TemplateButtonKind.quiet => (
        Colors.transparent,
        enabled
            ? (danger ? skin.dangerText : skin.textSecondary)
            : skin.textDisabled,
      ),
    };
    // 实心上的状态要更明显，而且是「压暗」而不是按主题方向（见 solidHoverOn）
    final solid = kind == TemplateButtonKind.solid && enabled;

    final button = ReboundButton(
      onTap: enabled ? (onTap ?? () {}) : null,
      backgroundColor: background,
      hoverColor: !enabled
          ? Colors.transparent
          : solid
          ? skin.solidHoverOn(background)
          : skin.hoverOn(background),
      highlightColor: !enabled
          ? Colors.transparent
          : solid
          ? skin.solidPressedOn(background)
          : skin.pressedOn(background),
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.lg,
        vertical: TemplateSpace.sm + 1,
      ),
      // 文字样式走 Text.style 合并环境样式；整层换 DefaultTextStyle 会把字体族一起丢掉
      child: IconTheme(
        data: IconThemeData(color: foreground, size: 18),
        child: Row(
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: expanded
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          spacing: TemplateSpace.sm,
          children: [
            Icon(icon),
            Text(
              label,
              style: TemplateType.item.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );

    return button;
  }
}

/// 开关：**直接用 Flutter 原生的 [Switch]**（用户 2026-11-03：原生的挺好看，别再自己画）
///
/// 尺寸也沿用原生的一套：默认点按热区 48 高 ⇒ 单行设置 tile 的高度就取它
/// 开关：自绘（M3 形制）——原生 `Switch.thumbIcon` 只收 [Icon]，
/// 圆球里要放会加粗、会形变的勾/叉，只能自己画
///
/// 用户 2026-11-03 的口径：**槽 = 实色，圆球 = 亮色（亮色模式）/ 暗色（暗色模式）**，
/// 暗色圆球用凹槽面而不是页底（页底太黑）；圆球里 开 = 勾、关 = 叉，切换做形变过渡
class TemplateSwitch extends StatefulWidget {
  const TemplateSwitch({
    super.key,
    required this.skin,
    required this.value,
    required this.onTap,
    this.enabled = true,
  });

  /// 原生开关的默认高度（含点按热区），单行设置 tile 也按它对齐
  static const double height = kMinInteractiveDimension;

  final TemplateSkin skin;
  final bool value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<TemplateSwitch> createState() => _TemplateSwitchState();
}

class _TemplateSwitchState extends State<TemplateSwitch>
    with TickerProviderStateMixin {
  static const double _trackWidth = 52;
  static const double _trackHeight = 32;
  static const double _thumbSize = 24;
  static const double _pad = 4;

  /// 按住 / 拖动时球被拉长到多少（M3 的「球被拉伸」）
  static const double _stretchExtra = 12;

  /// 松手回弹用弹簧（阻尼比 ≈ 0.6，会有一点点过冲，看起来像回弹）
  static const SpringDescription _spring = SpringDescription(
    mass: 1,
    stiffness: 550,
    damping: 28,
  );

  /// 允许一点越界，过冲才画得出来（画的时候再夹回 0~1）
  late final AnimationController _position = AnimationController(
    vsync: this,
    lowerBound: -0.04,
    upperBound: 1.04,
    duration: const Duration(milliseconds: 220),
    value: widget.value ? 1 : 0,
  );
  late final AnimationController _stretch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );

  bool _dragging = false;
  double _velocity = 0;
  double _lastT = 0;
  Duration _lastStamp = Duration.zero;

  @override
  void didUpdateWidget(covariant TemplateSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_dragging) {
      _settle(widget.value ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _position.dispose();
    _stretch.dispose();
    super.dispose();
  }

  /// 用弹簧把 t 落到目标值（回弹动画）
  void _settle(double target) {
    _position.animateWith(
      SpringSimulation(_spring, _position.value, target, 0),
    );
  }

  /// 把拖动横坐标换算成 0~1 的 t（球心跟着指针）
  double _tForDx(double dx) {
    final thumb = _thumbSize + _stretchExtra * _stretch.value;
    final travel = _trackWidth - _pad * 2 - thumb;
    if (travel <= 0) return 0;
    return ((dx - _pad - thumb / 2) / travel).clamp(0.0, 1.0);
  }

  void _onDragStart(DragStartDetails details) {
    _dragging = true;
    _position.stop();
    _stretch.animateTo(1, duration: const Duration(milliseconds: 120));
    _lastT = _position.value;
    _lastStamp = Duration.zero;
    _velocity = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final t = _tForDx(details.localPosition.dx);
    _position.value = t;
    final stamp = details.sourceTimeStamp;
    if (stamp != null && _lastStamp != Duration.zero) {
      final dt = (stamp - _lastStamp).inMicroseconds / 1e6;
      if (dt > 0) _velocity = ((t - _lastT) / dt).clamp(-6.0, 6.0);
    }
    _lastStamp = stamp ?? _lastStamp;
    _lastT = t;
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    _stretch.animateTo(0, duration: const Duration(milliseconds: 160));
    // 惯性：往哪边甩就翻到哪边，否则看位置过半没有
    final target = (_position.value + _velocity * 0.05) >= 0.5 ? 1.0 : 0.0;
    _position.animateWith(
      SpringSimulation(_spring, _position.value, target, _velocity),
    );
    if ((target > 0.5) != widget.value) widget.onTap();
    _velocity = 0;
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final enabled = widget.enabled;
    // 暗色圆球掺主题色（用户 2026-11-04「圆球主题色再明显一点」）：22% → 38%
    final thumbOn = skin.dark
        ? Color.lerp(skin.sunken, skin.accent, 0.38)!
        : skin.surface;
    return SizedBox(
      width: _trackWidth,
      height: TemplateSwitch.height,
      child: Center(
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 点按：按下先拉长球，松手弹回
            onTapDown: enabled
                ? (_) => _stretch.animateTo(
                    1,
                    duration: const Duration(milliseconds: 110),
                  )
                : null,
            onTapUp: enabled
                ? (_) => _stretch.animateTo(
                    0,
                    duration: const Duration(milliseconds: 160),
                  )
                : null,
            onTapCancel: enabled
                ? () => _stretch.animateTo(
                    0,
                    duration: const Duration(milliseconds: 160),
                  )
                : null,
            onTap: enabled
                ? () {
                    final target = widget.value ? 0.0 : 1.0;
                    _settle(target);
                    widget.onTap();
                  }
                : null,
            // 横向拖动：球跟手、松手回弹到最近的一边
            onHorizontalDragStart: enabled ? _onDragStart : null,
            onHorizontalDragUpdate: enabled ? _onDragUpdate : null,
            onHorizontalDragEnd: enabled ? _onDragEnd : null,
            child: Semantics(
              toggled: widget.value,
              enabled: enabled,
              child: AnimatedBuilder(
                animation: Listenable.merge([_position, _stretch]),
                builder: (context, _) {
                  // 过冲夹回来再画，位置与颜色仍按夹过的 t
                  final t = _position.value.clamp(0.0, 1.0);
                  final stretch = Curves.easeOutCubic.transform(_stretch.value);
                  final thumbWidth = _thumbSize + _stretchExtra * stretch;
                  // 禁用时不保留强调色（与 M3 一致）：轨道回到凹槽面，球退成 38% 的字色
                  final trackColor = enabled
                      ? Color.lerp(skin.sunken, skin.accent, t)!
                      : skin.sunken;
                  final borderColor = enabled
                      ? Color.lerp(skin.controlBorder, Colors.transparent, t)!
                      : skin.controlBorderDisabled;
                  final thumbColor = enabled
                      ? Color.lerp(skin.textTertiary, thumbOn, t)!
                      : skin.textDisabled;
                  return Stack(
                    children: [
                      Container(
                        width: _trackWidth,
                        height: _trackHeight,
                        decoration: BoxDecoration(
                          color: trackColor,
                          borderRadius: BorderRadius.circular(_trackHeight / 2),
                          // 自研就把边缘加厚：常态 2px（原生是 1px），开态一起淡出
                          border: Border.all(color: borderColor, width: 2),
                        ),
                      ),
                      Positioned(
                        left: _pad + (_trackWidth - thumbWidth - _pad * 2) * t,
                        top: (_trackHeight - _thumbSize) / 2,
                        width: thumbWidth,
                        height: _thumbSize,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: thumbColor,
                            borderRadius: BorderRadius.circular(_thumbSize / 2),
                          ),
                          child: enabled
                              ? Center(
                                  child: CustomPaint(
                                    size: const Size.square(15),
                                    painter: _SwitchGlyphPainter(
                                      t: t,
                                      onColor: skin.accent,
                                      offColor: skin.dark
                                          ? skin.page
                                          : skin.surface,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 叉 → 勾的形变：两条笔画各自的端点线性插值（叉的两条对角线正好滑成勾的两段折线）
class _SwitchGlyphPainter extends CustomPainter {
  const _SwitchGlyphPainter({
    required this.t,
    required this.onColor,
    required this.offColor,
  });

  final double t;
  final Color onColor;
  final Color offColor;

  @override
  void paint(Canvas canvas, Size size) {
    Offset p(double x, double y) => Offset(x * size.width, y * size.height);
    final paint = Paint()
      ..color = Color.lerp(offColor, onColor, t)!
      // 加厚：笔画取边长 17%（16 的球里约 2.7）
      ..strokeWidth = size.width * 0.17
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // 笔画一：叉的左上一笔 → 勾的短边
    canvas.drawLine(
      Offset.lerp(p(0.28, 0.28), p(0.26, 0.56), t)!,
      Offset.lerp(p(0.72, 0.72), p(0.45, 0.74), t)!,
      paint,
    );
    // 笔画二：叉的右上一笔 → 勾的长边（终点重合在勾的拐点上）
    canvas.drawLine(
      Offset.lerp(p(0.72, 0.28), p(0.45, 0.74), t)!,
      Offset.lerp(p(0.28, 0.72), p(0.77, 0.28), t)!,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SwitchGlyphPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.onColor != onColor ||
      oldDelegate.offColor != offColor;
}

/// 一条独立设置：单行标题 + 右侧控件，**高度取原生开关的默认高度**
///
/// 这样「一个开关 = 一条设置」在一列里高度一致，接下去设置页都按这个规格排
class TemplateSettingTile extends StatelessWidget {
  const TemplateSettingTile({
    super.key,
    required this.skin,
    required this.title,
    this.trailing,
    this.onTap,
  });

  final TemplateSkin skin;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: TemplateSpace.md),
      child: SizedBox(
        height: TemplateSwitch.height,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TemplateType.item.copyWith(color: skin.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// 单选分段：单选语义就用它，别拿复选框手拼
///
/// 选中格的**面是一道轻渐变**（上亮下暗 = 抬起），三个状态改变这道渐变而不是叠色：
/// 悬停整体深/浅一档、**按下把渐变反过来**（上暗下亮 = 压进去）。
/// 这样按下与悬停的区别是「光的方向」而不是明度差 —— 凹槽底与选中格本来只差 8 个 tone，
/// 继续靠压暗做按下就会撞上凹槽底，看着既糊又怪
class TemplateSegment extends StatelessWidget {
  const TemplateSegment({
    super.key,
    required this.skin,
    required this.options,
    required this.value,
    required this.onTap,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final List<String> options;
  final int value;
  final void Function(int index) onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(TemplateSpace.xs),
      decoration: BoxDecoration(
        color: skin.sunken,
        borderRadius: BorderRadius.circular(
          TemplateRadius.control + TemplateSpace.xs,
        ),
        border: Border.all(
          color: enabled ? skin.controlBorder : skin.controlBorderDisabled,
        ),
      ),
      child: Row(
        spacing: TemplateSpace.xs,
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: _SegmentPill(
                skin: skin,
                label: options[i],
                selected: value == i,
                enabled: enabled,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
  }
}

/// 分段的单格：自己跟踪悬停 / 按下，好让三态各自给一道渐变
class _SegmentPill extends StatefulWidget {
  const _SegmentPill({
    required this.skin,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final TemplateSkin skin;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_SegmentPill> createState() => _SegmentPillState();
}

class _SegmentPillState extends State<_SegmentPill> {
  bool _hover = false;

  /// 选中格的渐变两端（tone）：静止 / 悬停
  ///
  /// 用户 2026-11-03：**要这层「小立体」**——不明显，但质感提升很多（别做成纯色）。
  /// 取值的边界没变：**最暗的一档不能碰到凹槽底**（亮色底 tone 90 / 暗色底 20），
  /// 悬停时整体挪一档；按下不改底色，只留回弹缩放
  (double, double) get _stops {
    if (widget.skin.dark) return _hover ? (32, 27) : (29, 25);
    return _hover ? (97, 95) : (98, 96);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final selected = widget.selected;
    final enabled = widget.enabled;

    // 需要按悬停换渐变，而 rebound 的悬停是它自己的内部状态（没有回调可用）
    // ⇒ 这里自己监听指针：MouseRegion 是被动观察，不抢点击与回弹
    return MouseRegion(
      onEnter: (_) {
        if (enabled) setState(() => _hover = true);
      },
      onExit: (_) {
        if (enabled) setState(() => _hover = false);
      },
      child: ReboundContainer(
        onTap: enabled ? widget.onTap : null,
        pressedScale: 0.96,
        borderRadius: BorderRadius.circular(TemplateRadius.control),
        backgroundColor: Colors.transparent,
        // 状态由渐变表达，这里不再叠色（叠色正是「融合」的来源）；
        // 主题的水波（splash）也关掉，不然点击瞬间会闪过一层旧强调色
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        // 一律用渐变（未选中＝两端同色的透明/薄底）：同类型之间才插值得平滑，
        // 底色与渐变互换时会硬切
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            vertical: TemplateSpace.sm,
            horizontal: TemplateSpace.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TemplateRadius.control),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: selected
                  ? [skin.neutralTone(_stops.$1), skin.neutralTone(_stops.$2)]
                  : [
                      enabled && _hover
                          ? skin.hoverOn(Colors.transparent)
                          : Colors.transparent,
                      enabled && _hover
                          ? skin.hoverOn(Colors.transparent)
                          : Colors.transparent,
                    ],
            ),
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TemplateType.item.copyWith(
              color: !enabled
                  ? skin.textDisabled
                  : selected
                  ? skin.textPrimary
                  : skin.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// 标签页（下划线式）：一级分类切换，比分段控件更轻，适合「版本列表 / 介绍 / Readme」这种并列内容
class TemplateTabBar extends StatelessWidget {
  const TemplateTabBar({
    super.key,
    required this.skin,
    required this.tabs,
    required this.value,
    required this.onTap,
    this.trailing,
  });

  final TemplateSkin skin;
  final List<String> tabs;
  final int value;
  final ValueChanged<int> onTap;

  /// 右侧附加内容（比如计数、刷新按钮）
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 整条底边线：选中项自己再压一道强调色
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(height: 1, color: skin.border),
        ),
        Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              _TabItem(
                skin: skin,
                label: tabs[i],
                selected: i == value,
                onTap: () => onTap(i),
              ),
            const Spacer(),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(bottom: TemplateSpace.xs),
                child: trailing!,
              ),
            const SizedBox(width: TemplateSpace.md),
          ],
        ),
      ],
    );
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.skin,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final TemplateSkin skin;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: TemplateSpace.sm,
            vertical: TemplateSpace.sm,
          ),
          color: _hover && !widget.selected
              ? skin.hoverOn(skin.page)
              : Colors.transparent,
          // IntrinsicWidth：Row 里子项宽度不定，这里先按文字宽度定死，下划线才能撑满
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: TemplateSpace.sm,
              children: [
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: TemplateType.item.copyWith(
                    color: widget.selected
                        ? skin.textPrimary
                        : skin.textSecondary,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 2,
                  decoration: BoxDecoration(
                    color: widget.selected ? skin.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 提示条的语气
enum TemplateNoticeTone { info, success, warning, danger, note }

/// 提示条：靠底色与左边一道强调线，不靠描边把整条圈起来
///
/// 2026-11-05 补：语气（info / success / warning / danger）、可关闭、行内动作——
/// 覆盖度审计 P0-10（原来的静态一条替代不了错误 / 成功这些场景）
class TemplateNotice extends StatelessWidget {
  const TemplateNotice({
    super.key,
    required this.skin,
    required this.text,
    this.tone = TemplateNoticeTone.info,
    this.icon,
    this.title,
    this.action,
    this.onClose,
  });

  final TemplateSkin skin;
  final String text;
  final TemplateNoticeTone tone;

  /// 不给就按语气取默认图标
  final IconData? icon;
  final String? title;

  /// 行内动作，一般是一个安静的按钮
  final Widget? action;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final (bar, iconColor) = switch (tone) {
      TemplateNoticeTone.info => (skin.accent, skin.accentText),
      TemplateNoticeTone.success => (skin.success, skin.success),
      TemplateNoticeTone.warning => (skin.warning, skin.warning),
      TemplateNoticeTone.danger => (skin.danger, skin.dangerText),
      TemplateNoticeTone.note => (skin.note, skin.noteText),
    };
    final resolvedIcon =
        icon ??
        switch (tone) {
          TemplateNoticeTone.info => Icons.info_outline,
          TemplateNoticeTone.success => Icons.check_circle_outline,
          TemplateNoticeTone.warning => Icons.warning_amber_outlined,
          TemplateNoticeTone.danger => Icons.error_outline,
          TemplateNoticeTone.note => Icons.lightbulb_outline,
        };
    // 外面不再自带边距：它是卡里的一项，间距由卡片自己（`TemplateSection.spacing`）管
    return DecoratedBox(
      decoration: BoxDecoration(
        color: skin.sunken,
        borderRadius: BorderRadius.circular(TemplateRadius.card),
        border: Border(left: BorderSide(color: bar, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TemplateSpace.lg,
          vertical: TemplateSpace.md,
        ),
        child: Row(
          spacing: TemplateSpace.md,
          children: [
            Icon(resolvedIcon, size: 18, color: iconColor),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: TemplateType.item.copyWith(
                        color: skin.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    text,
                    style: TemplateType.caption.copyWith(
                      color: skin.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) action!,
            if (onClose != null)
              TemplateIconButton(
                skin: skin,
                icon: Icons.close,
                size: 24,
                iconSize: 14,
                tooltip: '关闭',
                onTap: onClose,
              ),
          ],
        ),
      ),
    );
  }
}

/// 快捷入口小方块：并列入口，中性重量
class TemplateShortcut extends StatelessWidget {
  const TemplateShortcut({
    super.key,
    required this.skin,
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? skin.textSecondary : skin.textDisabled;
    return ReboundContainer(
      onTap: enabled ? (onTap ?? () {}) : null,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      backgroundColor: skin.sunken,
      hoverColor: enabled ? skin.hoverOn(skin.sunken) : Colors.transparent,
      highlightColor: enabled
          ? skin.pressedOn(skin.sunken)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.lg,
        vertical: TemplateSpace.md,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: TemplateSpace.sm,
        children: [
          Icon(icon, size: 18, color: foreground),
          Text(label, style: TemplateType.item.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

/// 下拉行：左边标签、右边下拉框（值 + 箭头）
///
/// 模版还没有真正的下拉组件，这里先给它的样子；[onTap] 为空时就是个静态框
class TemplateSelectRow extends StatelessWidget {
  const TemplateSelectRow({
    super.key,
    required this.skin,
    required this.title,
    required this.value,
    this.onTap,
    this.enabled = true,
    this.labelWidth = 150,
  });

  final TemplateSkin skin;
  final String title;
  final String value;
  final VoidCallback? onTap;
  final bool enabled;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      onTap: onTap,
      enabled: enabled,
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              title,
              style: TemplateType.item.copyWith(
                color: enabled ? skin.textPrimary : skin.textDisabled,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: TemplateSpace.lg),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: TemplateSpace.md,
                vertical: TemplateSpace.sm,
              ),
              decoration: BoxDecoration(
                color: skin.sunken,
                borderRadius: BorderRadius.circular(TemplateRadius.control),
                border: Border.all(
                  color: enabled
                      ? skin.controlBorder
                      : skin.controlBorderDisabled,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: TemplateType.item.copyWith(
                        color: enabled ? skin.textPrimary : skin.textDisabled,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.expand_more,
                    size: 18,
                    color: enabled ? skin.textSecondary : skin.textDisabled,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 进度条：细轨 + 实心填充（列表行内与内存占用都用它）
///
/// 默认高度 12（用户 2026-11-03 定：不同位置可以各自覆盖，但全项目默认 12）
class TemplateProgressBar extends StatelessWidget {
  const TemplateProgressBar({
    super.key,
    required this.skin,
    required this.value,
    this.height = 12,
    this.enabled = true,
    this.indeterminate = false,
    this.secondary,
  });

  final TemplateSkin skin;
  final double value;
  final double height;
  final bool enabled;

  /// 总量未知时用不确定态：一条色块来回滑，比恒为 0 的进度条诚实
  final bool indeterminate;

  /// 第二段（0~1）：内存「已分配」这类底量，画成淡主题色，[value] 再叠在上面
  final double? secondary;

  @override
  Widget build(BuildContext context) {
    if (indeterminate) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(TemplateRadius.pill),
        child: SizedBox(
          height: height,
          child: _IndeterminateBar(skin: skin),
        ),
      );
    }
    if (secondary != null) {
      // 双段：淡底（已分配）+ 实心（已用）；宽度按分数直接算，不依赖 Flex
      final filled = value.clamp(0.0, 1.0);
      final reserved = secondary!.clamp(0.0, 1.0);
      return ClipRRect(
        borderRadius: BorderRadius.circular(TemplateRadius.pill),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              Widget band(double fraction, Color color) => Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: width * fraction,
                child: ColoredBox(color: color),
              );
              return Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: skin.sunken)),
                  if (reserved > 0)
                    band(
                      reserved,
                      // 淡主题色：用强调色加透明度，暗色下也看得见（accentTint 在暗色里与凹槽底太接近）
                      enabled
                          ? skin.accent.withAlpha(
                              (skin.dark ? 0.30 : 0.32) * 255 ~/ 1,
                            )
                          : skin.standardDisabledSurface,
                    ),
                  if (filled > 0)
                    band(filled, enabled ? skin.accent : skin.textDisabled),
                ],
              );
            },
          ),
        ),
      );
    }
    // 用两段 Expanded 拼出来：FractionallySizedBox 里的 ColoredBox 没有子节点时会量成 0 宽，
    // 填充段在样张里根本画不出来（2026-10-24 渲染时发现）
    final clamped = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(TemplateRadius.pill),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            if (clamped > 0)
              Expanded(
                flex: (clamped * 1000).round(),
                child: ColoredBox(
                  color: enabled ? skin.accent : skin.textDisabled,
                  child: const SizedBox.expand(),
                ),
              ),
            if (clamped < 1)
              Expanded(
                flex: ((1 - clamped) * 1000).round(),
                child: ColoredBox(
                  color: skin.sunken,
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 不确定进度：槽底 + 一段 35% 宽的色块来回滑动
class _IndeterminateBar extends StatefulWidget {
  const _IndeterminateBar({required this.skin});

  final TemplateSkin skin;

  @override
  State<_IndeterminateBar> createState() => _IndeterminateBarState();
}

class _IndeterminateBarState extends State<_IndeterminateBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return ColoredBox(
      color: skin.sunken,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return FractionallySizedBox(
            alignment: Alignment.centerLeft,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 色块从左侧滑出、到右侧完全出去：位置 = -0.35 → 1.0
                final position = -0.35 + _controller.value * 1.35;
                return Stack(
                  children: [
                    Positioned(
                      left: constraints.maxWidth * position,
                      width: constraints.maxWidth * 0.35,
                      top: 0,
                      bottom: 0,
                      child: ColoredBox(color: skin.accent),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// 滑条行：标题 + 实时值 + 可点可拖的轨道
class TemplateSliderRow extends StatelessWidget {
  const TemplateSliderRow({
    super.key,
    required this.skin,
    required this.title,
    required this.value,
    required this.label,
    this.onChanged,
    this.divisions = 20,
    this.enabled = true,
    this.minLabel,
    this.maxLabel,
    this.showTicks = false,
  });

  final TemplateSkin skin;
  final String title;
  final double value;
  final String label;
  final ValueChanged<double>? onChanged;
  final int divisions;
  final bool enabled;

  /// 轨道两端的量程文字（如 `0 GB` / `8 GB`）
  final String? minLabel;
  final String? maxLabel;

  /// 轨道下画刻度点（档位数取 [divisions]，太多会自动稀疏）
  final bool showTicks;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      enabled: enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.md,
        children: [
          Row(
            children: [
              Expanded(
                child: TemplateTwoLine(
                  skin: skin,
                  title: title,
                  enabled: enabled,
                ),
              ),
              const SizedBox(width: TemplateSpace.lg),
              Text(
                label,
                style: TemplateType.item.copyWith(
                  color: enabled ? skin.textPrimary : skin.textDisabled,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          _buildTrack(),
          if (showTicks || minLabel != null || maxLabel != null) ...[
            const SizedBox(height: TemplateSpace.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TemplateSpace.sm,
              children: [
                if (minLabel != null)
                  Text(
                    minLabel!,
                    style: TemplateType.micro.copyWith(
                      color: skin.textTertiary,
                    ),
                  ),
                if (showTicks) ...[
                  Expanded(child: _buildTicks()),
                ] else
                  const Spacer(),
                if (maxLabel != null)
                  Text(
                    maxLabel!,
                    style: TemplateType.micro.copyWith(
                      color: skin.textTertiary,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 刻度点：0 ~ 1 之间均匀画 [divisions] + 1 个点，超过 12 档就每 2 档点一个
  Widget _buildTicks() {
    final count = divisions + 1;
    final step = count > 12 ? (count / 12).ceil() : 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < count; i += step)
          Container(
            width: 2,
            height: 4,
            color: enabled ? skin.borderStrong : skin.controlBorderDisabled,
          ),
      ],
    );
  }

  Widget _buildTrack() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        void update(double dx) {
          if (!enabled || onChanged == null || width <= 0) return;
          final raw = (dx / width).clamp(0.0, 1.0);
          final stepped = divisions <= 1
              ? raw
              : (raw * divisions).roundToDouble() / divisions;
          onChanged!(stepped);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled
              ? (detail) => update(detail.localPosition.dx)
              : null,
          onHorizontalDragUpdate: enabled
              ? (detail) => update(detail.localPosition.dx)
              : null,
          child: SizedBox(
            height: 40,
            child: LayoutBuilder(
              builder: (context, inner) {
                // 「24 版」：粗实心轨道 + 一根细长竖杆当把手（比轨道高一截），
                // 杆两侧留缝把轨道断开；杆色亮色模式取亮、暗色模式取暗（用户 2026-11-03）
                // 竖杆高度 18 → 24（用户 2026-11-04「滑杆过矮，提高一点」）
                const trackHeight = 12.0;
                const handleWidth = 4.0;
                const handleHeight = 24.0;
                const gap = 3.0;
                final trackWidth = inner.maxWidth;
                final x = trackWidth * value.clamp(0.0, 1.0);
                final handleColor = enabled
                    ? (skin.dark ? skin.sunken : skin.surface)
                    : skin.controlBorderDisabled;

                Widget segment(double left, double right, Color color) {
                  final segWidth = (right - left).clamp(0.0, trackWidth);
                  return Positioned(
                    left: left,
                    width: segWidth,
                    top: (40 - trackHeight) / 2,
                    height: trackHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(trackHeight / 2),
                      ),
                    ),
                  );
                }

                return Stack(
                  children: [
                    segment(0, x - gap, enabled ? skin.accent : skin.sunken),
                    segment(
                      (x + gap).clamp(0.0, trackWidth),
                      trackWidth,
                      skin.sunken,
                    ),
                    Positioned(
                      left: (x - handleWidth / 2).clamp(
                        0.0,
                        (trackWidth - handleWidth).clamp(0.0, trackWidth),
                      ),
                      top: (40 - handleHeight) / 2,
                      width: handleWidth,
                      height: handleHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: handleColor,
                          borderRadius: BorderRadius.circular(handleWidth / 2),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// 输入框：单行 / 多行 / 密码（可显隐）/ 后缀控件 / 错误说明 / 字数上限
///
/// 覆盖度审计 P1-11：原先只有「标题 + 单行输入」的 [TemplateInputRow]，
/// 设置页里的参数框、备注、端口、路径都需要这些形态
class TemplateTextField extends StatefulWidget {
  const TemplateTextField({
    super.key,
    required this.skin,
    required this.controller,
    this.hint = '',
    this.enabled = true,
    this.maxLines = 1,
    this.obscure = false,
    this.error,
    this.maxLength,
    this.suffix,
    this.onSubmitted,
  });

  final TemplateSkin skin;
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final int maxLines;

  /// 密码态：右侧自动加一个显隐按钮
  final bool obscure;

  /// 给了就是错误态（描边与说明都换成危险色）
  final String? error;

  /// 字数上限：给了就在右下角显示 `n / max`
  final int? maxLength;

  /// 输入框内的后缀（单位、浏览按钮…）
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  State<TemplateTextField> createState() => _TemplateTextFieldState();
}

class _TemplateTextFieldState extends State<TemplateTextField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final hasError = widget.error != null;
    final borderColor = !widget.enabled
        ? skin.controlBorderDisabled
        : hasError
        ? skin.danger
        : skin.controlBorder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TemplateSpace.xs,
      children: [
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          maxLines: widget.maxLines,
          obscureText: widget.obscure && !_revealed,
          maxLength: widget.maxLength,
          onSubmitted: widget.onSubmitted,
          style: TemplateType.item.copyWith(
            color: widget.enabled ? skin.textPrimary : skin.textDisabled,
          ),
          cursorColor: skin.accent,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            hintStyle: TemplateType.item.copyWith(color: skin.textTertiary),
            // 字数自己画在下面，关掉 Material 那套计数器
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: TemplateSpace.md,
              vertical: TemplateSpace.md,
            ),
            filled: true,
            fillColor: skin.sunken,
            suffixIcon: widget.obscure
                ? IconButton(
                    onPressed: () => setState(() => _revealed = !_revealed),
                    icon: Icon(
                      _revealed ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                      color: skin.textTertiary,
                    ),
                  )
                : widget.suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TemplateRadius.control),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TemplateRadius.control),
              borderSide: BorderSide(
                color: hasError ? skin.danger : skin.accent,
                width: 2,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TemplateRadius.control),
              borderSide: BorderSide(color: skin.controlBorderDisabled),
            ),
          ),
        ),
        if (hasError || widget.maxLength != null)
          Row(
            children: [
              Expanded(
                child: hasError
                    ? Text(
                        widget.error!,
                        style: TemplateType.caption.copyWith(
                          color: skin.dangerText,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (widget.maxLength != null)
                Text(
                  '${widget.controller.text.characters.length} / ${widget.maxLength}',
                  style: TemplateType.micro.copyWith(color: skin.textTertiary),
                ),
            ],
          ),
      ],
    );
  }
}

/// 输入行：标题 + 输入框（聚焦时描边换强调色）
class TemplateInputRow extends StatelessWidget {
  const TemplateInputRow({
    super.key,
    required this.skin,
    required this.title,
    required this.controller,
    this.hint = '',
    this.enabled = true,
    this.multiline = false,
    this.obscure = false,
    this.error,
    this.maxLength,
    this.suffix,
  });

  final TemplateSkin skin;
  final String title;
  final TextEditingController controller;
  final String hint;
  final bool enabled;

  /// 多行（说明 / 备注 / 参数），给 4 行高
  final bool multiline;
  final bool obscure;
  final String? error;
  final int? maxLength;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TemplateRow(
      skin: skin,
      enabled: enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TemplateSpace.sm,
        children: [
          Text(
            title,
            style: TemplateType.caption.copyWith(
              color: enabled ? skin.textTertiary : skin.textDisabled,
            ),
          ),
          TemplateTextField(
            skin: skin,
            controller: controller,
            hint: hint,
            enabled: enabled,
            maxLines: multiline ? 4 : 1,
            obscure: obscure,
            error: error,
            maxLength: maxLength,
            suffix: suffix,
          ),
        ],
      ),
    );
  }
}

/// 列表项卡：图标 / 封面 + 两行文字 + 右侧动作 + 角标
///
/// 覆盖度审计 P0-9：`TemplateTwoLine` 只有两行纯文本且 maxLines 1，
/// 版本列表 / 模组列表 / 存档列表都需要「图 + 元信息 + 动作 + 状态角标」
class TemplateListCard extends StatelessWidget {
  const TemplateListCard({
    super.key,
    required this.skin,
    required this.title,
    this.subtitle,
    this.icon,
    this.cover,
    this.badge,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  final TemplateSkin skin;
  final String title;
  final String? subtitle;

  /// 前导图标；给了 [cover] 就用图
  final IconData? icon;
  final Widget? cover;
  final Widget? badge;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final background = selected ? skin.selected : Colors.transparent;
    return ReboundContainer(
      onTap: enabled ? onTap : null,
      pressedScale: 0.995,
      borderRadius: BorderRadius.circular(TemplateRadius.control),
      backgroundColor: background,
      hoverColor: enabled ? skin.hoverOn(background) : Colors.transparent,
      highlightColor: enabled ? skin.pressedOn(background) : Colors.transparent,
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateSpace.md,
        vertical: TemplateSpace.sm,
      ),
      child: Row(
        spacing: TemplateSpace.md,
        children: [
          if (cover != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(TemplateRadius.control),
              child: SizedBox(width: 40, height: 40, child: cover),
            )
          else if (icon != null)
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: skin.sunken,
                borderRadius: BorderRadius.circular(TemplateRadius.control),
              ),
              child: Icon(
                icon,
                size: 18,
                color: enabled ? skin.textSecondary : skin.textDisabled,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Row(
                  spacing: TemplateSpace.sm,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TemplateType.item.copyWith(
                          color: enabled ? skin.textPrimary : skin.textDisabled,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (badge != null) badge!,
                  ],
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TemplateType.caption.copyWith(
                      color: enabled ? skin.textTertiary : skin.textDisabled,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 网格卡：封面 + 标题 + 副标题，资源页 / 版本页的卡片格
class TemplateGridCard extends StatelessWidget {
  const TemplateGridCard({
    super.key,
    required this.skin,
    required this.title,
    this.subtitle,
    this.cover,
    this.icon,
    this.badge,
    this.onTap,
    this.selected = false,
  });

  final TemplateSkin skin;
  final String title;
  final String? subtitle;
  final Widget? cover;
  final IconData? icon;
  final Widget? badge;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final background = selected ? skin.selected : skin.surface;
    return ReboundContainer(
      onTap: onTap,
      pressedScale: 0.985,
      borderRadius: BorderRadius.circular(TemplateRadius.card),
      backgroundColor: background,
      hoverColor: skin.hoverOn(background),
      highlightColor: skin.pressedOn(background),
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TemplateRadius.card),
          border: Border.all(color: selected ? skin.accent : skin.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(TemplateRadius.card - 1),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child:
                    cover ??
                    ColoredBox(
                      color: skin.sunken,
                      child: Icon(
                        icon ?? Icons.image_outlined,
                        size: 28,
                        color: skin.textTertiary,
                      ),
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(TemplateSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Row(
                    spacing: TemplateSpace.sm,
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TemplateType.item.copyWith(
                            color: skin.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null) badge!,
                    ],
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TemplateType.caption.copyWith(
                        color: skin.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分页器：第 x / y 页 + 上一页 / 下一页（可选首末页）
class TemplatePager extends StatelessWidget {
  const TemplatePager({
    super.key,
    required this.skin,
    required this.page,
    required this.pageCount,
    required this.onPage,
    this.firstLast = false,
  });

  final TemplateSkin skin;

  /// 1 起
  final int page;
  final int pageCount;
  final ValueChanged<int> onPage;

  /// 是否给「首页 / 末页」
  final bool firstLast;

  @override
  Widget build(BuildContext context) {
    Widget button(String label, IconData icon, int target) => TemplateButton(
      skin: skin,
      label: label,
      icon: icon,
      kind: TemplateButtonKind.quiet,
      enabled: target >= 1 && target <= pageCount && target != page,
      onTap: () => onPage(target),
    );

    return Row(
      spacing: TemplateSpace.sm,
      children: [
        Expanded(
          child: Text(
            '第 $page / $pageCount 页',
            style: TemplateType.caption.copyWith(color: skin.textTertiary),
          ),
        ),
        if (firstLast) button('首页', Icons.first_page, 1),
        button('上一页', Icons.chevron_left, page - 1),
        button('下一页', Icons.chevron_right, page + 1),
        if (firstLast) button('末页', Icons.last_page, pageCount),
      ],
    );
  }
}

/// 折叠面板：标题行（可点整行）+ 展开后的内容
///
/// 展开态用 [AnimatedSize] 过渡；内容由调用方给（一般是一组 KeyRow / 设置行）
class TemplateCollapse extends StatefulWidget {
  const TemplateCollapse({
    super.key,
    required this.skin,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.initiallyExpanded = false,
  });

  final TemplateSkin skin;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<TemplateCollapse> createState() => _TemplateCollapseState();
}

class _TemplateCollapseState extends State<TemplateCollapse> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return Container(
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(TemplateRadius.card),
        border: Border.all(color: skin.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReboundContainer(
            onTap: () => setState(() => _expanded = !_expanded),
            pressedScale: 0.995,
            borderRadius: BorderRadius.circular(TemplateRadius.card),
            backgroundColor: Colors.transparent,
            hoverColor: skin.hoverOn(skin.surface),
            highlightColor: skin.pressed,
            padding: const EdgeInsets.all(TemplateSpace.md),
            child: Row(
              spacing: TemplateSpace.sm,
              children: [
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: skin.textTertiary,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TemplateType.item.copyWith(
                          color: skin.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          style: TemplateType.caption.copyWith(
                            color: skin.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(
                          horizontal: TemplateSpace.md,
                        ),
                        color: skin.border,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(TemplateSpace.md),
                        child: widget.child,
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
