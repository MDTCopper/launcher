import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/core/app_paths.dart';
import 'package:copper_launcher/domain/bridge_library.dart';
import 'package:copper_launcher/util/version_strings.dart' as version_strings;
import 'package:path/path.dart' as p;

/// Android 桥的**载荷**：JRE / arc 原生库 / bridge.jar 从哪来、放哪、齐没齐
///
/// - **JRE 分两个包**（`universal.tar.xz` ABI 无关 + `bin-<abi>.tar.xz` ABI 相关），
///   两个都要叠加解压到同一棵树 —— 只解一个，JVM 起不来；release 按 Java 大版本
///   打 tag（`jre17` / `jre25`），安装与选择都按大版本走（见 [JreLibrary]）
/// - **arc 原生库必须与本体 jar 里的 arc 同一个 ref**：v8 及以前查该版本
///   `gradle.properties` 的 `archash`；v9 起 arc 并进本体仓库，原生库跟着本体提交走
///   （见 [arcNativeLibUrl]）
/// - **`bridge.jar` 一个包三种 ABI 都有**，不用按设备分；`snapshot` 是固定链接，想钉版本就给 tag
class BridgePayload {
  BridgePayload._();

  /// Android JRE 的仓库：release 按 **Java 大版本** 打 tag（`jre17` / `jre25`）
  static const jreRepo = 'MDTCopper/android-openjdk';

  /// JRE release tag 的前缀：`jre` + Java 大版本
  static const jreTagPrefix = 'jre';

  /// 某个 Java 大版本对应的 release tag
  static String jreTagFor(String version) => '$jreTagPrefix$version';

  /// `jre25` → `25`；不是 JRE tag 返回 null
  static String? jreVersionOfTag(String tag) =>
      RegExp('^$jreTagPrefix(\\d+)\$').firstMatch(tag.trim())?.group(1);

  /// tag 列表里的 Java 大版本（去重、降序，最新在前）
  static List<String> jreVersionsOfTags(Iterable<String> tags) {
    final versions = <String>{};
    for (final tag in tags) {
      final version = jreVersionOfTag(tag);
      if (version != null) versions.add(version);
    }
    return versions.toList()
      ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));
  }

  /// tag 列表里最新的 Java 大版本
  static String? latestJreVersionOfTags(Iterable<String> tags) {
    final versions = jreVersionsOfTags(tags);
    return versions.isEmpty ? null : versions.first;
  }

  /// 桥的仓库
  static const bridgeRepo = 'MDTCopper/android-bridge';

  /// loader-wrapper 的仓库与**钉住的版本**（Android 走 mod 时注入 loader 用）
  ///
  /// wrapper 是薄适配器：把桥给的 classpath 转成 CopperLoader 的命令行。
  /// **运行期不检查它和 loader / 游戏版本是否匹配**：wrapper 自适配任意 loader 版本，
  /// 只要桌面 loader jar 在就注入
  static const loaderWrapperRepo = 'MDTCopper/loader-wrapper';
  static const loaderWrapperVersion = '0.1.0';

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

  /// 某个 Java 大版本的两个包：ABI 无关包 + 该 ABI 的分包（叠加解压到同一棵树）
  static List<({String name, String url})> jreAssets(
    String version,
    String abi,
  ) {
    final packageName = jrePackageFor(abi);
    if (packageName == null) return const [];
    final base =
        'https://github.com/$jreRepo/releases/download/${jreTagFor(version)}';
    return [
      (name: 'universal.tar.xz', url: '$base/universal.tar.xz'),
      (name: 'bin-$packageName.tar.xz', url: '$base/bin-$packageName.tar.xz'),
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

  /// 已装好的桥 jar（用哪一份由 [BridgeLibrary.selectedBridgeJar] 决定：
  /// 钉住的版本优先，没钉才挑最新）；一份都没装返回 null
  ///
  /// 首次运行的「装没装完」检查用它 —— 那一刻还不知道该用哪个 tag，所以按目录里现成的找
  static File? installedBridgeJar({String? directory}) =>
      BridgeLibrary.selectedBridgeJar(bridgeDirPath: directory);

  /// `.../bridge-0.1.3.jar` → `0.1.3`、`.../bridge-snapshot.jar` → `snapshot`；
  /// 命名不对返回 null
  static String? bridgeTagOf(String jarPath) =>
      _bridgeJarPattern.firstMatch(p.basename(jarPath))?.group(1);

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
  /// 仓库里的路径是 `natives/<模块>/libs/<abi>/` —— **那个 `natives/` 前缀不能少**；
  /// v9 起 freetype 并进 `libarc.so`，只剩 `natives-android` 一个模块
  static const arcNativeModules = [
    'natives-android',
    'natives-freetype-android',
  ];

  /// v105–v126.2 的 box2d 还单独占一个 natives 模块；v127 起不再带这份库
  static const arcBox2dNativeModule = 'natives-box2d-android';

  /// GDX 时代（Mindustry v33–v104.6）的 Android 原生库仓库
  ///
  /// 这些版本直接用 libGDX 的 Android 包，原生库不来自 Arc 仓库；各版本线的
  /// release zip 由 `MDTCopper/android-gdx` 按 `libgdx-<版本>-android.zip` 提供，
  /// 解压后就是 `armeabi/`、`arm64-v8a/` 这类 ABI 目录。
  static const gdxRepo = 'MDTCopper/android-gdx';

  /// GDX zip 里每个 ABI 目录下需要的文件
  static const gdxAndroidLibNames = ['libgdx.so', 'libgdx-freetype.so'];

  /// GDX 三个版本线：v33–v57 用 1.9.8，v65–v82.x 用 1.9.9，v83–v104.6 用 1.9.10
  static const gdxVersion198 = '1.9.8';
  static const gdxVersion199 = '1.9.9';
  static const gdxVersion1910 = '1.9.10';

  /// GDX 原生库的 release zip 地址
  static String gdxAndroidZipUrl(String version) =>
      'https://github.com/$gdxRepo/releases/download/$version/'
      'libgdx-$version-android.zip';

  /// GDX 库目录的 ref：和 arc ref 共用 `bridge/arc/<ref>/<abi>` 这套落点
  static String gdxRef(String version) => 'gdx-$version';

  /// 这个版本是不是 GDX 时代、该用哪版 GDX；不是返回 null
  ///
  /// 范围来自原生库归档表：
  /// - 正式版 33–57 → 1.9.8；65.0–82.x → 1.9.9；83.0–104.6 → 1.9.10
  /// - BE 4975–8090 → 1.9.10（1.9.9 没有可用 BE 归档）
  ///
  /// 范围外（BE 4975 之前）仍按老的 arc 查询流程走，保持原行为
  static String? gdxVersionFor({required double build, required bool isBe}) {
    if (build <= 0) return null;
    if (isBe) {
      return build >= 4975 && build <= 8090 ? gdxVersion1910 : null;
    }
    if (build >= 33 && build <= 57) return gdxVersion198;
    if (build >= 65 && build < 83) return gdxVersion199;
    if (build >= 83 && build < 105) return gdxVersion1910;
    return null;
  }

  /// arc 时代要不要额外装 `libarc-box2d.so`
  ///
  /// 正式版 105.0–126.2、BE 8108–21312 带 box2d；v127 / BE 21313 起不再有这一份
  static bool arcNeedsBox2d({required double build, required bool isBe}) {
    if (build <= 0) return false;
    if (isBe) return build >= 8108 && build <= 21312;
    return build >= 105 && build <= 126.2;
  }

  /// v9 起 arc 并入本体仓库：ref 记成 `mindustry-<提交或 tag>`，原生库也从本体仓库取
  ///
  /// 老版本仍是 Anuken/Arc 仓库的一份 `archash`；两种 ref 在 [arcNativeLibUrl] 里分流
  static const arcMergedRefPrefix = 'mindustry-';

  /// 把本体的提交 / tag 包成 arc ref
  static String mergedArcRef(String revision) => '$arcMergedRefPrefix$revision';

  /// 这个 ref 是不是 v9 起的合并形态
  static bool isMergedArcRef(String arcRef) =>
      arcRef.startsWith(arcMergedRefPrefix);

  /// 合并形态的 ref 里取回本体提交 / tag
  static String mergedArcRevision(String arcRef) =>
      arcRef.substring(arcMergedRefPrefix.length);

  /// 这个 ref 要装哪些 natives 模块
  ///
  /// v9 的 `arc/natives` 只有 `natives-android`；老版本两个模块都要。
  /// [includeBox2d] 由调用方按**游戏版本**给（v105–v126.2 才多这份库），
  /// 合并形态的 ref 里没有独立 box2d 模块，给了也不加。
  static List<String> arcNativeModulesFor(
    String arcRef, {
    bool includeBox2d = false,
  }) => [
    ...(isMergedArcRef(arcRef) ? const ['natives-android'] : arcNativeModules),
    if (includeBox2d && !isMergedArcRef(arcRef)) arcBox2dNativeModule,
  ];

  /// arc 原生库所在仓库
  static String _arcRepo(String arcRef) =>
      isMergedArcRef(arcRef) ? 'Anuken/Mindustry' : 'Anuken/Arc';

  /// 仓库里的 ref：合并形态要剥掉 `mindustry-` 前缀
  static String _arcUrlRef(String arcRef) =>
      isMergedArcRef(arcRef) ? mergedArcRevision(arcRef) : arcRef;

  /// 仓库里的目录：v9 在 `arc/natives/` 下，老版本在根部的 `natives/` 下
  static String _arcNativeDirPath(String arcRef, String abi, String module) =>
      isMergedArcRef(arcRef)
      ? 'arc/natives/$module/libs/$abi'
      : 'natives/$module/libs/$abi';

  /// 各模块里那份原生库的**常规文件名**：列目录用不了时按它下
  ///
  /// 列目录走 GitHub contents API，镜像节点常常不代理 api 或共享 IP 被限流 ——
  /// 所以「列目录」只当**补充**，常规名单才是保底（列目录成功时会补上多出来的库）
  static List<String> arcNativeDefaultLibs(String module) => switch (module) {
    'natives-freetype-android' => const ['libarc-freetype.so'],
    'natives-box2d-android' => const ['libarc-box2d.so'],
    _ => const ['libarc.so'],
  };

  /// 列某个模块 / ABI 下有哪些文件（GitHub contents API）
  static String arcNativeContentsUrl(
    String arcRef,
    String abi, {
    String module = 'natives-android',
  }) =>
      'https://api.github.com/repos/${_arcRepo(arcRef)}/contents/'
      '${_arcNativeDirPath(arcRef, abi, module)}?ref=${_arcUrlRef(arcRef)}';

  /// 单个原生库的下载地址（raw，按 ref 钉死）
  static String arcNativeLibUrl(
    String arcRef,
    String abi,
    String fileName, {
    String module = 'natives-android',
  }) =>
      'https://raw.githubusercontent.com/${_arcRepo(arcRef)}/'
      '${_arcUrlRef(arcRef)}/${_arcNativeDirPath(arcRef, abi, module)}/$fileName';

  /// 查某个游戏版本的 `gradle.properties`
  ///
  /// v8 及以前里面有 `archash`（指到 `Anuken/Arc` 的提交）；v9 起这个键没了，
  /// 因为 arc 已并进本体仓库（原生库跟着同一个提交 / tag 走）
  ///
  /// **走 raw 地址，不用 `github.com/.../raw/...` 那种重定向形式**：后者要多一跳、
  /// 而且有节点不代理它（回 404，还会被当成「上游说没有」而不换节点）
  static String arcRefUrlForTag(String versionTag) =>
      'https://raw.githubusercontent.com/Anuken/Mindustry/refs/tags/$versionTag/gradle.properties';

  /// 按 commit 查同一份文件（BE 构建没有 Mindustry tag 时用）
  static String arcRefUrlForCommit(String commit) =>
      'https://raw.githubusercontent.com/Anuken/Mindustry/$commit/gradle.properties';

  /// 从 `gradle.properties` 里读 `archash`（纯函数）
  ///
  /// 那是 java properties 格式：`key=value`，`#` / `!` 起头是注释；读不到返回 null
  /// （v9 起恒为 null，不是错误）
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
  ///
  /// [jreDirPath] 由调用方从 `JreLibrary.selectedJreRoot()` 取：JRE 按 Java 大版本分目录，
  /// 这里不替它做选择
  static BridgePayloadPaths pathsFor({
    required String abi,
    required String arcRef,
    required List<String> arcLibNames,
    required String jreDirPath,
    String? bridgeTag,
  }) {
    final jarName = bridgeJarFileName(bridgeTag ?? bridgeSnapshot);
    return BridgePayloadPaths(
      jreDirPath: jreDirPath,
      arcDirPath: AppPaths.bridgeArcDirPath(arcRef, abi),
      bridgeJar: AppPaths.bridgeJarFile(jarName),
      arcLibNames: arcLibNames,
    );
  }
}

/// 一个游戏版本的原生库获取方案
///
/// GDX 时代（v33–v104.6）从 `android-gdx` 的 release zip 取 `libgdx.so` /
/// `libgdx-freetype.so`；arc 时代仍按 arc ref 从 GitHub 仓库取（v105–v126.2 多一份
/// `libarc-box2d.so`）。两种来源共用 [AppPaths.bridgeArcDirPath] 这套落点，
/// 目录名用 [ref] 区分，桥只负责把目录里的 `.so` 按原文件名交给 arc。
class NativeLibPlan {
  const NativeLibPlan._({
    required this.ref,
    this.gdxVersion,
    this.arcRef,
    this.includeBox2d = false,
  });

  /// GDX 方案：`gdx-<版本>`
  factory NativeLibPlan.gdx(String version) =>
      NativeLibPlan._(ref: BridgePayload.gdxRef(version), gdxVersion: version);

  /// arc 方案：目录名就是 arc ref
  factory NativeLibPlan.arc(String arcRef, {bool includeBox2d = false}) =>
      NativeLibPlan._(ref: arcRef, arcRef: arcRef, includeBox2d: includeBox2d);

  /// 库目录名：GDX 是 `gdx-<版本>`，arc 就是 arc ref
  final String ref;

  /// 非 null 表示走 GDX 的 release zip
  final String? gdxVersion;

  /// 非 null 表示走 arc 仓库
  final String? arcRef;

  /// arc 时代是否额外取 box2d（v105–v126.2 / 对应 BE 区间）
  final bool includeBox2d;

  bool get isGdx => gdxVersion != null;
}

/// 载荷在磁盘上的落点 + 「齐没齐」的检查
class BridgePayloadPaths {
  const BridgePayloadPaths({
    required this.jreDirPath,
    required this.arcDirPath,
    required this.bridgeJar,
    required this.arcLibNames,
  });

  /// JRE 根（`universal` 与 `bin-<abi>` 两个包叠加解压到这里）
  final String jreDirPath;

  /// 该 arc ref / ABI 的原生库目录（要给桥，且**必须可写**）
  final String arcDirPath;

  /// 桥自己的 jar
  final String bridgeJar;

  /// 这次要摆进 [arcDirPath] 的原生库文件名
  final List<String> arcLibNames;

  /// `--java` 要的是 `<jre>/bin/java`
  String get javaExe => p.join(jreDirPath, 'bin', 'java');

  /// 缺哪些文件（空列表 = 齐了）
  ///
  /// `bin/java` 来自 ABI 分包、`lib/modules` 来自 ABI 无关包 —— 两个都查，
  /// 才能验出「只解了一个包」这种半成品
  List<String> missingFiles() => [
    if (!File(javaExe).existsSync()) javaExe,
    if (!File(p.join(jreDirPath, 'lib', 'modules')).existsSync())
      p.join(jreDirPath, 'lib', 'modules'),
    if (!File(bridgeJar).existsSync()) bridgeJar,
    for (final name in arcLibNames)
      if (!File(p.join(arcDirPath, name)).existsSync())
        p.join(arcDirPath, name),
  ];
}
