import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/ui/components/core/cu_frosted_panel.dart';
import 'package:copper_launcher/ui/components/core/cu_pressable.dart';
import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu.dart';
import 'package:copper_launcher/ui/components/overlay_layer/hint_layer.dart';
import 'package:copper_launcher/ui/feature/version_icon.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/material.dart';

/// 主页底部启动区布局样式（默认底部悬浮岛）
enum HomeDockStyle {
  island('island', '底部悬浮岛', '居中整合 · 默认', Icons.dock_rounded),
  cornerPod(
    'corner_pod',
    '右下启动舱',
    '角落收纳 · 留白最大',
    Icons.picture_in_picture_alt_rounded,
  ),
  splitAnchors(
    'split_anchors',
    '左右双锚点',
    '左版本卡 · 右独立启动',
    Icons.splitscreen_rounded,
  );

  const HomeDockStyle(this.storageKey, this.label, this.description, this.icon);

  final String storageKey;
  final String label;
  final String description;
  final IconData icon;

  static HomeDockStyle fromStorageKey(Object? raw) {
    if (raw is String) {
      for (final value in values) {
        if (value.storageKey == raw) return value;
      }
    }
    return HomeDockStyle.island;
  }
}

enum _DockPart { shellBackground, versionCluster, launchButton }

class _DockPose {
  const _DockPose({
    required this.alignX,
    required this.islandT,
    required this.splitT,
  });

  /// 外壳水平对齐：-1.0 贴左，0.0 居中，1.0 贴右
  final double alignX;

  /// 浮岛舒展系数：1.0 为较宽浮岛，0.0 为紧凑胶囊 / 版本卡
  final double islandT;

  /// 启动按钮脱离系数：0.0 嵌在磨砂外壳内，1.0 独立停靠右下角
  final double splitT;

  static _DockPose of(HomeDockStyle style) => switch (style) {
    HomeDockStyle.island => const _DockPose(
      alignX: 0.0,
      islandT: 1.0,
      splitT: 0.0,
    ),
    HomeDockStyle.cornerPod => const _DockPose(
      alignX: 1.0,
      islandT: 0.0,
      splitT: 0.0,
    ),
    HomeDockStyle.splitAnchors => const _DockPose(
      alignX: -1.0,
      islandT: 0.0,
      splitT: 1.0,
    ),
  };

  static _DockPose lerp(_DockPose a, _DockPose b, double t) {
    return _DockPose(
      alignX: lerpDouble(a.alignX, b.alignX, t)!,
      islandT: lerpDouble(a.islandT, b.islandT, t)!,
      splitT: lerpDouble(a.splitT, b.splitT, t)!,
    );
  }
}

/// 主页底部可切换样式的启动区
///
/// 三套布局共享同一套磨砂外壳、版本 tile 与启动按钮实例，由单一姿态动画连续驱动：
/// - 版本 tile 始终处于磨砂外壳内，三套布局的图标、字号、副标题与设置按钮完全一致
/// - 启动按钮脱离到左右双锚点右下角时，高度 / 位置 / 轻弧线连续插值，外壳同步平滑收窄
/// - 浮岛拥有更宽裕的展示宽度（设上限防过宽），版本名变化时 tile 宽度通过 AnimatedSize 平滑适配
class HomeLaunchDock extends StatefulWidget {
  const HomeLaunchDock({
    super.key,
    required this.style,
    required this.selectedVersion,
    required this.hasAnyVersion,
    required this.recentVersionMenuBuilder,
    required this.onSelectVersionTap,
    required this.onVersionSettingTap,
    required this.onLaunchTap,
  });

  final HomeDockStyle style;
  final Mindustry? selectedVersion;
  final bool hasAnyVersion;
  final List<ContextMenuEntry> Function(BuildContext context)
  recentVersionMenuBuilder;
  final VoidCallback onSelectVersionTap;
  final VoidCallback onVersionSettingTap;
  final VoidCallback onLaunchTap;

  @override
  State<HomeLaunchDock> createState() => _HomeLaunchDockState();
}

class _HomeLaunchDockState extends State<HomeLaunchDock>
    with SingleTickerProviderStateMixin {
  static const _poseDuration = Duration(milliseconds: 360);
  static const _stageHeight = 72.0;
  static const _shellPadding = 7.0;
  static const _dockedButtonGap = 8.0;
  static const _splitMinGap = 12.0;

  /// 浮岛总宽上限，避免超宽屏下拉得过散
  static const _islandMaxWidth = 560.0;

  /// 版本 tile 宽度范围：浮岛舒展、其余布局紧凑自适应
  static const _islandMinTileWidth = 288.0;
  static const _islandMaxTileWidth = 368.0;
  static const _compactMinTileWidth = 148.0;
  static const _compactMaxTileWidth = 252.0;

  /// 启动按钮合体态 ↔ 独立态尺寸（随 splitT 连续插值，杜绝高度瞬变）
  static const _dockedLaunchHeight = 42.0;
  static const _splitLaunchHeight = 48.0;
  static const _dockedLaunchPaddingH = 18.0;
  static const _splitLaunchPaddingH = 22.0;

  static const _settingIcon = Icons.settings_outlined;
  static const _switchHintIcon = Icons.unfold_more_rounded;
  static const _menuPositionDelegate = _AboveMousePositionDelegate(gap: 4);

  late final AnimationController _poseController = AnimationController(
    vsync: this,
    duration: _poseDuration,
    value: 1.0,
  );
  late final Animation<double> _poseCurve = CurvedAnimation(
    parent: _poseController,
    curve: Curves.easeInOutCubic,
  );

  late _DockPose _fromPose = _DockPose.of(widget.style);
  late _DockPose _toPose = _fromPose;

  _DockPose get _currentPose =>
      _DockPose.lerp(_fromPose, _toPose, _poseCurve.value);

  @override
  void didUpdateWidget(covariant HomeLaunchDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) {
      // 从当前实时姿态衔接新目标，连续快速切换也不会瞬移
      _fromPose = _currentPose;
      _toPose = _DockPose.of(widget.style);
      _poseController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _poseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = cuSkinOf(context);
    final version = widget.selectedVersion;

    if (version == null) {
      return AnimatedAlign(
        alignment: widget.style == HomeDockStyle.cornerPod
            ? Alignment.bottomRight
            : Alignment.bottomCenter,
        duration: _poseDuration,
        curve: Curves.easeInOutCubic,
        child: _buildEmptyDock(skin),
      );
    }

    return SizedBox(
      height: _stageHeight,
      child: AnimatedBuilder(
        animation: _poseController,
        builder: (context, _) {
          final pose = _currentPose;
          final shellRadius = lerpDouble(13.0, 14.0, pose.islandT)!;
          final launchHeight = lerpDouble(
            _dockedLaunchHeight,
            _splitLaunchHeight,
            pose.splitT,
          )!;
          final launchPaddingH = lerpDouble(
            _dockedLaunchPaddingH,
            _splitLaunchPaddingH,
            pose.splitT,
          )!;
          final launchRadius = lerpDouble(10.0, 11.0, pose.splitT)!;

          return CustomMultiChildLayout(
            delegate: _HomeDockLayoutDelegate(
              pose: pose,
              shellPadding: _shellPadding,
              dockedButtonGap: _dockedButtonGap,
              splitMinGap: _splitMinGap,
              islandMaxWidth: _islandMaxWidth,
              dockedLaunchHeight: _dockedLaunchHeight,
            ),
            children: [
              LayoutId(
                id: _DockPart.shellBackground,
                child: CuFrostedPanel(
                  radius: shellRadius,
                  blur: 22,
                  child: const SizedBox.expand(),
                ),
              ),
              LayoutId(
                id: _DockPart.versionCluster,
                child: _buildVersionCluster(skin, version: version, pose: pose),
              ),
              LayoutId(
                id: _DockPart.launchButton,
                child: _buildLaunchButton(
                  skin,
                  height: launchHeight,
                  horizontalPadding: launchPaddingH,
                  radius: launchRadius,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVersionCluster(
    TemplateSkin skin, {
    required Mindustry version,
    required _DockPose pose,
  }) {
    final tileMinWidth = lerpDouble(
      _compactMinTileWidth,
      _islandMinTileWidth,
      pose.islandT,
    )!;
    final tileMaxWidth = lerpDouble(
      _compactMaxTileWidth,
      _islandMaxTileWidth,
      pose.islandT,
    )!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: _buildVersionTile(
            skin,
            version: version,
            minWidth: tileMinWidth,
            maxWidth: tileMaxWidth,
          ),
        ),
        Container(
          width: 1,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          color: skin.border,
        ),
        _buildSettingButton(skin),
      ],
    );
  }

  /// 三套布局完全统一的版本 tile：不改文案与字号，版本切换时平滑适配宽度
  Widget _buildVersionTile(
    TemplateSkin skin, {
    required Mindustry version,
    required double minWidth,
    required double maxWidth,
  }) {
    final badgeLabel = _versionBadgeText(version);
    final storageLabel = _versionStorageLabel(version);
    final tooltip = isDesktop ? '点击选择版本 · 右键快切最近版本' : '点击选择版本 · 长按快切最近版本';

    return HintLayer(
      hint: tooltip,
      child: _wrapRecentContextMenu(
        child: CuPressable(
          onTap: widget.onSelectVersionTap,
          borderRadius: BorderRadius.circular(9),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerLeft,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    for (final prev in previousChildren)
                      Positioned.fill(
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: 0,
                            maxWidth: maxWidth,
                            child: prev,
                          ),
                        ),
                      ),
                    ?currentChild,
                  ],
                ),
                child: Row(
                  key: ValueKey(version.id),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFilledVersionIcon(skin, version: version, size: 38),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  version.tag,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: skin.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _switchHintIcon,
                                size: 15,
                                color: skin.textTertiary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 6,
                            children: [
                              _buildVersionBadge(skin, badgeLabel),
                              Flexible(
                                child: Text(
                                  storageLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: skin.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 圆角铺满的版本图标
  Widget _buildFilledVersionIcon(
    TemplateSkin skin, {
    required Mindustry version,
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: skin.sunken.withAlpha(skin.dark ? 165 : 205),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: skin.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: VersionIcon(
          version: version,
          height: size,
          width: size,
          fallbackScale: 1.0,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildVersionBadge(TemplateSkin skin, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: skin.accentTint,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: skin.onAccentTint,
        ),
      ),
    );
  }

  /// 三套布局完全统一的设置按钮
  Widget _buildSettingButton(TemplateSkin skin) {
    return HintLayer(
      hint: '版本设置',
      child: CuPressable(
        onTap: widget.onVersionSettingTap,
        backgroundColor: skin.raised.withAlpha(skin.dark ? 110 : 170),
        borderRadius: BorderRadius.circular(9),
        decoration: BoxDecoration(border: Border.all(color: skin.border)),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(_settingIcon, size: 17, color: skin.textSecondary),
        ),
      ),
    );
  }

  Widget _buildLaunchButton(
    TemplateSkin skin, {
    required double height,
    required double horizontalPadding,
    required double radius,
  }) {
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: skin.accent.withAlpha(skin.dark ? 70 : 52),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CuPressable(
        onTap: widget.onLaunchTap,
        backgroundColor: skin.accent,
        hoverColor: skin.hoverOn(skin.accent),
        pressedColor: skin.pressedOn(skin.accent),
        borderRadius: borderRadius,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Icon(Icons.play_arrow_rounded, size: 21, color: skin.onAccent),
              Text(
                '启动游戏',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: skin.onAccent,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 未选择版本空态
  Widget _buildEmptyDock(TemplateSkin skin) {
    final hintSuffix = !widget.hasAnyVersion
        ? ''
        : isDesktop
        ? '，或右键快捷切换'
        : '，或长按快捷切换';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: _wrapRecentContextMenu(
        child: CuFrostedPanel(
          radius: 14,
          blur: 22,
          padding: const EdgeInsets.fromLTRB(12, 9, 9, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: skin.sunken.withAlpha(180),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: skin.border),
                ),
                child: Icon(
                  Icons.view_in_ar_outlined,
                  size: 18,
                  color: skin.textTertiary,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '尚未选择游戏版本',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: skin.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '选择已有版本$hintSuffix',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: skin.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              CuPressable(
                onTap: widget.onSelectVersionTap,
                backgroundColor: skin.accent,
                hoverColor: skin.hoverOn(skin.accent),
                pressedColor: skin.pressedOn(skin.accent),
                borderRadius: BorderRadius.circular(9),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SizedBox(
                  height: 38,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 5,
                    children: [
                      Icon(Icons.add_rounded, size: 17, color: skin.onAccent),
                      Text(
                        '选择版本',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: skin.onAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wrapRecentContextMenu({required Widget child}) {
    return ContextMenuField(
      positionDelegate: _menuPositionDelegate,
      style: const ContextMenuStyle(iconSize: 32),
      menuBuilder: widget.recentVersionMenuBuilder,
      child: child,
    );
  }

  String _versionBadgeText(Mindustry version) {
    if (version.steam) return 'Steam ${version.release}';
    if (version.isBe) return 'BE ${version.release}';
    return version.release.isEmpty ? '未知版本' : version.release;
  }

  String _versionStorageLabel(Mindustry version) {
    if (version.launcher == LauncherType.copper) return 'Copper';
    if (version.isolation) return '隔离目录';
    return '官方核心';
  }
}

/// 同一帧内联排外壳、版本组与启动按钮：
/// 外壳始终包住版本组，并按 (1 - splitT) 预留启动按钮槽位实现脱离时的自适应收窄；
/// 启动按钮沿平滑弧线从壳内滑出到右下角，零跳变
class _HomeDockLayoutDelegate extends MultiChildLayoutDelegate {
  _HomeDockLayoutDelegate({
    required this.pose,
    required this.shellPadding,
    required this.dockedButtonGap,
    required this.splitMinGap,
    required this.islandMaxWidth,
    required this.dockedLaunchHeight,
  });

  final _DockPose pose;
  final double shellPadding;
  final double dockedButtonGap;
  final double splitMinGap;
  final double islandMaxWidth;
  final double dockedLaunchHeight;

  @override
  void performLayout(Size size) {
    final btnSize = layoutChild(
      _DockPart.launchButton,
      BoxConstraints.loose(size),
    );

    // 启动按钮还在壳内时占壳内槽位，完全脱离后槽位归零
    final reservedSlotWidth =
        (btnSize.width + dockedButtonGap) * (1.0 - pose.splitT);
    final maxShellWidth = lerpDouble(
      size.width - (pose.splitT > 0 ? btnSize.width + splitMinGap : 0.0),
      math.min(size.width, islandMaxWidth),
      pose.islandT,
    )!;
    final maxClusterWidth = math.max(
      0.0,
      maxShellWidth - shellPadding * 2 - reservedSlotWidth,
    );

    final clusterSize = layoutChild(
      _DockPart.versionCluster,
      BoxConstraints(maxWidth: maxClusterWidth, maxHeight: size.height),
    );

    final shellWidth = math.min(
      size.width,
      clusterSize.width + reservedSlotWidth + shellPadding * 2,
    );
    final shellHeight =
        math.max(clusterSize.height, dockedLaunchHeight) + shellPadding * 2;

    layoutChild(
      _DockPart.shellBackground,
      BoxConstraints.tight(Size(shellWidth, shellHeight)),
    );

    final shellX = (size.width - shellWidth) * ((pose.alignX + 1.0) / 2.0);
    final shellY = size.height - shellHeight;
    positionChild(_DockPart.shellBackground, Offset(shellX, shellY));

    final clusterX = shellX + shellPadding;
    final clusterY = shellY + (shellHeight - clusterSize.height) / 2.0;
    positionChild(_DockPart.versionCluster, Offset(clusterX, clusterY));

    // 启动按钮：从壳内右侧精准出发，带轻盈上浮弧线滑停到右下角
    final dockedBtnX = shellX + shellWidth - shellPadding - btnSize.width;
    final dockedBtnY = shellY + (shellHeight - btnSize.height) / 2.0;
    final splitBtnX = size.width - btnSize.width;
    final splitBtnY = size.height - btnSize.height;
    final arcLift = -6.0 * math.sin(pose.splitT * math.pi);

    final btnX = lerpDouble(dockedBtnX, splitBtnX, pose.splitT)!;
    final btnY = lerpDouble(dockedBtnY, splitBtnY, pose.splitT)! + arcLift;
    positionChild(_DockPart.launchButton, Offset(btnX, btnY));
  }

  @override
  bool shouldRelayout(covariant _HomeDockLayoutDelegate oldDelegate) =>
      oldDelegate.pose.alignX != pose.alignX ||
      oldDelegate.pose.islandT != pose.islandT ||
      oldDelegate.pose.splitT != pose.splitT ||
      oldDelegate.shellPadding != shellPadding ||
      oldDelegate.dockedButtonGap != dockedButtonGap ||
      oldDelegate.splitMinGap != splitMinGap ||
      oldDelegate.islandMaxWidth != islandMaxWidth ||
      oldDelegate.dockedLaunchHeight != dockedLaunchHeight;
}

/// 位置策略：菜单显示在鼠标上方（上方放不下才翻到下方）
class _AboveMousePositionDelegate extends ContextMenuPositionDelegate {
  const _AboveMousePositionDelegate({this.gap = 4});

  final double gap;

  @override
  ContextMenuPlacement place({
    required ContextMenuAnchor anchor,
    required Size panelSize,
    required Size overlaySize,
    required EdgeInsets safeArea,
    required bool isSubmenu,
  }) {
    final mouse = anchor.bounds.topLeft;
    final left = mouse.dx - panelSize.width / 2;
    var top = mouse.dy - panelSize.height - gap;
    if (top < safeArea.top) top = mouse.dy + gap;
    final offset = ContextMenuPositionDelegate.clampToSafeArea(
      offset: Offset(left, top),
      panelSize: panelSize,
      overlaySize: overlaySize,
      safeArea: safeArea,
    );
    return ContextMenuPlacement(
      offset: offset,
      growFrom: ContextMenuPositionDelegate.growAlignment(
        offset: offset,
        panelSize: panelSize,
        anchorPoint: mouse,
      ),
    );
  }
}
