import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:path/path.dart' as p;

/// 恢复完本机还缺什么：**缺哪些模组、缺哪个游戏版本**
///
/// 「恢复」是覆盖式的，云端包里只带**我们自己打包时收进去的东西** ——
/// 模组字节默认不进包（一份配额连 11 个真模组都放不下），所以恢复完经常是
/// 「存档回来了、模组没回来」，进游戏才发现开不了。这里把缺口算出来，
/// 交给界面提示 + 一键补全
class CloudRestoreGap {
  const CloudRestoreGap({
    required this.dataPath,
    required this.missingMods,
    this.missingGame,
  });

  /// 恢复到哪个数据目录 —— 提示里要说清（多个版本共用一份目录时尤其）
  final String dataPath;

  /// 本机没有的模组（按文件名比，禁用后缀也算装了）
  final List<CloudModEntry> missingMods;

  /// 本机没有对应 tag / 发布号的游戏版本；有就不给
  final CloudGameInfo? missingGame;

  bool get isEmpty => missingMods.isEmpty && missingGame == null;

  /// 缺的模组里**能一键下回来**的：字节本来就不在包里，且要么记了来源（`repo`），
  /// 要么有内部名（官方列表现在带 `internalName`，能据此查到仓库）
  List<CloudModEntry> get downloadableMods => [
    for (final mod in missingMods)
      if (_canLookUp(mod)) mod,
  ];

  /// 只能提示、代不了的：
  /// - 既没记来源（模组自己没写 `repo`）也没有内部名
  /// - 本来随包带了字节却没落地（那种该重新下载云端快照，而不是去下模组）
  List<CloudModEntry> get undownloadableMods => [
    for (final mod in missingMods)
      if (!_canLookUp(mod)) mod,
  ];

  static bool _canLookUp(CloudModEntry mod) =>
      !mod.includeBytes &&
      ((mod.source?.trim().isNotEmpty ?? false) ||
          (mod.internalName?.trim().isNotEmpty ?? false));

  /// 提示里显示的名字：优先显示名，其次内部名，最后文件名
  static String displayNameOf(CloudModEntry mod) {
    final display = mod.displayName?.trim() ?? '';
    if (display.isNotEmpty) return display;
    final internal = mod.internalName?.trim() ?? '';
    if (internal.isNotEmpty) return internal;
    return mod.fileName;
  }
}

/// 一句话说清「恢复完还缺什么」—— 通知与弹窗共用一份说法，别各写各的
String describeRestoreGap(CloudRestoreGap gap) {
  final parts = <String>[
    if (gap.missingMods.isNotEmpty) '缺 ${gap.missingMods.length} 个模组',
    if (gap.missingGame != null) '本机没有游戏版本 ${gap.missingGame!.release}',
  ];
  if (parts.isEmpty) return '什么都不缺';
  return '${parts.join('、')}（恢复到 ${gap.dataPath}）';
}

/// 比对「包里的清单」与「本机现状」
///
/// 纯计算：不联网、不写盘。[installedGameTags] 传本机装着的版本标识
/// （tag 与发布号都认，见 [installedGameIdentifiers]）
CloudRestoreGap computeRestoreGap({
  required String dataPath,
  required CloudManifest manifest,
  required Iterable<String> installedGameTags,
}) {
  final localModFiles = _localModFileNames(dataPath);
  final missingMods = [
    for (final mod in manifest.mods)
      if (!localModFiles.contains(normalizedModFileName(mod.fileName))) mod,
  ];

  final installed = {
    for (final identifier in installedGameTags) identifier.trim(),
  };
  final game = manifest.game;
  final hasGame = installed.contains(game.tag.trim()) ||
      (game.release.trim().isNotEmpty && installed.contains(game.release.trim()));

  return CloudRestoreGap(
    dataPath: dataPath,
    missingMods: missingMods,
    missingGame: hasGame ? null : game,
  );
}

/// 本机装着的版本标识：分类 tag + 每个版本的发布号
///
/// 包里的 `game.tag` 是「版本记录里的 tag」（如 `v8 Build 160.5`），
/// 本机换了 tag 但发布号相同的情况（用户改过版本名）也该算「有这个版本」
Iterable<String> installedGameIdentifiers() sync* {
  for (final fold in config.versionOptions.versionFolds) {
    yield fold.tag;
    for (final version in fold.versions) {
      yield version.release;
    }
  }
}

/// 比较用的模组文件名：小写、去掉禁用后缀
///
/// 云端清单记的是**当时的真实文件名**，禁用态可能带 `.disable`，本机也可能反过来，
/// 所以两边都要归一过再比，否则「装了但禁用着」会被当成没装
String normalizedModFileName(String name) {
  var normalized = name.trim().toLowerCase();
  for (final suffix in const ['.disabled', '.disable']) {
    if (normalized.endsWith(suffix)) {
      normalized = normalized.substring(0, normalized.length - suffix.length);
    }
  }
  return normalized;
}

/// 本机数据目录里现有的模组文件名（归一后的小写名）
///
/// 两个地方都要看：原版模组在 `mods/`、Copper 原生模组在 `copper/mods/`。
/// Mindustry 禁用模组会把文件后缀改掉（`<名字>.jar.disable`），那也算装了
Set<String> _localModFileNames(String dataPath) {
  final names = <String>{};
  for (final folder in const ['mods', 'copper/mods']) {
    final directory = Directory(p.joinAll([dataPath, ...folder.split('/')]));
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      names.add(normalizedModFileName(p.basename(entity.path)));
    }
  }
  return names;
}
