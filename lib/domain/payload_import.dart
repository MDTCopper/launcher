import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'bridge_payload.dart';

/// 本地载荷导入失败：message 就是给界面看的中文原因
///
/// 导入的是用户自己准备的文件，错误一律走这个类型，
/// 不把 zip / 文件系统的原始异常漏给调用方
class PayloadImportException implements Exception {
  const PayloadImportException(this.message);

  /// 给用户看的中文原因
  final String message;

  @override
  String toString() => message;
}

/// 读 jar 的条目名清单，顺带当「能不能当 jar 打开」的校验
///
/// 打不开（不是 zip / 文件坏了 / 文件不在了）抛 [PayloadImportException]
Future<List<String>> readJarEntryNames(String jarPath) =>
    _withJar(jarPath, (archive) {
      return [for (final entry in archive.files) entry.name];
    });

/// 读 jar 里某个 properties 条目的某个键；条目或键不存在返回 null
Future<String?> readJarProperty(String jarPath, String entryName, String key) =>
    _withJar(jarPath, (archive) {
      final bytes = archive.findFile(entryName)?.readBytes();
      if (bytes == null) return null;
      return BridgePayload.propertyValue(
        utf8.decode(bytes, allowMalformed: true),
        key,
      );
    });

/// 复制到目标位置：先写同目录的临时文件再改名，中途失败不会留半截文件
///
/// 目标已存在就替换；旧文件被桥改成只读、删不掉时给中文错误
Future<void> copyFileAtomically(File source, String targetPath) async {
  if (!source.existsSync()) {
    throw const PayloadImportException('选的文件不在了，重新选一次');
  }

  final target = File(targetPath);
  final tempPath = '$targetPath.importing';
  try {
    await target.parent.create(recursive: true);
    await source.copy(tempPath);
  } catch (_) {
    _deleteFileQuietly(tempPath);
    throw const PayloadImportException('写不进目标目录：可能权限不足或空间不够');
  }

  try {
    await File(tempPath).rename(targetPath);
    return;
  } on FileSystemException {
    // 改名盖不住已有文件（Windows 这类）：把旧的删掉再改名
  }

  try {
    if (target.existsSync()) target.deleteSync();
    await File(tempPath).rename(targetPath);
  } catch (_) {
    _deleteFileQuietly(tempPath);
    throw const PayloadImportException('旧的同名文件删不掉，可能被桥改成了只读，先清掉运行环境再导入');
  }
}

/// 打开 jar 交给 [body]，读完必定释放文件句柄
///
/// 句柄不关的话 Windows 上后面要删这个 jar 会失败；打不开统一成中文错误
Future<T> _withJar<T>(String jarPath, T Function(Archive archive) body) async {
  if (!File(jarPath).existsSync()) {
    throw const PayloadImportException('选的文件不在了，重新选一次');
  }

  InputFileStream? stream;
  Archive? archive;
  try {
    stream = InputFileStream(jarPath);
    archive = ZipDecoder().decodeStream(stream);
    return body(archive);
  } on PayloadImportException {
    rethrow;
  } catch (_) {
    throw const PayloadImportException('不是有效的 jar，打不开这个压缩包');
  } finally {
    archive?.clearSync();
    stream?.closeSync();
  }
}

void _deleteFileQuietly(String filePath) {
  try {
    final file = File(filePath);
    if (file.existsSync()) file.deleteSync();
  } catch (_) {
    // 临时文件删不掉不影响这次导入的结果判断
  }
}
