import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/domain/bridge_payload.dart';
import 'package:copper_launcher/util/app_paths.dart';
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
  /// 首次运行的安装页只装它（arc 原生库跟着具体游戏版本走，见 [installArcNatives]）
  static Future<String> installRuntime({
    required String abi,
    String? bridgeTag,
    CancelToken? cancelToken,
    void Function(String status)? onStatus,
    void Function(HttpDownloadState state)? onProgress,
  }) async {
    final packageName = BridgePayload.jrePackageFor(abi);
    if (packageName == null) {
      throw StateError('不支持的设备 ABI：$abi（JRE 只有 arm64 / arm / x86_64 分包）');
    }

    var tag = bridgeTag;
    if (tag == null) {
      final latest = await fetchLatestBridge();
      if (latest == null) throw StateError('查不到桥的可用版本');
      tag = latest.tag;
    }

    await Directory(AppPaths.bridge).create(recursive: true);
    await _installJre(
      abi: abi,
      packageName: packageName,
      cancelToken: cancelToken,
      onStatus: onStatus,
      onProgress: onProgress,
    );
    await _installBridgeJar(
      tag: tag,
      cancelToken: cancelToken,
      onStatus: onStatus,
      onProgress: onProgress,
    );

    return tag;
  }

  /// 首次运行的「装没装完」检查（**不联网**）：JRE 两个包都在 + 桥 jar 在
  static bool isRuntimeReady() {
    final jreDir = Directory(AppPaths.bridgeJre);
    final hasJre =
        File(p.join(jreDir.path, 'bin', 'java')).existsSync() &&
        File(p.join(jreDir.path, 'lib', 'modules')).existsSync();
    return hasJre && BridgePayload.installedBridgeJar() != null;
  }

  /// 问设备自己是什么 ABI（桥的 JRE 要按 ABI 选分包）
  ///
  /// 走 `getprop`：`ro.product.cpu.abi` 是主 ABI，拿不到再读 `abilist` 挑一个支持的。
  /// 都问不出来返回 null（调用方报错让用户反馈，别瞎猜）
  static Future<String?> detectDeviceAbi() async {
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

  /// JRE：两个包（ABI 无关 + 该 ABI 的分包）都要，叠在同一棵树解压
  static Future<void> _installJre({
    required String packageName,
    required String abi,
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
    if (isReady &&
        !BridgePayload.shouldRefreshJre(
          localVersion: localVersion,
          remoteVersion: remoteVersion,
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
  /// 跟具体游戏版本走（该版本的 `archash`），所以不在首次运行的安装页里做
  static Future<List<String>> installArcNatives({
    required String arcRef,
    required String abi,
    CancelToken? cancelToken,
    void Function(String status)? onStatus,
  }) async {
    final arcDir = Directory(AppPaths.bridgeArcDir(arcRef, abi));
    await arcDir.create(recursive: true);

    final names = <String>[];
    for (final module in BridgePayload.arcNativeModules) {
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

  /// 桥自己的 jar：同一个版本已存在就直接复用
  static Future<void> _installBridgeJar({
    required String tag,
    CancelToken? cancelToken,
    void Function(String status)? onStatus,
    void Function(HttpDownloadState state)? onProgress,
  }) async {
    final target = File(BridgePayload.bridgeJarFilePath(tag));
    if (target.existsSync()) {
      onStatus?.call('桥已就绪：$tag');
      return;
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
