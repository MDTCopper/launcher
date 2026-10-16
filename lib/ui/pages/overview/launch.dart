import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/animation/animated_opacity_size.dart';
import 'package:copper_launcher/util/io/os.dart';
import 'package:flutter/material.dart';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import '../../../core/app_config.dart';
import '../../feature/images.dart';

class LaunchPage extends StatefulWidget {
  const LaunchPage({super.key});

  @override
  State<StatefulWidget> createState() => _LaunchPageState();
}

class _LaunchPageState extends State<LaunchPage> {
  /// 选中版本来源：config 持有单一事实
  Mindustry? get _selectedVersion => config.versionOptions.selectedVersion;

  Widget _buildVersionTile(Mindustry? selectedVersion) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);

    Widget buildEmptyTile() {
      final hasVersion =
          config.versionOptions.versionFolds.firstOrNull?.versions.isNotEmpty ??
          false;
      final addtion = !hasVersion
          ? ''
          : isDesktop
          ? '或右键'
          : '或长按';
      return ReboundListTile(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.pushNamed(
            context,
            '/version_select',
            arguments: {'lead': '版本选择'},
          );
        },
        title: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              '未选择版本',
              style: theme.textTheme.displayLarge?.copyWith(
                color: colors.itemHint,
              ),
            ),
          ),
        ),
        subtitle: SizedBox(
          height: 16,
          child: Center(child: Text('点击$addtion以选择游戏版本')),
        ),
      );
    }

    Widget buildTile(Mindustry selectedVersion) => ReboundListTile(
      padding: EdgeInsets.all(8),
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (selectedVersion != _selectedVersion) return;
        Navigator.pushNamed(
          context,
          '/version_select',
          arguments: {'lead': '版本选择'},
        );
      },
      // 选中版本切换时：图标 / 名称 / 版本号 交叠切换（淡入 + 向上位移）
      leading: Image.asset(
        selectedVersion.launcher == .copper ? Images.copper : Images.mindustry,
        key: ValueKey(selectedVersion.id),
        scale: 0.66,
        height: 64,
      ),
      title: Text(
        selectedVersion.tag,
        key: ValueKey(selectedVersion.id),
        style: TextStyle(
          color: Theme.of(context).colorScheme.secondary,
          fontWeight: FontWeight.w900,
          fontSize: 28,
        ),
        maxLines: 1,
        overflow: .ellipsis,
      ),
      subtitle: Text(
        selectedVersion.release,
        key: ValueKey(selectedVersion.id),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
      trailing: ReboundButton(
        borderRadius: BorderRadius.circular(8),
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.all(8),
        child: Icon(
          Icons.settings,
          color: Theme.of(context).iconTheme.color,
          size: 50,
        ),
        onTap: () {
          if (selectedVersion != _selectedVersion) return;
          Navigator.pushNamed(
            context,
            '/version_setting',
            arguments: {
              'lead': '版本设置',
              'version': selectedVersion,
              'title': selectedVersion.tag,
            },
          );
        },
      ),
    );
    Widget child = selectedVersion == null
        ? buildEmptyTile()
        : buildTile(selectedVersion);

    child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 700),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: .bottomCenter,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        final isForward = !animation.status.isForwardOrCompleted;

        final scale = isForward
            ? AlwaysStoppedAnimation(1.0)
            : Tween<double>(begin: 1.0, end: 0.9).animate(
                CurvedAnimation(
                  parent: ReverseAnimation(animation),
                  curve: Interval(0.0, 0.7, curve: Curves.easeOutCirc),
                ),
              );
        child = ScaleTransition(scale: scale, child: child);

        final position = !isForward
            ? AlwaysStoppedAnimation(Offset.zero)
            : Tween<Offset>(
                begin: const Offset(-1.0, 0.0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Interval(0.3, 1.0, curve: Curves.fastOutSlowIn),
                ),
              );

        child = SlideTransition(position: position, child: child);

        final opacity = isForward
            ? Tween<double>(begin: 0.5, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Interval(0.35, 0.7)),
              )
            : AlwaysStoppedAnimation(1.0);

        child = FadeTransition(opacity: opacity, child: child);
        return child;
      },
      child: KeyedSubtree(
        key: ValueKey(selectedVersion?.id ?? 'null'),
        child: child,
      ),
    );

    // 右键 / 长按：快捷选择最近游玩过的其他版本（最多 5 个）
    child = ContextMenuField(
      positionDelegate: const _AboveMousePositionDelegate(gap: 4),
      // 条目里放的是启动器品牌图，图标槽要留够
      style: const ContextMenuStyle(iconSize: 32),
      menuBuilder: (context) => _buildRecentVersionMenu(),
      child: child,
    );
    return child;
  }

  /// 最近游玩过的其他版本（不含当前选中），按最近启动时间倒序，最多 5 个
  List<Mindustry> _recentVersions() {
    final versions = config.versionOptions.versionFolds
        .expand((fold) => fold.versions)
        .where(
          (version) =>
              version.id != _selectedVersion?.id &&
              version.lastLaunchTime != null,
        )
        .toList();
    versions.sort((a, b) => b.lastLaunchTime!.compareTo(a.lastLaunchTime!));
    return versions.take(5).toList();
  }

  List<ContextMenuEntry> _buildRecentVersionMenu() {
    final recent = _recentVersions();
    return [
      const ContextMenuHeader('选择版本'),
      if (recent.isEmpty)
        const ContextMenuAction(label: '暂无最近游玩的其他版本', enabled: false)
      else
        for (final version in recent)
          ContextMenuAction(
            // 品牌图直接进图标槽（尺寸由这条菜单的 iconSize 定）
            leading: Image.asset(
              version.launcher == LauncherType.copper
                  ? Images.copper
                  : Images.mindustry,
              fit: BoxFit.fill,
            ),
            label: version.tag,
            onSelected: () {
              config.versionOptions.selectedVersion = version;
              config.save();
              // 不手动 setState：notifier 驱动的 ValueListenableBuilder 会重建 tile
            },
          ),
    ];
  }

  Widget _buildLaunchButton() {
    Widget? child = _selectedVersion == null
        ? null
        : Padding(
            padding: EdgeInsets.only(left: 8),
            child: SizedBox(
              height: 80,
              width: 225,
              child: ReboundButton(
                pressedScale: 0.9,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 16,
                  children: [
                    Icon(
                      Icons.play_arrow,
                      size: 50,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    Text(
                      "启动游戏",
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                    SizedBox(),
                  ],
                ),
                onTap: () {
                  if (_selectedVersion == null) return;
                  addTask(LaunchMindustryTask(_selectedVersion!));
                },
              ),
            ),
          );

    child = AnimatedOpacitySize(child: child);
    return child;
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Column(
      //主页面
      children: [
        Expanded(child: SizedBox()),
        Padding(
          padding: EdgeInsets.all(8),
          child: ValueListenableBuilder(
            valueListenable: config.versionOptions.selectedVersionNotifier,
            builder: (context, selectVersion, _) {
              return Row(
                //下方操作条
                crossAxisAlignment: .center,
                children: [
                  Expanded(child: _buildVersionTile(selectVersion)),
                  _buildLaunchButton(),
                ],
              );
            },
          ),
        ),
      ],
    );

    return child;
  }
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
    // 水平：菜单中点对齐鼠标 x，再由安全区收一次
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
