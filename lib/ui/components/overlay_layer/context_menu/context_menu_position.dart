import 'dart:math' as math;

import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/widgets.dart';

/// 菜单锚点：根菜单是一个点（点击位置），子菜单是父条目的矩形
///
/// 坐标一律是 overlay 坐标；点锚点用零尺寸矩形表达
@immutable
class ContextMenuAnchor {
  ContextMenuAnchor.point(Offset point)
    : bounds = Rect.fromLTWH(point.dx, point.dy, 0, 0);

  const ContextMenuAnchor.item(Rect itemBounds) : bounds = itemBounds;

  final Rect bounds;

  bool get isPoint => bounds.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ContextMenuAnchor && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;
}

/// 定位结果
@immutable
class ContextMenuPlacement {
  const ContextMenuPlacement({
    required this.offset,
    required this.growFrom,
    this.slideFrom = Offset.zero,
  });

  /// 面板左上角
  final Offset offset;

  /// 锚点在面板内的归一化位置
  ///
  /// 入场缩放的锚点、内容改尺寸时的固定角都用它；贴边偏移多远都还能对着锚点长
  final Alignment growFrom;

  /// 入场滑动的起点偏移，收尾时归零；方向朝锚点，看起来就是从锚点长出来
  final Offset slideFrom;
}

/// 面板位置策略
abstract class ContextMenuPositionDelegate {
  const ContextMenuPositionDelegate();

  /// 按平台取默认策略：桌面跟鼠标，移动端避手指
  static ContextMenuPositionDelegate forPlatform() => isMobile
      ? const ContextMenuMobilePosition()
      : const ContextMenuDesktopPosition();

  ContextMenuPlacement place({
    required ContextMenuAnchor anchor,

    /// 面板量出来的最终尺寸
    required Size panelSize,
    required Size overlaySize,

    /// 必须避开的安全区：刘海 / 系统栏 / 键盘，已含屏幕边距
    required EdgeInsets safeArea,
    required bool isSubmenu,
  });

  /// 锚点在面板内的归一化位置
  static Alignment growAlignment({
    required Offset offset,
    required Size panelSize,
    required Offset anchorPoint,
  }) {
    final dx = panelSize.width <= 0
        ? 0.0
        : ((anchorPoint.dx - offset.dx) / panelSize.width) * 2 - 1;
    final dy = panelSize.height <= 0
        ? 0.0
        : ((anchorPoint.dy - offset.dy) / panelSize.height) * 2 - 1;
    return Alignment(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0));
  }

  /// 兜底贴边：面板比可用区还大时贴住起始边，不越出安全区
  static Offset clampToSafeArea({
    required Offset offset,
    required Size panelSize,
    required Size overlaySize,
    required EdgeInsets safeArea,
  }) {
    final maxLeft = math.max(
      safeArea.left,
      overlaySize.width - safeArea.right - panelSize.width,
    );
    final maxTop = math.max(
      safeArea.top,
      overlaySize.height - safeArea.bottom - panelSize.height,
    );
    return Offset(
      offset.dx.clamp(safeArea.left, maxLeft).toDouble(),
      offset.dy.clamp(safeArea.top, maxTop).toDouble(),
    );
  }

  /// 子菜单挂在父条目旁边
  ///
  /// [preferRight] 决定两边都合适时用哪边；只有一边放得下就用那一边，
  /// 两边都放不下时按 [preferRight] 定方向，交给贴边兜底
  ContextMenuPlacement placeBesideItem({
    required ContextMenuAnchor anchor,
    required Size panelSize,
    required Size overlaySize,
    required EdgeInsets safeArea,
    required double gap,
    bool preferRight = true,
  }) {
    final item = anchor.bounds;
    final toRight = item.right + gap;
    final toLeft = item.left - gap - panelSize.width;
    final fitsRight =
        toRight + panelSize.width <= overlaySize.width - safeArea.right;
    final fitsLeft = toLeft >= safeArea.left;
    final openRight = fitsRight == fitsLeft ? preferRight : fitsRight;
    final offset = clampToSafeArea(
      offset: Offset(openRight ? toRight : toLeft, item.top - 4),
      panelSize: panelSize,
      overlaySize: overlaySize,
      safeArea: safeArea,
    );
    return ContextMenuPlacement(
      offset: offset,
      growFrom: openRight ? Alignment.topLeft : Alignment.topRight,
      slideFrom: openRight ? const Offset(-12, 0) : const Offset(12, 0),
    );
  }
}

/// 桌面策略：跟随鼠标，四向翻转（右下 → 左下 → 右上 → 左上），兜底沉底
class ContextMenuDesktopPosition extends ContextMenuPositionDelegate {
  const ContextMenuDesktopPosition({this.gap = 2});

  /// 菜单与鼠标之间的间隙
  final double gap;

  @override
  ContextMenuPlacement place({
    required ContextMenuAnchor anchor,
    required Size panelSize,
    required Size overlaySize,
    required EdgeInsets safeArea,
    required bool isSubmenu,
  }) {
    if (isSubmenu) {
      return placeBesideItem(
        anchor: anchor,
        panelSize: panelSize,
        overlaySize: overlaySize,
        safeArea: safeArea,
        gap: gap,
      );
    }

    final mouse = anchor.bounds.topLeft;
    final width = panelSize.width;
    final height = panelSize.height;
    final right = overlaySize.width - safeArea.right;
    final bottom = overlaySize.height - safeArea.bottom;

    // 屏幕放得下就按优先级挑一角，四个方向都放不下则沉底
    Offset offset;
    if (mouse.dx + width <= right && mouse.dy + height <= bottom) {
      offset = Offset(mouse.dx + gap, mouse.dy + gap);
    } else if (mouse.dx - width - gap >= safeArea.left &&
        mouse.dy + height <= bottom) {
      offset = Offset(mouse.dx - width - gap, mouse.dy + gap);
    } else if (mouse.dx + width <= right &&
        mouse.dy - height - gap >= safeArea.top) {
      offset = Offset(mouse.dx + gap, mouse.dy - height - gap);
    } else if (mouse.dx - width - gap >= safeArea.left &&
        mouse.dy - height - gap >= safeArea.top) {
      offset = Offset(mouse.dx - width - gap, mouse.dy - height - gap);
    } else {
      final left = mouse.dx + width > right
          ? mouse.dx - width - gap
          : mouse.dx + gap;
      offset = Offset(left, bottom - height);
    }

    final clamped = ContextMenuPositionDelegate.clampToSafeArea(
      offset: offset,
      panelSize: panelSize,
      overlaySize: overlaySize,
      safeArea: safeArea,
    );
    return ContextMenuPlacement(
      offset: clamped,
      growFrom: ContextMenuPositionDelegate.growAlignment(
        offset: clamped,
        panelSize: panelSize,
        anchorPoint: mouse,
      ),
    );
  }
}

/// 移动端策略：竖直方向对准触点上方，水平方向往屏幕的对侧铺
///
/// 竖直：手指与手掌都在触点下方，压在下面会被挡，所以优先摆在触点上方，
/// 上方放不下才落到下方
///
/// 水平：触点在屏幕右半就贴着触点往左铺，菜单右边缘 = 触点；左半往右铺
class ContextMenuMobilePosition extends ContextMenuPositionDelegate {
  const ContextMenuMobilePosition({this.touchGap = 24, this.submenuGap = 8});

  /// 菜单与触点之间留出的避让距离，约一根手指的宽度
  final double touchGap;

  /// 子菜单与父条目的间隙
  final double submenuGap;

  @override
  ContextMenuPlacement place({
    required ContextMenuAnchor anchor,
    required Size panelSize,
    required Size overlaySize,
    required EdgeInsets safeArea,
    required bool isSubmenu,
  }) {
    if (isSubmenu) {
      // 与主菜单同一条规则：父条目在屏幕右半就往左展开，左半往右展开
      final item = anchor.bounds;
      return placeBesideItem(
        anchor: anchor,
        panelSize: panelSize,
        overlaySize: overlaySize,
        safeArea: safeArea,
        gap: submenuGap,
        preferRight: item.center.dx <= overlaySize.width / 2,
      );
    }

    final touch = anchor.bounds.topLeft;
    final above = touch.dy - touchGap - panelSize.height;
    final below = touch.dy + touchGap;
    final fitsAbove = above >= safeArea.top;
    final fitsBelow =
        below + panelSize.height <= overlaySize.height - safeArea.bottom;

    final double top;
    if (fitsAbove) {
      top = above;
    } else if (fitsBelow) {
      top = below;
    } else {
      // 上下都不够：倒向触点占空间更大的一侧，交给贴边兜底
      top = touch.dy > overlaySize.height / 2 ? above : below;
    }

    // 右半屏往左铺、左半往右铺：菜单不压在手底下，也不顶到最近那条边
    final expandToLeft = touch.dx > overlaySize.width / 2;
    final left = expandToLeft ? touch.dx - panelSize.width : touch.dx;

    final clamped = ContextMenuPositionDelegate.clampToSafeArea(
      offset: Offset(left, top),
      panelSize: panelSize,
      overlaySize: overlaySize,
      safeArea: safeArea,
    );
    return ContextMenuPlacement(
      offset: clamped,
      growFrom: ContextMenuPositionDelegate.growAlignment(
        offset: clamped,
        panelSize: panelSize,
        anchorPoint: touch,
      ),
      // 从触点那一侧滑上来，别从屏幕外滑进来
      slideFrom: Offset(0, clamped.dy < touch.dy ? 12 : -12),
    );
  }
}
