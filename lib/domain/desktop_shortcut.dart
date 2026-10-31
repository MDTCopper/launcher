import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/data/mindustry/mindustry.dart';
import 'package:copper_launcher/domain/launch_request.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 创建桌面快捷方式的结果
class DesktopShortcutResult {
  const DesktopShortcutResult({required this.shortcutPath, this.iconPath});

  /// 生成的 `.lnk` 路径
  final String shortcutPath;

  /// 实际写进快捷方式的 `.ico`；null 表示回退到启动器 exe 的图标
  final String? iconPath;
}

/// Windows 桌面快捷方式：在桌面建一个「双击直接启动这个版本」的 `.lnk`
///
/// 快捷方式带 `--launch-version <version.id>`（见 [LaunchRequest]），由启动器
/// 起来后接手启动。图标优先用玩家给版本换的那张，转成 `.ico` 缓存进
/// [AppPaths.shortcutIcons]；没有图标或转换失败时用启动器 exe 的图标。
class DesktopShortcut {
  DesktopShortcut._();

  /// 给 [version] 在桌面建快捷方式
  ///
  /// 失败抛异常（message 可直接给用户看）；图标问题不抛，回退 exe 图标
  static Future<DesktopShortcutResult> create(Mindustry version) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('桌面快捷方式只支持 Windows');
    }

    final executable = Platform.resolvedExecutable;
    final iconPath = await _prepareIcon(version);
    final desktop = await _desktopDirectory();
    final shortcutPath = p.join(desktop, shortcutFileName(version.tag));

    await _runPowerShell(
      buildCreateShortcutScript(
        shortcutPath: shortcutPath,
        targetPath: executable,
        arguments: '${LaunchRequest.argument} ${version.id}',
        workingDirectory: p.dirname(executable),
        description: version.tag,
        iconPath: iconPath,
      ),
    );

    return DesktopShortcutResult(shortcutPath: shortcutPath, iconPath: iconPath);
  }

  /// 桌面目录：路径按 UTF-16LE + Base64 传回，绕开控制台代码页的编码差异
  static Future<String> _desktopDirectory() async {
    final encoded = await _runPowerShell(
      r"[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes([Environment]::GetFolderPath('Desktop')))",
    );
    final path = _decodeUtf16Le(base64Decode(encoded.trim()));
    if (path.trim().isEmpty) throw Exception('拿不到桌面目录');
    return path;
  }

  /// 准备快捷方式图标：能转就返回 `.ico` 路径，转不了返回 null（回退 exe 图标）
  static Future<String?> _prepareIcon(Mindustry version) async {
    final source = version.resolvedIconPath;
    if (source == null) return null;
    final file = File(source);
    if (!await file.exists()) return null;

    try {
      final directory = Directory(AppPaths.shortcutIcons);
      await directory.create(recursive: true);
      final target = File(
        p.join(directory.path, '${_safeId(version.id)}.ico'),
      );

      // 已经是 ico：直接复制，不用再转
      if (p.extension(source).toLowerCase() == '.ico') {
        await target.writeAsBytes(await file.readAsBytes(), flush: true);
        return target.path;
      }

      // 其他图片：PowerShell 缩到 256x256 PNG，再包成 Vista+ 的 PNG-compressed ICO
      final pngBytes = await _resizeToPng(source);
      await target.writeAsBytes(wrapPngAsIco(pngBytes), flush: true);
      return target.path;
    } catch (error) {
      debugPrint('版本图标转 ico 失败，快捷方式改用启动器图标：$error');
      return null;
    }
  }

  /// 用 System.Drawing 把图片缩成 256x256 PNG，返回 PNG 字节
  static Future<Uint8List> _resizeToPng(String sourcePath) async {
    final temp = await Directory.systemTemp.createTemp('copper_shortcut_icon_');
    try {
      final target = p.join(temp.path, 'icon.png');
      await _runPowerShell(
        buildResizeIconScript(sourcePath: sourcePath, targetPath: target),
      );
      return await File(target).readAsBytes();
    } finally {
      try {
        await temp.delete(recursive: true);
      } catch (_) {
        // 临时目录删不掉不影响结果
      }
    }
  }

  /// 跑一段 PowerShell：非 0 退出码抛异常（带 stderr，去掉换行）
  static Future<String> _runPowerShell(String script) async {
    final ProcessResult result;
    try {
      result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]);
    } on ProcessException catch (error) {
      throw Exception('无法运行 PowerShell：${removeNewlines('$error')}');
    }
    if (result.exitCode != 0) {
      throw Exception(
        'PowerShell 执行失败：${removeNewlines('${result.stderr}')}',
      );
    }
    return '${result.stdout}';
  }

  /// 版本 id 理论上都是 uuid，保险起见把文件名里不安全的字符换掉
  static String _safeId(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

/// 快捷方式文件名：版本 tag 里 Windows 文件名非法字符换成 `_`，
/// 去掉首尾空格 / 点；空则回退 `Mindustry`，扩展名 `.lnk`
String shortcutFileName(String tag) {
  var name = tag.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  name = name.replaceAll(RegExp(r'^[\s.]+|[\s.]+$'), '');
  return '${name.isEmpty ? 'Mindustry' : name}.lnk';
}

/// 把一张 PNG 包成 Vista+ 支持的 PNG-compressed ICO
///
/// 结构：6 字节头（保留 0、类型 1、数量 1）+ 16 字节目录项 + 原始 PNG；
/// 宽高从 PNG 的 IHDR 读，读不出 / 达到 256 都记 0（ICO 里 0 表示 256）
Uint8List wrapPngAsIco(Uint8List pngBytes) {
  final size = _pngSize(pngBytes);
  final width = size?.$1 ?? 256;
  final height = size?.$2 ?? 256;

  final header = ByteData(22);
  header.setUint16(0, 0, Endian.little); // 保留
  header.setUint16(2, 1, Endian.little); // 类型：图标
  header.setUint16(4, 1, Endian.little); // 图片数量
  header.setUint8(6, width >= 256 ? 0 : width);
  header.setUint8(7, height >= 256 ? 0 : height);
  header.setUint8(8, 0); // 调色板颜色数
  header.setUint8(9, 0); // 保留
  header.setUint16(10, 1, Endian.little); // 颜色平面
  header.setUint16(12, 32, Endian.little); // 位深
  header.setUint32(14, pngBytes.length, Endian.little); // 图片数据长度
  header.setUint32(18, 22, Endian.little); // 图片数据偏移

  final result = Uint8List(22 + pngBytes.length);
  result.setRange(0, 22, header.buffer.asUint8List());
  result.setRange(22, result.length, pngBytes);
  return result;
}

/// 生成创建 `.lnk` 的 PowerShell 脚本（纯函数，方便单测引号转义）
String buildCreateShortcutScript({
  required String shortcutPath,
  required String targetPath,
  required String arguments,
  required String workingDirectory,
  String? iconPath,
  String? description,
}) {
  final script = StringBuffer()
    ..writeln(r'$shell = New-Object -ComObject WScript.Shell')
    ..writeln('\$shortcut = \$shell.CreateShortcut(${_psQuote(shortcutPath)})')
    ..writeln('\$shortcut.TargetPath = ${_psQuote(targetPath)}')
    ..writeln('\$shortcut.Arguments = ${_psQuote(arguments)}')
    ..writeln('\$shortcut.WorkingDirectory = ${_psQuote(workingDirectory)}');
  if (description != null && description.isNotEmpty) {
    script.writeln('\$shortcut.Description = ${_psQuote(description)}');
  }
  if (iconPath != null) {
    script.writeln('\$shortcut.IconLocation = ${_psQuote('$iconPath,0')}');
  }
  script.writeln(r'$shortcut.Save()');
  return script.toString();
}

/// 生成「缩放到 256x256 PNG」的 PowerShell 脚本（纯函数，方便单测引号转义）
String buildResizeIconScript({
  required String sourcePath,
  required String targetPath,
}) {
  return '''
Add-Type -AssemblyName System.Drawing
\$source = [System.Drawing.Image]::FromFile(${_psQuote(sourcePath)})
\$bitmap = New-Object -TypeName System.Drawing.Bitmap -ArgumentList 256, 256
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
\$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
\$graphics.DrawImage(\$source, 0, 0, 256, 256)
\$graphics.Dispose()
\$source.Dispose()
\$bitmap.Save(${_psQuote(targetPath)}, [System.Drawing.Imaging.ImageFormat]::Png)
\$bitmap.Dispose()
''';
}

/// PowerShell 单引号字符串：内部单引号写成两个
String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// 从 PNG 的 IHDR 读宽高；签名 / IHDR 对不上返回 null
(int, int)? _pngSize(Uint8List bytes) {
  if (bytes.length < 24) return null;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return null;
  }
  // 12..16 是 chunk 类型，必须是 IHDR
  if (bytes[12] != 0x49 ||
      bytes[13] != 0x48 ||
      bytes[14] != 0x44 ||
      bytes[15] != 0x52) {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}

/// UTF-16LE 字节转字符串（PowerShell 传路径用，避免控制台编码）
String _decodeUtf16Le(Uint8List bytes) {
  final units = <int>[
    for (var i = 0; i + 1 < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
  ];
  return String.fromCharCodes(units);
}
