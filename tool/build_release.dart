// 一键构建版本脚本
//
// 做三件事：
//   1. 交互式收集本次构建信息（版本号 / 发布类型 / 是否计入 build number / 构建目标）
//   2. 写入 lib/core/app_constant.dart 的版本信息块与 pubspec.yaml 的 version
//   3. 调 flutter build <目标> --release
//
// 用法：
//   dart tool/build_release.dart                 // 全交互（回车用默认值）
//   dart tool/build_release.dart --no-build      // 只写版本信息，不构建
//   dart tool/build_release.dart --version 0.2.0 --channel alpha --bump --platform windows,android --yes
//
// 版本号与通道（详见 .project_status/architecture.md 的「版本号与发布通道」）：
//   - 版本号 `X.Y.Z`：`Y` 加功能 / 破坏性变更，`Z` 只在**正式版已发布之后**的修复才动
//   - 预发布带**通道序号**（`alpha1`…`alphaN`），每通道、每版本各自从 1 开始
//   - `appBuildNumber` 是**全局构建号**，只增不减（Android versionCode 用它），与通道序号无关
//   - tag / 显示版本 / 产物名同源：`v0.2.0-alpha1` / `v0.2.0 alpha 1` / `copper-launcher-v0.2.0-alpha1-windows-x64.zip`
//
// 构建目标可多选（windows / android / linux / macos），但桌面目标只能在对应宿主上
// 构建——选了不匹配的目标会跳过并提示，不会中止其它目标的构建
//
// 放 tool/ 下是有原因的：Dart-Code 只认 bin / tool / .dart_tool 为「Dart 程序」，
// 放别处（如 .script/）在 Flutter 项目里会被当 Flutter 会话跑，而 Flutter 会话
// 不支持 console: terminal → stdin 读不到，交互提问会卡住
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:copper_launcher/util/version_strings.dart';
import 'package:path/path.dart' as p;

/// 版本信息写在这个文件的标记块里
const appConstantPath = 'lib/core/app_constant.dart';

/// pubspec 的 version 段 = 版本号（预发布带通道与序号）+ 全局构建号
const pubspecPath = 'pubspec.yaml';

/// 记住上次选的构建目标（本地状态，不入库）
const statePath = 'tool/build_release_state.json';

/// 更新引导脚本：仓库里的模板，以及它进包后的文件名
///
/// 打包时放进产物目录（exe 旁边），更新时由启动器覆盖完新文件后调用，
/// 用来处理光靠覆盖不行的破坏性变更；契约写在模板头部
const updateScriptTemplatePath = 'tool/update_script.cmd';
const updateScriptName = 'update.cmd';

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

/// 构建目标
///
/// 桌面目标只能在对应宿主上构建（Flutter 不支持交叉构建），[requiredHost] 为 null
/// 表示任意宿主都能构建；一次可以选多个目标
enum BuildTarget {
  windows('Windows', 'windows', 'windows'),
  android('Android', 'apk', null),
  linux('Linux', 'linux', 'linux'),
  macos('macOS', 'macos', 'macos');

  const BuildTarget(this.label, this.flutterTarget, this.requiredHost);

  final String label;

  /// `flutter build` 的目标名
  final String flutterTarget;

  /// 必须在这个宿主上构建；null = 任意宿主
  final String? requiredHost;

  /// 该目标支持的打包方式（不含「不打包」），apk 本身就是产物、无需再打包
  List<PackageFormat> get packageFormats => switch (this) {
    BuildTarget.windows => const [
      PackageFormat.zip,
      PackageFormat.setup,
      PackageFormat.both,
    ],
    BuildTarget.linux => const [PackageFormat.tarball],
    BuildTarget.macos => const [PackageFormat.dmg],
    BuildTarget.android => const [],
  };

  /// 该目标额外的构建参数
  ///
  /// android 拆 ABI：不拆的话 Flutter 默认吐 universal（fat）APK，v7a + arm64 +
  /// x86_64 三个 ABI 打一起约 70MB；拆完每个 ABI 一个包，用户按机型装
  List<String> get extraBuildArgs => switch (this) {
    BuildTarget.android => const ['--split-per-abi'],
    BuildTarget.windows || BuildTarget.linux || BuildTarget.macos => const [],
  };
}

/// 当前宿主系统，叫法与 [BuildTarget.requiredHost] 一致
String get _currentHost => Platform.isWindows
    ? 'windows'
    : Platform.isMacOS
    ? 'macos'
    : Platform.isLinux
    ? 'linux'
    : Platform.operatingSystem;

/// 构建模式
enum BuildMode {
  release('正式', 'release', 'Release'),
  debug('调试', 'debug', 'Debug'),
  profile('性能分析', 'profile', 'Profile');

  const BuildMode(this.label, this.flutterMode, this.outputFolderName);

  final String label;

  /// 传给 `flutter build --<mode>` 的值
  final String flutterMode;

  /// Windows 产物目录名（build/windows/x64/runner/<名字>）
  final String outputFolderName;
}

/// 构建完的打包方式；可选范围由已构建的目标决定（见 [BuildTarget.packageFormats]）
enum PackageFormat {
  none('不打包'),
  zip('Zip（解压即用）'),
  setup('Setup（安装包）'),
  both('Zip + Setup'),
  tarball('tar.gz（解压即用）'),
  dmg('dmg（磁盘映像）');

  const PackageFormat(this.label);

  final String label;
}

/// 命令行参数（不传的部分才会提问）
class BuildOptions {
  String? versionName;
  ReleaseChannel? channel;

  /// 通道序号（预发布用）；不传则按「同版本同通道上次 +1」推荐
  int? channelSeq;
  bool? countBuildNumber;
  List<BuildTarget>? targets;
  BuildMode? mode;
  PackageFormat? packageFormat;
  bool skipBuild = false;
  bool skipConfirm = false;

  /// 构建前跑 flutter analyze + test 当门禁
  bool runChecks = false;

  /// 构建完是否打开产物文件夹；null = 交互模式提问 / --yes 模式不问也不开
  bool? openFolder;
}

/// 当前版本信息（从 app_constant.dart 读出来）
class CurrentVersion {
  const CurrentVersion({
    required this.versionName,
    required this.buildNumber,
    required this.buildTime,
    required this.displayVersion,
  });

  final String versionName;

  /// 全局构建号：只增不减（Android 拿它当 versionCode），与通道序号不是一回事
  final int buildNumber;

  final String buildTime;

  /// 显示版本原文（`v0.2.0 alpha 6`），用来算下一个通道序号
  final String displayVersion;
}

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) return; // --help

  final mode =
      options.mode ??
      _askChoice(
        question: '构建模式',
        values: BuildMode.values,
        defaultValue: BuildMode.release,
        labelOf: (mode) => mode.label,
      );
  final targets = options.targets ?? _askTargets();

  // 调试构建只是拿个能跑的包，不改版本号、不打包
  if (mode == BuildMode.debug) {
    return _runBuildOnly(options: options, mode: mode, targets: targets);
  }

  final current = _readCurrentVersion();
  stdout.writeln(
    '\n当前版本：v${current.versionName}（build ${current.buildNumber}，${current.buildTime}）',
  );

  final versionName = options.versionName ?? _askVersionName(current.versionName);
  final channel = options.channel ?? _askChannel();
  final countBuildNumber = options.countBuildNumber ?? _askCountBuildNumber();

  // 通道序号（`alpha` / `beta` 后面那个数字）：每通道、每版本各自从 1 开始，
  // 与全局构建号分开算 —— 后者只增不减（Android 的 versionCode 用它）
  final channelSuffix = channel.suffix.isEmpty ? null : channel.suffix;
  int? channelSeq;
  if (channelSuffix != null) {
    final suggestedSeq = nextChannelSeq(
      currentDisplayVersion: current.displayVersion,
      version: versionName,
      channel: channelSuffix,
    );
    // 免交互（--yes）时不能提问，直接用推荐值
    channelSeq =
        options.channelSeq ??
        (options.skipConfirm ? suggestedSeq : _askChannelSeq(suggestedSeq));
  }

  // 只改版本号（不构建）：--no-build / --version-only 跳过提问，交互模式下问一步
  final shouldBuild = options.skipBuild
      ? false
      : (options.skipConfirm ||
            _askYesNo('是否执行构建？（选 n 只写版本信息）'));

  final buildNumber = countBuildNumber
      ? current.buildNumber + 1
      : current.buildNumber;
  final buildTime = _formatBuildTime(DateTime.now());
  final release = ReleaseVersion(
    version: versionName,
    channel: channelSuffix,
    seq: channelSeq,
  );

  stdout.writeln('\n将要写入：');
  stdout.writeln('  appVersion      = ${release.display}');
  stdout.writeln('  appBuildNumber  = $buildNumber');
  stdout.writeln('  appBuildTime    = $buildTime');
  stdout.writeln('  pubspec version = ${release.semver}+$buildNumber');
  stdout.writeln('  release tag     = ${release.tag}');
  stdout.writeln(
    '  构建            = ${shouldBuild ? '${targets.map((target) => target.label).join(' + ')} · ${mode.label}' : '否（只写版本信息）'}',
  );

  if (!options.skipConfirm && !_askYesNo('\n确认执行？')) {
    stdout.writeln('已取消');
    return;
  }

  _writeVersionBlock(
    displayVersion: release.display,
    buildNumber: buildNumber,
    buildTime: buildTime,
  );
  _writePubspecVersion('${release.semver}+$buildNumber');
  _saveTargets(targets);
  stdout.writeln('\n版本信息已写入 $appConstantPath / $pubspecPath');

  if (!shouldBuild) return;

  if (!await _runChecks(options)) return;
  final builtTargets = await _buildTargets(targets, mode);
  if (builtTargets == null) return;
  stdout.writeln('\n构建完成');

  final outputFolders = _outputFolders(builtTargets, mode);
  for (final folder in outputFolders) {
    stdout.writeln('产物目录：${_normalizePath(folder.path)}');
  }

  final distFolder = await _packageIfNeeded(
    options: options,
    mode: mode,
    release: release,
    builtTargets: builtTargets,
  );

  // apk 本身就是产物、没有打包环节，但拆 ABI 后是多个 `app-<abi>-release.apk`，
  // 收进 build/dist 并统一命名，免得几个同风格的 app-*.apk 混在构建目录里
  final apkFolder = builtTargets.contains(BuildTarget.android)
      ? await _collectAndroidApks(mode: mode, release: release)
      : null;

  await _openFoldersIfWanted(
    options: options,
    folders: [...outputFolders, ?distFolder, ?apkFolder],
  );
}

/// 调试构建：不改版本信息，构建完只提供打开产物目录
Future<void> _runBuildOnly({
  required BuildOptions options,
  required BuildMode mode,
  required List<BuildTarget> targets,
}) async {
  if (!await _runChecks(options)) return;
  final builtTargets = await _buildTargets(targets, mode);
  if (builtTargets == null) return;
  stdout.writeln('\n构建完成（${mode.label}，未改动版本信息）');

  final outputFolders = _outputFolders(builtTargets, mode);
  for (final folder in outputFolders) {
    stdout.writeln('产物目录：${_normalizePath(folder.path)}');
  }
  await _openFoldersIfWanted(options: options, folders: outputFolders);
}

/// 构建前的可选质量门禁（analyze + test），不过就中止
Future<bool> _runChecks(BuildOptions options) async {
  if (!options.runChecks) return true;

  for (final task in ['analyze', 'test']) {
    stdout.writeln('\n> flutter $task');
    final exitCode = await _runFlutter([task]);
    if (exitCode != 0) {
      stderr.writeln('flutter $task 未通过（退出码 $exitCode），中止构建');
      return false;
    }
  }
  return true;
}

/// 逐个目标构建，返回实际构建成功的目标
///
/// 目标要求的宿主与当前宿主不一致时跳过并提示（Flutter 不支持交叉构建）；
/// 构建失败或一个目标都没构建成时返回 null
Future<List<BuildTarget>?> _buildTargets(
  List<BuildTarget> targets,
  BuildMode mode,
) async {
  final host = _currentHost;
  final builtTargets = <BuildTarget>[];

  for (final target in targets) {
    final requiredHost = target.requiredHost;
    if (requiredHost != null && requiredHost != host) {
      stdout.writeln('\n跳过 ${target.label}：只能在 $requiredHost 上构建（当前 $host）');
      continue;
    }

    final buildArguments = [
      'build',
      target.flutterTarget,
      '--${mode.flutterMode}',
      ...target.extraBuildArgs,
    ];
    stdout.writeln('\n> flutter ${buildArguments.join(' ')}');
    final exitCode = await _runFlutter(buildArguments);
    if (exitCode != 0) {
      stderr.writeln('flutter build ${target.flutterTarget} 失败（退出码 $exitCode）');
      return null;
    }
    builtTargets.add(target);
  }

  if (builtTargets.isEmpty) {
    stderr.writeln('\n所选目标都要在对应宿主上构建，当前 $host 一个都跑不了，中止构建');
    return null;
  }
  return builtTargets;
}

Future<int> _runFlutter(List<String> arguments) async {
  final process = await Process.start(
    'flutter',
    arguments,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  return process.exitCode;
}

/// 按需打开产物目录；--yes 免交互时不主动弹文件管理器，只认 --open-folder
Future<void> _openFoldersIfWanted({
  required BuildOptions options,
  required List<Directory> folders,
}) async {
  if (folders.isEmpty) return;

  final shouldOpenFolder =
      options.openFolder ??
      (!options.skipConfirm && _askYesNo('打开产物文件夹？'));
  if (!shouldOpenFolder) return;
  for (final folder in folders) {
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
      case '--seq':
        options.channelSeq = _positiveIntOf(nextValue(), '--seq');
      case '--bump':
        options.countBuildNumber = true;
      case '--no-bump':
        options.countBuildNumber = false;
      case '--platform':
        options.targets = _targetsOf(nextValue());
      case '--mode':
        options.mode = _modeOf(nextValue());
      case '--check':
        options.runChecks = true;
      case '--no-check':
        options.runChecks = false;
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
          '  --version <大.小.热修>   版本号，如 0.2.0\n'
          '  --channel <release|alpha|beta>  发布类型（也认首字母 r/a/b）\n'
          '  --seq <N>                通道序号（预发布用，如 alpha6 的 6）；\n'
          '                            不传则按「同版本同通道上次 +1」推荐，可交互确认\n'
          '  --bump / --no-bump       本次是否计入 build number（全局递增，Android versionCode 用它）\n'
          '  --platform <windows,android,linux,macos>  构建目标，可多选、逗号分隔（也认首字母 w/a/l/m）\n'
          '                            交互提问只会列出当前宿主能构建的目标；桌面目标选了不匹配的会跳过\n'
          '  --mode <release|debug|profile>  构建模式（也认首字母 r/d/p）\n'
          '  --check / --no-check     构建前跑 flutter analyze + test\n'
          '  --package <zip|setup|both|tarball|dmg|none>  构建完打包（也认首字母）\n'
          '                            Windows 出 zip / Setup，Linux 出 tar.gz，macOS 出 dmg\n'
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

/// 取一个正整数参数（通道序号这类）
int _positiveIntOf(String value, String arg) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw ArgumentError('$arg 需要正整数，收到：$value');
  }
  return parsed;
}

/// 解析逗号分隔的构建目标列表，可填名称或首字母
List<BuildTarget> _targetsOf(String value) {
  final targets = <BuildTarget>[];
  for (final part in value.split(RegExp(r'[,\s]+'))) {
    if (part.isEmpty) continue;
    final target = _matchEnum(BuildTarget.values, part);
    if (target == null) {
      throw ArgumentError('构建目标只能是 windows / android / linux / macos，收到：$part');
    }
    if (!targets.contains(target)) targets.add(target);
  }
  if (targets.isEmpty) throw ArgumentError('--platform 至少要给一个目标');
  return targets;
}

PackageFormat _packageFormatOf(String value) {
  final format = _matchEnum(PackageFormat.values, value);
  if (format == null) {
    throw ArgumentError(
      '打包方式只能是 none / zip / setup / both / tarball / dmg，收到：$value',
    );
  }
  return format;
}

BuildMode _modeOf(String value) {
  final mode = _matchEnum(BuildMode.values, value);
  if (mode == null) {
    throw ArgumentError('构建模式只能是 release / debug / profile，收到：$value');
  }
  return mode;
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

/// 通道序号：同一个版本号、同一个通道里的第几次（`alpha1`…`alphaN`，换了版本号或通道重新从 1 起）
///
/// 与全局 build number 是两回事：那个只增不减（Android versionCode 用它）
int _askChannelSeq(int defaultSeq) {
  while (true) {
    final input = _ask('通道序号（该版本该通道的第几次）', '$defaultSeq');
    final seq = int.tryParse(input);
    if (seq != null && seq > 0) return seq;
    stdout.writeln('应为正整数，形如 1');
  }
}

/// 构建目标多选：只列出当前宿主能构建的目标，逗号或空格分隔，可填序号 / 名称 / 首字母
List<BuildTarget> _askTargets() {
  final buildableTargets = _buildableTargets;
  final defaultTargets = _defaultTargets(buildableTargets);
  final defaultText = defaultTargets.map((target) => target.name).join(',');
  final optionLine = [
    for (var index = 0; index < buildableTargets.length; index++)
      '${index + 1}) ${buildableTargets[index].label}(${buildableTargets[index].name})',
  ].join('  ');
  final buildableText = buildableTargets.map((target) => target.label).join(' / ');

  stdout.writeln('检测到宿主：$_currentHost，可构建目标：$buildableText');
  while (true) {
    final input = _ask('构建目标（可多选，逗号分隔）', defaultText, options: optionLine);
    final targets = _parseTargetInput(input, buildableTargets);
    if (targets.isNotEmpty) return targets;
    stdout.writeln('至少选一个，可选：$buildableText');
  }
}

/// 当前宿主能构建的目标，宿主自身的桌面目标排最前
///
/// apk 不需要宿主匹配，桌面目标只能在对应宿主上构建（Flutter 不支持交叉构建）
List<BuildTarget> get _buildableTargets {
  final buildable = [
    for (final target in BuildTarget.values)
      if (target.requiredHost == null || target.requiredHost == _currentHost)
        target,
  ];
  final hostTargets = [
    for (final target in buildable)
      if (target.requiredHost == _currentHost) target,
  ];
  return [
    ...hostTargets,
    for (final target in buildable)
      if (!hostTargets.contains(target)) target,
  ];
}

/// 默认目标：优先沿用上次选过的（先滤掉本机构建不了的），没有可沿用的就用宿主桌面目标
List<BuildTarget> _defaultTargets(List<BuildTarget> buildableTargets) {
  final savedTargets = [
    for (final target in _loadTargets() ?? const <BuildTarget>[])
      if (buildableTargets.contains(target)) target,
  ];
  return savedTargets.isNotEmpty ? savedTargets : [buildableTargets.first];
}

/// 解析多选输入：序号（1 起，对应列出的可选项）/ 名称 / 首字母，逗号或空格分隔
List<BuildTarget> _parseTargetInput(
  String input,
  List<BuildTarget> buildableTargets,
) {
  final targets = <BuildTarget>[];
  for (final part in input.split(RegExp(r'[,\s]+'))) {
    if (part.isEmpty) continue;
    final target = _targetOfToken(part, buildableTargets);
    if (target != null && !targets.contains(target)) targets.add(target);
  }
  return targets;
}

/// 单个目标输入：先按序号（1 起，对应可选项列表）解析，不是序号再按名称 / 首字母匹配
BuildTarget? _targetOfToken(String token, List<BuildTarget> buildableTargets) {
  final index = int.tryParse(token);
  if (index == null) return _matchEnum(buildableTargets, token);
  if (index < 1 || index > buildableTargets.length) return null;
  return buildableTargets[index - 1];
}

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

  final String? line;
  try {
    line = stdin.readLineSync()?.trim();
  } on StdinException {
    // 没有可用终端（stdin 被重定向 / 无效句柄）：取默认值，别直接崩
    stdout.writeln('（读不到输入，取默认值 $defaultValue）');
    return defaultValue;
  }
  if (line == null || line.isEmpty) return defaultValue;
  return line;
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

/// 各目标的产物目录；老版本 Flutter 的输出路径不同，取第一个存在的
List<Directory> _outputFolders(List<BuildTarget> targets, BuildMode mode) => [
  for (final target in targets) ?_outputFolderOf(target, mode),
];

Directory? _outputFolderOf(BuildTarget target, BuildMode mode) => switch (target) {
  // 老版本 Flutter 是 build/windows/runner/<模式>
  BuildTarget.windows => _firstExistingFolder([
    'build/windows/x64/runner/${mode.outputFolderName}',
    'build/windows/runner/${mode.outputFolderName}',
  ]),
  BuildTarget.android => _firstExistingFolder([
    'build/app/outputs/flutter-apk',
    'build/app/outputs/apk/release',
  ]),
  // Linux 的产物名不带模式大写，目录是 build/linux/<架构>/<小写模式>/bundle
  BuildTarget.linux => _firstExistingFolder([
    'build/linux/x64/${mode.flutterMode}/bundle',
    'build/linux/${mode.flutterMode}/bundle',
  ]),
  BuildTarget.macos => _firstExistingFolder([
    'build/macos/Build/Products/${mode.outputFolderName}',
  ]),
};

Directory? _firstExistingFolder(List<String> candidates) {
  for (final candidate in candidates) {
    final folder = Directory(candidate);
    if (folder.existsSync()) return folder;
  }
  return null;
}

/// 构建后按需打包；返回产物所在目录，没打包返回 null
///
/// 打包方式随已构建的目标而定：Windows 沿用 zip / Setup 提问，
/// Linux / macOS 各自固定为 tar.gz / dmg、不额外提问；
/// --yes 免交互时不主动打包，只认 --package
Future<Directory?> _packageIfNeeded({
  required BuildOptions options,
  required BuildMode mode,
  required ReleaseVersion release,
  required List<BuildTarget> builtTargets,
}) async {
  // apk 本身就是产物，一个可打包的桌面目标都没有就直接结束
  final packagableTargets = [
    for (final target in builtTargets)
      if (target.packageFormats.isNotEmpty) target,
  ];
  if (packagableTargets.isEmpty) return null;

  final packageFormat = _resolvePackageFormat(
    options: options,
    packagableTargets: packagableTargets,
  );
  if (packageFormat == PackageFormat.none) return null;

  final distFolder = Directory('build/dist');
  for (final target in packagableTargets) {
    final sourceFolder = _outputFolderOf(target, mode);
    if (sourceFolder == null) {
      stderr.writeln('没找到 ${target.label} 产物目录，跳过打包');
      continue;
    }
    await _packageTarget(
      target: target,
      packageFormat: packageFormat,
      sourceFolder: sourceFolder,
      distFolder: distFolder,
      baseName: _packageBaseName(
        release: release,
        target: target,
        sourceFolder: sourceFolder,
      ),
      // 安装包版本写进卸载键的 DisplayVersion（tag 形态，不带 v）：更新时
      // 安装器会把它当「来源版本」传给引导脚本，所以必须与 release tag 同源
      appVersion: release.semver,
    );
  }
  return distFolder;
}

/// 收集 Android 产物：`--split-per-abi` 后产物是多个 `app-<abi>-release.apk`，
/// 统一改名成 `copper-launcher-v<版本><渠道>-android-<abi>.apk` 收进 build/dist
///
/// 拆 ABI 前（或指定了别的 target-platform）是单个 universal 包，名字里不带 ABI 段；
/// apk 不走打包环节，这里只做「归拢 + 改名」，原文件留在构建目录里不动
Future<Directory?> _collectAndroidApks({
  required BuildMode mode,
  required ReleaseVersion release,
}) async {
  final sourceFolder = _outputFolderOf(BuildTarget.android, mode);
  if (sourceFolder == null) {
    stderr.writeln('没找到 Android 产物目录，跳过 APK 收集');
    return null;
  }

  final apks = [
    for (final entity in sourceFolder.listSync())
      if (entity is File && entity.path.toLowerCase().endsWith('.apk')) entity,
  ];
  if (apks.isEmpty) {
    stderr.writeln('${_normalizePath(sourceFolder.path)} 里没有 apk，跳过收集');
    return null;
  }

  // 拆 ABI 的构建不会产出 universal 包：构建目录里同时有 `app-release.apk` 时，
  // 那是上一次没拆 ABI 的残留（`flutter build` 不清目录），收进来会被当成本次产物
  final splitApks = [
    for (final apk in apks)
      if (_abiPartOfApk(apk).isNotEmpty) apk,
  ];
  final universalApks = [
    for (final apk in apks)
      if (_abiPartOfApk(apk).isEmpty) apk,
  ];
  if (splitApks.isNotEmpty) {
    for (final stale in universalApks) {
      stdout.writeln(
        '  跳过构建目录里的 universal 包（拆 ABI 构建不会产出它，应是旧构建残留）：'
        '${_normalizePath(stale.path)}',
      );
    }
  }
  final collectedApks = splitApks.isNotEmpty ? splitApks : universalApks;

  final baseName = _packageBaseName(
    release: release,
    target: BuildTarget.android,
    sourceFolder: sourceFolder,
  );
  final distFolder = Directory('build/dist');
  await distFolder.create(recursive: true);

  for (final apk in collectedApks) {
    final targetPath = p.join(
      distFolder.path,
      '$baseName${_abiPartOfApk(apk)}.apk',
    );
    final targetFile = File(targetPath);
    if (await targetFile.exists()) await targetFile.delete();
    await apk.copy(targetPath);
    stdout.writeln('APK 产物：${_normalizePath(targetPath)}');
  }
  return distFolder;
}

/// APK 文件名里的 ABI 段：`app-arm64-v8a-release.apk` → `-arm64-v8a`；
/// universal 包（`app-release.apk`）没有 ABI 段，返回空串
String _abiPartOfApk(File apk) {
  final name = p.basenameWithoutExtension(apk.path);
  final architecture = RegExp(r'^app-(.+)-release$').firstMatch(name)?.group(1);
  return architecture == null ? '' : '-$architecture';
}

/// 决定打包方式：可选项跟着已构建的桌面目标走
PackageFormat _resolvePackageFormat({
  required BuildOptions options,
  required List<BuildTarget> packagableTargets,
}) {
  final supportedFormats = [
    for (final target in packagableTargets) ...target.packageFormats,
  ];

  final requested = options.packageFormat;
  if (requested != null) {
    if (requested == PackageFormat.none || supportedFormats.contains(requested)) {
      return requested;
    }
    // 指定的方式在当前目标上用不上，退回该目标的固定格式
    stdout.writeln(
      '打包方式 ${requested.name} 不适用于本次构建，改用 ${supportedFormats.first.name}',
    );
    return supportedFormats.first;
  }

  if (options.skipConfirm) return PackageFormat.none;
  return _askChoice(
    question: '是否打包',
    values: [PackageFormat.none, ...supportedFormats],
    defaultValue: PackageFormat.none,
    labelOf: (format) => format.label,
  );
}

/// 把仓库里的引导脚本模板复制进产物目录（zip / Setup 都要带上它）
///
/// 统一写成 CRLF：cmd 对 LF-only 脚本里的标签 / 跳转处理有坑
Future<void> _copyUpdateScript(Directory sourceFolder) async {
  final template = File(updateScriptTemplatePath);
  if (!await template.exists()) {
    stderr.writeln(
      '没找到引导脚本模板 $updateScriptTemplatePath，本次产物不带 $updateScriptName',
    );
    return;
  }

  final content = (await template.readAsString())
      .replaceAll('\r\n', '\n')
      .replaceAll('\n', '\r\n');
  final target = File(p.join(sourceFolder.path, updateScriptName));
  await target.writeAsString(content, flush: true);
  stdout.writeln('\n已放入更新引导脚本：${_normalizePath(target.path)}');
}

/// 按目标打包：Windows 走 zip / Setup，Linux 走 tar.gz，macOS 走 dmg
Future<void> _packageTarget({
  required BuildTarget target,
  required PackageFormat packageFormat,
  required Directory sourceFolder,
  required Directory distFolder,
  required String baseName,
  required String appVersion,
}) async {
  switch (target) {
    case BuildTarget.windows:
      await _copyUpdateScript(sourceFolder);
      if (packageFormat == PackageFormat.zip ||
          packageFormat == PackageFormat.both) {
        await _packageZip(sourceFolder, distFolder, baseName);
      }
      if (packageFormat == PackageFormat.setup ||
          packageFormat == PackageFormat.both) {
        await _packageSetup(sourceFolder, distFolder, baseName, appVersion);
      }
    case BuildTarget.linux:
      await _packageTarball(sourceFolder, distFolder, baseName);
    case BuildTarget.macos:
      await _packageDmg(sourceFolder, distFolder, baseName);
    case BuildTarget.android:
      break; // 打包前已排除，这里只是为了穷尽分支
  }
}

/// 产物名（不含后缀）：copper-launcher-v0.2.0-alpha2-windows-x64
///
/// 直接由 release tag 拼出来 —— 产物名与 tag 同源，更新器按这个格式认版本
String _packageBaseName({
  required ReleaseVersion release,
  required BuildTarget target,
  required Directory sourceFolder,
}) =>
    'copper-launcher-${release.tag}-${_platformPartOf(target, sourceFolder)}';

/// 产物名的平台段：`build/linux/x64/...` 这类带架构的目录标出 x64
String _platformPartOf(BuildTarget target, Directory sourceFolder) {
  final architecturePart = sourceFolder.path.contains('x64') ? '-x64' : '';
  return switch (target) {
    BuildTarget.windows => 'windows$architecturePart',
    BuildTarget.android => 'android',
    BuildTarget.linux => 'linux$architecturePart',
    BuildTarget.macos => 'macos',
  };
}

/// 打包 Linux 产物为 tar.gz
///
/// 用系统 tar 而不是 Dart 的归档实现：tar 保留符号链接与可执行权限位，
/// 更贴近 Linux 产物的语义（Dart 归档会跟随符号链接、把内容展开）
Future<File?> _packageTarball(
  Directory sourceFolder,
  Directory distFolder,
  String baseName,
) async {
  final archiveFile = File(
    '${distFolder.path}${Platform.pathSeparator}$baseName.tar.gz',
  );
  await distFolder.create(recursive: true);
  if (await archiveFile.exists()) await archiveFile.delete();

  // tar 的顶层目录名跟着被归档目录的目录名走（这里是 bundle）；
  // 先把 bundle 改成发布名，打完包在 finally 里改回来（同盘改名，开销可忽略）
  final releaseFolder = sourceFolder.parent;
  final stagedFolder = Directory(
    '${releaseFolder.path}${Platform.pathSeparator}$baseName',
  );
  if (await stagedFolder.exists()) await stagedFolder.delete(recursive: true);
  await sourceFolder.rename(stagedFolder.path);

  stdout.writeln('\n正在打包 tar.gz：$baseName.tar.gz');
  try {
    final result = await Process.run('tar', [
      '-czf',
      archiveFile.absolute.path,
      '-C',
      releaseFolder.absolute.path,
      // 不打构建目录里的运行时数据（见 [_isRuntimeData]）；
      // tar 的 --exclude 不含分隔符时按名字匹配，子目录里的同名项也会排除
      ..._runtimeDataNames.map((name) => '--exclude=$name'),
      baseName,
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('tar 打包失败（退出码 ${result.exitCode}）');
      if ('${result.stderr}'.trim().isNotEmpty) stderr.writeln(result.stderr);
      return null;
    }
  } finally {
    await stagedFolder.rename(sourceFolder.path);
  }

  stdout.writeln('打包产物：${_normalizePath(archiveFile.path)}');
  return archiveFile;
}

/// 打包 macOS 产物为 dmg
///
/// 用系统 hdiutil（macOS 自带）从 .app 直接生成压缩磁盘映像，镜像里就是 .app 本体
Future<File?> _packageDmg(
  Directory releaseFolder,
  Directory distFolder,
  String baseName,
) async {
  final appBundle = _firstExistingAppBundle(releaseFolder);
  if (appBundle == null) {
    stderr.writeln(
      '没在 ${_normalizePath(releaseFolder.path)} 里找到 .app，跳过 dmg 打包',
    );
    return null;
  }

  final dmgFile = File(
    '${distFolder.path}${Platform.pathSeparator}$baseName.dmg',
  );
  await distFolder.create(recursive: true);
  if (await dmgFile.exists()) await dmgFile.delete();

  stdout.writeln('\n正在打包 dmg：$baseName.dmg');
  final result = await Process.run('hdiutil', [
    'create',
    '-volname',
    _appDisplayName(appBundle),
    '-srcfolder',
    appBundle.absolute.path,
    '-ov',
    '-format',
    'UDZO',
    dmgFile.absolute.path,
  ]);
  if (result.exitCode != 0) {
    stderr.writeln('hdiutil 打包失败（退出码 ${result.exitCode}）');
    if ('${result.stderr}'.trim().isNotEmpty) stderr.writeln(result.stderr);
    return null;
  }

  stdout.writeln('打包产物：${_normalizePath(dmgFile.path)}');
  return dmgFile;
}

/// 在产物目录里找 .app：产物名跟着 PRODUCT_NAME 走，不写死
Directory? _firstExistingAppBundle(Directory folder) {
  for (final entity in folder.listSync()) {
    if (entity is Directory &&
        entity.path.toLowerCase().endsWith('.app')) {
      return entity;
    }
  }
  return null;
}

/// .app 挂成磁盘映像后的卷名：去掉 .app 后缀
String _appDisplayName(Directory appBundle) {
  final bundleName = appBundle.path.split(Platform.pathSeparator).last;
  return bundleName.replaceAll(RegExp(r'\.app$', caseSensitive: false), '');
}

/// 启动器运行时数据的名字（见 AppPaths 的数据根：绿色版下这些数据生成在 exe 旁边）
///
/// 构建目录里这些是本机调试残留，`flutter build` 不会清理目录。打进发布包后，
/// 解压出来的启动器会发现 exe 旁边有 config → 数据根跟着落到解压目录，
/// 版本路径还指向构建机的 versions 目录；构建目标不同机器时就是一串错路径
const _runtimeDataNames = <String>{
  'config.json',
  'config.bin',
  'control.lock',
  'single_instance.port',
  'logs',
  'remote_data',
  'versions',
  'versionsFolds',
  'mindustrys',
  'java',
};

/// [path] 是否落在启动器运行时数据里：任一层目录名 / 文件名命中就算
///
/// 按"任一层"判定是为了排除掉 `logs` 这类目录后，它下面的文件不会被逐个收回来
bool _isRuntimeData(String path) {
  final segments = p.split(p.normalize(path));
  return segments.any(_runtimeDataNames.contains);
}

/// 打包 Zip（包内直接是目录内容，解压即用）
Future<File> _packageZip(
  Directory sourceFolder,
  Directory distFolder,
  String baseName,
) async {
  final zipFile = File('${distFolder.path}/$baseName.zip');
  await zipFile.parent.create(recursive: true);
  if (await zipFile.exists()) await zipFile.delete();

  stdout.writeln('\n正在打包 Zip：$baseName.zip');
  final excluded = <String>{};
  final encoder = ZipFileEncoder();
  await encoder.zipDirectory(
    sourceFolder,
    filename: zipFile.path,
    filter: (entity, _) {
      if (!_isRuntimeData(entity.path)) return ZipFileOperation.include;
      // 报告里只记顶层名字，免得 logs 底下的日志文件刷一屏
      final relative = p.relative(entity.path, from: sourceFolder.path);
      excluded.add(p.split(relative).first);
      return ZipFileOperation.skip;
    },
  );
  if (excluded.isNotEmpty) {
    stdout.writeln('  已排除运行时数据：${excluded.join('、')}');
  }
  stdout.writeln('打包产物：${_normalizePath(zipFile.path)}');
  return zipFile;
}

/// 打包 Setup 安装包（Inno Setup 编译 tool/windows_installer.iss）
Future<File?> _packageSetup(
  Directory sourceFolder,
  Directory distFolder,
  String baseName,
  String appVersion,
) async {
  final iscc = _findInnoSetupCompiler();
  if (iscc == null) {
    stderr.writeln(
      '没找到 Inno Setup 的 ISCC.exe，跳过 Setup 打包\n'
      '  安装：winget install JRSoftware.InnoSetup（或 https://jrsoftware.org/isdl.php）',
    );
    return null;
  }

  await distFolder.create(recursive: true);
  // Inno 的 OutputBaseFilename 只能是文件名，不能带路径
  final outputBaseName = '$baseName-setup';
  final setupFile = File(
    '${distFolder.path}${Platform.pathSeparator}$outputBaseName.exe',
  );
  if (await setupFile.exists()) await setupFile.delete();

  stdout.writeln('\n正在编译 Setup：$outputBaseName.exe');
  final scriptPath = File('tool/windows_installer.iss').absolute.path;
  final chineseMessages = File(
    'tool/languages/ChineseSimplified.isl',
  ).absolute.path;
  final result = await Process.run(iscc, [
    '/DAppVersion=$appVersion',
    '/DSourceDir=${_normalizePath(sourceFolder.absolute.path)}',
    '/DOutputDir=${_normalizePath(distFolder.absolute.path)}',
    '/DOutputBaseName=$outputBaseName',
    '/DSetupIconFile=${_normalizePath(File('windows/runner/resources/app_icon.ico').absolute.path)}',
    if (File(chineseMessages).existsSync())
      '/DChineseMessagesFile=${_normalizePath(chineseMessages)}',
    _normalizePath(scriptPath),
  ]);

  if (result.exitCode != 0 || !await setupFile.exists()) {
    stderr.writeln('Inno Setup 编译失败（退出码 ${result.exitCode}）');
    if ('${result.stdout}'.trim().isNotEmpty) stdout.writeln(result.stdout);
    if ('${result.stderr}'.trim().isNotEmpty) stderr.writeln(result.stderr);
    return null;
  }
  stdout.writeln('打包产物：${_normalizePath(setupFile.path)}');
  return setupFile;
}

/// 找 Inno Setup 的编译器：PATH 优先，再找默认安装目录（含用户级安装）
String? _findInnoSetupCompiler() {
  const folderNames = ['Inno Setup 7', 'Inno Setup 6', 'Inno Setup 5'];
  final appData = Platform.environment['LOCALAPPDATA'];
  final candidates = <String>[
    'iscc',
    for (final folder in folderNames) ...[
      '${Platform.environment['ProgramFiles']}\\$folder\\ISCC.exe',
      '${Platform.environment['ProgramFiles(x86)']}\\$folder\\ISCC.exe',
      if (appData != null) '$appData\\Programs\\$folder\\ISCC.exe',
    ],
  ];

  for (final candidate in candidates) {
    if (!candidate.contains(Platform.pathSeparator)) {
      // 裸命令：交给 PATH 解析，找不到就是 null
      final resolved = _resolveOnPath(candidate);
      if (resolved != null) return resolved;
      continue;
    }
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// 在 PATH 里找可执行文件
String? _resolveOnPath(String command) {
  final pathValue = Platform.environment['PATH'] ?? '';
  final extensions = Platform.isWindows
      ? (Platform.environment['PATHEXT'] ?? '.EXE').split(';')
      : [''];
  for (final folder in pathValue.split(Platform.isWindows ? ';' : ':')) {
    if (folder.trim().isEmpty) continue;
    for (final extension in extensions) {
      final file = File('$folder$Platform.pathSeparator$command$extension');
      if (file.existsSync()) return file.path;
    }
  }
  return null;
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

  // 显示版本形如 v0.2.0 alpha 12：取第一段当纯版本号
  final versionName = displayVersion.replaceFirst('v', '').split(' ').first;
  return CurrentVersion(
    versionName: versionName,
    buildNumber: buildNumber ?? 0,
    buildTime: _matchValue(block, 'appBuildTime'),
    displayVersion: displayVersion,
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

/// 读上次选的构建目标；旧版本状态文件存的是单值 `platform`，一并兼容
List<BuildTarget>? _loadTargets() {
  final file = File(statePath);
  if (!file.existsSync()) return null;
  try {
    final state = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final raw = state['targets'] ?? state['platform'];
    final names = switch (raw) {
      List<dynamic>() => raw.cast<String>(),
      String() => [raw],
      _ => const <String>[],
    };

    final targets = <BuildTarget>[];
    for (final name in names) {
      final target = _matchEnum(BuildTarget.values, name);
      if (target != null && !targets.contains(target)) targets.add(target);
    }
    return targets.isEmpty ? null : targets;
  } catch (_) {
    return null;
  }
}

void _saveTargets(List<BuildTarget> targets) {
  File(statePath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'targets': [for (final target in targets) target.name],
    }),
    flush: true,
  );
}
