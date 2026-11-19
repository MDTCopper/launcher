import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/game_instance.dart';
import 'package:copper_launcher/ui/components/core/cu_frosted_panel.dart';
import 'package:copper_launcher/ui/components/core/cu_pressable.dart';
import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/components/overlay_layer/context_menu/context_menu.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/feature/images.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:copper_launcher/ui/pages/overview/home_board.dart';
import 'package:copper_launcher/ui/pages/overview/home_drifting_grid.dart';
import 'package:copper_launcher/ui/pages/overview/home_launch_dock.dart';
import 'package:flutter/material.dart';

/// 主页：漂移网格画布 + 模数栅格看板 + 可切换样式的底部启动区
class LaunchPage extends StatefulWidget {
  const LaunchPage({super.key});

  @override
  State<StatefulWidget> createState() => _LaunchPageState();
}

class _LaunchPageState extends State<LaunchPage> {
  static const _dockStyleSettingKey = 'home_dock_style';
  static const _boardCardsSettingKey = 'home_board_cards';
  static const _gridEnabledSettingKey = 'home_grid_enabled';

  late HomeDockStyle _dockStyle;
  late List<HomeBoardCardId> _enabledBoardCards;
  late bool _gridEnabled;

  /// 选中版本来源：config 持有单一事实
  Mindustry? get _selectedVersion => config.versionOptions.selectedVersion;

  bool get _hasAnyVersion => config.versionOptions.versionFolds.any(
    (fold) => fold.versions.isNotEmpty,
  );

  @override
  void initState() {
    super.initState();
    _dockStyle = HomeDockStyle.fromStorageKey(
      config.setting.getCustomSetting(
        _dockStyleSettingKey,
        HomeDockStyle.island.storageKey,
      ),
    );
    _enabledBoardCards = _readBoardCards();
    _gridEnabled =
        config.setting.getCustomSetting(_gridEnabledSettingKey, true) == true;
  }

  List<HomeBoardCardId> _readBoardCards() {
    final raw = config.setting.getCustomSetting(
      _boardCardsSettingKey,
      HomeBoardCardId.defaultEnabled.map((item) => item.storageKey).toList(),
    );
    if (raw is! List) return List.of(HomeBoardCardId.defaultEnabled);

    final parsed = <HomeBoardCardId>[];
    for (final item in raw) {
      if (item is! String) continue;
      final id = HomeBoardCardId.fromStorageKey(item);
      if (id != null && !parsed.contains(id)) parsed.add(id);
    }
    return parsed;
  }

  void _setDockStyle(HomeDockStyle next) {
    if (_dockStyle == next) return;
    setState(() => _dockStyle = next);
    config.setting.customSetting[_dockStyleSettingKey] = next.storageKey;
    config.save();
  }

  void _toggleBoardCard(HomeBoardCardId id) {
    final next = List<HomeBoardCardId>.of(_enabledBoardCards);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      // 按枚举定义顺序插入，保证栅格排列顺序稳定
      next.add(id);
      next.sort((a, b) => a.index.compareTo(b.index));
    }
    setState(() => _enabledBoardCards = next);
    config.setting.customSetting[_boardCardsSettingKey] = next
        .map((item) => item.storageKey)
        .toList();
    config.save();
  }

  void _toggleGrid() {
    final next = !_gridEnabled;
    setState(() => _gridEnabled = next);
    config.setting.customSetting[_gridEnabledSettingKey] = next;
    config.save();
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

  void _selectVersion(Mindustry version) {
    config.versionOptions.selectedVersion = version;
    config.save();
  }

  void _openVersionSelect() {
    Navigator.pushNamed(context, '/version_select');
  }

  void _openVersionSetting() {
    final version = _selectedVersion;
    if (version == null) return;
    Navigator.pushNamed(
      context,
      '/version_setting',
      arguments: {'version': version},
    );
  }

  void _launchSelectedVersion() {
    final version = _selectedVersion;
    if (version == null) return;
    GameInstance.launch(version);
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
            leading: Image.asset(
              version.launcher == LauncherType.copper
                  ? Images.copper
                  : Images.mindustry,
              fit: BoxFit.fill,
            ),
            label: version.tag,
            onSelected: () => _selectVersion(version),
          ),
    ];
  }

  void _showDockStyleMenu(BuildContext buttonContext) {
    ContextMenu.showBelow(
      context: buttonContext,
      entries: [
        const ContextMenuHeader('启动区布局'),
        for (final style in HomeDockStyle.values)
          ContextMenuAction(
            icon: style.icon,
            label: style.label,
            checked: _dockStyle == style,
            onSelected: () => _setDockStyle(style),
          ),
      ],
    );
  }

  void _showBoardMenu(BuildContext buttonContext) {
    ContextMenu.showBelow(
      context: buttonContext,
      entries: [
        const ContextMenuHeader('主页看板卡片'),
        for (final card in HomeBoardCardId.values)
          ContextMenuAction(
            icon: card.icon,
            label: card.label,
            checked: _enabledBoardCards.contains(card),
            onSelected: () => _toggleBoardCard(card),
          ),
      ],
    );
  }

  void _showBackgroundMenu(BuildContext buttonContext) {
    ContextMenu.showBelow(
      context: buttonContext,
      entries: [
        const ContextMenuHeader('主页背景'),
        ContextMenuAction(
          icon: Icons.grid_4x4_rounded,
          label: '动态漂移网格',
          checked: _gridEnabled,
          onSelected: _toggleGrid,
        ),
        const ContextMenuDivider(),
        const ContextMenuAction(
          icon: Icons.image_outlined,
          label: '自定义图片背景（即将支持）',
          enabled: false,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_gridEnabled) const HomeDriftingGrid(),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: ValueListenableBuilder<Mindustry?>(
            valueListenable: config.versionOptions.selectedVersionNotifier,
            builder: (context, selectedVersion, _) {
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    right: 196,
                    bottom: 84,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: CuSingleChildScrollView(
                        clipBehavior: Clip.none,
                        showScrollbar: false,
                        fadeMask: false,
                        child: HomeBoard(
                          enabledCards: _enabledBoardCards,
                          selectedVersion: selectedVersion,
                          recentVersions: _recentVersions(),
                          onSelectVersion: _selectVersion,
                          onOpenVersionSelect: _openVersionSelect,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: _buildCornerToolbar(cuSkinOf(context)),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: HomeLaunchDock(
                      style: _dockStyle,
                      selectedVersion: selectedVersion,
                      hasAnyVersion: _hasAnyVersion,
                      recentVersionMenuBuilder: (_) =>
                          _buildRecentVersionMenu(),
                      onSelectVersionTap: _openVersionSelect,
                      onVersionSettingTap: _openVersionSetting,
                      onLaunchTap: _launchSelectedVersion,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCornerToolbar(TemplateSkin skin) {
    return CuFrostedPanel(
      radius: 8,
      blur: 14,
      opacity: skin.dark ? 0.60 : 0.72,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(
            builder: (buttonContext) => _buildToolChip(
              skin,
              icon: Icons.dashboard_customize_outlined,
              label: '看板',
              onTap: () => _showBoardMenu(buttonContext),
            ),
          ),
          _buildToolbarDivider(skin),
          Builder(
            builder: (buttonContext) => _buildToolChip(
              skin,
              icon: Icons.view_carousel_outlined,
              label: '布局',
              onTap: () => _showDockStyleMenu(buttonContext),
            ),
          ),
          _buildToolbarDivider(skin),
          Builder(
            builder: (buttonContext) => _buildToolChip(
              skin,
              icon: Icons.wallpaper_outlined,
              label: '背景',
              onTap: () => _showBackgroundMenu(buttonContext),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarDivider(TemplateSkin skin) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: skin.border.withAlpha(150),
    );
  }

  Widget _buildToolChip(
    TemplateSkin skin, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return CuPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(icon, size: 13, color: skin.textSecondary),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: skin.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
