import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'log.dart';

/// 压缩包解压（zip / tar.gz / tar.xz），桌面 JDK 与 Android 桥的载荷共用
///
/// 解出来的条目权限位一律不带（桥会自己把 `.so` 改成可执行 + 只读；
/// 桥 0.1.3 及更早的构建要宿主管，见《android-bridge 使用文档》§3.7）
///
/// 每个条目先过一遍路径校验：绝对路径 / 盘符 / UNC / 含 `..` 越界的条目跳过并记警告，
/// 不让一个坏条目把整包解压拖失败
Future<void> extractArchive(String archivePath, String extractDirPath) async {
  final bytes = await File(archivePath).readAsBytes();
  final lower = archivePath.toLowerCase();

  final Archive archive;
  if (lower.endsWith('.zip')) {
    archive = ZipDecoder().decodeBytes(bytes);
  } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
    archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  } else if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) {
    archive = TarDecoder().decodeBytes(XZDecoder().decodeBytes(bytes));
  } else {
    throw ArgumentError('不认识的压缩包：$archivePath');
  }

  await _extractToDisk(archive, extractDirPath);
}

Future<void> _extractToDisk(Archive archive, String extractDirPath) async {
  final rootPath = p.normalize(p.absolute(extractDirPath));

  for (final file in archive.files) {
    if (!file.isFile) continue;

    final targetPath = _safeTargetPath(rootPath, file.name);
    if (targetPath == null) {
      addLog(.warning, '压缩包条目路径不合法，已跳过：${file.name}', tag: 'Archive');
      continue;
    }

    final outputFile = File(targetPath);
    if (!await outputFile.parent.exists()) {
      await outputFile.parent.create(recursive: true);
    }
    await outputFile.writeAsBytes(file.content as List<int>);
  }
}

/// 把条目名落到目标目录内的绝对路径；绝对路径 / 盘符 / UNC / `..` 越界一律给 null
String? _safeTargetPath(String rootPath, String entryName) {
  final unified = entryName.trim().replaceAll('\\', '/');
  if (unified.isEmpty) return null;
  // `p.posix` 认不出盘符与 UNC，单独拦一次（`C:/x` 在 Windows 上也是绝对路径）
  if (_driveLetterPath.hasMatch(unified) || unified.startsWith('//')) {
    return null;
  }
  if (p.posix.isAbsolute(unified)) return null;

  final normalized = p.posix.normalize(unified);
  if (normalized == '.' || normalized == '..' || normalized.startsWith('../')) {
    return null;
  }

  final targetPath = p.normalize(
    p.joinAll([rootPath, ...normalized.split('/')]),
  );
  // 兜底再核一次：解出来的文件必须还在目标目录里
  if (!p.isWithin(rootPath, targetPath)) return null;
  return targetPath;
}

final RegExp _driveLetterPath = RegExp(r'^[A-Za-z]:/');
