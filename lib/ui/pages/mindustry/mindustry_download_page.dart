import 'package:copper_launcher/data/mindustry_version_snapshot.dart';
import 'package:copper_launcher/data/net_asset.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/components/animation/animated_expansion.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';

import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/remote_data.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_config.dart';
import '../../../core/app_constant.dart';
import '../../../domain/task_manager.dart';
import '../../../domain/tasks/download_mindustry.dart';
import '../../../util/mindustry_version_era.dart';
import '../../../util/validate/windows_file_name_validator.dart';

import '../../vars.dart';

class MindustryDownloadPage extends StatefulWidget {
  const MindustryDownloadPage({super.key});

  @override
  State<StatefulWidget> createState() => _MindustryDownloadPageState();
}

class _MindustryDownloadPageState extends State<MindustryDownloadPage> {
  static final List<MindustryGithubMeta> _versionList = [];

  /// 最新 be；拿不到（网络 / 限流）时为 null，页面不显示该入口
  static MindustryGithubMeta? _latestBeta;

  /// 版本列表：先读 remote 快照（历史版本基本不变，不用反复问 API），
  /// 再用 API 取最新一页合并；API 挂了就只用快照，至少老版本还能下
  Future<bool> _fetchVersionAssets() async {
    if (_versionList.isNotEmpty) return true;

    final snapshot = MindustryVersionSnapshot.parse(
      await RemoteData.load(mindustryVersionsFile),
    );

    List<MindustryGithubMeta> latest;
    try {
      latest = await _fetchLatestReleases();
    } catch (e) {
      addLogAndPrint(.warning, '获取最新版本列表失败：$e');
      latest = const [];
      if (snapshot.isEmpty) return false;
    }

    _versionList
      ..clear()
      ..addAll(MindustryVersionSnapshot.merge(snapshot, latest));

    //be 的 build 太多，只取最新一条，其余走「下载指定 build」
    try {
      _latestBeta = await _fetchLatestBeta();
    } catch (e) {
      addLogAndPrint(.warning, '获取最新 be 版本失败：$e');
      _latestBeta = null;
    }
    return true;
  }

  /// 取官方最新一页 release（一页 100 条，够覆盖新版本）
  Future<List<MindustryGithubMeta>> _fetchLatestReleases() async {
    final response = await cio.get<List<dynamic>>(
      '$githubMindustryUrl?per_page=$mindustryVersionPageSize',
      headers: gameDownloadHeaders,
    );
    return [
      for (final release in response.data!)
        MindustryGithubMeta.fromJson(release as Map<String, dynamic>),
    ];
  }

  Future<MindustryGithubMeta> _fetchLatestBeta() async {
    final response = await cio.get<List<dynamic>>(
      '$githubBeUrl?per_page=1',
      headers: gameDownloadHeaders,
    );
    return MindustryGithubMeta.fromJson(
      response.data!.first as Map<String, dynamic>,
    );
  }

  /// 取某时代的正式版：无 assets 的 release 本来就下不了，直接排除
  List<MindustryGithubMeta> _versionsOfEra(MindustryVersionEra era) {
    return [
      for (final version in _versionList)
        if (version.assets.isNotEmpty && version.era == era) version,
    ];
  }

  /// 一个时代一段：标题带数量，下面跟一句该时代的说明
  Widget _buildEraVersionList(
    MindustryVersionEra era,
    List<MindustryGithubMeta> versionList,
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
        Text('${era.label}(${versions.length.toString()})'),
        Text(era.summary, style: theme.textTheme.bodySmall),
      ],
    );

    return AnimatedExpansion(title: title, children: versions);
  }

  void _buildDownloadPopup(MindustryGithubMeta mindustry) {
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
    final mindustryMeta = await showAnimatedDialog<MindustryGithubMeta>(
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

  /// 手动刷新：清掉内存里的列表与 be，交给 [build] 重新走一遍获取流程
  void _refreshVersions() {
    setState(() {
      _versionList.clear();
      _latestBeta = null;
    });
  }

  Widget _buildVersionView() {
    final latestBeta = _latestBeta;

    return ListContentPanel(
      items: [
        Align(
          alignment: Alignment.centerRight,
          child: IconTextButton(
            icon: Icons.refresh,
            content: '刷新版本列表',
            onTap: _refreshVersions,
          ),
        ),
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
        for (final era in MindustryVersionEra.values)
          _buildEraVersionList(era, _versionsOfEra(era)),

        // 指定 build 入口放最后：be 的 build 太多，不适合跟正式版一起列
        ContentPanelModule(
          title: '预览版（BE）',
          child: ReboundListTile(
            pressedScale: 0.98,
            padding: EdgeInsets.all(8),
            borderRadius: BorderRadius.circular(4),
            leading: SizedBox(width: 48, child: Icon(Icons.tag, size: 32)),
            title: Text('下载指定 build'),
            subtitle: Text('输入 build 号，例如 27793'),
            onTap: _openBeBuildDownload,
          ),
        ),
        SizedBox(height: 40),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = FutureBuilder<bool>(
      future: _fetchVersionAssets(),
      builder: (context, snapshot) {
        late Widget widget;

        if (snapshot.connectionState == ConnectionState.waiting) {
          widget = Center(
            key: ValueKey(snapshot.connectionState),
            child: CircularProgressIndicator(color: Colors.grey),
          );
        } else {
          if (snapshot.data ?? false) {
            widget = _buildVersionView();
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
                      child: Icon(Icons.refresh, color: Colors.red, size: 40),
                      onTap: () {
                        setState(() {});
                      },
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
  final MindustryGithubMeta mindustryMeta;

  const _DownloadMindustryPopupPage(this.mindustryMeta);

  @override
  State<StatefulWidget> createState() => _DownloadMindustryPopupPageState();
}

class _DownloadMindustryPopupPageState
    extends State<_DownloadMindustryPopupPage> {
  late final MindustryGithubMeta mindustryMeta = widget.mindustryMeta;
  late String tag = mindustryMeta.name;
  String? copperVersion;

  String? error;

  late final TextEditingController textEditingController;

  late final ExpansibleController controller = ExpansibleController();

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

    addTask(DownloadMindustryTask(mindustryMeta: mindustryMeta, tag: tag));
    Navigator.of(context).pop();
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
Future<MindustryGithubMeta> _fetchBeByBuild(String build) async {
  final response = await cio.get<Map<String, dynamic>>(
    '$githubBeUrl/tags/$build',
    headers: gameDownloadHeaders,
  );
  return MindustryGithubMeta.fromJson(response.data!);
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
