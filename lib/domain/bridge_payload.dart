import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/version_strings.dart' as version_strings;
import 'package:path/path.dart' as p;

/// Android 桥的**载荷**：JRE / arc 原生库 / bridge.jar 从哪来、放哪、齐没齐
///
/// 全部按《android-bridge 使用文档》§3 的口径：
/// - **JRE 分两个包**（`universal.tar.xz` ABI 无关 + `bin-<abi>.tar.xz` ABI 相关），
///   两个都要叠加解压到同一棵树 —— 只解一个，JVM 起不来
/// - **arc 原生库必须与本体 jar 里的 arc 同一个 ref**（该版本 `gradle.properties` 的
///   `archash`）：对不上往往不是启动就炸，而是第一次用到才炸
/// - **`bridge.jar` 一个包三种 ABI 都有**，不用按设备分；`snapshot` 是固定链接，想钉版本就给 tag
class BridgePayload {
  BridgePayload._();

  /// Android JRE 的仓库与 release（`jre25` = JDK 25）
  static const jreRepo = 'MDTCopper/android-openjdk';
  static const jreReleaseTag = 'jre25';

  /// 桥的仓库
  static const bridgeRepo = 'MDTCopper/android-bridge';

  /// loader-wrapper 的仓库与**钉住的版本**（Android 走 mod 时注入 loader 用）
  ///
  /// wrapper 是薄适配器：把桥给的 classpath 转成 CopperLoader 的命令行。它按
  /// `loaderVersion` 编译，**那份 loader 桌面 jar 运行期必须在**，版本也要与它一致
  static const loaderWrapperRepo = 'MDTCopper/loader-wrapper';
  static const loaderWrapperVersion = '0.1.0';

  /// 这份 wrapper 编译时针对的 loader 版本（jar 里 `wrapper-version.properties` 的
  /// `loaderVersion`）；装了别的 loader 版本时要重新编 wrapper
  static const loaderWrapperLoaderVersion = '0.2.0';

  /// wrapper 的主类：桥用 `--main` 指定它接管启动（桥自己的选项，不是位置参数）
  static const wrapperMainClass = 'copper.wrapper.Main';

  /// 快照 release：资产固定叫 `bridge-snapshot.jar`，每次 push 都重建
  static const bridgeSnapshot = 'snapshot';

  /// 桥支持的设备 ABI（与载荷对齐）
  static const supportedAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

  /// 设备 ABI → JRE 的 ABI 分包名；`x86` 没有（JDK 25 不提供），返回 null
  static String? jrePackageFor(String abi) => switch (abi) {
    'arm64-v8a' => 'arm64',
    'armeabi-v7a' => 'arm',
    'x86_64' => 'x86_64',
    _ => null,
  };

  /// JRE 的下载地址：ABI 无关包、该 ABI 的分包、版本号文件（纯数字构建号，判断要不要重下）
  static List<String> jreAssetUrls(String abi) {
    final packageName = jrePackageFor(abi);
    if (packageName == null) return const [];
    final base =
        'https://github.com/$jreRepo/releases/download/$jreReleaseTag';
    return [
      '$base/universal.tar.xz',
      '$base/bin-$packageName.tar.xz',
      '$base/version',
    ];
  }

  /// 桥 jar 的下载地址：不给 [tag] 就是快照（固定链接，不用查 API）
  static String bridgeJarUrl({String? tag}) {
    final name = tag ?? bridgeSnapshot;
    return 'https://github.com/$bridgeRepo/releases/download/$name/bridge-$name.jar';
  }

  /// 桥 jar 的库内文件名：`bridge-<tag>.jar`（快照就是 `bridge-snapshot.jar`）
  static String bridgeJarFileName(String tag) => 'bridge-$tag.jar';

  /// 桥 jar 的库内路径（共享库目录，跨版本复用）
  static String bridgeJarFilePath(String tag) =>
      AppPaths.bridgeJarFile(bridgeJarFileName(tag));

  /// wrapper jar 的下载地址：与桥同套路 —— `releases/download/<版本>/loader-wrapper-<版本>.jar`
  static String loaderWrapperJarUrl({String? version}) {
    final tag = version ?? loaderWrapperVersion;
    return 'https://github.com/$loaderWrapperRepo/releases/download/$tag/'
        'loader-wrapper-$tag.jar';
  }

  /// wrapper jar 的库内文件名
  static String loaderWrapperJarFileName(String version) =>
      'loader-wrapper-$version.jar';

  /// wrapper jar 的库内路径（与桥、JRE 同一层共享库目录）
  static String loaderWrapperJarFilePath({String? version}) =>
      AppPaths.bridgeJarFile(
        loaderWrapperJarFileName(version ?? loaderWrapperVersion),
      );

  /// wrapper 能不能配这个 loader 版本用：jar 里记的 `loaderVersion` 要与桌面 jar 一致
  ///
  /// 对不上就是「wrapper 编的时候针对另一版 loader」——运行期 classpath 会错，宁可不起
  static bool wrapperMatchesLoader({
    required String? wrapperLoaderVersion,
    required String? desktopLoaderVersion,
  }) {
    if (wrapperLoaderVersion == null || desktopLoaderVersion == null) {
      return false;
    }
    return wrapperLoaderVersion.trim() == desktopLoaderVersion.trim();
  }

  /// 已装好的桥 jar（库里**版本最高**的那个）；一个都没有返回 null
  ///
  /// 首次运行的「装没装完」检查用它 —— 那一刻还不知道该用哪个 tag，所以按目录里现成的找
  static File? installedBridgeJar({String? directory}) {
    final bridgeDir = Directory(directory ?? AppPaths.bridge);
    if (!bridgeDir.existsSync()) return null;
    final jars = [
      for (final entity in bridgeDir.listSync())
        if (entity is File && _bridgeJarPattern.hasMatch(p.basename(entity.path)))
          entity,
    ];
    if (jars.isEmpty) return null;
    jars.sort(
      (a, b) => compareVersionTags(bridgeTagOf(b.path), bridgeTagOf(a.path)),
    );
    return jars.first;
  }

  /// `.../bridge-0.1.3.jar` → `0.1.3`、`.../bridge-snapshot.jar` → `snapshot`；
  /// 命名不对返回 null
  static String? bridgeTagOf(String jarPath) => _bridgeJarPattern
      .firstMatch(p.basename(jarPath))
      ?.group(1);

  static final RegExp _bridgeJarPattern = RegExp(
    r'^bridge-(\d+(?:\.\d+)*|snapshot)\.jar$',
  );

  /// 比两个版本号（桥取最新一版、库里挑最新 jar 都用它）
  static int compareVersionTags(String? a, String? b) =>
      version_strings.compareVersion(a, b);

  /// 从设备给的 ABI 候选里挑一个我们支持的（按候选顺序，通常第一个就是主 ABI）
  ///
  /// `ro.product.cpu.abilist` 那种逗号列表也走它：挑第一个能对上 JRE 分包的
  static String? pickSupportedAbi(Iterable<String> candidates) {
    for (final candidate in candidates) {
      final abi = candidate.trim();
      if (supportedAbis.contains(abi)) return abi;
    }
    return null;
  }

  /// arc 原生库所在的 natives 模块（库的**名单**按 ref 走，模块名这里是结构常量）
  ///
  /// 仓库里的路径是 `natives/<模块>/libs/<abi>/` —— **那个 `natives/` 前缀不能少**，
  /// 少了就是 404（文档 §3.3 的地址里都有）
  static const arcNativeModules = [
    'natives-android',
    'natives-freetype-android',
  ];

  /// 各模块里那份原生库的**常规文件名**：列目录用不了时按它下
  ///
  /// 列目录走 GitHub contents API，镜像节点常常不代理 api 或共享 IP 被限流
  /// （真机实测三家里两家空回、一家 `API rate limit exceeded`）—— 所以「列目录」
  /// 只当**补充**，常规名单才是保底（真要少一个文件，列目录成功时会补上）
  static List<String> arcNativeDefaultLibs(String module) =>
      module == 'natives-freetype-android'
      ? const ['libarc-freetype.so']
      : const ['libarc.so'];

  /// 列某个模块 / ABI 下有哪些文件（GitHub contents API）
  static String arcNativeContentsUrl(
    String arcRef,
    String abi, {
    String module = 'natives-android',
  }) =>
      'https://api.github.com/repos/Anuken/Arc/contents/natives/$module/libs/$abi?ref=$arcRef';

  /// 单个原生库的下载地址（raw，按 ref 钉死）
  static String arcNativeLibUrl(
    String arcRef,
    String abi,
    String fileName, {
    String module = 'natives-android',
  }) =>
      'https://raw.githubusercontent.com/Anuken/Arc/$arcRef/natives/$module/libs/$abi/$fileName';

  /// 查某个游戏版本用的是哪个 arc：Mindustry 的 `gradle.properties` 里的 `archash`
  /// （必须与本体 jar 里的 arc 同源，见文档 §3.3）
  static String arcRefUrlForTag(String versionTag) =>
      'https://github.com/Anuken/Mindustry/raw/refs/tags/$versionTag/gradle.properties';

  /// 按 commit 查同一份文件（BE 构建没有 Mindustry tag 时用）
  static String arcRefUrlForCommit(String commit) =>
      'https://github.com/Anuken/Mindustry/raw/$commit/gradle.properties';

  /// 从 `gradle.properties` 里读 `archash`（纯函数）
  ///
  /// 那是 java properties 格式：`key=value`，`#` / `!` 起头是注释；读不到返回 null
  static String? parseArchash(String? content) =>
      propertyValue(content, 'archash');

  /// 本体 jar 里 `version.properties` 的 `commitHash`：**编这份本体用的 Mindustry 提交**
  ///
  /// 比按 tag 查更准：BE（自构建）版本没有 Mindustry tag，`release` 记的是构建号；
  /// 官方版本两个都能查，但提交就是这份 jar 的来源，一条路走通两种版本（文档 §3.3）
  static String? parseCommitHash(String? content) =>
      propertyValue(content, 'commitHash');

  /// 读 java properties 文本里的某个键（`key=value`，`#` / `!` 起头是注释）
  static String? propertyValue(String? content, String key) {
    if (content == null) return null;
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
        continue;
      }
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      if (line.substring(0, separator).trim() != key) continue;
      final value = line.substring(separator + 1).trim();
      return value.isEmpty ? null : value;
    }
    return null;
  }

  /// 从 tag 列表里挑最新一版（版本号形态的 tag，如 `0.1.3`）
  ///
  /// 用 git ref 广告就能拿到的形态，不吃 GitHub API 额度（对照 loader 那套）
  static String? newestVersionTag(List<String> tags) {
    final versionTags = [
      for (final tag in tags)
        if (_versionTagPattern.hasMatch(tag.trim())) tag.trim(),
    ]..sort((a, b) => version_strings.compareVersion(b, a));
    return versionTags.isEmpty ? null : versionTags.first;
  }

  static final RegExp _versionTagPattern = RegExp(r'^\d+(\.\d+)*$');

  /// JRE 要不要重新解压装一遍：本地没记过版本、或远端 `version` 文件变了就要
  ///
  /// （远端读不到时按「不用重装」处理 —— 载荷齐就能跑，别因为一次网络抖动重下几百 MB）
  static bool shouldRefreshJre({
    required String? localVersion,
    required String? remoteVersion,
  }) {
    if (localVersion == null || localVersion.isEmpty) return true;
    if (remoteVersion == null || remoteVersion.isEmpty) return false;
    return localVersion != remoteVersion;
  }

  /// 从 contents API 的返回里挑出原生库文件名（`lib*.so`）
  ///
  /// **不写死成「两个」**：某个 arc ref 多一个库时，列出来就能一起下
  static List<String> arcNativeLibNames(Object? body) {
    final Object? decoded;
    try {
      // 取回来可能是字符串（镜像常常不是 JSON content-type），也可能已经被上层解好
      decoded = body is String ? jsonDecode(body) : body;
    } catch (_) {
      // 内容不是 JSON（镜像回了 HTML 错误页之类）：当「一个库都没列出来」，
      // 交给调用方判失败，别把解析异常抛到 UI 层
      return const [];
    }
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map && item['name'] is String)
          if ('${item['name']}'.endsWith('.so')) '${item['name']}',
    ];
  }

  /// 这份载荷的落点（都在共享库 `<数据根>/bridge/` 下，跨版本复用）
  static BridgePayloadPaths pathsFor({
    required String abi,
    required String arcRef,
    required List<String> arcLibNames,
    String? bridgeTag,
  }) {
    final jarName = bridgeJarFileName(bridgeTag ?? bridgeSnapshot);
    return BridgePayloadPaths(
      jreDir: AppPaths.bridgeJre,
      arcDir: AppPaths.bridgeArcDir(arcRef, abi),
      bridgeJar: AppPaths.bridgeJarFile(jarName),
      arcLibNames: arcLibNames,
    );
  }
}

/// 载荷在磁盘上的落点 + 「齐没齐」的检查
class BridgePayloadPaths {
  const BridgePayloadPaths({
    required this.jreDir,
    required this.arcDir,
    required this.bridgeJar,
    required this.arcLibNames,
  });

  /// JRE 根（`universal` 与 `bin-<abi>` 两个包叠加解压到这里）
  final String jreDir;

  /// 该 arc ref / ABI 的原生库目录（要给桥，且**必须可写**）
  final String arcDir;

  /// 桥自己的 jar
  final String bridgeJar;

  /// 这次要摆进 [arcDir] 的原生库文件名
  final List<String> arcLibNames;

  /// `--java` 要的是 `<jre>/bin/java`
  String get javaExe => p.join(jreDir, 'bin', 'java');

  /// 缺哪些文件（空列表 = 齐了）
  ///
  /// `bin/java` 来自 ABI 分包、`lib/modules` 来自 ABI 无关包 —— 两个都查，
  /// 才能验出「只解了一个包」这种半成品
  List<String> missingFiles() => [
    if (!File(javaExe).existsSync()) javaExe,
    if (!File(p.join(jreDir, 'lib', 'modules')).existsSync())
      p.join(jreDir, 'lib', 'modules'),
    if (!File(bridgeJar).existsSync()) bridgeJar,
    for (final name in arcLibNames)
      if (!File(p.join(arcDir, name)).existsSync()) p.join(arcDir, name),
  ];
}
