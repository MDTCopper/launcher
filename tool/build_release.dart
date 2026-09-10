// 一键构建版本脚本
//
// 做三件事：
//   1. 交互式收集本次构建信息（版本号 / 发布类型 / 是否计入 build number / 构建平台）
//   2. 写入 lib/core/app_constant.dart 的版本信息块与 pubspec.yaml 的 version
//   3. 调 flutter build <平台> --release
//
// 用法：
//   dart tool/build_release.dart                 // 全交互（回车用默认值）
//   dart tool/build_release.dart --no-build      // 只写版本信息，不构建
//   dart tool/build_release.dart --version 0.0.2 --channel alpha --bump --platform both --yes
//
// 放 tool/ 下是有原因的：Dart-Code 只认 bin / tool / .dart_tool 为「Dart 程序」，
// 放别处（如 .script/）在 Flutter 项目里会被当 Flutter 会话跑，而 Flutter 会话
// 不支持 console: terminal → stdin 读不到，交互提问会卡住
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

/// 版本信息写在这个文件的标记块里
const appConstantPath = 'lib/core/app_constant.dart';

/// pubspec 的 version 段 = 版本号 + YYMMDD
const pubspecPath = 'pubspec.yaml';

/// 记住上次选的构建平台（本地状态，不入库）
const statePath = 'tool/build_release_state.json';

/// 版本信息块的边界标记
const versionBlockStart = '// ===== 版本信息（由 tool/build_release.dart 生成，勿手改）=====';
const versionBlockEnd = '// ===== 版本信息结束 =====';

/// 发布类型
enum ReleaseChannel {
  release('正式', ''),
  alpha('内测', 'alpha'),
  beta('公测', 'beta');

  const ReleaseChannel(this.label, this.suffix);

  final String label;

  /// UI 版本号尾缀，正式版为空；内测 / 公测接 build number
  final String suffix;
}

/// 构建平台
enum BuildPlatform {
  windows('Windows', ['windows']),
  android('Android', ['apk']),
  both('两者', ['windows', 'apk']);

  const BuildPlatform(this.label, this.flutterTargets);

  final String label;

  /// `flutter build` 的目标名
  final List<String> flutterTargets;
}

/// 构建完的打包方式（以后加 setup / dmg 就在这里加一项）
enum PackageFormat {
  none('不打包'),
  zip('Zip（解压即用）');

  const PackageFormat(this.label);

  final String label;
}

/// 命令行参数（不传的部分才会提问）
class BuildOptions {
  String? versionName;
  ReleaseChannel? channel;
  bool? countBuildNumber;
  BuildPlatform? platform;
  PackageFormat? packageFormat;
  bool skipBuild = false;
  bool skipConfirm = false;

  /// 构建完是否打开产物文件夹；null = 交互模式提问 / --yes 模式不问也不开
  bool? openFolder;
}

/// 当前版本信息（从 app_constant.dart 读出来）
class CurrentVersion {
  const CurrentVersion({
    required this.versionName,
    required this.buildNumber,
    required this.buildTime,
  });

  final String versionName;
  final int buildNumber;
  final String buildTime;
}

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) return; // --help

  final current = _readCurrentVersion();
  stdout.writeln(
    '当前版本：v${current.versionName}（build ${current.buildNumber}，${current.buildTime}）\n',
  );

  final versionName = options.versionName ?? _askVersionName(current.versionName);
  final channel = options.channel ?? _askChannel();
  final countBuildNumber = options.countBuildNumber ?? _askCountBuildNumber();
  final platform = options.platform ?? _askPlatform();

  // 只改版本号（不构建）：--no-build / --version-only 跳过提问，交互模式下问一步
  final shouldBuild = options.skipBuild
      ? false
      : (options.skipConfirm ||
            _askYesNo('是否执行构建？（选 n 只写版本信息）'));

  final buildNumber = countBuildNumber
      ? current.buildNumber + 1
      : current.buildNumber;
  final buildTime = _formatBuildTime(DateTime.now());
  final pubspecBuildTime = _formatPubspecBuildTime(DateTime.now());
  final displayVersion = channel.suffix.isEmpty
      ? 'v$versionName'
      : 'v$versionName ${channel.suffix} $buildNumber';

  stdout.writeln('\n将要写入：');
  stdout.writeln('  appVersion      = $displayVersion');
  stdout.writeln('  appBuildNumber  = $buildNumber');
  stdout.writeln('  appBuildTime    = $buildTime');
  stdout.writeln('  pubspec version = $versionName+$pubspecBuildTime');
  stdout.writeln(
    '  构建            = ${shouldBuild ? platform.label : '否（只写版本信息）'}',
  );

  if (!options.skipConfirm && !_askYesNo('\n确认执行？')) {
    stdout.writeln('已取消');
    return;
  }

  _writeVersionBlock(
    displayVersion: displayVersion,
    buildNumber: buildNumber,
    buildTime: buildTime,
  );
  _writePubspecVersion('$versionName+$pubspecBuildTime');
  _savePlatform(platform);
  stdout.writeln('\n版本信息已写入 $appConstantPath / $pubspecPath');

  if (!shouldBuild) return;

  for (final target in platform.flutterTargets) {
    stdout.writeln('\n> flutter build $target --release');
    final process = await Process.start(
      'flutter',
      ['build', target, '--release'],
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      stderr.writeln('flutter build $target 失败（退出码 $exitCode）');
      exit(exitCode);
    }
  }
  stdout.writeln('\n构建完成');

  final outputFolders = _outputFolders(platform);
  for (final folder in outputFolders) {
    stdout.writeln('产物目录：${_normalizePath(folder.path)}');
  }

  final archive = await _packageIfNeeded(
    options: options,
    versionName: versionName,
    channel: channel,
    buildNumber: buildNumber,
  );

  final foldersToOpen = <Directory>[
    ...outputFolders,
    if (archive != null) archive.parent,
  ];
  if (foldersToOpen.isEmpty) return;

  // --yes 免交互时不主动弹文件管理器，只认 --open-folder
  final shouldOpenFolder =
      options.openFolder ??
      (!options.skipConfirm && _askYesNo('打开产物文件夹？'));
  if (!shouldOpenFolder) return;
  for (final folder in foldersToOpen) {
    await _openFolder(folder.path);
  }
}

// ---------------------------------------------------------------------------
// 命令行参数
// ---------------------------------------------------------------------------

/// 解析参数；返回 null 表示只打印了帮助，不继续
BuildOptions? _parseArgs(List<String> args) {
  final options = BuildOptions();
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String nextValue() {
      if (i + 1 >= args.length) throw ArgumentError('$arg 缺少取值');
      return args[++i];
    }

    switch (arg) {
      case '--version':
        options.versionName = nextValue();
      case '--channel':
        options.channel = _channelOf(nextValue());
      case '--bump':
        options.countBuildNumber = true;
      case '--no-bump':
        options.countBuildNumber = false;
      case '--platform':
        options.platform = _platformOf(nextValue());
      case '--package':
        options.packageFormat = _packageFormatOf(nextValue());
      case '--no-package':
        options.packageFormat = PackageFormat.none;
      case '--yes':
        options.skipConfirm = true;
      case '--open-folder':
        options.openFolder = true;
      case '--no-open-folder':
        options.openFolder = false;
      case '--no-build':
      case '--version-only':
        options.skipBuild = true;
      case '--help':
      case '-h':
        stdout.writeln(
          '用法：dart tool/build_release.dart [选项]\n'
          '  --version <大.小.热修>   版本号，如 0.0.2\n'
          '  --channel <release|alpha|beta>  发布类型（也认首字母 r/a/b）\n'
          '  --bump / --no-bump       本次是否计入 build number\n'
          '  --platform <windows|android|both>  也认首字母 w/a/b\n'
          '  --package <zip|none>     构建完打包（也认首字母 z/n）\n'
          '  --yes                    不再确认（也不问打包与产物文件夹）\n'
          '  --open-folder            构建完直接打开产物文件夹\n'
          '  --no-open-folder         构建完不打开、也不问\n'
          '  --no-build / --version-only  只写版本信息，不构建\n'
          '\n交互提问里：选项可填 序号 / 首字母 / 名称，回车用默认值',
        );
        return null;
      default:
        throw ArgumentError('未知参数：$arg');
    }
  }
  return options;
}

ReleaseChannel _channelOf(String value) {
  final channel = _matchEnum(ReleaseChannel.values, value);
  if (channel == null) {
    throw ArgumentError('发布类型只能是 release / alpha / beta，收到：$value');
  }
  return channel;
}

BuildPlatform _platformOf(String value) {
  final platform = _matchEnum(BuildPlatform.values, value);
  if (platform == null) {
    throw ArgumentError('构建平台只能是 windows / android / both，收到：$value');
  }
  return platform;
}

PackageFormat _packageFormatOf(String value) {
  final format = _matchEnum(PackageFormat.values, value);
  if (format == null) {
    throw ArgumentError('打包方式只能是 zip / none，收到：$value');
  }
  return format;
}

/// 按 名称 / 唯一前缀（含首字母）匹配枚举值；匹配不到或有歧义返回 null
T? _matchEnum<T extends Enum>(List<T> values, String input) {
  final lower = input.toLowerCase();
  for (final value in values) {
    if (value.name.toLowerCase() == lower) return value;
  }
  final matches = [
    for (final value in values)
      if (value.name.toLowerCase().startsWith(lower)) value,
  ];
  return matches.length == 1 ? matches.first : null;
}

// ---------------------------------------------------------------------------
// 交互提问
// ---------------------------------------------------------------------------

String _askVersionName(String defaultVersion) {
  while (true) {
    final input = _ask('版本号（大版本号.小版本号.热修改号）', defaultVersion);
    if (RegExp(r'^\d+\.\d+\.\d+$').hasMatch(input)) return input;
    stdout.writeln('格式不对，应形如 0.0.2');
  }
}

ReleaseChannel _askChannel() => _askChoice(
  question: '发布类型',
  values: ReleaseChannel.values,
  defaultValue: ReleaseChannel.release,
  labelOf: (channel) => channel.label,
);

bool _askCountBuildNumber() => _askYesNo('本次是否计入 build number（不计入则沿用上次）');

BuildPlatform _askPlatform() => _askChoice(
  question: '构建平台',
  values: BuildPlatform.values,
  defaultValue: _loadPlatform() ?? BuildPlatform.windows,
  labelOf: (platform) => platform.label,
);

/// 选项提问：序号（1 起）/ 首字母 / 名称 都能选，回车取默认项
T _askChoice<T extends Enum>({
  required String question,
  required List<T> values,
  required T defaultValue,
  required String Function(T value) labelOf,
}) {
  final optionLine = [
    for (var index = 0; index < values.length; index++)
      '${index + 1}) ${labelOf(values[index])}(${values[index].name})',
  ].join('  ');

  while (true) {
    final input = _ask(question, defaultValue.name, options: optionLine);

    final index = int.tryParse(input);
    if (index != null && index >= 1 && index <= values.length) {
      return values[index - 1];
    }

    // 中文名（如「内测」）也认
    for (final value in values) {
      if (labelOf(value).toLowerCase() == input) return value;
    }

    final matched = _matchEnum(values, input);
    if (matched != null) return matched;

    stdout.writeln(
      '填序号或首字母都行，可选：${values.map((it) => it.name).join(' / ')}',
    );
  }
}

/// 提问并回车取默认值；给了 [options] 就先打印一行选项说明
String _ask(String question, String defaultValue, {String? options}) {
  if (options == null) {
    stdout.write('$question [$defaultValue]: ');
  } else {
    stdout.writeln('$question：$options');
    stdout.write('选择 [$defaultValue]: ');
  }
  final input = stdin.readLineSync()?.trim();
  if (input == null || input.isEmpty) return defaultValue;
  return input;
}

/// 是否提问：Y/y/yes/1/是 为真，n/no/0/否 为假，其它重问
bool _askYesNo(String question) {
  while (true) {
    final input = _ask('$question（Y/n）', 'Y').toLowerCase();
    if (const ['y', 'yes', '1', '是', 'true'].contains(input)) return true;
    if (const ['n', 'no', '0', '否', 'false'].contains(input)) return false;
    stdout.writeln('填 Y 或 n（也可以 1 / 0）');
  }
}

// ---------------------------------------------------------------------------
// 构建产物与文件管理器
// ---------------------------------------------------------------------------

/// 各平台的产物目录；老版本 Flutter 的 windows 输出路径不同，取第一个存在的
List<Directory> _outputFolders(BuildPlatform platform) {
  return [
    if (platform != BuildPlatform.android) ?_windowsReleaseFolder(),
    if (platform != BuildPlatform.windows) ?_androidOutputFolder(),
  ];
}

/// Windows 产物目录（老版本 Flutter 是 build/windows/runner/Release）
Directory? _windowsReleaseFolder() => _firstExistingFolder([
  'build/windows/x64/runner/Release',
  'build/windows/runner/Release',
]);

/// Android 产物目录
Directory? _androidOutputFolder() => _firstExistingFolder([
  'build/app/outputs/flutter-apk',
  'build/app/outputs/apk/release',
]);

Directory? _firstExistingFolder(List<String> candidates) {
  for (final candidate in candidates) {
    final folder = Directory(candidate);
    if (folder.existsSync()) return folder;
  }
  return null;
}

/// 构建后按需打包；返回压缩包文件，没打包返回 null
///
/// --yes 免交互时不主动打包，只认 --package
Future<File?> _packageIfNeeded({
  required BuildOptions options,
  required String versionName,
  required ReleaseChannel channel,
  required int buildNumber,
}) async {
  final packageFormat =
      options.packageFormat ??
      (options.skipConfirm
          ? PackageFormat.none
          : _askChoice(
              question: '是否打包',
              values: PackageFormat.values,
              defaultValue: PackageFormat.none,
              labelOf: (format) => format.label,
            ));
  if (packageFormat == PackageFormat.none) return null;

  final sourceFolder = _windowsReleaseFolder();
  if (sourceFolder == null) {
    stderr.writeln('没找到 Windows 产物目录，跳过打包');
    return null;
  }

  final fileName = _archiveFileName(
    versionName: versionName,
    channel: channel,
    buildNumber: buildNumber,
    sourceFolder: sourceFolder,
  );
  final zipPath = '${_normalizePath(Directory('build/dist').absolute.path)}'
      '${Platform.pathSeparator}$fileName';

  stdout.writeln('\n正在打包 ${_normalizePath(sourceFolder.path)} → $fileName');
  final archive = await _zipFolder(sourceFolder, zipPath);
  stdout.writeln('打包产物：${_normalizePath(archive.path)}');
  return archive;
}

/// 压缩包名：copper-launcher-v0.0.2-alpha2-windows-x64.zip
String _archiveFileName({
  required String versionName,
  required ReleaseChannel channel,
  required int buildNumber,
  required Directory sourceFolder,
}) {
  final channelPart = channel.suffix.isEmpty
      ? ''
      : '-${channel.suffix}$buildNumber';
  final platformPart = sourceFolder.path.contains('x64')
      ? 'windows-x64'
      : 'windows';
  return 'copper-launcher-v$versionName$channelPart-$platformPart.zip';
}

/// 把目录压成 zip（包内直接是目录内容，解压即用）
Future<File> _zipFolder(Directory sourceFolder, String zipPath) async {
  final zipFile = File(zipPath);
  await zipFile.parent.create(recursive: true);
  if (await zipFile.exists()) await zipFile.delete();

  final encoder = ZipFileEncoder();
  await encoder.zipDirectory(sourceFolder, filename: zipPath);
  return zipFile;
}

/// 用系统文件管理器打开目录
///
/// 路径必须先按平台分隔符规范化：脚本里写的候选路径用 `/`，
/// 而 `Directory.absolute` 不会转换分隔符，带正斜杠的路径喂给 explorer 打不开
Future<void> _openFolder(String path) async {
  final absolutePath = _normalizePath(Directory(path).absolute.path);
  final command = Platform.isWindows
      ? 'explorer'
      : Platform.isMacOS
      ? 'open'
      : 'xdg-open';
  try {
    await Process.start(
      command,
      [absolutePath],
      mode: ProcessStartMode.detached,
    );
  } catch (error) {
    stderr.writeln('打开文件夹失败（$absolutePath）：$error');
  }
}

/// 统一成当前平台的分隔符（Windows 下 `/` → `\`）
String _normalizePath(String path) =>
    Platform.isWindows ? path.replaceAll('/', r'\') : path;

// ---------------------------------------------------------------------------
// 版本信息读写
// ---------------------------------------------------------------------------

CurrentVersion _readCurrentVersion() {
  final content = File(appConstantPath).readAsStringSync();
  final block = _versionBlockOf(content);
  final displayVersion = _matchValue(block, 'appVersion');
  final buildNumber = int.tryParse(_matchValue(block, 'appBuildNumber'));

  // 显示版本形如 v0.0.2 alpha 12：取第一段当纯版本号
  final versionName = displayVersion.replaceFirst('v', '').split(' ').first;
  return CurrentVersion(
    versionName: versionName,
    buildNumber: buildNumber ?? 0,
    buildTime: _matchValue(block, 'appBuildTime'),
  );
}

String _versionBlockOf(String content) {
  final start = content.indexOf(versionBlockStart);
  final end = content.indexOf(versionBlockEnd);
  if (start == -1 || end == -1) {
    throw StateError('$appConstantPath 里找不到版本信息块，请检查标记是否被改动');
  }
  return content.substring(start, end);
}

String _matchValue(String block, String name) {
  final match = RegExp("const $name = '?([^';]+)'?;").firstMatch(block);
  if (match == null) throw StateError('版本信息块里没有 $name');
  return match.group(1)!;
}

void _writeVersionBlock({
  required String displayVersion,
  required int buildNumber,
  required String buildTime,
}) {
  final file = File(appConstantPath);
  final content = file.readAsStringSync();
  final start = content.indexOf(versionBlockStart);
  final end = content.indexOf(versionBlockEnd);
  if (start == -1 || end == -1) {
    throw StateError('$appConstantPath 里找不到版本信息块，请检查标记是否被改动');
  }

  // 跟文件已有的换行风格保持一致，别把整份文件的行尾改掉
  final lineEnding = _lineEndingOf(content);
  final block = [
    versionBlockStart,
    '///UI 显示的版本号，形如 v0.0.2 / v0.0.2 alpha 12 / v0.0.2 beta 7',
    "const appVersion = '$displayVersion';",
    '',
    '///本次构建的 build number，同一版本重复构建时可选择不计入',
    'const appBuildNumber = $buildNumber;',
    '',
    '///本次构建时间',
    "const appBuildTime = '$buildTime';",
    versionBlockEnd,
  ].join(lineEnding);

  final updated = content.replaceRange(
    start,
    end + versionBlockEnd.length,
    block,
  );
  file.writeAsStringSync(updated, flush: true);
}

void _writePubspecVersion(String version) {
  final file = File(pubspecPath);
  final content = file.readAsStringSync();
  // 用 [^\r\n] 而不是 .* ：`.` 会连行尾的 \r 一起吃掉，CRLF 文件就被改成 LF 了
  final pattern = RegExp(r'^version:[^\r\n]*', multiLine: true);
  if (!pattern.hasMatch(content)) {
    throw StateError('$pubspecPath 里找不到 version 段');
  }
  file.writeAsStringSync(
    content.replaceFirst(pattern, 'version: $version'),
    flush: true,
  );
}

/// 文件用的是 CRLF 还是 LF
String _lineEndingOf(String content) =>
    content.contains('\r\n') ? '\r\n' : '\n';

// ---------------------------------------------------------------------------
// 时间格式与本地状态
// ---------------------------------------------------------------------------

/// UI 显示用：2026-09-10 18:30
String _formatBuildTime(DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)}';
}

/// pubspec 的 + 段：YYMMDD（Android versionCode 直接用它，位数不能太长）
String _formatPubspecBuildTime(DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(now.year % 100)}${two(now.month)}${two(now.day)}';
}

BuildPlatform? _loadPlatform() {
  final file = File(statePath);
  if (!file.existsSync()) return null;
  try {
    final state = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final name = state['platform'] as String?;
    return _platformOf(name ?? '');
  } catch (_) {
    return null;
  }
}

void _savePlatform(BuildPlatform platform) {
  File(statePath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'platform': platform.name}),
    flush: true,
  );
}
