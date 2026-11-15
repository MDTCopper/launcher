import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/generated/android_call.g.dart';
import 'package:copper_launcher/domain/bridge_launcher.dart';
import 'package:copper_launcher/domain/bridge_payload.dart';
import 'package:copper_launcher/domain/bridge_runtime_options.dart';
import 'package:copper_launcher/domain/loader_library.dart';
import 'package:copper_launcher/domain/payload_import.dart';
import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/archive_extract.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/git_refs.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/version_strings.dart' as version_strings;
import 'package:path/path.dart' as p;

/// 桥的安装：查最新一版 → 下 JRE（两个包）/ arc 原生库 / bridge.jar → 校验齐不齐
///
/// 首次运行时装（装完才让进主页）。**换载荷要先删旧文件**：桥会把 `.so` 改成
/// 可执行 + 只读，原地覆盖写不进去（《android-bridge 使用文档》§3.7）
class BridgeInstaller {
  BridgeInstaller._();

  /// 本地记的 JRE 版本（远端 `version` 文件变没变，用来判断要不要重装）
  static String get jreVersionMarker =>
      p.join(AppPaths.bridgeJre, '.installed-version');

  /// 上次装桥时的启动器构建号：APK 更新后宿主类的编译期桥可能已变，
  /// 旧运行期 bridge.jar 必须重装，否则会出现 NoSuchFieldError
  static String get bridgeBuildMarkerPath =>
      p.join(AppPaths.bridge, '.launcher-build');

  static bool bridgeBuildMatches() {
    try {
      final marker = File(bridgeBuildMarkerPath);
      return marker.existsSync() &&
          marker.readAsStringSync().trim() == '$appBuildNumber';
    } catch (_) {
      return false;
    }
  }

  static bool needsRuntimeRefresh() => !bridgeBuildMatches();

  static void _writeBridgeBuildMarker() {
    try {
      File(bridgeBuildMarkerPath).writeAsStringSync('$appBuildNumber');
    } catch (_) {
      // 写不进去下次会再装一次，不影响本次启动
    }
  }

  /// 查桥的最新版本（**版本号形态的 tag**，不要 snapshot：快照每次 push 都会变）
  ///
  /// 先走 git ref 广告（不吃 GitHub API 匿名额度），拿不到再退 release 接口
  static Future<({String tag, String url})?> fetchLatestBridge() async {
    try {
      final tags = await GitRefs.fetchTags(BridgePayload.bridgeRepo);
      final tag = BridgePayload.newestVersionTag(tags);
      if (tag != null) {
        return (tag: tag, url: BridgePayload.bridgeJarUrl(tag: tag));
      }
      // 一个版本号 tag 都没有（桥仓库现在就是这样，只有 snapshot）：用快照
      return (
        tag: BridgePayload.bridgeSnapshot,
        url: BridgePayload.bridgeJarUrl(),
      );
    } catch (error) {
      addLogAndPrint(
        .warning,
        '列桥的 tag 失败，改查 release 接口：${removeNewlines('$error')}',
        tag: 'Bridge',
      );
    }

    try {
      final decoded = await fetchJsonBody(
        '$githubAPI/repos/${BridgePayload.bridgeRepo}/releases?per_page=10',
      );
      return parseLatestRelease(decoded);
    } catch (error) {
      addLogAndPrint(
        .warning,
        '查询桥版本失败：${removeNewlines('$error')}',
        tag: 'Bridge',
      );
      return null;
    }
  }

  /// 从 release 列表里挑一个可下的桥 jar（纯函数）
  ///
  /// **优先版本号发行版**（`bridge-0.1.3.jar`，挑版本最高的）；一个都没有才退回
  /// `bridge-snapshot.jar` —— 它也是正式 release，只是每次 push 会重建
  static ({String tag, String url})? parseLatestRelease(Object? body) {
    final Object? decoded;
    try {
      decoded = body is String ? jsonDecode(body) : body;
    } catch (_) {
      return null;
    }
    if (decoded is! List) return null;

    final versioned = <({String tag, String url})>[];
    ({String tag, String url})? snapshot;
    for (final release in decoded) {
      if (release is! Map) continue;
      final assets = release['assets'];
      if (assets is! List) continue;
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name'];
        final url = asset['browser_download_url'];
        if (name is! String || url is! String) continue;
        final tag = _tagOfBridgeAsset(name);
        if (tag == null) continue;
        if (tag == BridgePayload.bridgeSnapshot) {
          snapshot ??= (tag: tag, url: url);
        } else {
          versioned.add((tag: tag, url: url));
        }
      }
    }

    if (versioned.isNotEmpty) {
      versioned.sort((a, b) => version_strings.compareVersion(b.tag, a.tag));
      return versioned.first;
    }
    return snapshot;
  }

  /// `bridge-0.1.3.jar` → `0.1.3`、`bridge-snapshot.jar` → `snapshot`；
  /// 其它命名返回 null
  static String? _tagOfBridgeAsset(String name) {
    if (name == 'bridge-${BridgePayload.bridgeSnapshot}.jar') {
      return BridgePayload.bridgeSnapshot;
    }
    return RegExp(r'^bridge-(\d+(?:\.\d+)*)\.jar$').firstMatch(name)?.group(1);
  }

  /// 装一份能跑的载荷，返回落点（调用方用 `missingFiles()` 复核一遍）
  ///
  /// [bridgeTag] 不给就查最新一版；[onStatus] 给界面看的一句话，[onProgress]
  /// 拿整份下载状态（总大小 / 已下载 / 速度）
  static Future<BridgePayloadPaths> install({
    required String abi,
    required String arcRef,
    String? bridgeTag,
    CancelToken? cancelToken,
    void Function(String status)? onStatus,
    void Function(HttpDownloadState state)? onProgress,
  }) async {
    final runtimeTag = await installRuntime(
      abi: abi,
      bridgeTag: bridgeTag,
      cancelToken: cancelToken,
      onStatus: onStatus,
      onProgress: onProgress,
    );
    final arcLibNames = await installArcNatives(
      arcRef: arcRef,
      abi: abi,
      cancelToken: cancelToken,
      onStatus: onStatus,
    );

    return BridgePayload.pathsFor(
      abi: abi,
      arcRef: arcRef,
      arcLibNames: arcLibNames,
      bridgeTag: runtimeTag,
    );
  }

  /// 装**与游戏版本无关**的那份：JRE + 桥 jar，返回实际用的桥版本
  ///
  /// 首次运行的安装页只装它（arc 原生库跟着具体游戏版本走，见 [installArcNatives]）；
  /// [force] 为 true 时不管本地是不是齐的都重下（设置页的「重装」用它）
  static Future<String> installRuntime({
    required String abi,
    String? bridgeTag,
    bool force = false,
    BridgeRuntimeOptions? runtimeOptions,
    CancelToken? cancelToken,
    void Function(String status)? onStatus,
    void Function(HttpDownloadState state)? onProgress,
  }) async {
    final packageName = BridgePayload.jrePackageFor(abi);
    if (packageName == null) {
      throw StateError('不支持的设备 ABI：$abi（JRE 只有 arm64 / arm / x86_64 分包）');
    }

    final options = runtimeOptions ?? BridgeRuntimeOptions.load();
    var tag = bridgeTag ?? options.bridgeTag;
    if (tag == null) {
      final latest = await fetchLatestBridge();
      if (latest == null) throw StateError('查不到桥的可用版本');
      tag = latest.tag;
    }

    await Directory(AppPaths.bridge).create(recursive: true);
    await installJre(
      abi: abi,
      force: force,
      runtimeOptions: options,
      cancelToken: cancelToken,
      onStatus: onStatus,
      onProgress: onProgress,
    );
    await installBridgeJar(
      tag: tag,
      force: force || needsRuntimeRefresh(),
      cancelToken: cancelToken,
      onStatus: onStatus,
      onProgress: onProgress,
    );
    _writeBridgeBuildMarker();

    return tag;
  }

  /// 首次运行的「装没装完」检查（**不联网**）：JRE 两个包都在 + 桥 jar 在
  ///
  /// [bridgeDirPath] 只为用例注入，正常走 [AppPaths.bridge]
  static bool isRuntimeReady({String? bridgeDirPath}) {
    final jreDir = Directory(
      bridgeDirPath == null ? AppPaths.bridgeJre : p.join(bridgeDirPath, 'jre'),
    );
    final hasJre =
        File(p.join(jreDir.path, 'bin', 'java')).existsSync() &&
        File(p.join(jreDir.path, 'lib', 'modules')).existsSync();
    final bridgeJar = bridgeDirPath == null
        ? BridgePayload.installedBridgeJar()
        : BridgePayload.installedBridgeJar(directory: bridgeDirPath);
    if (!hasJre || bridgeJar == null) return false;
    // 用例注入目录不依赖启动器构建号；真机要保证运行期桥与本 APK 编译期桥匹配
    if (bridgeDirPath != null) return true;
    return bridgeBuildMatches();
  }

  /// 只装 Java 运行环境（设置页那一行用；门禁与一键走 [installRuntime]）
  ///
  /// 钉了构建号就按钉的那份校验，[force] 为 true 时无条件重下
  static Future<void> installJre({
    required String abi,
    bool force = false,
    BridgeRuntimeOptions? runtimeOptions,
    CancelToken? cancelToken,
    void Function(String status)? onStatus,
    void Function(HttpDownloadState state)? onProgress,
  }) async {
    final packageName = BridgePayload.jrePackageFor(abi);
    if (packageName == null) {
      throw StateError('不支持的设备 ABI：$abi（JRE 只有 arm64 / arm / x86_64 分包）');
    }
    await _installJre(
      abi: abi,
      packageName: packageName,
      pinnedBuild: (runtimeOptions ?? BridgeRuntimeOptions.load()).jreBuild,
      force: force,
      cancelToken: cancelToken,
      onStatus: onStatus,
      onProgress: onProgress,
    );
  }

  /// 只装桥 jar（[tag] 不给就用钉住的版本，都没钉就查最新一版）
  static Future<String> installBridgeJar({
    String? tag,
    bool force = false,
    CancelToken? cancelToken,
    void Function(String status)? onStatus,
    void Function(HttpDownloadState state)? onProgress,
  }) async {
    var target = tag ?? BridgeRuntimeOptions.load().bridgeTag;
    if (target == null) {
      final latest = await fetchLatestBridge();
      if (latest == null) throw StateError('查不到桥的可用版本');
      target = latest.tag;
    }

    await Directory(AppPaths.bridge).create(recursive: true);
    await _installBridgeJar(
      tag: target,
      force: force,
      cancelToken: cancelToken,
      onStatus: onStatus,
      onProgress: onProgress,
    );
    _writeBridgeBuildMarker();
    return target;
  }

  /// 只装模组加载器适配层（走 mod 时才用得上；不装上也不影响原版启动）
  static Future<String> installLoaderWrapper({
    bool force = false,
    CancelToken? cancelToken,
    void Function(String status)? onStatus,
  }) async {
    final target = File(BridgePayload.loaderWrapperJarFilePath());
    await target.parent.create(recursive: true);

    if (target.existsSync()) {
      if (!force) {
        onStatus?.call('模组加载器适配层已就绪');
        return target.path;
      }
      // 桥会把载荷改成只读，重装要先把旧文件删掉（原地覆盖写不进去）
      try {
        target.deleteSync();
      } catch (error) {
        addLogAndPrint(
          .warning,
          '删旧的模组加载器适配层失败：${removeNewlines('$error')}',
          tag: 'Bridge',
        );
      }
    }

    onStatus?.call('正在下载模组加载器适配层…');
    await cio.download(
      url: BridgePayload.loaderWrapperJarUrl(),
      savePath: target.path,
      cancelToken: cancelToken,
    );
    addLogAndPrint(
      .info,
      'Android 桥：模组加载器适配层装好了（${BridgePayload.loaderWrapperVersion}）',
      tag: 'Bridge',
    );
    return target.path;
  }

  /// 本地导入桥 jar：校验像个 jar，落到 `bridge-<tag>.jar`
  ///
  /// [tag] 不给就从文件名读（`bridge-0.1.3.jar` / `0.1.3.jar` / `bridge-snapshot.jar`）；
  /// 与联网安装一样记下启动器构建号，[isRuntimeReady] 才认这份载荷
  static Future<String> importBridgeJar(File source, {String? tag}) async {
    final entries = await readJarEntryNames(source.path);
    final looksLikeBridge =
        entries.contains('META-INF/MANIFEST.MF') &&
        entries.any((name) => name.endsWith('.class'));
    if (!looksLikeBridge) {
      throw const PayloadImportException(
        '这个 jar 不像是桥：里面缺 MANIFEST.MF 或 class 文件',
      );
    }

    final resolvedTag = _bridgeTagOf(tag ?? p.basename(source.path));
    if (resolvedTag == null) {
      throw const PayloadImportException(
        '读不出桥的版本：文件名要写成 bridge-<版本>.jar（如 bridge-0.1.3.jar），'
        '或导入时指定版本',
      );
    }

    final targetPath = BridgePayload.bridgeJarFilePath(resolvedTag);
    await copyFileAtomically(source, targetPath);
    _writeBridgeBuildMarker();
    addLogAndPrint(.info, 'Android 桥：本地导入了桥 $resolvedTag', tag: 'Bridge');
    return targetPath;
  }

  /// 本地导入 Java 运行环境：压缩包（zip / tar.xz）或已经解压好的目录
  ///
  /// 先收进与 JRE 同层的临时目录，验过 `bin/java` 与 `lib/modules` 才替换旧的；
  /// 中途失败旧的那份原样留着，返回 JRE 根路径
  static Future<String> importJre(
    String sourcePath, {
    void Function(String status)? onStatus,
  }) async {
    final sourceType = FileSystemEntity.typeSync(sourcePath);
    if (sourceType == FileSystemEntityType.notFound) {
      throw const PayloadImportException('选的路径不在了，重新选一次');
    }
    if (sourceType == FileSystemEntityType.file &&
        !_jreArchiveSuffixes.any(
          (suffix) => sourcePath.toLowerCase().endsWith(suffix),
        )) {
      throw const PayloadImportException('只收 zip / tar.xz 压缩包，或者已经解压好的 JRE 目录');
    }

    final bridgeDir = Directory(AppPaths.bridge)..createSync(recursive: true);
    // 临时目录与 jre 同一层：换到位靠改名，不跨文件系统复制
    final stagingDir = Directory(
      p.join(bridgeDir.path, 'tmp', 'jre-importing'),
    );
    _deleteQuietly(stagingDir);
    stagingDir.createSync(recursive: true);

    try {
      late String stagedJreRootPath;
      if (sourceType == FileSystemEntityType.directory) {
        onStatus?.call('正在收集本地 Java 运行环境…');
        final sourceJreRootPath = _jreRootIn(sourcePath);
        if (sourceJreRootPath == null) {
          throw const PayloadImportException(
            '这个目录里没有 bin/java 和 lib/modules，不是可用的 Java 运行环境',
          );
        }
        await _copyDirectoryContents(Directory(sourceJreRootPath), stagingDir);
        stagedJreRootPath = stagingDir.path;
      } else {
        onStatus?.call('正在解压 Java 运行环境…');
        await extractArchive(sourcePath, stagingDir.path);
        final extractedJreRootPath = _jreRootIn(stagingDir.path);
        if (extractedJreRootPath == null) {
          throw const PayloadImportException(
            '这个压缩包里没有 bin/java 和 lib/modules，不是可用的 Java 运行环境',
          );
        }
        stagedJreRootPath = extractedJreRootPath;
      }

      onStatus?.call('正在替换 Java 运行环境…');
      await _replaceJreDirectory(stagedJreRootPath);
    } on PayloadImportException {
      rethrow;
    } catch (error) {
      addLogAndPrint(
        .warning,
        '本地导入 Java 运行环境失败：${removeNewlines('$error')}',
        tag: 'Bridge',
      );
      throw const PayloadImportException('这份文件收不进来：解压或复制出错，换一份再试');
    } finally {
      // 换到位后这里只剩空壳或压缩包自带的散件
      _deleteQuietly(stagingDir);
    }

    await _ensureJavaExecutable();
    addLogAndPrint(.info, 'Android 桥：本地导入了 Java 运行环境', tag: 'Bridge');
    return AppPaths.bridgeJre;
  }

  /// 本地导入模组加载器适配层：校验 jar 里的 `loaderVersion` 读得出来，落到固定落点
  static Future<String> importLoaderWrapper(File source) async {
    final loaderVersion = await readJarProperty(
      source.path,
      'wrapper-version.properties',
      'loaderVersion',
    );
    if (loaderVersion == null) {
      throw const PayloadImportException(
        '这个 jar 不是模组加载器适配层：读不到 wrapper-version.properties 里的 loaderVersion',
      );
    }

    final targetPath = BridgePayload.loaderWrapperJarFilePath();
    await copyFileAtomically(source, targetPath);
    addLogAndPrint(
      .info,
      'Android 桥：本地导入了模组加载器适配层（针对 loader $loaderVersion）',
      tag: 'Bridge',
    );
    return targetPath;
  }

  /// 能当 JRE 导入的压缩包后缀：与 [extractArchive] 支持的形态一致
  static const _jreArchiveSuffixes = [
    '.zip',
    '.tar.xz',
    '.txz',
    '.tar.gz',
    '.tgz',
  ];

  /// 从参数或文件名认出桥的版本号：`bridge-0.1.3.jar` → `0.1.3`、`snapshot` 原样
  ///
  /// 认不出来返回 null：落盘名字必须是 `bridge-<版本>.jar`，
  /// [BridgePayload.installedBridgeJar] 才认得出这份载荷
  static String? _bridgeTagOf(String raw) {
    var name = p.basename(raw.trim());
    if (name.toLowerCase().endsWith('.jar')) {
      name = name.substring(0, name.length - '.jar'.length);
    }
    if (name.startsWith('bridge-')) name = name.substring('bridge-'.length);
    if (name == BridgePayload.bridgeSnapshot) return name;
    return RegExp(r'^\d+(?:\.\d+)*$').hasMatch(name) ? name : null;
  }

  /// 找 JRE 根：含 `bin/java` 与 `lib/modules` 的那一层，压缩包里常还套一层目录
  static String? _jreRootIn(String rootPath) {
    if (_looksLikeJre(rootPath)) return rootPath;
    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) return null;
    for (final entity in rootDir.listSync()) {
      if (entity is Directory && _looksLikeJre(entity.path)) {
        return entity.path;
      }
    }
    return null;
  }

  /// 这一层是不是 JRE：`bin/java`（ABI 分包给的）与 `lib/modules`（ABI 无关包给的）都在
  static bool _looksLikeJre(String dirPath) =>
      File(p.join(dirPath, 'bin', 'java')).existsSync() &&
      File(p.join(dirPath, 'lib', 'modules')).existsSync();

  /// 把 [sourceDir] 里的内容按相对结构复制到 [targetDir]
  static Future<void> _copyDirectoryContents(
    Directory sourceDir,
    Directory targetDir,
  ) async {
    await targetDir.create(recursive: true);
    await for (final entity in sourceDir.list(
      recursive: true,
      followLinks: false,
    )) {
      final relativePath = p.relative(entity.path, from: sourceDir.path);
      final targetPath = p.join(targetDir.path, relativePath);
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(targetPath)).create(recursive: true);
        await entity.copy(targetPath);
      }
    }
  }

  /// 把验过的 JRE 目录换到 [AppPaths.bridgeJre]：旧的先挪到临时目录，新的挪过去再删旧的
  static Future<void> _replaceJreDirectory(String stagedRootPath) async {
    final jreDir = Directory(AppPaths.bridgeJre);
    final backupDir = Directory(p.join(AppPaths.bridge, 'tmp', 'jre-old'));
    _deleteQuietly(backupDir);

    final hasOldJre = jreDir.existsSync();
    if (hasOldJre) await jreDir.rename(backupDir.path);
    try {
      await Directory(stagedRootPath).rename(jreDir.path);
    } catch (error) {
      // 新的没挪过去就把旧的挪回来，别让运行环境凭空没了
      if (hasOldJre && backupDir.existsSync()) {
        await backupDir.rename(jreDir.path);
      }
      rethrow;
    }
    if (hasOldJre) _deleteQuietly(backupDir);
  }

  /// 解压 / 复制都不带权限位，非 Windows 上给 `bin/java` 补个可执行位
  static Future<void> _ensureJavaExecutable() async {
    if (Platform.isWindows) return;
    final javaPath = p.join(AppPaths.bridgeJre, 'bin', 'java');
    if (!File(javaPath).existsSync()) return;

    try {
      final result = await Process.run('chmod', ['755', javaPath]);
      if (result.exitCode == 0) return;
    } catch (_) {
      // 没有 chmod 的环境（沙箱）不让导入因此失败
    }
    addLogAndPrint(
      .warning,
      'Java 运行环境的 bin/java 没补上可执行位，启动前要确认权限',
      tag: 'Bridge',
    );
  }

  /// 可选的版本列表（设置页的下拉用）：两边仓库的 tag
  ///
  /// Java 侧现在只有 `jre25` 一个 tag（能钉的是里面的构建号），桥侧现在只有 `snapshot`
  static Future<({List<String> jreTags, List<String> bridgeTags})>
  fetchAvailableVersions() async {
    Future<List<String>> tagsOf(String repo) async {
      try {
        return await GitRefs.fetchTags(repo);
      } catch (error) {
        addLogAndPrint(
          .warning,
          '查 $repo 的版本失败：${removeNewlines('$error')}',
          tag: 'Bridge',
        );
        return const [];
      }
    }

    return (
      jreTags: await tagsOf(BridgePayload.jreRepo),
      bridgeTags: await tagsOf(BridgePayload.bridgeRepo),
    );
  }

  /// 问设备自己是什么 ABI（桥的 JRE 要按 ABI 选分包）
  ///
  /// 走 `getprop`：`ro.product.cpu.abi` 是主 ABI，拿不到再读 `abilist` 挑一个支持的。
  /// 都问不出来返回 null（调用方报错让用户反馈，别瞎猜）
  static Future<String?> detectDeviceAbi() async {
    // 原生 Build.SUPPORTED_ABIS 最可靠；拿不到再退回 getprop
    try {
      final native = BridgePayload.pickSupportedAbi(
        await AndroidCall.getSupportedAbis(),
      );
      if (native != null) return native;
    } catch (_) {}
    const keys = ['ro.product.cpu.abi', 'ro.product.cpu.abilist'];
    for (final key in keys) {
      try {
        final result = await Process.run('getprop', [key]);
        if (result.exitCode != 0) continue;
        final abi = BridgePayload.pickSupportedAbi(
          '${result.stdout}'.split(','),
        );
        if (abi != null) return abi;
      } catch (_) {
        // 没有 getprop / 不允许执行：换下一个键，最后返回 null
      }
    }
    return null;
  }

  /// 读一遍运行环境的现状（给设置页看）：各项版本与占用空间
  ///
  /// 不联网、只读本地；[bridgeDirPath] 只为用例注入，正常走 [AppPaths.bridge]
  static Future<BridgeRuntimeStatus> readRuntimeStatus({
    String? bridgeDirPath,
  }) async {
    final rootPath = bridgeDirPath ?? AppPaths.bridge;

    final jreDir = Directory(p.join(rootPath, 'jre'));
    final bridgeJar = bridgeDirPath == null
        ? BridgePayload.installedBridgeJar()
        : BridgePayload.installedBridgeJar(directory: rootPath);
    final wrapperJar = File(
      p.join(
        rootPath,
        BridgePayload.loaderWrapperJarFileName(
          BridgePayload.loaderWrapperVersion,
        ),
      ),
    );
    final markerFile = File(p.join(jreDir.path, '.installed-version'));

    return BridgeRuntimeStatus(
      isReady: isRuntimeReady(bridgeDirPath: bridgeDirPath),
      jreVersion: markerFile.existsSync()
          ? markerFile.readAsStringSync().trim()
          : null,
      jreBytes: _sizeOf(jreDir.path),
      bridgeTag: bridgeJar == null
          ? null
          : BridgePayload.bridgeTagOf(bridgeJar.path),
      bridgeBytes: bridgeJar == null ? 0 : _sizeOf(bridgeJar.path),
      wrapperVersion: wrapperJar.existsSync()
          ? BridgePayload.loaderWrapperVersion
          : null,
      wrapperBytes: wrapperJar.existsSync() ? _sizeOf(wrapperJar.path) : 0,
    );
  }

  /// 清掉**与游戏版本无关**的那份载荷：JRE + 桥 jar + 适配层 + 临时目录
  ///
  /// 留着 arc 原生库（它按游戏版本的 arc ref 分目录，清了要按版本重下）；
  /// 清完 [isRuntimeReady] 会变 false，下次启动会重新走安装页。
  /// 桥会把载荷里的文件改成只读，Android 上删只读文件没问题（看目录写权限），
  /// 单个删不掉只记一条日志，不让整次清理失败
  static Future<void> clearRuntime({String? bridgeDirPath}) async {
    final rootPath = bridgeDirPath ?? AppPaths.bridge;

    _deleteQuietly(Directory(p.join(rootPath, 'jre')));
    _deleteQuietly(Directory(p.join(rootPath, 'tmp')));
    _deleteQuietly(File(p.join(rootPath, 'jre-version')));
    _deleteQuietly(File(p.join(rootPath, '.launcher-build')));

    final dir = Directory(rootPath);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final isBridgeJar = name.startsWith('bridge-');
      final isWrapperJar = name.startsWith('loader-wrapper-');
      if (isBridgeJar || isWrapperJar) _deleteQuietly(entity);
    }
  }

  /// 目录 / 文件占多少字节；不存在返回 0
  static int _sizeOf(String path) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      var total = 0;
      for (final entity in Directory(path).listSync(recursive: true)) {
        if (entity is File) {
          try {
            total += entity.lengthSync();
          } catch (_) {
            // 个别文件读不到（权限 / 正在被写）就跳过，别让整块统计失败
          }
        }
      }
      return total;
    }
    if (type == FileSystemEntityType.file) {
      try {
        return File(path).lengthSync();
      } catch (_) {
        return 0;
      }
    }
    return 0;
  }

  static void _deleteQuietly(FileSystemEntity entity) {
    try {
      if (entity.existsSync()) entity.deleteSync(recursive: true);
    } catch (error) {
      addLogAndPrint(
        .warning,
        '清理运行环境时删不掉 ${entity.path}：${removeNewlines('$error')}',
        tag: 'Bridge',
      );
    }
  }

  /// JRE：两个包（ABI 无关 + 该 ABI 的分包）都要，叠在同一棵树解压
  ///
  /// [pinnedBuild] 是设置里钉住的构建号（不给就跟随远端最新的 `version`）；
  /// [force] 为 true 时无条件重下
  static Future<void> _installJre({
    required String packageName,
    required String abi,
    String? pinnedBuild,
    bool force = false,
    CancelToken? cancelToken,
    void Function(String status)? onStatus,
    void Function(HttpDownloadState state)? onProgress,
  }) async {
    final jreDir = Directory(AppPaths.bridgeJre);
    final javaExe = File(p.join(jreDir.path, 'bin', 'java'));
    final moduleFile = File(p.join(jreDir.path, 'lib', 'modules'));
    final marker = File(jreVersionMarker);

    // 远端构建号：读不到就当「不用重装」（载荷是齐的，别为一次网络抖动重下几百 MB）
    String? remoteVersion;
    try {
      final urls = BridgePayload.jreAssetUrls(abi);
      final response = await cio.get<String>(
        urls.last,
        responseType: ResponseType.plain,
        cancelToken: cancelToken,
      );
      remoteVersion = '${response.data}'.trim();
    } catch (_) {}

    final localVersion = marker.existsSync()
        ? marker.readAsStringSync().trim()
        : null;
    final isReady = javaExe.existsSync() && moduleFile.existsSync();
    final targetVersion = pinnedBuild ?? remoteVersion;
    if (!force &&
        isReady &&
        !BridgePayload.shouldRefreshJre(
          localVersion: localVersion,
          remoteVersion: targetVersion,
        )) {
      onStatus?.call('Java 运行环境已就绪');
      return;
    }

    onStatus?.call('正在下载 Java 运行环境…');
    final tempDir = Directory(p.join(AppPaths.bridge, 'tmp'))
      ..createSync(recursive: true);
    final archivePaths = <String>[];
    for (final name in ['universal.tar.xz', 'bin-$packageName.tar.xz']) {
      final savePath = p.join(tempDir.path, name);
      await cio.download(
        url:
            'https://github.com/${BridgePayload.jreRepo}/releases/download/'
            '${BridgePayload.jreReleaseTag}/$name',
        savePath: savePath,
        cancelToken: cancelToken,
        onStatus: onProgress,
      );
      archivePaths.add(savePath);
    }

    // 换载荷先删旧文件：旧的已被桥改成只读，覆盖写不进去
    if (jreDir.existsSync()) jreDir.deleteSync(recursive: true);
    jreDir.createSync(recursive: true);

    onStatus?.call('正在解压 Java 运行环境…');
    for (final archivePath in archivePaths) {
      // 两个包都对着 JRE 根打的，直接叠在同一棵树
      await extractArchive(archivePath, jreDir.path);
      File(archivePath).deleteSync();
    }

    if (remoteVersion != null && remoteVersion.isNotEmpty) {
      marker.writeAsStringSync(remoteVersion);
    }
    addLogAndPrint(.info, 'Android 桥：Java 运行环境装好了（$abi）', tag: 'Bridge');
  }

  /// arc 原生库：按 ref + ABI 取进共享库目录，返回装好的文件名
  ///
  /// 名单先按**常规文件名**铺底（`libarc.so` / `libarc-freetype.so`），再尽力列一次
  /// 目录补上多出来的库 —— 列目录走 api，镜像节点常常不代理它（或共享 IP 被限流），
  /// 所以它失败只记一条警告，不能因此一个 `.so` 都不下
  ///
  /// 跟具体游戏版本走（v8 是该版本的 `archash`、v9 起是本体提交，见
  /// [BridgePayload.arcNativeLibUrl]），所以不在首次运行的安装页里做
  static Future<List<String>> installArcNatives({
    required String arcRef,
    required String abi,
    CancelToken? cancelToken,
    void Function(String status)? onStatus,
  }) async {
    final arcDir = Directory(AppPaths.bridgeArcDirPath(arcRef, abi));
    await arcDir.create(recursive: true);

    final names = <String>[];
    for (final module in BridgePayload.arcNativeModulesFor(arcRef)) {
      final moduleNames = <String>{
        ...BridgePayload.arcNativeDefaultLibs(module),
      };
      try {
        final body = await fetchJsonBody(
          BridgePayload.arcNativeContentsUrl(arcRef, abi, module: module),
        );
        moduleNames.addAll(BridgePayload.arcNativeLibNames(body));
      } catch (error) {
        addLogAndPrint(
          .warning,
          '列 arc 原生库失败（$module）：${removeNewlines('$error')}，按常规名单下',
          tag: 'Bridge',
        );
      }

      for (final name in moduleNames) {
        if (!names.contains(name)) names.add(name);
        final target = File(p.join(arcDir.path, name));
        // 已经在库里就直接复用；要重下时才删旧文件（旧的只读，覆盖写不进去）
        if (target.existsSync()) continue;
        onStatus?.call('正在下载 arc 原生库：$name');
        try {
          await cio.download(
            url: BridgePayload.arcNativeLibUrl(
              arcRef,
              abi,
              name,
              module: module,
            ),
            savePath: target.path,
            cancelToken: cancelToken,
          );
        } catch (error) {
          // 该 ref 里没有这个文件（404）不该拖垮整份安装：记一条，继续下一个
          names.remove(name);
          addLogAndPrint(
            .warning,
            'arc 原生库 $name 下载失败：${removeNewlines('$error')}',
            tag: 'Bridge',
          );
        }
      }
    }
    return names;
  }

  /// 装 loader-wrapper（走 mod 时才需要）：已装好就直接复用，否则按固定链接下
  ///
  /// 返回装好的 jar 路径；桌面 loader 缺失才返回 null（版本不一致只记日志，wrapper 自适配任意 loader 版本）
  static Future<String?> ensureLoaderWrapper({
    required String? desktopLoaderPath,
    CancelToken? cancelToken,
    void Function(String status)? onStatus,
  }) async {
    final target = File(BridgePayload.loaderWrapperJarFilePath());
    if (!target.existsSync()) {
      try {
        await installLoaderWrapper(
          cancelToken: cancelToken,
          onStatus: onStatus,
        );
      } catch (error) {
        // 下不到就按「不注入 loader」处理（调用方会按原版起），别把启动直接掀了
        addLogAndPrint(
          .warning,
          '模组加载器适配层下载失败：${removeNewlines('$error')}',
          tag: 'Bridge',
        );
        return null;
      }
    }

    // 没有桌面 loader 就没法注入（调用方按原版起）
    if (desktopLoaderPath == null) return null;

    final desktopLoaderVersion = LoaderLibrary.versionOf(
      File(desktopLoaderPath),
    );
    final wrapperLoaderVersion = await BridgeLauncher.wrapperLoaderVersionOf(
      target.path,
    );
    if (!BridgePayload.wrapperMatchesLoader(
      wrapperLoaderVersion: wrapperLoaderVersion,
      desktopLoaderVersion: desktopLoaderVersion,
    )) {
      addLogAndPrint(
        .warning,
        '模组加载器适配层版本不一致：适配层针对 loader '
        '${wrapperLoaderVersion ?? '（读不出）'}、当前 loader '
        '${desktopLoaderVersion ?? '（读不出）'}；wrapper 自适配任意 loader 版本，继续注入',
        tag: 'Bridge',
      );
    } else {
      addLogAndPrint(
        .info,
        'Android 桥：模组加载器适配层就绪（wrapper '
        '${BridgePayload.loaderWrapperVersion} ↔ loader $desktopLoaderVersion）',
        tag: 'Bridge',
      );
    }
    return target.path;
  }

  /// 桥自己的 jar：同一个版本已存在就直接复用（[force] 时删掉重下）
  static Future<void> _installBridgeJar({
    required String tag,
    bool force = false,
    CancelToken? cancelToken,
    void Function(String status)? onStatus,
    void Function(HttpDownloadState state)? onProgress,
  }) async {
    final target = File(BridgePayload.bridgeJarFilePath(tag));
    if (target.existsSync()) {
      if (!force) {
        onStatus?.call('桥已就绪：$tag');
        return;
      }
      // 旧的那份可能已被桥改成只读，重装先删掉
      try {
        target.deleteSync();
      } catch (error) {
        addLogAndPrint(
          .warning,
          '删旧的桥 jar 失败：${removeNewlines('$error')}',
          tag: 'Bridge',
        );
      }
    }

    onStatus?.call('正在下载桥（$tag）…');
    await target.parent.create(recursive: true);
    await cio.download(
      url: BridgePayload.bridgeJarUrl(tag: tag),
      savePath: target.path,
      cancelToken: cancelToken,
      onStatus: onProgress,
    );
    addLogAndPrint(.info, 'Android 桥：装好了 $tag', tag: 'Bridge');
  }
}

/// 运行环境的现状：给设置页展示用（版本号 + 占用空间）
class BridgeRuntimeStatus {
  const BridgeRuntimeStatus({
    required this.isReady,
    required this.jreVersion,
    required this.jreBytes,
    required this.bridgeTag,
    required this.bridgeBytes,
    required this.wrapperVersion,
    required this.wrapperBytes,
  });

  /// JRE 与桥 jar 都齐了（与 [BridgeInstaller.isRuntimeReady] 同口径）
  final bool isReady;

  /// JRE 的远端版本号（`.installed-version` 里记的），没装过为 null
  final String? jreVersion;
  final int jreBytes;

  /// 桥 jar 的 tag（`snapshot` / `0.1.3`…），没有为 null
  final String? bridgeTag;
  final int bridgeBytes;

  /// 模组加载器适配层的版本号，没装为 null
  final String? wrapperVersion;
  final int wrapperBytes;

  /// 三项加起来的占用
  int get totalBytes => jreBytes + bridgeBytes + wrapperBytes;
}
