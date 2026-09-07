import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/setting_bar/input_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/option_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/slider_setting_bar.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
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
  }

  @override
  void dispose() {
    githubTokenController.dispose();
    proxyHostController.dispose();
    proxyPortController.dispose();
    proxyUsernameController.dispose();
    proxyPasswordController.dispose();
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
            value: rankIndex.toDouble(),
            min: 0,
            max: divisions.toDouble(),
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

  @override
  Widget build(BuildContext context) {
    return ListContentPanel(
      items: [
        _buildDownloadModule(),
        _buildProxyModule(),
      ],
    );
  }
}