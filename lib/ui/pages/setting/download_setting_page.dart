import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/scroll/single_child_scroll_view.dart';
import 'package:copper_launcher/ui/components/setting_bar/input_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/option_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/slider_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/switch_setting_bar.dart';
import 'package:copper_launcher/ui/components/tile/rebound_list_tile.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/github_mirror.dart';
import 'package:flutter/material.dart';

class DownloadSettingPage extends StatefulWidget {
  const DownloadSettingPage({super.key});

  @override
  State<StatefulWidget> createState() => _DownloadSettingPageState();
}

class _DownloadSettingPageState extends State<DownloadSettingPage> {
  Setting get setting => config.setting;

  DownloadOptions get downloadOptions => setting.downloadOptions;

  ProxyOptions get proxyOptions => setting.proxyOptions;

  ///限速档位（MB/s），0 表示不限速
  static const List<double> speedRankMBList = [
    0, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512,
  ];

  late final TextEditingController githubTokenController;
  late final TextEditingController proxyHostController;
  late final TextEditingController proxyPortController;
  late final TextEditingController proxyUsernameController;
  late final TextEditingController proxyPasswordController;
  late final TextEditingController customNodeController;

  ///节点 → 测速耗时毫秒（null 表示失败）
  final Map<String, int?> _latencyMap = {};

  ///正在测速的节点
  final Set<String> _testingNodes = {};

  bool _testingAll = false;
  bool _crawling = false;

  @override
  void initState() {
    super.initState();
    githubTokenController = TextEditingController(text: setting.githubToken);
    proxyHostController = TextEditingController(text: proxyOptions.host);
    proxyPortController = TextEditingController(
      text: proxyOptions.port <= 0 ? '' : '${proxyOptions.port}',
    );
    proxyUsernameController = TextEditingController(text: proxyOptions.username);
    proxyPasswordController = TextEditingController(text: proxyOptions.password);
    customNodeController = TextEditingController();
  }

  @override
  void dispose() {
    githubTokenController.dispose();
    proxyHostController.dispose();
    proxyPortController.dispose();
    proxyUsernameController.dispose();
    proxyPasswordController.dispose();
    customNodeController.dispose();
    super.dispose();
  }

  ///写回 config 并同步网络单例（新请求/新下载即时生效）
  void _persistAndSync() {
    config.save();
    cio.applySettings();
  }

  ///当前限速在档位列表中的下标（不在表中时向上取整到最近的档位）
  int _speedRankIndex() {
    final bytes = downloadOptions.speedLimitBytes;
    if (bytes <= 0) return 0;
    final mb = bytes / MB;
    for (int i = 0; i < speedRankMBList.length; i++) {
      if (speedRankMBList[i] >= mb) return i;
    }
    return speedRankMBList.length - 1;
  }

  void _saveProxyCustom() {
    setState(() {
      proxyOptions.host = proxyHostController.text.trim();
      proxyOptions.port = int.tryParse(proxyPortController.text.trim()) ?? 0;
      proxyOptions.username = proxyUsernameController.text.trim();
      proxyOptions.password = proxyPasswordController.text;
    });
    _persistAndSync();
  }

  Widget _buildDownloadModule() {
    final rankIndex = _speedRankIndex();
    final divisions = speedRankMBList.length - 1;

    return ContentPanelModule(
      title: '下载',
      child: Column(
        spacing: 8,
        children: [
          SliderSettingBar(
            title: '最大下载速度',
            label: rankIndex == 0
                ? '不限速'
                : '${speedRankMBList[rankIndex].toStringAsFixed(0)} MB/s',
            value: rankIndex / divisions,
            divisions: divisions,
            onChanged: (value) {
              final rank = (value * divisions).round().clamp(0, divisions);
              setState(() {
                downloadOptions.speedLimitBytes =
                    (speedRankMBList[rank] * MB).round();
              });
              _persistAndSync();
            },
          ),
          SliderSettingBar(
            title: '最大线程数',
            label: downloadOptions.maxTread.toString(),
            value: downloadOptions.maxTread.toDouble(),
            min: 1,
            max: 16,
            divisions: 15,
            onChanged: (value) {
              setState(() {
                downloadOptions.maxTread = value.round();
              });
              _persistAndSync();
            },
          ),
          InputSettingBar(
            title: 'github访问Token',
            controller: githubTokenController,
            onEditingComplete: () {
              setState(() {
                setting.githubToken = githubTokenController.text.trim();
              });
              _persistAndSync();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProxyCustomModule() {
    //非自定义代理模式不展示地址表单
    if (proxyOptions.mode != ProxyMode.custom) return const SizedBox.shrink();

    return Column(
      spacing: 8,
      children: [
        InputSettingBar(
          title: '代理地址',
          controller: proxyHostController,
          onEditingComplete: _saveProxyCustom,
        ),
        InputSettingBar(
          title: '端口',
          controller: proxyPortController,
          onEditingComplete: _saveProxyCustom,
        ),
        InputSettingBar(
          title: '用户名（可选）',
          controller: proxyUsernameController,
          onEditingComplete: _saveProxyCustom,
        ),
        InputSettingBar(
          title: '密码（可选）',
          controller: proxyPasswordController,
          onEditingComplete: _saveProxyCustom,
        ),
      ],
    );
  }

  Widget _buildProxyModule() {
    return ContentPanelModule(
      title: 'HTTP 代理',
      child: Column(
        spacing: 8,
        children: [
          OptionSettingBar<ProxyMode>(
            title: '代理方式',
            initialValue: proxyOptions.mode,
            onSelect: (mode) {
              setState(() {
                proxyOptions.mode = mode;
                //切到自定义且没填地址时给常用默认值，避免留下空表单
                if (mode == ProxyMode.custom) {
                  if (proxyOptions.host.isEmpty) {
                    proxyOptions.host = '127.0.0.1';
                    proxyHostController.text = proxyOptions.host;
                  }
                  if (proxyOptions.port <= 0) {
                    proxyOptions.port = 7890;
                    proxyPortController.text = '${proxyOptions.port}';
                  }
                }
              });
              _persistAndSync();
            },
            options: [
              DropdownOption(value: ProxyMode.system, label: '跟随系统'),
              DropdownOption(value: ProxyMode.custom, label: '自定义'),
              DropdownOption(value: ProxyMode.off, label: '关闭'),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.ease,
            alignment: Alignment.topCenter,
            child: _buildProxyCustomModule(),
          ),
        ],
      ),
    );
  }

  // ---- GitHub 镜像 ----

  Future<void> _crawlNodes() async {
    setState(() => _crawling = true);
    await GithubMirror.instance.refreshCrawledNodes();
    if (mounted) {
      setState(() {
        _crawling = false;
        _latencyMap.clear();
        //展示爬取预检得到的延迟
        _latencyMap.addAll(GithubMirror.instance.crawledLatencies);
      });
      addNotice(
        icon: Icons.cloud_done_outlined,
        title: '拉取节点',
        content: '已拉取并预检 github.akams.cn 社区节点（失败的已剔除）',
      );
    }
  }

  Future<void> _testNode(String node) async {
    if (_testingNodes.contains(node)) return;
    setState(() => _testingNodes.add(node));
    final ms = await GithubMirror.instance.measure(node, GithubMirror.probeUrl);
    if (mounted) {
      setState(() {
        _testingNodes.remove(node);
        _latencyMap[node] = ms;
      });
    }
  }

  Future<void> _testAllNodes() async {
    final nodes = GithubMirror.instance.allNodes;
    if (nodes.isEmpty) return;
    setState(() {
      _testingAll = true;
      _testingNodes.addAll(nodes);
    });
    for (final node in nodes) {
      final ms = await GithubMirror.instance.measure(node, GithubMirror.probeUrl);
      if (!mounted) return;
      setState(() {
        _testingNodes.remove(node);
        _latencyMap[node] = ms;
      });
    }
    setState(() => _testingAll = false);
  }

  void _addCustomNode() {
    final node = GithubMirror.normalizeNode(customNodeController.text);
    final customs = config.setting.mirrorOptions.customNodes;
    if (node == null) {
      addNotice(icon: Icons.error_outline, title: '添加失败', content: '请输入有效的镜像节点地址');
      return;
    }
    if (customs.contains(node)) {
      addNotice(icon: Icons.info_outline, title: '提示', content: '该节点已存在');
      return;
    }
    setState(() {
      customs.add(node);
      customNodeController.clear();
      _latencyMap.remove(node);
    });
    _persistAndSync();
    addNotice(icon: Icons.check, title: '已添加', content: node);
  }

  void _removeCustomNode(String node) {
    setState(() {
      config.setting.mirrorOptions.customNodes.remove(node);
      _latencyMap.remove(node);
    });
    _persistAndSync();
  }

  String _latencyText(String node) {
    if (_testingNodes.contains(node)) return '测速中...';
    final ms = _latencyMap[node];
    if (ms == null) return _latencyMap.containsKey(node) ? '不可用' : '点击测速';
    return '$ms ms';
  }

  Widget _buildNodeTile(String node, {required bool isCustom}) {
    return ReboundListTile(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Icon(
        isCustom ? Icons.star_outline : Icons.public,
        size: 18,
      ),
      title: Text(node, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_latencyText(node)),
      trailing: isCustom
          ? ReboundButton(
              padding: EdgeInsets.zero,
              onTap: () => _removeCustomNode(node),
              child: Icon(Icons.delete_outline, size: 18),
            )
          : null,
      onTap: () => _testNode(node),
    );
  }

  Widget _buildMirrorModule() {
    final mirror = GithubMirror.instance;
    final customs = config.setting.mirrorOptions.customNodes;
    final presetCount = mirror.presetNodes.length + mirror.crawledNodes.length;

    final nodes = <({String node, bool custom})>[
      for (final node in mirror.presetNodes) (node: node, custom: false),
      for (final node in mirror.crawledNodes) (node: node, custom: false),
      for (final node in customs) (node: node, custom: true),
    ];

    return ContentPanelModule(
      title: 'GitHub 镜像加速',
      child: Column(
        spacing: 8,
        children: [
          SwitchSettingBar(
            title: '启用镜像加速',
            value: mirror.enabled,
            onChanged: (value) {
              setState(() {
                config.setting.mirrorOptions.enabled = value;
              });
              _persistAndSync();
            },
          ),
          Text(
            '官方直连失败时自动走最快的镜像。预设节点 $presetCount 个，自定义节点 ${customs.length} 个。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Row(
            spacing: 8,
            children: [
              IconTextButton(
                icon: Icons.cloud_download_outlined,
                content: _crawling ? '拉取中...' : '拉取节点',
                onTap: _crawling ? null : _crawlNodes,
              ),
              IconTextButton(
                icon: Icons.speed,
                content: _testingAll ? '测速中...' : '全部测速',
                onTap: _testingAll ? null : _testAllNodes,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedTextField(
                  controller: customNodeController,
                  label: '节点前缀',
                  onEditingComplete: _addCustomNode,
                ),
              ),
              const SizedBox(width: 8),
              IconTextButton(
                icon: Icons.add,
                content: '添加自定义',
                onTap: _addCustomNode,
              ),
            ],
          ),
          SizedBox(
            height: 260,
            child: nodes.isEmpty
                ? const Center(
                    child: Text('暂无节点，可点击「拉取节点」或添加自定义节点'),
                  )
                : CopperSingleChildScrollView(
                    child: Column(
                      spacing: 4,
                      children: [
                        for (final entry in nodes)
                          _buildNodeTile(entry.node, isCustom: entry.custom),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        _buildDownloadModule(),
        _buildProxyModule(),
        _buildMirrorModule(),
      ],
    );
  }
}