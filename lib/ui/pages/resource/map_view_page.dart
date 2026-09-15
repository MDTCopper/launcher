import 'dart:typed_data';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/mindustry_top_map.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/download_map.dart';
import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/mindustry_top_map_api.dart';
import 'package:copper_launcher/util/validate/windows_file_name_validator.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// mindustry.top 社区地图站
///
/// 列表按 offset 翻页（站点每页 15 条，越界返回 400 由 api 层折算成空列表）；
/// 搜索走服务端 `search` 参数；玩法模式接口没有筛选参数，所以按已加载的条目筛
class MapViewPage extends StatefulWidget {
  const MapViewPage({super.key});

  @override
  State<MapViewPage> createState() => _MapViewPageState();
}

/// 玩法模式的中文名（筛选按钮与瓦片共用）
String _modeLabel(MindustryTopMapMode mode) => switch (mode) {
  MindustryTopMapMode.survive => '生存',
  MindustryTopMapMode.pvp => 'PVP',
  MindustryTopMapMode.sandbox => '沙盒',
  MindustryTopMapMode.attack => '进攻',
  MindustryTopMapMode.unknown => '未标注',
};

/// 已加载地图列表的进程内缓存：资源页切 tab / 离开再回来时复用，不从头拉。
///
/// 只缓存**未搜索**的默认列表——搜索结果是一次性的，不落缓存。
/// 点「刷新」会清空重拉并覆盖这里。
class _MapListCache {
  static final List<MindustryTopMapMeta> maps = [];
  static bool hasMore = true;
}

class _MapViewPageState extends State<MapViewPage> {
  /// 已加载的地图（跨页累积，翻页在此基础上继续取）
  final List<MindustryTopMapMeta> _maps = [];

  final TextEditingController _searchController = TextEditingController();

  /// 选中的玩法模式（空 = 不限）
  final Set<MindustryTopMapMode> _modeFilter = {};

  bool _loading = false;

  /// 还能继续翻页：上一页拿满了 [MindustryTopMapApi.pageSize] 条
  bool _hasMore = true;

  /// 网络类失败。与"没有更多"分开，好给重试入口
  String? _error;

  /// 请求序号：搜索 / 刷新之后，旧请求回来不许覆盖新结果
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    // 有缓存就复用，不再从头拉；要重来点「刷新」
    if (_MapListCache.maps.isEmpty) {
      _loadMore(reset: true);
    } else {
      _maps.addAll(_MapListCache.maps);
      _hasMore = _MapListCache.hasMore;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 拉一页地图；[reset] 为 true 时清空重来（搜索 / 刷新）
  Future<void> _loadMore({bool reset = false}) async {
    if (_loading) return;
    final seq = ++_requestSeq;
    final search = _searchController.text.trim();
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _maps.clear();
        _hasMore = true;
      }
    });

    try {
      final page = await MindustryTopMapApi.list(
        begin: reset ? 0 : _maps.length,
        search: search,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _maps.addAll(page);
        _hasMore = page.length >= MindustryTopMapApi.pageSize;
        _loading = false;
      });
      _cacheIfDefault(search);
    } catch (error) {
      if (!mounted || seq != _requestSeq) return;
      MindustryTopMapApi.logFailure(error, context: '列表');
      setState(() {
        _error = '地图列表获取失败，检查网络或代理后重试';
        _loading = false;
      });
    }
  }

  /// 默认列表（未搜索）才写缓存，搜索结果不落
  void _cacheIfDefault(String search) {
    if (search.isNotEmpty) return;
    _MapListCache.maps
      ..clear()
      ..addAll(_maps);
    _MapListCache.hasMore = _hasMore;
  }

  /// 模式筛过之后真正展示的条目
  List<MindustryTopMapMeta> get _visibleMaps => _modeFilter.isEmpty
      ? _maps
      : [
          for (final map in _maps)
            if (_modeFilter.contains(map.mode)) map,
        ];

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(items: [_buildHeadBar(), _buildList()]);
  }

  Widget _buildHeadBar() {
    return ContentPanelModule(
      title: '搜索与筛选',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: OutlinedTextField(
                  label: '地图名称或简介',
                  controller: _searchController,
                ),
              ),
              IconTextButton(
                icon: Icons.search,
                content: '搜索',
                onTap: () => _loadMore(reset: true),
              ),
              IconTextButton(
                icon: Icons.refresh,
                content: '刷新',
                onTap: () {
                  _searchController.clear();
                  setState(_modeFilter.clear);
                  _loadMore(reset: true);
                },
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in MindustryTopMapMode.values)
                ActionButton(
                  content: Text(_modeLabel(mode)),
                  selected: _modeFilter.contains(mode),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  onTap: () => setState(() {
                    _modeFilter.contains(mode)
                        ? _modeFilter.remove(mode)
                        : _modeFilter.add(mode);
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final theme = Theme.of(context);
    final visible = _visibleMaps;

    return ContentPanelModule(
      title: '地图（已加载 ${_maps.length}，显示 ${visible.length}）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          if (_error != null)
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(_error!, style: theme.textTheme.bodyMedium),
                ),
                IconTextButton(
                  icon: Icons.refresh,
                  content: '重试',
                  onTap: _loadMore,
                ),
              ],
            ),
          if (visible.isEmpty && !_loading && _error == null)
            Text('没有匹配的地图', style: theme.textTheme.bodyMedium),
          for (final map in visible) _buildMapTile(map),
          if (_loading) Text('加载中…', style: theme.textTheme.bodySmall),
          if (!_loading && _error == null && _hasMore)
            Center(
              child: IconTextButton(
                icon: Icons.expand_more,
                content: '加载更多',
                onTap: _loadMore,
              ),
            ),
          if (!_loading && !_hasMore && _maps.isNotEmpty)
            Center(child: Text('已经到底了', style: theme.textTheme.labelMedium)),
        ],
      ),
    );
  }

  /// 点瓦片看详情：列表里只有站点给的摘要，作者 / 保存时间 / 波次 / 依赖 mod
  /// 这些得拉一次详情接口，弹窗里先展示已知信息、详情回来再补
  Future<void> _showMapDetail(MindustryTopMapMeta map) => showAnimatedDialog(
    pageBuilder: (_, _, _) =>
        _MapDetailPanel(map: map, onDownload: _downloadMap),
  );

  /// 下载地图到当前选中版本的地图目录
  ///
  /// 地图是"资源"，所以和资源导入一样受 v126 门禁约束：数据目录指不过去的版本
  /// 放进去游戏也读不到
  Future<void> _downloadMap(MindustryTopMapMeta map) async {
    final version = config.versionOptions.selectedVersion;
    if (version == null) {
      addNotice(
        icon: Icons.info_outline,
        title: '先选一个版本',
        content: '地图要放进某个版本的地图目录，先在主页选一个版本',
      );
      return;
    }
    if (!version.supportsResourceImport) {
      addNotice(
        icon: Icons.error_outline,
        title: '该版本不支持',
        content: '[${version.tag}] 是 v126 之前的版本，无法指定游戏数据目录，放进去游戏读不到',
      );
      return;
    }

    final savePath = p.join(
      version.mapsPath,
      '${WindowsFileNameValidator.sanitizeFileName(map.name)}.msav',
    );
    addTask(DownloadMapTask(map: map, version: version, savePath: savePath));
  }

  Widget _buildMapTile(MindustryTopMapMeta map) {
    final versionTag = map.gameVersionTag?.label;

    return ReboundListTile(
      onTap: () => _showMapDetail(map),
      leading: _MapPreviewImage(url: map.previewUrl),
      trailing: IconTextButton(
        icon: Icons.download,
        content: '下载',
        onTap: () => _downloadMap(map),
      ),
      title: Text(map.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text([_modeLabel(map.mode), map.sizeText, ?versionTag].join('  |  ')),
          if (map.description.isNotEmpty)
            Text(map.description, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// 地图预览图：走 [cio] 拉字节（跟随代理设置），带进程内缓存
///
/// 缩略图不大，缓存整张字节即可；取过但失败的也记住（null），避免滚回去反复重试。
/// Future 一起缓存：FutureBuilder 的 future 若在 build 里新建，每次重建都会重发请求
class _MapPreviewImage extends StatefulWidget {
  const _MapPreviewImage({
    required this.url,
    this.width = 96,
    this.height = 60,
  });

  final String url;

  ///显示尺寸：列表里是小缩略图，详情弹窗里放大用（字节缓存共用，不会重复下载）
  final double width;
  final double height;

  @override
  State<_MapPreviewImage> createState() => _MapPreviewImageState();
}

class _MapPreviewImageState extends State<_MapPreviewImage> {
  static final Map<String, Future<Uint8List?>> _futureCache = {};

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: FutureBuilder<Uint8List?>(
          future: _futureCache.putIfAbsent(widget.url, _fetch),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null || bytes.isEmpty) {
              return Icon(
                Icons.map_outlined,
                size: 24,
                color: AppColors.of(context).itemHint,
              );
            }
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              //按显示尺寸解码：列表里几十张缩略图，按原图分辨率解一遍太浪费
              cacheWidth:
                  (MediaQuery.devicePixelRatioOf(context) * widget.width)
                      .round(),
            );
          },
        ),
      ),
    );
  }

  Future<Uint8List?> _fetch() async {
    try {
      final res = await cio.get<Uint8List>(
        widget.url,
        responseType: ResponseType.bytes,
      );
      final data = res.data;
      if (res.statusCode != 200 || data == null || data.isEmpty) return null;
      return data;
    } catch (_) {
      return null;
    }
  }
}

/// 地图详情弹窗
///
/// 用 `pageBuilder` 给的这个 context（不借页面的）：借页面的读主题 / MediaQuery，
/// 关掉弹窗后依赖仍挂在页面元素上，一调整窗口页面就会反复重建
class _MapDetailPanel extends StatefulWidget {
  const _MapDetailPanel({required this.map, required this.onDownload});

  final MindustryTopMapMeta map;

  ///点「下载到当前版本」时回调（选版本、拼路径、起任务都由页面负责）
  final ValueChanged<MindustryTopMapMeta> onDownload;

  @override
  State<_MapDetailPanel> createState() => _MapDetailPanelState();
}

class _MapDetailPanelState extends State<_MapDetailPanel> {
  late final Future<MindustryTopMapDetail> _detail = MindustryTopMapApi.detail(
    widget.map.id,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final screen = MediaQuery.of(context).size;
    final map = widget.map;

    return Center(
      child: Material(
        elevation: 8,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxWidth: screen.width * 0.6,
            maxHeight: screen.height * 0.8,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              top: BorderSide(color: colors.border, width: 1.5),
              left: BorderSide(color: colors.border, width: 0.75),
              right: BorderSide(color: colors.border, width: 0.75),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Text(
                      map.name,
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ReboundButton(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close),
                  ),
                ],
              ),
              Flexible(
                child: CopperSingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: _MapPreviewImage(
                          url: map.previewUrl,
                          width: 360,
                          height: 200,
                        ),
                      ),
                      Text(
                        [
                          _modeLabel(map.mode),
                          map.sizeText,
                          ?map.gameVersionTag?.label,
                        ].join('  |  '),
                        style: theme.textTheme.bodyMedium,
                      ),
                      FutureBuilder<MindustryTopMapDetail>(
                        future: _detail,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Text(
                              '详情获取失败，检查网络或代理后重试',
                              style: theme.textTheme.bodySmall,
                            );
                          }
                          final detail = snapshot.data;
                          if (detail == null) {
                            return Text(
                              '载入详情…',
                              style: theme.textTheme.bodySmall,
                            );
                          }
                          return _buildDetailRows(theme, detail);
                        },
                      ),
                      if (map.description.isNotEmpty)
                        Text(
                          map.description,
                          style: theme.textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Spacer(),
                  IconTextButton(
                    icon: Icons.download,
                    content: '下载到当前版本',
                    onTap: () {
                      Navigator.pop(context);
                      widget.onDownload(map);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 详情段：这些字段随游戏版本增减（来自 .msav 内的 tags），缺哪个就少哪行
  Widget _buildDetailRows(ThemeData theme, MindustryTopMapDetail detail) {
    final info = detail.mapInfo;
    final author = detail.user?.name;
    final internalName = info.mapName;
    final savedAt = info.savedAt;

    final rows = <String>[
      if (author != null && author.isNotEmpty) '作者：$author',
      if (internalName != null && internalName != widget.map.name)
        '地图内部名：$internalName',
      if (info.gameBuild != null) '保存时 build：${info.gameBuild}',
      if (savedAt != null) '保存时间：${savedAt.toString().split('.').first}',
      if (info.wave != null) '波次：${info.wave}',
      if (info.mods.isNotEmpty) '依赖 mod：${info.mods.join('、')}',
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        for (final row in rows) Text(row, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
