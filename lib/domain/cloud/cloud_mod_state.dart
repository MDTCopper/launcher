import 'dart:io';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/domain/cloud/cloud_manifest.dart';
import 'package:copper_launcher/domain/cloud/cloud_restore_gap.dart';
import 'package:copper_launcher/domain/mod_install.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

/// 按云清单把模组的启用 / 禁用态落回本机的结果
class CloudModStateReport {
  int disabled = 0;
  int enabled = 0;
  int missing = 0;
  int conflicts = 0;

  bool get isEmpty => disabled == 0 && enabled == 0;

  String describe() {
    if (isEmpty) return '模组启用态没有要改的';
    final parts = <String>[
      if (disabled > 0) '禁用 $disabled 个',
      if (enabled > 0) '启用 $enabled 个',
      if (missing > 0) '有 $missing 个本机没有',
      if (conflicts > 0) '有 $conflicts 个目标名已存在、没动',
    ];
    return parts.join('；');
  }
}

/// 把云清单里的模组启用态落回本机
///
/// **只改文件名后缀**（禁用 → `.disable`，启用 → 去掉后缀），不碰 `settings.bin`：
/// 那份已经按云包逐字节覆盖过了，游戏真正跳过禁用模组靠的是后缀。
/// 同一个模组在 `mods/` 与 `copper/mods/` 都可能有一份：先按清单里的 `isCopper` 与文件名找，
/// 找不到再按内部名两边找（补全 / 下载装的版本文件名可能与清单记的不一致）
Future<CloudModStateReport> applyModEnabledStates({
  required String dataPath,
  required CloudManifest manifest,
}) async {
  final report = CloudModStateReport();

  //按内部名兜底查找要解析目录里的模组元数据：整个清单只扫一次
  List<InstalledModFile>? installedMods;
  Future<List<File>> findFiles(CloudModEntry mod) async {
    final directory = Directory(modsDirIn(dataPath, copper: mod.isCopper));
    if (directory.existsSync()) {
      final wanted = normalizedModFileName(mod.fileName);
      final matches = [
        for (final entity in directory.listSync())
          if (entity is File &&
              normalizedModFileName(p.basename(entity.path)) == wanted)
            entity,
      ];
      if (matches.isNotEmpty) return matches;
    }

    final internalName = mod.internalName;
    if (internalName == null) return const [];
    installedMods ??= await scanInstalledMods(allModsDirsIn(dataPath));
    return [
      for (final file in installedMods!)
        if (file.internalName == internalName) File(file.path),
    ];
  }

  for (final mod in manifest.mods) {
    final desired = mod.enabled ?? manifest.modStates[mod.internalName ?? ''];
    if (desired == null) continue;

    final matches = await findFiles(mod);
    if (matches.isEmpty) {
      report.missing++;
      continue;
    }

    for (final file in matches) {
      final name = p.basename(file.path);
      final hasSuffix = _hasDisabledSuffix(name);
      if (desired && !hasSuffix) continue;
      if (!desired && hasSuffix) continue;

      final directory = p.dirname(file.path);
      final targetName = desired ? _stripDisabledSuffix(name) : '$name.disable';
      final target = File(p.join(directory, targetName));
      if (target.existsSync() && target.path != file.path) {
        // 目标名已经有文件：留着两份也不对，宁可不动并记一笔
        report.conflicts++;
        continue;
      }

      try {
        file.renameSync(target.path);
        if (desired) {
          report.enabled++;
        } else {
          report.disabled++;
        }
      } catch (error) {
        addLog(
          .warning,
          '调整模组启用态失败（$name）：${removeNewlines('$error')}',
          tag: 'Cloud',
        );
      }
    }
  }

  if (!report.isEmpty) {
    addLogAndPrint(
      .info,
      '按云清单调整模组启用态：${report.describe()}',
      tag: 'Cloud',
    );
  }
  return report;
}

bool _hasDisabledSuffix(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.disabled') || lower.endsWith('.disable');
}

String _stripDisabledSuffix(String name) {
  final lower = name.toLowerCase();
  for (final suffix in const ['.disabled', '.disable']) {
    if (lower.endsWith(suffix)) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}
