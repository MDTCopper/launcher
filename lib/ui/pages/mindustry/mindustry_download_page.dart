import 'dart:convert';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/data/net/mindustry/mindustry_release_manifest.dart';
import 'package:copper_launcher/data/net/mindustry/mindustry_release_list_snapshot.dart';
import 'package:copper_launcher/domain/loader_library.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/dialog/loader_picker_dialog.dart';
import 'package:copper_launcher/ui/components/animation/animated_expansion.dart';
import 'package:copper_launcher/ui/components/button/capsule_action_bar.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';

import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/path_selector.dart';
import 'package:copper_launcher/util/io/remote_data.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_config.dart';
import '../../../core/app_constant.dart';
import '../../../domain/task_manager.dart';
import '../../../domain/tasks/mindustry_download_task.dart';
import '../../../util/mindustry_major_version.dart';
import '../../../util/validate/windows_file_name_validator.dart';

import '../../vars.dart';

class MindustryDownloadPage extends StatefulWidget {
  const MindustryDownloadPage({super.key});

  @override
  State<StatefulWidget> createState() => _MindustryDownloadPageState();
}

class _MindustryDownloadPageState extends State<MindustryDownloadPage> {
  static final List<MindustryRelease> _versionList = [];

  /// 最新 be；拿不到（网络 / 限流）时为 null，页面不显示该入口
  static MindustryRelease? _latestBeta;

  /// 当前这份列表是按哪个来源策略拉的：设置里改了策略就得重拉
  static BodySourceStrategy? _versionListSource;

  /// 列表只在这里建一次 future，手动刷新才重建；
  /// 若写在 build 里，任何 setState 都会让 FutureBuilder 回到 waiting、列表闪加载圈
  late Future<bool> _versionFuture = _fetchVersionAssets();

  /// 版本列表：来源策略决定列表从哪来，保证列出来的版本都下得动
  ///
  /// - 只用国内源：只列国内源有的版本 —— 不合快照，快照里的老版本（v125.1 及以下）
  ///   国内源没有，列出来选中也是没有可用下载来源
  /// - 只用官方源：完全不碰国内主机，列表走官方 API，失败退快照
  /// - 优先两档：国内 manifest 优先，失败退官方 API，再与快照合并补老版本
  Future<bool> _fetchVersionAssets() async {
    final bodySource = config.setting.downloadOptions.bodySource;

    //列表是按来源策略拉的：策略没变、列表还在，就直接用缓存
    if (_versionList.isNotEmpty && _versionListSource == bodySource) {
      return true;
    }
    _versionList.clear();
    _latestBeta = null;
    _versionListSource = bodySource;

    final snapshot = MindustryReleaseListSnapshot.parse(
      await RemoteData.load(mindustryVersionsFile),
    );
    final isDomesticOnly = bodySource == BodySourceStrategy.domesticOnly;

    List<MindustryRelease> latest;
    if (isDomesticOnly) {
      try {
        latest = await _fetchManifestReleases();
      } catch (e) {
        addLogAndPrint(
          .warning,
          '国内源版本列表拿不到：${removeNewlines('$e')}',
          tag: 'MindustryDownload',
        );
        latest = const [];
      }
      _versionList
        ..clear()
        ..addAll(latest);
    } else if (bodySource == BodySourceStrategy.githubOnly) {
      try {
        latest = await _fetchLatestReleases();
      } catch (e) {
        addLogAndPrint(
          .warning,
          '获取最新版本列表失败，只列快照里的版本：${removeNewlines('$e')}',
          tag: 'MindustryDownload',
        );
        latest = const [];
      }
      _versionList
        ..clear()
        ..addAll(MindustryReleaseListSnapshot.merge(snapshot, latest));
    } else {
      try {
        latest = await _fetchManifestReleases();
      } catch (e) {
        addLogAndPrint(
          .warning,
          '国内源版本列表拿不到，退 GitHub API：${removeNewlines('$e')}',
          tag: 'MindustryDownload',
        );
        try {
          latest = await _fetchLatestReleases();
        } catch (e) {
          addLogAndPrint(
            .warning,
            '获取最新版本列表失败，只列快照里的版本：${removeNewlines('$e')}',
            tag: 'MindustryDownload',
          );
          latest = const [];
        }
      }
      _versionList
        ..clear()
        ..addAll(MindustryReleaseListSnapshot.merge(snapshot, latest));
    }

    //be 的 build 太多，只取最新一条，其余走「下载指定 build」；
    //国内 manifest 里没有 BE，只用国内源时这段整个不显示
    if (isDomesticOnly) {
      _latestBeta = null;
    } else {
      try {
        _latestBeta = await _fetchLatestBeta();
      } catch (e) {
        addLogAndPrint(
          .warning,
          '获取最新 be 版本失败：${removeNewlines('$e')}',
          tag: 'MindustryDownload',
        );
        _latestBeta = null;
      }
    }
    return _versionList.isNotEmpty;
  }

  /// 取国内源的版本清单（一次拿全量，本体地址也直接指向它）
  Future<List<MindustryRelease>> _fetchManifestReleases() async {
    final response = await cio.get<String>(
      mindustryManifestUrl,
      responseType: ResponseType.plain,
    );
    return parseMindustryManifest(response.data ?? '');
  }

  /// 取官方最新一页 release（一页 100 条，够覆盖新版本）
  Future<List<MindustryRelease>> _fetchLatestReleases() async {
    final releases = await _fetchReleaseArray(
      '$githubMindustryUrl?per_page=$mindustryVersionPageSize',
    );
    return [
      for (final release in releases)
        MindustryRelease.fromGithubJson(release as Map<String, dynamic>),
    ];
  }

  Future<MindustryRelease> _fetchLatestBeta() async {
    final releases = await _fetchReleaseArray('$githubBeUrl?per_page=1');
    return MindustryRelease.fromGithubJson(
      releases.first as Map<String, dynamic>,
    );
  }

  /// 取 release 数组，防御式解析。
  ///
  /// 不能直接用 `cio.get<List<dynamic>>`：dio 只在响应 content-type 是 JSON 时
  /// 才 `jsonDecode`，而镜像节点回包有时带非 json 的 content-type（或直接是 HTML
  /// 错误页）——此时 data 是 String，强转就会抛
  /// `type 'String' is not a subtype of type 'List<dynamic>?'`。这里拿原始串自己
  /// 解析，内容不对抛清晰错误（调用方回退快照）
  Future<List<dynamic>> _fetchReleaseArray(String url) async {
    final response = await cio.get<String>(
      url,
      headers: gameDownloadHeaders,
      responseType: ResponseType.plain,
    );
    final raw = response.data ?? '';

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw FormatException('release 响应不是 JSON：${_preview(raw)}');
    }
    if (decoded is! List) {
      throw FormatException('release 响应不是 JSON 数组：${_preview(raw)}');
    }
    return decoded;
  }

  /// 异常信息里的响应预览：压成一行并截断，别把整页 HTML 打进日志
  static String _preview(String raw) {
    final text = removeNewlines(raw);
    return text.length <= 120 ? text : '${text.substring(0, 120)}…';
  }

  /// 取某大版本的正式版：无 assets 的 release 本来就下不了，直接排除
  List<MindustryRelease> _versionsOfMajor(MindustryMajorVersion major) {
    return [
      for (final version in _versionList)
        if (version.assets.isNotEmpty && version.major == major) version,
    ];
  }

  /// 各分段：按大版本分，空段不显示
  ///
  /// 来源策略会改变列表范围
  /// 空着的大版本就别留一个空标题在那里
  List<Widget> _buildMajorSections() {
    final sections = <Widget>[];
    for (final major in MindustryMajorVersion.values) {
      final versions = _versionsOfMajor(major);
      if (versions.isEmpty) continue;
      sections.add(_buildMajorVersionList(major, versions));
    }
    return sections;
  }

  /// 一个大版本一段：标题带数量，下面跟一句区间说明
  Widget _buildMajorVersionList(
    MindustryMajorVersion major,
    List<MindustryRelease> versionList,
  ) {
    final theme = Theme.of(context);
    List<Widget> versions = [];

    for (var version in versionList) {
      final Widget subtitle = Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          Row(
            spacing: 8,
            children: [
              Icon(Icons.date_range_outlined, size: 18),
              Text(version.releaseDate.split('T').first),
            ],
          ),
        ],
      );

      final Widget widget = ReboundListTile(
        padding: EdgeInsets.all(8),
        borderRadius: BorderRadius.circular(4),
        leading: Image.asset('assets/images/logo.png', width: 48),
        title: Text(version.name),
        subtitle: subtitle,
        onTap: () {
          _buildDownloadPopup(version);
        },
      );
      versions.add(widget);
    }

    final Widget title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${major.label}  (${versions.length.toString()})'),
        Text(
          _rangeSummaryOf(major, versionList),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );

    return AnimatedExpansion(title: title, children: versions);
  }

  /// 分段说明：区间上界取**实际列出来的最后那个版本**
  ///
  /// 不拿下一档的起点当上界——那个版本属于下一档（v4 的上界是 v96，不是 v97）
  String _rangeSummaryOf(
    MindustryMajorVersion major,
    List<MindustryRelease> versions,
  ) {
    final minBuild = major.minBuild;
    if (major.maxBuild == null) return 'v${_trimBuild(minBuild)}+';

    var lastBuild = minBuild;
    for (final version in versions) {
      final build = version.buildNumber;
      if (build != null && build > lastBuild) lastBuild = build;
    }
    return 'v${_trimBuild(minBuild)} ~ v${_trimBuild(lastBuild)}';
  }

  /// build 号去掉多余的小数位（41.0 → 41、104.6 原样）
  String _trimBuild(double build) => build == build.roundToDouble()
      ? build.toInt().toString()
      : build.toString();

  void _buildDownloadPopup(MindustryRelease mindustry) {
    showAnimatedDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 350),
      animationType: DialogAnimation.leapOut,
      pageBuilder: (context, _, _) {
        return _DownloadMindustryPopupPage(mindustry);
      },
    );
  }

  /// 输入 build 号下载 be：先查 release，拿到元数据再走统一的下载弹窗
  Future<void> _openBeBuildDownload() async {
    final mindustryMeta = await showAnimatedDialog<MindustryRelease>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 350),
      animationType: DialogAnimation.leapOut,
      pageBuilder: (context, _, _) => const _BeBuildDownloadDialog(),
    );
    if (mindustryMeta == null || !mounted) return;
    _buildDownloadPopup(mindustryMeta);
  }

  /// 手动刷新：清掉内存里的列表与 be，重建 future 重新拉一遍
  void _refreshVersions() {
    setState(() {
      _versionList.clear();
      _latestBeta = null;
      _versionFuture = _fetchVersionAssets();
    });
  }

  Widget _buildVersionView() {
    final latestBeta = _latestBeta;

    return ListContentPanel(
      // 顶部留出浮动胶囊的位置，列表从它下面开始
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      items: [
        // 最新正式版与最新预览版并排，其余版本按时代分段列在下面
        ContentPanelModule(
          title: '最新版本',
          child: Column(
            spacing: 8,
            children: [
              ReboundListTile(
                pressedScale: 0.98,
                padding: EdgeInsets.all(8),
                borderRadius: BorderRadius.circular(4),
                leading: Image.asset('assets/images/logo.png', width: 48),
                title: Text(_versionList.first.name),
                subtitle: Row(
                  spacing: 8,
                  children: [
                    Icon(Icons.date_range_outlined, size: 18),
                    Text(_versionList.first.releaseDate.split('T').first),
                  ],
                ),
                onTap: () {
                  _buildDownloadPopup(_versionList.first);
                },
              ),
              if (latestBeta != null)
                ReboundListTile(
                  pressedScale: 0.98,
                  padding: EdgeInsets.all(8),
                  borderRadius: BorderRadius.circular(4),
                  leading: Image.asset('assets/images/logo.png', width: 48),
                  title: Text('预览版 ${latestBeta.name}'),
                  subtitle: Row(
                    spacing: 8,
                    children: [
                      Icon(Icons.date_range_outlined, size: 18),
                      Text(latestBeta.releaseDate.split('T').first),
                    ],
                  ),
                  onTap: () {
                    _buildDownloadPopup(latestBeta);
                  },
                ),
            ],
          ),
        ),
        ..._buildMajorSections(),
        SizedBox(height: 40),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    //设置里改了来源策略就重拉列表：页面可能还留在路由栈里，不会重跑 initState
    if (_versionListSource != config.setting.downloadOptions.bodySource) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshVersions();
      });
    }

    final child = FutureBuilder<bool>(
      future: _versionFuture,
      builder: (context, snapshot) {
        late Widget widget;

        if (snapshot.connectionState == ConnectionState.waiting) {
          widget = Center(
            key: ValueKey(snapshot.connectionState),
            child: CircularProgressIndicator(color: Colors.grey),
          );
        } else {
          if (snapshot.data ?? false) {
            // 列表上浮一层放胶囊操作，滚动时停在右上角
            widget = Stack(
              children: [
                _buildVersionView(),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20, right: 40),
                    child: CapsuleActionBar(
                      actions: [
                        CapsuleAction(
                          icon: Icons.refresh,
                          hint: '刷新版本列表',
                          onTap: _refreshVersions,
                        ),
                        //BE 只在官方源有
                        if (config.setting.downloadOptions.bodySource !=
                            BodySourceStrategy.domesticOnly)
                          CapsuleAction(
                            icon: Icons.tag,
                            hint: '下载指定 build',
                            onTap: _openBeBuildDownload,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          } else {
            widget = Card(
              child: Padding(
                padding: EdgeInsetsGeometry.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    Text(
                      '网络错误，请检查网络环境后再重试',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ReboundButton(
                      onTap: _refreshVersions,
                      child: Icon(Icons.refresh, color: Colors.red, size: 40),
                    ),
                  ],
                ),
              ),
            );
          }
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: widget,
        );
      },
    );

    return child;
  }
}

class _DownloadMindustryPopupPage extends StatefulWidget {
  final MindustryRelease mindustryMeta;

  const _DownloadMindustryPopupPage(this.mindustryMeta);

  @override
  State<StatefulWidget> createState() => _DownloadMindustryPopupPageState();
}

class _DownloadMindustryPopupPageState
    extends State<_DownloadMindustryPopupPage> {
  late final MindustryRelease mindustryMeta = widget.mindustryMeta;
  late String tag = mindustryMeta.name;

  ///选中的启动方式（loader 的选择结果）；null / [LoaderChoice.none] = 原版启动
  ///
  /// 这里只记选择，不下载：需要下载的 loader 由 [MindustryDownloadTask] 与本体
  /// 一起下
  ///
  /// 下载前还不知道游戏大版本号（要读 jar 里的 version.properties），
  /// 所以选择页这里不做适配表标注
  LoaderChoice? loaderChoice;

  String? error;

  late final TextEditingController textEditingController;

  late final ExpansibleController controller = ExpansibleController();

  ///这条会从哪下：按当前策略取第一个可用地址，看它是不是国内源
  ///
  /// 策略是优先那档时，这里显示的是会先试的那个来源，失败才换另一边
  String get _bodySourceLabel {
    final asset = mindustryMeta.desktopJarAsset;
    if (asset == null) return '该版本没有本体';

    final candidateUrls = asset.urlsFor(
      config.setting.downloadOptions.bodySource,
    );
    if (candidateUrls.isEmpty) return '没有可用来源';

    return candidateUrls.first.startsWith(mindustryManifestBase)
        ? '国内源'
        : '官方源';
  }

  @override
  void initState() {
    error = check(tag);
    textEditingController = TextEditingController(text: tag)
      ..addListener(() {
        tag = textEditingController.text;
        final text = textEditingController.text;
        setState(() {
          error = check(text);
        });
      });
    super.initState();
  }

  @override
  void dispose() {
    textEditingController.dispose();
    controller.dispose();
    super.dispose();
  }

  String? check(String? tag) {
    final error = WindowsFileNameValidator.tagValidate(tag);
    if (error != null) return error;

    final versionFolds = config.versionOptions.versionFolds;
    for (final versionFold in versionFolds) {
      for (final versions in versionFold.versions) {
        if (versions.tag == tag) {
          return '名称已存在';
        }
      }
    }
    return null;
  }

  void startDownload() {
    if (error != null) return;

    addTask(
      MindustryDownloadTask(
        mindustryMeta: mindustryMeta,
        tag: tag,
        loader: loaderChoice,
      ),
    );
    Navigator.of(context).pop();
  }

  /// 选启动方式：原版，或用 Copper 加载器（可挑版本，库里已有的直接复用）
  ///
  /// 挑本地 jar 要开文件选择器，所以在界面这层就把它挑完（任务里没法弹窗）；
  /// 远程版本只记下选择，真正的下载交给下载任务
  Future<void> chooseLauncher() async {
    var choice = await pickLoaderChoice(
      context,
      currentLoaderPath: loaderChoice?.loaderPath,
      allowNone: true,
      gameVersion: gameVersionOf(
        release: mindustryMeta.tag,
        isBe: mindustryMeta.isBe,
      ),
    );
    if (choice == null || !mounted) return;

    if (choice.pickLocalFile) {
      final picked = await PathSelector.selectFile(
        acceptedTypeGroups: const [loaderJarTypeGroup],
      );
      if (picked == null || !mounted) return;
      choice = LoaderChoice.localFile(picked);
    }

    setState(() => loaderChoice = choice);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Material(
          color: Colors.transparent,
          elevation: 4,
          shadowColor: Colors.black,
          child: Container(
            width: 500,
            padding: EdgeInsets.all(8),
            constraints: BoxConstraints(maxHeight: 380),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              spacing: 8,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    ReboundButton(
                      child: Icon(Icons.arrow_back_ios_new),
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                    ),
                    Text(
                      '下载 ${mindustryMeta.name}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),

                OutlinedTextField(
                  label: '游戏名称',
                  error: error,
                  controller: textEditingController,
                ),

                //下载时就能选启动方式：选 Copper 的话这个版本直接建好 loader，
                //不用先下原版再去换启动器新建；loader 的下载/收进库由下载任务做
                Row(
                  spacing: 8,
                  children: [
                    Text('启动方式', style: theme.textTheme.bodyMedium),
                    IconTextButton(
                      icon: (loaderChoice?.useNone ?? true)
                          ? Icons.rocket_launch_outlined
                          : Icons.extension_outlined,
                      content: loaderChoice?.describe ?? '原版 Jar',
                      onTap: chooseLauncher,
                    ),
                    Expanded(child: SizedBox()),
                    //下载来源：按设置里的策略取第一个可用地址，一眼看出这条会从哪下
                    Text(
                      '下载来源:  $_bodySourceLabel',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),

                // 老版本的能力缺失提示，只提示不拦下载
                if (mindustryMeta.era.downloadHint case final hint?)
                  Row(
                    spacing: 8,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      Flexible(
                        child: Text(
                          hint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
        ReboundButton(
          pressedScale: 0.95,
          elevation: 2,
          hoverElevation: 4,
          onTap: startDownload,
          child: SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.file_download_outlined,
                  size: 40,
                  color: theme.colorScheme.secondary,
                ),
                Text(
                  '开始下载',
                  style: theme.textTheme.displayMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 按 build 号查 be release：MindustryBuilds 的 tag 就是 build 号
///
/// release 列表接口最多只翻得动 1000 条，更老的 build 从列表里拿不到，
/// 所以指定 build 一律走 tag 直查；build 不存在时 GitHub 返回 404，
/// dio 会抛出 [DioException]
Future<MindustryRelease> _fetchBeByBuild(String build) async {
  final response = await cio.get<Map<String, dynamic>>(
    '$githubBeUrl/tags/$build',
    headers: gameDownloadHeaders,
  );
  return MindustryRelease.fromGithubJson(response.data!);
}

/// 指定 build 下载弹窗：输入 build 号 → 查到 release → 带着元数据关闭，
/// 由调用方接着打开统一的下载弹窗（改名字、查重都在那边）
class _BeBuildDownloadDialog extends StatefulWidget {
  const _BeBuildDownloadDialog();

  @override
  State<StatefulWidget> createState() => _BeBuildDownloadDialogState();
}

class _BeBuildDownloadDialogState extends State<_BeBuildDownloadDialog> {
  final TextEditingController _buildController = TextEditingController();

  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _buildController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final build = _buildController.text.trim();
    if (build.isEmpty) {
      setState(() => _error = '请输入 build 号');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final mindustryMeta = await _fetchBeByBuild(build);
      if (!mounted) return;
      Navigator.of(context).pop(mindustryMeta);
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = statusCode == 404
            ? '没有 build $build 这个版本'
            : '获取失败：${statusCode ?? error.message}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '获取失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Material(
          color: Colors.transparent,
          elevation: 4,
          shadowColor: Colors.black,
          child: Container(
            width: 500,
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              spacing: 8,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    ReboundButton(
                      child: Icon(Icons.arrow_back_ios_new),
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                    ),
                    Text(
                      '下载指定 BE 版本',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),

                OutlinedTextField(
                  label: 'build 号',
                  error: _error,
                  controller: _buildController,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onEditingComplete: _confirm,
                ),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'MindustryBuilds 的 tag 即 build 号，例如 27793',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
        ReboundButton(
          pressedScale: 0.95,
          elevation: 2,
          hoverElevation: 4,
          onTap: _isLoading ? null : _confirm,
          child: SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  )
                else
                  Icon(
                    Icons.manage_search,
                    size: 40,
                    color: theme.colorScheme.secondary,
                  ),
                Text(
                  _isLoading ? '查询中' : '查询版本',
                  style: theme.textTheme.displayMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
