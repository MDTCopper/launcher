import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:archive/archive.dart';
import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/util/art_binding.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart';
import 'package:path/path.dart' as p;

import '../core/app_config.dart';
import 'bridge_payload.dart';

/// Android 桥（android-bridge）的载荷位置与启动参数
///
/// 桥在 Android 上起一个**真 JVM** 跑桌面版游戏 jar：Flutter 侧只做两件事 ——
/// 准备载荷、把参数交给 `Bridge.launch`（绑定在 `lib/util/art_binding.dart`）。
/// 参数口径对齐《android-bridge 使用文档》§4.3 / §5 / §7，三条硬规则：
/// `--bridge-jar` 由组件工厂追加（别自己传）、`--abi` 不用传（桥按设备认）、
/// `--arc-lib` / `--angle-path` 的目录必须可写（桥要在里面把 `.so` 改成可执行 + 只读）
class BridgeLauncher {
  BridgeLauncher._();

  /// 这次版本自己的桥运行期目录（参数 `-C`）：每版本一份，桥在里面摆原生库与 `tmp`
  static String cacheDirFor(Mindustry version) =>
      p.join(version.foldPath, 'bridge', 'cache');

  /// 组装桥的命令行（纯函数，方便用例覆盖「带 / 不带 loader」两种）
  ///
  /// 桥自己的选项必须写在**第一个 `--` 之前**；位置参数先给桥，注入 loader 时由
  /// loader 再吃掉一层 `--`，剩下的才轮到游戏。
  ///
  /// [arcDir] 给 null 就不带 `--arc-lib`（查不到该版本的 arc 时按「性能下降」照起，
  /// 别把「起不来」变成「点一下没反应」）
  static List<String> buildArguments({
    required String gameJar,
    required String dataPath,
    required String cacheDir,
    required String jreDir,
    String? arcDir,
    String? angleDir,
    bool gl3 = true,
    bool logcat = true,
    List<String> jvmArgs = const [],
    List<String> loaderJars = const [],
    String? loaderMainClass,
    List<String> loaderArgs = const [],
    List<String> gameArgs = const [],
  }) {
    final bridgeOptions = <String>[
      '-G',
      gameJar,
      '-D',
      dataPath,
      '-C',
      cacheDir,
      '--java',
      p.join(jreDir, 'bin', 'java'),
      if (arcDir != null) ...['--arc-lib', arcDir],
      if (angleDir != null) ...['--angle-path', angleDir],
      gl3 ? '--gl3' : '--gl2',
      for (final arg in jvmArgs) ...['-J', arg],
      if (logcat) '--logcat',
      // `-L` 的顺序就是 classpath 顺序：loader-wrapper 在前（它是主类），
      // loader 的桌面 jar 在后
      for (final jar in loaderJars) ...['-L', jar],
      if (loaderMainClass != null) ...['--main', loaderMainClass],
    ];

    final positional = <String>[];
    if (loaderJars.isEmpty) {
      // 不注入 loader：位置参数直接给游戏，一层 `--` 就够
      if (gameArgs.isNotEmpty) positional.addAll(['--', ...gameArgs]);
    } else {
      // 注入 loader：套两层 `--`（桥认第一层、loader 认第二层），
      // 给游戏的参数放第二个之后
      if (loaderArgs.isNotEmpty || gameArgs.isNotEmpty) {
        positional.addAll(['--', ...loaderArgs, '--', ...gameArgs]);
      }
    }

    return [...bridgeOptions, ...positional];
  }

  /// 把启动器现有设置搬成桥的 `-J`（JVM）参数
  ///
  /// 桌面上的窗口参数（`-width` / `-height` / `-maximized`）与 `-Dmindustry.data.dir`
  /// **不要带**：桥不读窗口参数，数据目录由 `-D` 交给它，多传会被当成未知选项报错
  static List<String> jvmArgsFrom({Memory? maxMemory, String? jvmParameter}) {
    return [
      if (maxMemory != null && maxMemory.inGB > 0.1) '-Xmx${maxMemory.mb}m',
      ...?jvmParameter
          ?.split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty),
    ];
  }

  /// 32 位 ARM 上 JDK 25 的 G1 不可用：桥默认注入的 `-XX:+UseG1GC` 会让 JVM 直接崩，
  /// 这个 ABI 要显式换成 SerialGC —— 一句话既选了 GC、又让桥的 G1 那组不再注入
  static List<String> gcSafetyArgsFor(String abi) =>
      abi == 'armeabi-v7a' ? const ['-XX:+UseSerialGC'] : const [];

  /// 桌面专属的 JVM 参数：数据目录由桥的 `-D` 交给游戏，自己再塞一份会让游戏认错目录
  /// （文档 §5.3；窗口参数是位置参数，本来就不在这条路上）
  static bool isDesktopOnlyJvmArg(String arg) =>
      arg.startsWith('-Dmindustry.data.dir');

  /// 这个版本自己的桥目录：`-C` 在里面，也放「这个版本用了哪份 arc」的记录
  static String bridgeDirFor(Mindustry version) =>
      p.join(version.foldPath, 'bridge');

  /// 记「这个版本用哪份 arc」的文件（查一次落盘，之后启动不再联网）
  static String arcRefFileFor(Mindustry version) =>
      p.join(bridgeDirFor(version), 'arc-ref');

  /// 这个版本该用哪份 arc（[Anuken/Arc] 的短 commit，文档 §3.3）
  ///
  /// 顺序：版本目录里的记录 → 本体 jar `version.properties` 的 `commitHash` 去查
  /// Mindustry 的 `gradle.properties` → 拿 `release` 当 tag 再查一次。
  /// **commit 那条是主路**：BE（自构建）版本没有 Mindustry tag（`release` 记的是构建号），
  /// 而官方版本的 jar 里同样有 `commitHash` —— 一份本体由哪个提交编出来，就查那个提交的
  /// `archash`，两种版本一条路。
  ///
  /// 查到就落盘；都查不到返回 null（调用方按「不带 arc 原生库启动、性能下降」处理）
  static Future<String?> arcRefOf(
    Mindustry version, {
    void Function(String status)? onStatus,
  }) async {
    final cacheFile = File(arcRefFileFor(version));
    if (cacheFile.existsSync()) {
      final cached = cacheFile.readAsStringSync().trim();
      if (cached.isNotEmpty) return cached;
    }

    final jar = File(version.resolvedJarPath);
    if (!jar.existsSync()) return null;

    onStatus?.call('正在确认这个版本用的 arc…');
    String? ref;
    final commit = await commitHashOfJar(jar.path);
    if (commit != null) {
      ref = await _fetchArchash(BridgePayload.arcRefUrlForCommit(commit));
    }
    ref ??= await _fetchArchash(BridgePayload.arcRefUrlForTag(version.release));
    if (ref == null) return null;

    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(ref);
    addLogAndPrint(.info, 'Android 桥：这个版本用 arc $ref', tag: 'Bridge');
    return ref;
  }

  static Future<String?> _fetchArchash(String url) async {
    try {
      final response = await cio.get<String>(
        url,
        responseType: ResponseType.plain,
      );
      return BridgePayload.parseArchash('${response.data}');
    } catch (error) {
      addLogAndPrint(
        .warning,
        '查 arc 版本失败：${removeNewlines('$error')}',
        tag: 'Bridge',
      );
      return null;
    }
  }

  /// 本体 jar 里 `version.properties` 的 `commitHash`；读不到返回 null
  ///
  /// （官方构建在 jar 里写的就是 `commitHash=unknown`，自构建才写得出真提交 —— 当没有处理）
  static Future<String?> commitHashOfJar(String jarPath) async {
    final commit = await jarPropertyOf(jarPath, 'commitHash');
    if (commit == null || commit.toLowerCase() == 'unknown') return null;
    return commit;
  }

  /// wrapper jar 里 `wrapper-version.properties` 的 `loaderVersion`（它编时针对哪版 loader）
  static Future<String?> wrapperLoaderVersionOf(String jarPath) =>
      jarPropertyOf(jarPath, 'loaderVersion');

  /// 从 jar 里读某个 properties 条目的值；读不到返回 null
  ///
  /// 用 zip 的流式解码只读这几个小条目（本体几十 MB，别整包读进内存）。
  /// **文件句柄必须自己关**：解码失败时 `ZipDecoder` 不会替我们关（Windows 上会
  /// 让「删这个 jar」直接失败），所以流要在 `finally` 里 `closeSync()`
  static Future<String?> jarPropertyOf(String jarPath, String key) async {
    Archive? archive;
    InputFileStream? stream;
    try {
      stream = InputFileStream(jarPath);
      archive = ZipDecoder().decodeStream(stream);
      for (final entryName in _propertiesEntries) {
        final entry = archive.findFile(entryName);
        final bytes = entry?.readBytes();
        if (bytes == null) continue;
        final value = BridgePayload.propertyValue(
          utf8.decode(bytes, allowMalformed: true),
          key,
        );
        if (value != null) return value;
      }
      return null;
    } catch (error) {
      addLogAndPrint(
        .warning,
        '读 jar 里的 $key 失败：${removeNewlines('$error')}',
        tag: 'Bridge',
      );
      return null;
    } finally {
      archive?.clearSync();
      stream?.closeSync();
    }
  }

  /// 版本信息可能落在哪个条目：本体是 `version.properties`，wrapper 是
  /// `wrapper-version.properties`（两边都试一次，省得调用方各记一份）
  static const _propertiesEntries = [
    'version.properties',
    'wrapper-version.properties',
  ];

  /// 把参数交给桥（`Bridge.launch`，绑定见 `lib/util/art_binding.dart`）
  ///
  /// **Activity 必须同步取、同步用**：`jni_flutter` 给的引用是易失的（旋转、切后台
  /// 都可能失效），中间不许 `await`；也不能退回 ApplicationContext —— 桥内部
  /// `startActivity` 没加 `FLAG_ACTIVITY_NEW_TASK`，传应用上下文会抛
  /// `AndroidRuntimeException`（文档 §4.2）。参数错 / jar 不存在会同步抛回调用方，
  /// 之后的失败发生在游戏进程里（只能看 `last_log.txt` 或占位 activity 的堆栈）
  static void launchWithBridge({
    required String bridgeJar,
    required List<String> args,
  }) {
    final engineId = PlatformDispatcher.instance.engineId;
    if (engineId == null) {
      throw StateError('拿不到 FlutterEngine id，取不到 Activity');
    }
    final activity = androidActivity(engineId);
    if (activity == null) {
      throw StateError('拿不到 Activity（应用在后台？）：桥要 Activity 才能起游戏');
    }

    final context = activity.as(Context.type, releaseOriginal: true);
    final jArgs = JArray.withLength(JString.type, args.length);
    for (var i = 0; i < args.length; i++) {
      jArgs[i] = args[i].toJString();
    }

    try {
      Bridge.launch(bridgeJar.toJString(), context, jArgs);
    } finally {
      jArgs.release();
      context.release();
    }
  }
}
