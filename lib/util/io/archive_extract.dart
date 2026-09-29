import 'dart:io';

import 'package:archive/archive.dart';

/// 压缩包解压（zip / tar.gz / tar.xz），桌面 JDK 与 Android 桥的载荷共用
///
/// 解出来的条目权限位一律不带（桥会自己把 `.so` 改成可执行 + 只读；
/// 桥 0.1.3 及更早的构建要宿主管，见《android-bridge 使用文档》§3.7）
Future<void> extractArchive(String archivePath, String extractDir) async {
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

  await _extractToDisk(archive, extractDir);
}

Future<void> _extractToDisk(Archive archive, String extractDir) async {
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final outputFile = File('$extractDir${Platform.pathSeparator}${file.name}');
    if (!await outputFile.parent.exists()) {
      await outputFile.parent.create(recursive: true);
    }
    await outputFile.writeAsBytes(file.content as List<int>);
  }
}
