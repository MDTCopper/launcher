import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/launch_mindustry_task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/menu_layer.dart';
import 'package:copper_launcher/ui/components/overlay_layer/popup_overlay.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import '../../../core/app_config.dart';
import '../../feature/images.dart';

class LaunchPage extends StatefulWidget {
  const LaunchPage({super.key});

  @override
  State<StatefulWidget> createState() => _LaunchPageState();
}

class _LaunchPageState extends State<LaunchPage> {
  Mindustry? get _selectedVersion => config.versionOptions.selectedVersion;

  @override
  void initState() {
    super.initState();
    // 监听选中版本变化（version_select / 右键菜单等写入点经 setter 通知），
    // 变化时刷新本页 tile，无需手动 setState
    config.versionOptions.selectedVersionNotifier
        .addListener(_onSelectedVersionChanged);
  }

  @override
  void dispose() {
    config.versionOptions.selectedVersionNotifier
        .removeListener(_onSelectedVersionChanged);
    super.dispose();
  }

  void _onSelectedVersionChanged() {
    if (mounted) setState(() {});
  }

  Widget _buildVersionTile() {
    if (_selectedVersion == null) {
      return ReboundListTile(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          await Navigator.pushNamed(
            context,
            '/version_select',
            arguments: {'lead': '版本选择', 'routes': []},
          );
          setState(() {});
        },
        title: SizedBox(
          height: 80,
          child: Center(
            child: Text(
              '未选择版本，点击以选择游戏版本',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 32),
            ),
          ),
        ),
      );
    }
    final tile = ReboundListTile(
      padding: EdgeInsets.all(8),
      borderRadius: BorderRadius.circular(8),

      onTap: () async {
        await Navigator.pushNamed(
          context,
          '/version_select',
          arguments: {'lead': '版本选择'},
        );
        setState(() {});
      },
      // 选中版本切换时：图标 / 名称 / 版本号 交叠切换（淡入 + 向上位移）
      leading: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchOutCurve: Curves.easeIn,
        switchInCurve: Curves.easeOut,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Image.asset(
          _selectedVersion!.launcher == .copper
              ? Images.copper
              : Images.mindustry,
          key: ValueKey(_selectedVersion!.id),
          scale: 0.66,
          height: 64,
        ),
      ),
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchOutCurve: Curves.easeIn,
        switchInCurve: Curves.easeOut,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.2),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Text(
          _selectedVersion!.tag,
          key: ValueKey(_selectedVersion!.id),
          style: TextStyle(
            color: Theme.of(context).colorScheme.secondary,
            fontWeight: FontWeight.w900,
            fontSize: 28,
          ),
        ),
      ),
      subtitle: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchOutCurve: Curves.easeIn,
        switchInCurve: Curves.easeOut,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.2),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Text(
          _selectedVersion!.release,
          key: ValueKey(_selectedVersion!.id),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
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
          Navigator.pushNamed(
            context,
            '/version_setting',
            arguments: {
              'lead': '版本设置',
              'version': _selectedVersion,
              'title': _selectedVersion?.tag ?? 'null',
            },
          );
        },
      ),
    );

    // 右键 / 长按：快捷选择最近游玩过的其他版本（最多 5 个）
    return MenuLayer(
      positionDelegate: const _AboveMousePositionDelegate(gap: 4),
      animation: _recentMenuAnimation,
      menuBuilder: (_, controller) => _buildRecentVersionMenu(controller),
      child: tile,
    );
  }

  Widget _recentMenuAnimation(
    BuildContext context,
    Animation<double> animation,
    Widget child,
    PopupOverlayPlacement? placement,
  ) {
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Transform.scale(
          scaleY: animation.value,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
        child: child,
      ),
    );
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

  List<Widget> _buildRecentVersionMenu(PopupOverlayController controller) {
    final theme = Theme.of(context);
    final recent = _recentVersions();
    return [
      Padding(
        padding: EdgeInsets.only(left: 8, bottom: 4),
        child: SizedBox(
          width: 180,
          child: Text('选择版本', style: theme.textTheme.bodyMedium),
        ),
      ),
      if (recent.isEmpty)
        Padding(
          padding: EdgeInsets.all(8),
          child: Text('暂无最近游玩的其他版本', style: theme.textTheme.bodySmall),
        )
      else
        for (final version in recent)
          SizedBox(
            width: 200,
            child: ReboundButton(
              pressedScale: 0.9,
              borderRadius: BorderRadius.circular(6),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              onTap: () {
                controller.dismiss();
                config.versionOptions.selectedVersion = version;
                config.save();
                setState(() {});
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    version.launcher == .copper
                        ? Images.copper
                        : Images.mindustry,
                    width: 32,
                    height: 32,
                    fit: BoxFit.fill,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      version.tag,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
    ];
  }

  Widget _buildLaunchButton() {
    if (_selectedVersion == null) return SizedBox();

    return SizedBox(
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
        onTap: () async {
          addTask(LaunchMindustryTask(_selectedVersion!));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Column(
      //主页面
      children: [
        Expanded(child: SizedBox()),
        Padding(
          padding: EdgeInsets.all(8),
          child: Row(
            //下方操作条
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(child: _buildVersionTile()),
              SizedBox(width: 8),
              _buildLaunchButton(),
            ],
          ),
        ),
      ],
    );

    return child;
  }
}

/// 位置策略：菜单永远显示在鼠标上方
class _AboveMousePositionDelegate extends PopupOverlayPositionDelegate {
  final double gap;

  const _AboveMousePositionDelegate({required this.gap});

  @override
  Offset getPosition({
    required Rect anchorRect,
    required Offset? position,
    required Size overlaySize,
    required Size childSize,
    required EdgeInsets padding,
  }) {
    // 鼠标在 overlay 中的位置：锚点内偏移 + 锚点原点
    final mouse = Offset(
      (position?.dx ?? anchorRect.width / 2) + anchorRect.left,
      (position?.dy ?? anchorRect.height / 2) + anchorRect.top,
    );

    // 水平：菜单中点对齐鼠标 x（超界收回安全边距）
    var left = mouse.dx - childSize.width / 2;
    left = left
        .clamp(
          padding.left,
          math.max(
            padding.left,
            overlaySize.width - padding.right - childSize.width,
          ),
        )
        .toDouble();

    // 垂直：底边贴鼠标上方（留 gap）
    var top = mouse.dy - childSize.height - gap;
    // 上方放不下 → 翻到鼠标下方
    if (top < padding.top) {
      top = mouse.dy + gap;
      // 下方也放不下（比屏幕高）→ 沉底
      if (top + childSize.height > overlaySize.height - padding.bottom) {
        top = overlaySize.height - padding.bottom - childSize.height;
      }
    }
    top = top
        .clamp(
          padding.top,
          math.max(
            padding.top,
            overlaySize.height - padding.bottom - childSize.height,
          ),
        )
        .toDouble();

    return Offset(left, top);
  }

  @override
  bool shouldReposition(PopupOverlayPositionDelegate oldDelegate) =>
      oldDelegate is! _AboveMousePositionDelegate;
}
