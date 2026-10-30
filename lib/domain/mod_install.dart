import 'dart:io';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:path/path.dart' as p;

/// 一个已装模组文件：内部名相同即视为同一个 mod（不看版本号）
class InstalledModFile {
  const InstalledModFile({
    required this.path,
    required this.internalName,
    required this.disabled,
  });

  final String path;
  final String internalName;

  /// 按文件名后缀判断的禁用态（`.disable` / `.disabled`）
  final bool disabled;
}

/// 一次装模组的结果
class ModInstallOutcome {
  const ModInstallOutcome({
    required this.path,
    required this.disabled,
    required this.removed,
  });

  /// 新文件最终落盘路径（沿用旧禁用态时带 `.disable`）
  final String path;

  /// 新文件是不是禁用态
  final bool disabled;

  /// 被清掉的同一个 mod 的旧文件
  final List<String> removed;
}

/// 扫描这些目录里认得出的模组文件（jar / zip，含禁用态）
///
/// 只扫目录第一层：模组文件都是平铺的；认不出元数据的文件（坏包 / 不是 mod 的 jar）跳过，
/// 不参与去重，避免拿不到内部名就误删
Future<List<InstalledModFile>> scanInstalledMods(
  Iterable<String> modsDirs,
) async {
  final found = <InstalledModFile>[];
  final seenDirs = <String>{};
  for (final dir in modsDirs) {
    if (!seenDirs.add(_normalizedPath(dir))) continue;
    final directory = Directory(dir);
    if (!await directory.exists()) continue;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final installed = await _readInstalledMod(entity.path);
      if (installed != null) found.add(installed);
    }
  }
  return found;
}

/// 装一份本地 mod 文件到 [targetDir]
///
/// 规则：同一个 mod（内部名相同）只留这一份新文件，旧版本文件全部删掉——
/// **不比版本号**，新文件总是赢；旧文件是禁用态时新文件也落成禁用态。
///
/// [modsDirs] 是这个数据目录下全部模组目录（用于找回旧版本，含 copper/mods）；
/// [targetDir] 是这份新文件该落的目录（按它是不是 Copper 原生模组决定）；
/// [tempDir] 放拷贝中的临时文件，别落在 mods 目录里（Steam 云会把 mods 下所有文件传上去）；
/// [known] 是批量导入时复用的一次扫描结果，会在装完后更新，避免每个文件都重扫目录
Future<ModInstallOutcome> installModFile({
  required String sourcePath,
  required Mod mod,
  required String targetDir,
  required Iterable<String> modsDirs,
  required String tempDir,
  List<InstalledModFile>? known,
}) async {
  final installed = known ?? await scanInstalledMods(modsDirs);
  final previous = _filesOf(installed, mod.internalName);
  final disabled =
      isDisabledModFileName(p.basename(sourcePath)) ||
      previous.any((file) => file.disabled);

  final destination = p.join(
    targetDir,
    _installedFileName(p.basename(sourcePath), disabled: disabled),
  );

  //先拷到临时位置：拷完再删旧文件，中途失败不会把旧版本弄丢
  final temporary = await _copyToTemp(sourcePath, tempDir, destination);
  try {
    final removed = <String>[];
    for (final file in previous) {
      if (await _deleteQuietly(file.path)) removed.add(file.path);
    }
    //目的地可能有认不出元数据的同名文件（坏包之类），按「新文件覆盖旧文件」一并盖掉
    if (!previous.any((file) => _samePath(file.path, destination))) {
      await _deleteQuietly(destination);
    }

    await Directory(targetDir).create(recursive: true);
    await File(temporary).rename(destination);

    _rememberInstalled(
      known,
      previous,
      InstalledModFile(
        path: destination,
        internalName: mod.internalName,
        disabled: disabled,
      ),
    );
    addLog(
      .info,
      '装模组：$sourcePath → $destination${disabled ? '（禁用态）' : ''}'
      '${removed.isEmpty ? '' : '；替换旧文件 ${removed.length} 个：${removed.join('；')}'}',
      tag: 'ModInstall',
    );
    return ModInstallOutcome(
      path: destination,
      disabled: disabled,
      removed: removed,
    );
  } catch (error) {
    await _deleteQuietly(temporary);
    rethrow;
  }
}

/// 文件已经写好（下载 / 源码解压完成）之后的去重收尾
///
/// 把同一个 mod 的其他文件删掉、旧版本是禁用态时把这份也改成禁用名；
/// 返回最终路径（可能带 `.disable`）
Future<ModInstallOutcome> dedupeInstalledMod({
  required String installedPath,
  required Mod mod,
  required Iterable<String> modsDirs,
}) async {
  final installed = await scanInstalledMods(modsDirs);
  final previous = [
    for (final file in _filesOf(installed, mod.internalName))
      if (!_samePath(file.path, installedPath)) file,
  ];
  final disabled = previous.any((file) => file.disabled);

  final removed = <String>[];
  for (final file in previous) {
    if (await _deleteQuietly(file.path)) removed.add(file.path);
  }

  var path = installedPath;
  var actualDisabled = isDisabledModFileName(p.basename(installedPath));
  var renamedToDisabled = false;
  if (disabled && !actualDisabled) {
    final renamed = '$installedPath.disable';
    try {
      await File(installedPath).rename(renamed);
      path = renamed;
      actualDisabled = true;
      renamedToDisabled = true;
    } catch (error) {
      addLog(
        .warning,
        '模组改成禁用名失败：$installedPath，${removeNewlines('$error')}',
        tag: 'ModInstall',
      );
    }
  }

  if (removed.isNotEmpty || renamedToDisabled) {
    addLog(
      .info,
      '模组去重：保留 $path'
      '${removed.isEmpty ? '' : '；删掉旧文件 ${removed.length} 个：${removed.join('；')}'}',
      tag: 'ModInstall',
    );
  }
  return ModInstallOutcome(
    path: path,
    disabled: actualDisabled,
    removed: removed,
  );
}

/// 清掉 [modsDirs] 里同一个 mod 的其他文件，只留 [keepPath]
///
/// 给「文件已经由别的流程写好了」的场景用（例如云存档恢复随包带的模组）
Future<List<String>> removeOtherModFiles({
  required String internalName,
  required Iterable<String> modsDirs,
  required String keepPath,
}) async {
  final installed = await scanInstalledMods(modsDirs);
  final removed = <String>[];
  for (final file in _filesOf(installed, internalName)) {
    if (_samePath(file.path, keepPath)) continue;
    if (await _deleteQuietly(file.path)) removed.add(file.path);
  }
  if (removed.isNotEmpty) {
    addLog(
      .info,
      '模组去重（$internalName）：保留 $keepPath；删掉旧文件 ${removed.length} 个：${removed.join('；')}',
      tag: 'ModInstall',
    );
  }
  return removed;
}

List<InstalledModFile> _filesOf(
  List<InstalledModFile> installed,
  String internalName,
) => [
  for (final file in installed)
    if (file.internalName == internalName) file,
];

Future<InstalledModFile?> _readInstalledMod(String path) async {
  final fileName = p.basename(path);
  final baseName = stripDisabledModSuffix(fileName).toLowerCase();
  if (!baseName.endsWith('.jar') && !baseName.endsWith('.zip')) return null;

  final reader = await FileReader.fromPath(path);
  final mod = reader.mod;
  if (mod == null) return null;
  return InstalledModFile(
    path: path,
    internalName: mod.internalName,
    disabled: isDisabledModFileName(fileName),
  );
}

/// 落盘用的文件名：源文件本来带禁用后缀就原样用，否则沿用旧禁用态加 `.disable`
String _installedFileName(String sourceFileName, {required bool disabled}) {
  final hasSuffix = isDisabledModFileName(sourceFileName);
  if (!disabled || hasSuffix) return sourceFileName;
  return '${stripDisabledModSuffix(sourceFileName)}.disable';
}

Future<String> _copyToTemp(
  String sourcePath,
  String tempDir,
  String destination,
) async {
  await Directory(tempDir).create(recursive: true);
  final fileName = p.basename(destination);
  final temporary = p.join(
    tempDir,
    '.mod-install-${DateTime.now().microsecondsSinceEpoch}-$fileName',
  );
  await File(sourcePath).copy(temporary);
  return temporary;
}

Future<bool> _deleteQuietly(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
    return true;
  } catch (error) {
    addLog(
      .warning,
      '删除旧模组文件失败：$path，${removeNewlines('$error')}',
      tag: 'ModInstall',
    );
    return false;
  }
}

void _rememberInstalled(
  List<InstalledModFile>? known,
  List<InstalledModFile> removed,
  InstalledModFile installed,
) {
  if (known == null) return;
  final removedPaths = {for (final file in removed) _normalizedPath(file.path)};
  known.removeWhere(
    (file) =>
        removedPaths.contains(_normalizedPath(file.path)) ||
        _samePath(file.path, installed.path),
  );
  known.add(installed);
}

bool _samePath(String a, String b) => _normalizedPath(a) == _normalizedPath(b);

String _normalizedPath(String path) => p.normalize(path).toLowerCase();
