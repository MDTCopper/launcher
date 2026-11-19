import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/ui/components/animation/appear_item.dart';
import 'package:copper_launcher/ui/components/core/cu_frosted_panel.dart';
import 'package:copper_launcher/ui/components/core/cu_pressable.dart';
import 'package:copper_launcher/ui/components/core/cu_skin.dart';
import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:flutter/material.dart';

/// 主页看板卡片类型（后续新卡片直接在这里追加，再于 [HomeBoard] 注册模板构建）
enum HomeBoardCardId {
  recentPlay('recent_play', '最近游玩', Icons.schedule_rounded),
  onlineStatus('online_status', '联机状态', Icons.public_outlined),
  quickSwitch('quick_switch', '快捷切换', Icons.bolt_rounded),
  instanceDigest('instance_digest', '实例概览', Icons.inventory_2_outlined),
  cloudSync('cloud_sync', '云存档', Icons.cloud_done_outlined);

  const HomeBoardCardId(this.storageKey, this.label, this.icon);

  final String storageKey;
  final String label;
  final IconData icon;

  /// 默认启用的首批轻量看板组合（保持主页大面积留白）
  static const List<HomeBoardCardId> defaultEnabled = [
    HomeBoardCardId.recentPlay,
    HomeBoardCardId.onlineStatus,
  ];

  static HomeBoardCardId? fromStorageKey(String key) {
    for (final value in values) {
      if (value.storageKey == key) return value;
    }
    return null;
  }
}

/// 看板卡片占用的栅格跨度
enum HomeBoardCardSpan { single, wide }

/// 看板单卡的统一模板外壳：定高对齐 + 一致的标题栏与底部元信息结构
class HomeBoardCardTemplate extends StatelessWidget {
  const HomeBoardCardTemplate({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
    this.footer,
    this.leadingDotColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget body;
  final Widget? trailing;
  final String? footer;
  final Color? leadingDotColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = cuSkinOf(context);
    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leadingDotColor != null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: leadingDotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ] else ...[
                Icon(icon, size: 13, color: skin.accentText),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: skin.textSecondary,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: body),
          ),
          if (footer != null) ...[
            const SizedBox(height: 4),
            Text(
              footer!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: skin.textTertiary),
            ),
          ],
        ],
      ),
    );

    final interactiveChild = onTap == null
        ? content
        : CuPressable(
            onTap: onTap,
            borderRadius: BorderRadius.circular(11),
            child: content,
          );

    return CuFrostedPanel(
      radius: 11,
      blur: 16,
      opacity: skin.dark ? 0.62 : 0.74,
      child: interactiveChild,
    );
  }
}

/// 主页模数栅格看板区
///
/// 统一列宽与行高，让卡片横竖严丝合缝对齐；空列或未启用任何卡片时不占空间
class HomeBoard extends StatelessWidget {
  const HomeBoard({
    super.key,
    required this.enabledCards,
    required this.selectedVersion,
    required this.recentVersions,
    required this.onSelectVersion,
    required this.onOpenVersionSelect,
  });

  final List<HomeBoardCardId> enabledCards;
  final Mindustry? selectedVersion;
  final List<Mindustry> recentVersions;
  final ValueChanged<Mindustry> onSelectVersion;
  final VoidCallback onOpenVersionSelect;

  static const double _cardHeight = 100.0;
  static const double _gap = 10.0;
  static const double _singleWidth = 176.0;

  @override
  Widget build(BuildContext context) {
    if (enabledCards.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = _columnCountFor(maxWidth);
        final rows = _packRows(enabledCards, columns);
        final unitWidth = _unitWidthFor(maxWidth, columns);

        final slotIndexMap = <HomeBoardCardId, int>{
          for (var i = 0; i < enabledCards.length; i++) enabledCards[i]: i + 1,
        };

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: _gap,
          children: [
            for (final row in rows)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: _gap,
                children: [
                  for (final cardId in row)
                    SizedBox(
                      width: _widthFor(cardId, unitWidth, columns),
                      height: _cardHeight,
                      child: AppearItem(
                        key: ValueKey(cardId),
                        slot: slotIndexMap[cardId] ?? 1,
                        offset: const Offset(0, 0.08),
                        scale: 0.965,
                        duration: const Duration(milliseconds: 220),
                        child: _buildCard(context, cardId),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  /// 按可用宽度决定栅格列数：默认窗口最多 2~3 列，宽屏可到 3 列并保持克制留白
  int _columnCountFor(double maxWidth) {
    if (maxWidth >= _singleWidth * 3 + _gap * 2) return 3;
    if (maxWidth >= _singleWidth * 2 + _gap) return 2;
    return 1;
  }

  double _unitWidthFor(double maxWidth, int columns) {
    final ideal = _singleWidth;
    final availablePerCol = (maxWidth - _gap * (columns - 1)) / columns;
    return availablePerCol < ideal ? availablePerCol : ideal;
  }

  HomeBoardCardSpan _spanOf(HomeBoardCardId id) => switch (id) {
    HomeBoardCardId.quickSwitch => HomeBoardCardSpan.wide,
    _ => HomeBoardCardSpan.single,
  };

  double _widthFor(HomeBoardCardId id, double unitWidth, int columns) {
    final span = _spanOf(id) == HomeBoardCardSpan.wide && columns >= 2 ? 2 : 1;
    return unitWidth * span + _gap * (span - 1);
  }

  /// 按列宽顺序装箱，保证宽卡独占 2 格不破坏竖向列线
  List<List<HomeBoardCardId>> _packRows(
    List<HomeBoardCardId> items,
    int columns,
  ) {
    final rows = <List<HomeBoardCardId>>[];
    var currentRow = <HomeBoardCardId>[];
    var used = 0;

    for (final item in items) {
      final span = _spanOf(item) == HomeBoardCardSpan.wide && columns >= 2
          ? 2
          : 1;
      if (used + span > columns && currentRow.isNotEmpty) {
        rows.add(currentRow);
        currentRow = <HomeBoardCardId>[];
        used = 0;
      }
      currentRow.add(item);
      used += span;
    }
    if (currentRow.isNotEmpty) rows.add(currentRow);
    return rows;
  }

  Widget _buildCard(BuildContext context, HomeBoardCardId id) {
    return switch (id) {
      HomeBoardCardId.recentPlay => _buildRecentPlayCard(context),
      HomeBoardCardId.onlineStatus => _buildOnlineStatusCard(context),
      HomeBoardCardId.quickSwitch => _buildQuickSwitchCard(context),
      HomeBoardCardId.instanceDigest => _buildInstanceDigestCard(context),
      HomeBoardCardId.cloudSync => _buildCloudSyncCard(context),
    };
  }

  Widget _buildRecentPlayCard(BuildContext context) {
    final skin = cuSkinOf(context);
    final versions = config.versionOptions.versionFolds
        .expand((fold) => fold.versions)
        .toList();
    final totalDuration = versions.fold<Duration>(
      Duration.zero,
      (sum, item) => sum + (item.playTime ?? Duration.zero),
    );
    final latest = _latestPlayedVersion(versions);
    final (valueText, unitText) = _formatPlayDuration(totalDuration);
    final footerText = latest == null
        ? '启动一次游戏后开始统计'
        : '${_formatRelativeTime(latest.lastLaunchTime!)} · ${latest.tag}';

    return HomeBoardCardTemplate(
      icon: HomeBoardCardId.recentPlay.icon,
      title: '最近游玩',
      trailing: Text(
        '累计',
        style: TextStyle(fontSize: 10, color: skin.textTertiary),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            valueText,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: skin.textPrimary,
              height: 1.05,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            unitText,
            style: TextStyle(fontSize: 11, color: skin.textSecondary),
          ),
        ],
      ),
      footer: footerText,
    );
  }

  Widget _buildOnlineStatusCard(BuildContext context) {
    final skin = cuSkinOf(context);
    return HomeBoardCardTemplate(
      icon: HomeBoardCardId.onlineStatus.icon,
      title: '联机状态',
      leadingDotColor: skin.textTertiary,
      trailing: _templateChip(skin, '模板'),
      body: Text(
        '待接入联机状态',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: skin.textPrimary,
        ),
      ),
      footer: '后续展示好友在线与联机房间',
    );
  }

  Widget _buildQuickSwitchCard(BuildContext context) {
    final skin = cuSkinOf(context);
    final current = selectedVersion;
    final candidates = <Mindustry>[
      ?current,
      ...recentVersions.take(current == null ? 2 : 1),
    ];

    return HomeBoardCardTemplate(
      icon: HomeBoardCardId.quickSwitch.icon,
      title: '快捷切换',
      trailing: Text(
        '${candidates.length} 个版本',
        style: TextStyle(fontSize: 10, color: skin.textTertiary),
      ),
      body: candidates.isEmpty
          ? _buildEmptyQuickSwitchRow(skin)
          : Row(
              spacing: 6,
              children: [
                for (final version in candidates)
                  Expanded(
                    child: _buildQuickVersionItem(
                      skin,
                      version: version,
                      active: version.id == current?.id,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildEmptyQuickSwitchRow(TemplateSkin skin) {
    return CuPressable(
      onTap: onOpenVersionSelect,
      borderRadius: BorderRadius.circular(7),
      backgroundColor: skin.sunken.withAlpha(skin.dark ? 110 : 140),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.add_rounded, size: 14, color: skin.accentText),
          const SizedBox(width: 6),
          Text(
            '选择或下载一个游戏版本',
            style: TextStyle(fontSize: 11.5, color: skin.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickVersionItem(
    TemplateSkin skin, {
    required Mindustry version,
    required bool active,
  }) {
    final meta = active
        ? '当前'
        : version.lastLaunchTime == null
        ? version.release
        : _formatRelativeTime(version.lastLaunchTime!);

    return CuPressable(
      onTap: active ? null : () => onSelectVersion(version),
      borderRadius: BorderRadius.circular(7),
      backgroundColor: active
          ? skin.accentTint
          : skin.sunken.withAlpha(skin.dark ? 115 : 145),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          Text(
            version.tag,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.25,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? skin.onAccentTint : skin.textPrimary,
            ),
          ),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.25,
              color: active ? skin.onAccentTint : skin.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstanceDigestCard(BuildContext context) {
    final skin = cuSkinOf(context);
    final version = selectedVersion;
    final modeLabel = version == null
        ? '未选择版本'
        : version.steam
        ? 'Steam 实例'
        : version.isolation
        ? '独立隔离目录'
        : '共享默认目录';

    return HomeBoardCardTemplate(
      icon: HomeBoardCardId.instanceDigest.icon,
      title: '实例概览',
      trailing: _templateChip(skin, '模板'),
      body: Text(
        version == null ? '--' : version.release,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: skin.textPrimary,
        ),
      ),
      footer: modeLabel,
    );
  }

  Widget _buildCloudSyncCard(BuildContext context) {
    final skin = cuSkinOf(context);
    return HomeBoardCardTemplate(
      icon: HomeBoardCardId.cloudSync.icon,
      title: '云存档',
      trailing: _templateChip(skin, '模板'),
      body: Text(
        '待接入云同步',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: skin.textPrimary,
        ),
      ),
      footer: '后续展示最近同步与备份状态',
    );
  }

  Widget _templateChip(TemplateSkin skin, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: skin.sunken.withAlpha(skin.dark ? 150 : 185),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9.5, color: skin.textTertiary),
      ),
    );
  }

  Mindustry? _latestPlayedVersion(List<Mindustry> versions) {
    Mindustry? latest;
    for (final version in versions) {
      final time = version.lastLaunchTime;
      if (time == null) continue;
      if (latest == null || time.isAfter(latest.lastLaunchTime!)) {
        latest = version;
      }
    }
    return latest;
  }

  (String, String) _formatPlayDuration(Duration duration) {
    if (duration.inMinutes < 60) {
      return ('${duration.inMinutes}', '分钟');
    }
    final hours = duration.inMinutes / 60.0;
    return (hours.toStringAsFixed(1), '小时');
  }

  String _formatRelativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${time.month}/${time.day}';
  }
}
