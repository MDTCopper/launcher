import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:copper_launcher/domain/cloud/cloud_restore_gap.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 恢复完发现本机缺东西时，玩家的选择
enum CloudRestoreGapChoice {
  /// 现在把能补的模组补上（排进下载队列）
  fillMods,

  /// 把云包里那个游戏版本装回来（排进下载队列）
  installGame,

  /// 先不管
  later,
}

/// 恢复完弹一次：**本机还缺什么**，能补的一键补
///
/// 只负责说清与收选择 —— 拉列表 / 排队下载由调用方去做（那条链要联网、会起任务，
/// 不适合塞在弹窗里）。没得补时调用方**别弹**这个（用 [CloudRestoreGap.isEmpty] 判）。
/// [offerModFill] / [offerGameInstall] 控制这一次露哪几个按钮：
/// 两件都缺时调用方**逐件问**，办完一件再把另一个藏掉
Future<CloudRestoreGapChoice> showRestoreGapPrompt({
  required CloudRestoreGap gap,
  required Mindustry version,
  String? versionTag,
  bool offerModFill = true,
  bool offerGameInstall = true,
  BuildContext? context,
}) async {
  final choice = await showAnimatedDialog<CloudRestoreGapChoice>(
    context: context,
    pageBuilder: (_, _, _) => _CloudRestoreGapDialog(
      gap: gap,
      version: version,
      versionTag: versionTag,
      offerModFill: offerModFill,
      offerGameInstall: offerGameInstall,
    ),
  );
  return choice ?? CloudRestoreGapChoice.later;
}

class _CloudRestoreGapDialog extends StatelessWidget {
  const _CloudRestoreGapDialog({
    required this.gap,
    required this.version,
    required this.offerModFill,
    required this.offerGameInstall,
    this.versionTag,
  });

  final CloudRestoreGap gap;
  final Mindustry version;
  final bool offerModFill;
  final bool offerGameInstall;
  final String? versionTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final screen = MediaQuery.of(context).size;
    final canFill = offerModFill && gap.downloadableMods.isNotEmpty;
    final canInstallGame = offerGameInstall && gap.missingGame != null;

    return Center(
      child: Material(
        elevation: 8,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxWidth: screen.width * 0.5,
            maxHeight: screen.height * 0.8,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              top: BorderSide(color: colors.border, width: 1.5),
              left: BorderSide(color: colors.border, width: 0.75),
              right: BorderSide(color: colors.border, width: 0.75),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text('恢复完成，本机还缺东西', style: theme.textTheme.titleLarge),
              Text(
                '${versionTag == null ? '这个版本' : '「$versionTag」'}的存档已经解到 '
                '${gap.dataPath}，但这份云包里还有本机没有的东西。',
                style: theme.textTheme.bodySmall,
              ),
              if (gap.missingMods.isNotEmpty) _buildMissingMods(context),
              if (gap.missingGame != null) _buildMissingGame(context),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  if (canFill)
                    IconTextButton(
                      icon: Icons.download_outlined,
                      content: '补全模组（${gap.downloadableMods.length}）',
                      onTap: () => Navigator.of(
                        context,
                      ).pop(CloudRestoreGapChoice.fillMods),
                    ),
                  if (canInstallGame)
                    IconTextButton(
                      icon: Icons.download_for_offline_outlined,
                      content: '装游戏版本',
                      onTap: () => Navigator.of(
                        context,
                      ).pop(CloudRestoreGapChoice.installGame),
                    ),
                  IconTextButton(
                    icon: Icons.close,
                    content: canFill || canInstallGame ? '以后再说' : '知道了',
                    onTap: () =>
                        Navigator.of(context).pop(CloudRestoreGapChoice.later),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 缺的模组分两拨列：**能自动补的**与**只能自己装的**（后者要说清为什么）
  Widget _buildMissingMods(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final downloadable = gap.downloadableMods;
    final manual = gap.undownloadableMods;
    final missingButCarried = [
      for (final mod in manual)
        if (mod.includeBytes) mod,
    ];
    final noSource = [
      for (final mod in manual)
        if (!mod.includeBytes) mod,
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.lowBackgroundOnCard,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text(
            '缺 ${gap.missingMods.length} 个模组',
            style: theme.textTheme.titleSmall,
          ),
          if (downloadable.isNotEmpty)
            _line(
              context,
              '能补：${_names(downloadable)}',
              '（按云包里记的来源，或按模组内部名从官方仓库下回来）',
            ),
          if (noSource.isNotEmpty)
            _line(
              context,
              '要你自己装：${_names(noSource)}',
              '（云包没记来源，官方列表里也按内部名对不上 —— 不按显示名猜，同名不同仓库的有好几对）',
            ),
          if (missingButCarried.isNotEmpty)
            _line(
              context,
              '得重新下载云端快照：${_names(missingButCarried)}',
              '（这些是随包带了字节却没落地的）',
            ),
        ],
      ),
    );
  }

  Widget _buildMissingGame(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final game = gap.missingGame!;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.lowBackgroundOnCard,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text('本机没有这个游戏版本', style: theme.textTheme.titleSmall),
          _line(
            context,
            '${game.tag}（${game.release}${game.build == null ? '' : ' · build ${game.build}'}）',
            '点「装游戏版本」直接下回来，或去「下载游戏本体」页自己挑；装完这份存档就能开',
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String title, String hint) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        Text(hint, style: theme.textTheme.labelMedium),
      ],
    );
  }

  String _names(List<CloudModEntry> mods) {
    final names = mods.take(3).map(CloudRestoreGap.displayNameOf).join('、');
    return mods.length > 3 ? '$names 等' : names;
  }
}
