import 'package:copper_launcher/domain/crash/crash_diagnosis.dart';
import 'package:copper_launcher/domain/crash/crash_evidence.dart';

/// 命中时返回命中的那一行，没命中返回空
typedef CrashRuleMatcher = String? Function(CrashEvidence evidence);

/// 一条崩溃规则
///
/// 规则只描述「怎么认」与「怎么解释」，不动磁盘、不改配置
class CrashRule {
  const CrashRule({
    required this.id,
    required this.title,
    required this.severity,
    required this.fatal,
    required this.weight,
    required this.reason,
    required this.suggestions,
    required this.matcher,
    this.action = CrashAction.none,
  });

  /// 稳定的错误码
  final String id;

  /// 短语，给通知标题用
  final String title;

  /// 展示级别
  final CrashSeverity severity;

  /// 这条规则命中的情况是不是「游戏真的崩了」
  final bool fatal;

  /// 基础分，多信号投票时按分排序
  final int weight;

  /// 人话原因
  final String reason;

  /// 用户能做的事
  final List<String> suggestions;

  /// 匹配函数，返回命中行
  final CrashRuleMatcher matcher;

  /// 建议的一键动作
  final CrashAction action;

  /// 是否命中
  bool matches(CrashEvidence evidence) => matcher(evidence) != null;
}

/// 全部规则；顺序只影响同分时的先后
///
/// 致命规则在前，非致命只在没有致命命中时才用得上
const List<CrashRule> kCrashRules = [
  CrashRule(
    id: 'JAVA_MISSING',
    title: '没有可用的 Java',
    severity: CrashSeverity.fatal,
    fatal: true,
    weight: 100,
    reason: '没找到能用的 Java，游戏进程根本没起来',
    suggestions: [
      '到「设置 - 启动」选一个 Java，或者直接下载一档',
      '确认 Java 安装目录没有被移动或删除',
      '走加载器时要完整 JDK，裁剪过的 JRE 带不动',
    ],
    matcher: _matchJavaMissing,
    action: CrashAction.pickJava,
  ),
  CrashRule(
    id: 'OUT_OF_MEMORY',
    title: '堆内存不足',
    severity: CrashSeverity.fatal,
    fatal: true,
    weight: 100,
    reason: '游戏把分配到的堆用完了，这一条跟存档和模组无关',
    suggestions: [
      '把本版本内存调高一档，整合包常用 4 GB 起',
      '关掉几个大模组，或者少装一点内容包',
      '游戏运行时别再开别的 JVM',
    ],
    matcher: _matchOutOfMemory,
    action: CrashAction.raiseMemory,
  ),
  CrashRule(
    id: 'MOD_GAME_VERSION_MISMATCH',
    title: '模组与游戏版本不匹配',
    severity: CrashSeverity.fatal,
    fatal: true,
    weight: 95,
    reason: '被点名的模组是按别的游戏版本编的，加载时找不到对应的类或方法',
    suggestions: ['先关掉被点名的模组，确认能进游戏', '换成与当前游戏版本匹配的模组版本', '不确定是哪几个就全关，再逐个打开试'],
    matcher: _matchModVersionMismatch,
    action: CrashAction.disableMod,
  ),
  CrashRule(
    id: 'JAVA_VERSION_MISMATCH',
    title: 'Java 版本不匹配',
    severity: CrashSeverity.fatal,
    fatal: true,
    weight: 90,
    reason: '这次用的 Java 满足不了游戏或加载器的要求',
    suggestions: [
      '换游戏版本推荐的那档 Java，v146 起用 17，新版可以用 23',
      'Steam 版走加载器时要换完整 JDK，Steam 自带 JRE 只有 java.base',
      '改完到版本设置里点一次保存再启动',
    ],
    matcher: _matchJavaVersionMismatch,
    action: CrashAction.pickJava,
  ),
  CrashRule(
    id: 'MOD_RUNTIME_ERROR',
    title: '模组自身出错',
    severity: CrashSeverity.fatal,
    fatal: true,
    weight: 85,
    reason: '模组代码在运行时抛了异常，游戏跟着退出',
    suggestions: ['关掉出错的模组再启动', '把 crashes 里这份报告发给模组作者', '联机时让同房间所有人用同一套模组'],
    matcher: _matchModRuntimeError,
    action: CrashAction.disableMod,
  ),
  CrashRule(
    id: 'ARC_NATIVE_MISSING',
    title: 'arc 原生库缺失或不匹配',
    severity: CrashSeverity.fatal,
    fatal: true,
    weight: 85,
    reason: '这次用的 arc 原生库跟游戏版本或设备 ABI 对不上',
    suggestions: [
      '重装桥运行环境，让原生库按 ABI 重下',
      '换回与该游戏版本匹配的桥版本',
      '清掉桥载荷里的 arc 目录后重下一次',
    ],
    matcher: _matchArcNativeMissing,
    action: CrashAction.reinstallBridge,
  ),
  CrashRule(
    id: 'DATA_DIR_NOT_WRITABLE',
    title: '数据目录写不进去',
    severity: CrashSeverity.fatal,
    fatal: true,
    weight: 85,
    reason: '版本自己的数据目录不可写，游戏写不出启动哨兵或设置',
    suggestions: ['把版本数据目录改到可写的位置', '确认盘还有空间，杀软没有拦这一下', '关掉隔离，用默认数据目录试一次'],
    matcher: _matchDataDirNotWritable,
    action: CrashAction.openVersionSettings,
  ),
  CrashRule(
    id: 'BRIDGE_RUNTIME_FAILED',
    title: 'Android 桥运行环境起不来',
    severity: CrashSeverity.fatal,
    fatal: true,
    weight: 80,
    reason: '桥的 JRE、ABI 或 so 加载失败，游戏进程没起来',
    suggestions: ['重装桥运行环境', '确认设备 ABI 与桥载荷一致', '换回匹配的桥版本'],
    matcher: _matchBridgeRuntime,
    action: CrashAction.reinstallBridge,
  ),
  CrashRule(
    id: 'SETTINGS_OR_SAVE_CORRUPT',
    title: '设置或存档损坏',
    severity: CrashSeverity.fatal,
    fatal: true,
    weight: 75,
    reason: 'settings.bin 或存档读不出来，游戏在加载阶段就退了',
    suggestions: [
      '从 settings.bin.copper-backup 或 settings_backup.bin 恢复设置',
      '从云存档历史恢复一份能进的存档',
      '把重复的 -cloud- 副本挪走再试',
    ],
    matcher: _matchSettingsCorrupt,
    action: CrashAction.openVersionSettings,
  ),
  CrashRule(
    id: 'GL_DRIVER',
    title: '显卡 / OpenGL 初始化失败',
    severity: CrashSeverity.fatal,
    fatal: true,
    weight: 60,
    reason: '游戏建不起 OpenGL 上下文，进程在开窗口阶段就退了',
    suggestions: ['更新显卡驱动', '到版本设置里改用独显启动', '远程桌面或虚拟显卡环境下先本地启动一次'],
    matcher: _matchGlDriver,
    action: CrashAction.openVersionSettings,
  ),
  CrashRule(
    id: 'PORT_IN_USE',
    title: '联机端口被占用',
    severity: CrashSeverity.info,
    fatal: false,
    weight: 40,
    reason: '6567 被上一局游戏或别的程序占着，只影响联机不影响单机',
    suggestions: ['关掉还在跑的游戏再开联机', '只开一种联机，官方联机或 LanLink 二选一', '等几秒再试'],
    matcher: _matchPortInUse,
  ),
  CrashRule(
    id: 'NON_FATAL_NETWORK',
    title: '社区服务器列表没取到',
    severity: CrashSeverity.info,
    fatal: false,
    weight: 20,
    reason: '拉社区服务器列表失败，纯网络问题，跟游戏能不能玩无关',
    suggestions: ['换个网络或挂代理再试'],
    matcher: _matchCommunityServers,
  ),
  CrashRule(
    id: 'NON_FATAL_GL_FALLBACK',
    title: '显卡走了降级路径',
    severity: CrashSeverity.info,
    fatal: false,
    weight: 20,
    reason: '游戏用自己的降级方式跑，GL2 / ANGLE / 着色器告警都不算崩溃',
    suggestions: ['更新显卡驱动', '版本设置里改用独显启动'],
    matcher: _matchGlFallback,
  ),
  CrashRule(
    id: 'NON_FATAL_SAVE_DUPLICATE',
    title: '同一区块有两份存档',
    severity: CrashSeverity.info,
    fatal: false,
    weight: 20,
    reason: '游戏自己会挑一份用，这条只是提示',
    suggestions: ['把 -cloud- 副本挪走'],
    matcher: _matchDuplicateSaves,
  ),
  CrashRule(
    id: 'NON_FATAL_MOD_NOISE',
    title: '模组提示，不是崩溃',
    severity: CrashSeverity.info,
    fatal: false,
    weight: 20,
    reason: '模组元数据多余字段、缺音效、联机模组不一致，都不影响单机',
    suggestions: ['按提示补齐资源或更新模组'],
    matcher: _matchModNoise,
  ),
];

/// 从崩溃报告里取出被点名的模组名；取不到返回空
String? namedModIn(String text) {
  for (final pattern in _namedModPatterns) {
    final name = pattern.firstMatch(text)?.group(1);
    if (name == null) continue;
    final plain = _stripColorTags(name);
    if (plain.isNotEmpty) return plain;
  }
  return null;
}

final _namedModPatterns = [
  RegExp(r"The mod '([^']+)' \("),
  RegExp(r'Likely Cause: (.+?) \('),
];

/// 模组名里可能带 `[accent]` 这类颜色标记，展示前去掉
String _stripColorTags(String raw) => raw.replaceAll(RegExp(r'\[[^\]]*\]'), '');

final _javaMissingPatterns = [
  RegExp(r'未找到可用 Java'),
  RegExp(r'未检测到 Java 环境'),
  RegExp(r'Cannot run program "java"'),
];

final _outOfMemoryPatterns = [
  RegExp(r'OutOfMemoryError: Java heap space'),
  RegExp(r'GC overhead limit exceeded'),
  RegExp(r'OutOfMemoryError: (Metaspace|Direct buffer memory)'),
  RegExp(r'OutOfMemoryError'),
];

/// 只看符号级报错：崩溃报告头里的「has caused」几乎每份都有，
/// 拿它判版本不匹配会把模组运行时异常也误判进来
final _modVersionMismatchPatterns = [
  RegExp(r'mindustry\.net\.Net\.registerPacket'),
  RegExp(r"NoSuchMethodError: '.*mindustry\."),
  RegExp(r'NoSuchFieldError: Class '),
  RegExp(r'NoClassDefFoundError: mindustry/'),
  RegExp(r'NoSuchMethodException: mindustry\.'),
  RegExp(r'Error loading mod [\w-]+'),
];

/// 游戏把不兼容的模组禁掉而不是崩掉时不再算崩溃
final _disabledModPatterns = [RegExp(r'has been disabled due to')];

final _javaVersionMismatchPatterns = [
  RegExp(r'UnsupportedClassVersionError'),
  RegExp(r'Unsupported JNI version'),
  RegExp(r'class file version \d+\.\d+'),
];

final _modRuntimePatterns = [
  RegExp(r'NullPointerException'),
  RegExp(r'IndexOutOfBoundsException'),
  RegExp(r"index can't be >= size"),
  RegExp(r'rhino\.EcmaError'),
  RegExp(r'rhino\.EvaluatorException'),
  RegExp(r'rhino\.JavaScriptException'),
];

final _arcNativeMissingPatterns = [
  RegExp(r'NoClassDefFoundError: arc/'),
  RegExp(r'Failed to locate library: liblwjgl\.so'),
  RegExp(r'libarc\.so'),
  RegExp(r'UnsatisfiedLinkError: .*liblwjgl'),
];

final _dataDirNotWritablePatterns = [
  RegExp(r'Error writing file:'),
  RegExp(r'Access is denied'),
  RegExp(r'Permission denied'),
  RegExp(r'Read-only file system'),
  RegExp(r'(There is not enough space|No space left on device)'),
];

final _bridgeRuntimePatterns = [
  RegExp(r'UnsatisfiedLinkError'),
  RegExp(r'dlopen failed'),
  RegExp(r'libcopperbridge\.so'),
  RegExp(r'桥运行环境'),
  RegExp(r'no matching abi', caseSensitive: false),
];

final _settingsCorruptPatterns = [
  RegExp(r'NumberFormatException: For input string'),
  RegExp(r'Error reading file: .*(settings|settings\.bin|saves/)'),
  RegExp(r'ArcRuntimeException: Error reading file'),
];

final _glDriverPatterns = [
  RegExp(r'Could not create GL'),
  RegExp(r'Failed to create window'),
  RegExp(r'GLFW error'),
  RegExp(r'No OpenGL'),
  RegExp(r'Failed to create GL context'),
];

final _glDisabledPatterns = [
  RegExp(r'#version directive missing'),
  RegExp(r'Using OpenGL 2'),
  RegExp(r'Intel GPU detected'),
];

final _portInUsePatterns = [
  RegExp(r'Address already in use'),
  RegExp(r'端口被占用'),
  RegExp(r'本机端口 6567 起不来'),
];

final _communityServersPatterns = [
  RegExp(r'Failed to fetch community servers'),
  RegExp(r'Connection reset'),
  RegExp(r'HttpStatusException'),
];

final _glFallbackPatterns = [
  RegExp(r'Intel GPU detected'),
  RegExp(r'Using OpenGL 2'),
  RegExp(r'ANGLE'),
  RegExp(r'#version directive missing'),
];

final _duplicateSavePatterns = [
  RegExp(r'has two corresponding saves'),
  RegExp(r'-cloud-'),
];

final _modNoisePatterns = [
  RegExp(r'Incompatible mods'),
  RegExp(r"Unknown field '"),
  RegExp(r'Audio file not found'),
];

String? _matchJavaMissing(CrashEvidence evidence) {
  if (!evidence.javaReady) return 'Java 状态：不可用';
  return _matchPatterns(evidence.diagnosticText, _javaMissingPatterns);
}

String? _matchOutOfMemory(CrashEvidence evidence) =>
    _matchPatterns(evidence.diagnosticText, _outOfMemoryPatterns);

String? _matchModVersionMismatch(CrashEvidence evidence) => _matchPatterns(
  evidence.diagnosticText,
  _modVersionMismatchPatterns,
  suppressors: _disabledModPatterns,
);

String? _matchJavaVersionMismatch(CrashEvidence evidence) {
  final text = evidence.diagnosticText;
  final hit = _matchPatterns(text, _javaVersionMismatchPatterns);
  if (hit != null) return hit;
  // Steam 裁剪过的 JRE 带不动 Mixin：只有这一条时也是 Java 的问题
  if (text.contains('java/util/logging/Logger') &&
      text.contains('MixinConfig.onLoad')) {
    return 'NoClassDefFoundError: java/util/logging/Logger';
  }
  return null;
}

String? _matchModRuntimeError(CrashEvidence evidence) {
  final text = evidence.diagnosticText;
  final hit = _matchPatterns(text, _modRuntimePatterns);
  if (hit == null) return null;
  return _mentionsMod(text) ? hit : null;
}

String? _matchArcNativeMissing(CrashEvidence evidence) =>
    _matchPatterns(evidence.diagnosticText, _arcNativeMissingPatterns);

String? _matchDataDirNotWritable(CrashEvidence evidence) =>
    _matchPatterns(evidence.diagnosticText, _dataDirNotWritablePatterns);

String? _matchBridgeRuntime(CrashEvidence evidence) {
  if (!evidence.bridgeReady) return '桥运行环境：不可用';
  return _matchPatterns(evidence.diagnosticText, _bridgeRuntimePatterns);
}

String? _matchSettingsCorrupt(CrashEvidence evidence) {
  final text = evidence.diagnosticText;
  final hit = _matchPatterns(text, _settingsCorruptPatterns);
  if (hit != null) return hit;
  // 越界报错要先看到 settings / 存档的字样，否则更像模组的运行时异常
  if (!text.contains("index can't be >= size")) return null;
  if (!_settingsOrSaveMentioned(text)) return null;
  return _lineContaining(text, "index can't be >= size");
}

String? _matchGlDriver(CrashEvidence evidence) => _matchPatterns(
  evidence.diagnosticText,
  _glDriverPatterns,
  suppressors: _glDisabledPatterns,
);

String? _matchPortInUse(CrashEvidence evidence) =>
    _matchPatterns(evidence.diagnosticText, _portInUsePatterns);

String? _matchCommunityServers(CrashEvidence evidence) =>
    _matchPatterns(evidence.diagnosticText, _communityServersPatterns);

String? _matchGlFallback(CrashEvidence evidence) =>
    _matchPatterns(evidence.diagnosticText, _glFallbackPatterns);

String? _matchDuplicateSaves(CrashEvidence evidence) =>
    _matchPatterns(evidence.diagnosticText, _duplicateSavePatterns);

String? _matchModNoise(CrashEvidence evidence) =>
    _matchPatterns(evidence.diagnosticText, _modNoisePatterns);

/// 在一份文本里按顺序找第一个命中行
String? _matchPatterns(
  String text,
  List<RegExp> patterns, {
  List<RegExp> suppressors = const [],
}) {
  if (text.isEmpty) return null;
  for (final suppressor in suppressors) {
    if (suppressor.hasMatch(text)) return null;
  }
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    return _lineAt(text, match.start);
  }
  return null;
}

String _lineAt(String text, int offset) {
  final start = text.lastIndexOf('\n', offset);
  final end = text.indexOf('\n', offset);
  return text.substring(start + 1, end < 0 ? text.length : end).trim();
}

String? _lineContaining(String text, String needle) {
  final index = text.indexOf(needle);
  if (index < 0) return null;
  return _lineAt(text, index);
}

bool _settingsOrSaveMentioned(String text) =>
    text.contains('settings.bin') ||
    text.contains('saves/') ||
    text.contains('.msav');

/// 文本里有没有指向某个模组的证据
bool _mentionsMod(String text) =>
    text.contains('has caused Mindustry to crash') ||
    text.contains('Likely Cause:') ||
    text.contains('Error loading mod') ||
    _modPackageIn(text) != null;

final _stackFramePattern = RegExp(r'^\s+at ([\w$.]+)', multiLine: true);

/// 栈里属于游戏 / 引擎 / 标准库的包，出现这些不算模组
const _corePackagePrefixes = [
  'mindustry.',
  'arc.',
  'io.anuke.arc.',
  'java.',
  'javax.',
  'jdk.',
  'sun.',
  'com.sun.',
  'org.spongepowered.',
  'copper.',
  'kotlin.',
  'rhino.',
  'org.lwjgl.',
  'com.badlogic.',
  'adapter',
];

/// 栈里第一个不属于核心的类，用它判断异常出在模组里
String? _modPackageIn(String text) {
  for (final match in _stackFramePattern.allMatches(text)) {
    final symbol = match.group(1);
    if (symbol == null || !symbol.contains('.')) continue;
    // JS 模组编译出来的类叫 rhino.gen.<脚本名>_<数字>
    if (symbol.startsWith('rhino.gen.')) return symbol;
    if (_corePackagePrefixes.any(symbol.startsWith)) continue;
    return symbol;
  }
  return null;
}
