import 'dart:io';

import 'package:copper_launcher/domain/bridge_installer.dart';
import 'package:copper_launcher/domain/bridge_payload.dart';
import 'package:copper_launcher/domain/bridge_runtime_options.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/task_manager.dart';
import 'package:copper_launcher/domain/tasks/bridge_runtime_task.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:copper_launcher/ui/components/setting_bar/option_setting_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/setting_bar_row.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:flutter/material.dart';

/// 移动端运行环境子路由（从「启动设置 → 高级选项」进）
const mobileRuntimePageRouteKey = '/setting/mobile_runtime';

/// Java 运行环境版本的「跟随最新」选项值（下拉里用不到具体值时拿它表示不钉）
const _followLatest = '';

/// 移动端运行环境：Android 上跑桌面版游戏要的那份载荷（Java + 桥 + 适配层）
///
/// 页面分三层：先说清这是什么与三个「为什么」，再给不懂的人一个「一键准备好」，
/// 最后是各部分的版本与重装；更细的说明留给帮助页
class MobileRuntimePage extends StatefulWidget {
  const MobileRuntimePage({super.key});

  @override
  State<MobileRuntimePage> createState() => _MobileRuntimePageState();
}

class _MobileRuntimePageState extends State<MobileRuntimePage> {
  BridgeRuntimeStatus? _status;
  BridgeRuntimeOptions _options = BridgeRuntimeOptions();
  String? _abi;

  /// 桥的可选版本（仓库 tag）；Java 侧只有构建号可钉，所以不进下拉
  List<String> _bridgeVersions = const [];

  bool _isLoadingVersions = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    _options = BridgeRuntimeOptions.load();
    final status = await BridgeInstaller.readRuntimeStatus();
    final abi = await BridgeInstaller.detectDeviceAbi();
    if (!mounted) return;
    setState(() {
      _status = status;
      _abi = abi;
    });
    _loadVersions();
  }

  /// 版本列表要联网（仓库 tag），单独加载，失败就只留「跟随最新」
  Future<void> _loadVersions() async {
    setState(() => _isLoadingVersions = true);
    final versions = await BridgeInstaller.fetchAvailableVersions();
    if (!mounted) return;
    setState(() {
      _bridgeVersions = versions.bridgeTags;
      _isLoadingVersions = false;
    });
  }

  Future<void> _saveOptions() async {
    await _options.save();
    if (!mounted) return;
    await _reload();
  }

  void _startTask(BridgeRuntimeTarget target, {required bool force}) {
    final task = BridgeRuntimeTask(target: target, force: force);
    // 任务在抽屉里跑，跑完把这一页的状态刷新一下（否则还显示旧的版本 / 占用）
    void onTaskChanged() {
      if (task.status == TaskStatus.process) return;
      task.removeListener(onTaskChanged);
      if (mounted) _reload();
    }

    task.addListener(onTaskChanged);
    addTask(task);
    addNotice(
      icon: Icons.downloading,
      title: '已加入任务',
      content: '${target.label}的进度在任务抽屉里',
    );
  }

  void _clear() {
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '清理移动端运行环境？',
      content:
          '会删掉 Java 运行环境、Copper 桥与模组加载器适配层'
          '（当前共 ${formatBytes(_status?.totalBytes ?? 0)}）；'
          'arc 原生库保留，下次启动会自动重新下载',
      action: () async {
        await BridgeInstaller.clearRuntime();
        if (!mounted) return;
        addNotice(
          icon: Icons.delete_outline,
          title: '已清理运行环境',
          content: '下次启动会重新下载',
        );
        await _reload();
      },
    );
  }

  /// 一行「版本 · 占用」，没装给「未安装」
  String _installedLine(String? version, int bytes) => version == null
      ? '未安装'
      : '$version · ${formatBytes(bytes)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final status = _status;
    final hintStyle = theme.textTheme.labelMedium?.copyWith(
      color: colors.itemHint,
    );

    final isReady = status?.isReady ?? false;

    return ListContentPanel(
      items: [
        ContentPanelModule(
          title: '这是什么',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Text(
                'Android 上跑桌面版游戏要用的一整套运行环境：一份 Java、一层 Copper 桥、'
                '一个跑模组时的适配层。与游戏版本无关，装一次所有版本共用。',
                style: theme.textTheme.bodyMedium,
              ),
              Text('为什么是 .jar 而不是 apk', style: theme.textTheme.titleSmall),
              Text(
                '官方 Android 版是另一套工程，桌面版的模组在它上面跑不了；'
                '这里跑的是桌面版本体，所以需要下面这些。',
                style: hintStyle,
              ),
              Text('为什么 Java 是特别定制的', style: theme.textTheme.titleSmall),
              Text(
                '官方 JDK 没有对应 Android 的完整分发，这份是按设备 ABI 重新构建的。',
                style: hintStyle,
              ),
              Text('Copper 桥是干什么的', style: theme.textTheme.titleSmall),
              Text(
                '负责把这份 Java 拉起来、摆好参数与模组环境，再把游戏画面接到 Android 上。',
                style: hintStyle,
              ),
            ],
          ),
        ),
        ContentPanelModule(
          title: '一键准备好',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text(
                '不想逐项挑版本就用这个：缺什么装什么，已经齐的不重下。',
                style: hintStyle,
              ),
              ReboundButton(
                onTap: () =>
                    _startTask(BridgeRuntimeTarget.all, force: false),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text('把运行环境装齐'),
                ),
              ),
            ],
          ),
        ),
        ContentPanelModule(
          title: 'Java 运行环境',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              SettingBarRow(
                title: '当前',
                control: Text(
                  _installedLine(status?.jreVersion, status?.jreBytes ?? 0),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              OptionSettingBar<String>(
                title: '版本',
                initialValue: _options.jreBuild ?? _followLatest,
                hintText: '跟随最新',
                options: [
                  const DropdownOption(value: _followLatest, label: '跟随最新'),
                  if (status?.jreVersion != null)
                    DropdownOption(
                      value: status!.jreVersion!,
                      label: '钉住当前（${status.jreVersion}）',
                    ),
                ],
                onSelect: (value) {
                  _options.jreBuild = value.isEmpty ? null : value;
                  _saveOptions();
                },
              ),
              Text(
                '钉住后即使上游出了新构建也不会自动重下；设备 ABI：${_abi ?? '未知'}',
                style: hintStyle,
              ),
              ReboundButton(
                onTap: () => _startTask(BridgeRuntimeTarget.jre, force: true),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('重装 Java 运行环境'),
                ),
              ),
            ],
          ),
        ),
        ContentPanelModule(
          title: 'Copper 桥',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              SettingBarRow(
                title: '当前',
                control: Text(
                  _installedLine(status?.bridgeTag, status?.bridgeBytes ?? 0),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              OptionSettingBar<String>(
                title: '版本',
                initialValue: _options.bridgeTag ?? _followLatest,
                hintText: _isLoadingVersions ? '读取中…' : '跟随最新',
                options: [
                  const DropdownOption(value: _followLatest, label: '跟随最新'),
                  for (final tag in _bridgeVersions)
                    DropdownOption(value: tag, label: tag),
                ],
                onSelect: (value) {
                  _options.bridgeTag = value.isEmpty ? null : value;
                  _saveOptions();
                },
              ),
              Text(
                '启动游戏时真正干活的那层（现在上游只有 snapshot：跟着 main 走）',
                style: hintStyle,
              ),
              ReboundButton(
                onTap: () =>
                    _startTask(BridgeRuntimeTarget.bridge, force: true),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('重装 Copper 桥'),
                ),
              ),
            ],
          ),
        ),
        ContentPanelModule(
          title: '模组加载器适配层',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              SettingBarRow(
                title: '当前',
                control: Text(
                  _installedLine(
                    status?.wrapperVersion,
                    status?.wrapperBytes ?? 0,
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                '只有跑 Copper 模组的版本才用得上，原版启动不需要它'
                '（版本固定 ${BridgePayload.loaderWrapperVersion}，与加载器一起编译）',
                style: hintStyle,
              ),
              ReboundButton(
                onTap: () =>
                    _startTask(BridgeRuntimeTarget.wrapper, force: true),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('重装模组加载器适配层'),
                ),
              ),
            ],
          ),
        ),
        ContentPanelModule(
          title: '清理',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text(
                '删掉上面三项（共 ${formatBytes(status?.totalBytes ?? 0)}），'
                'arc 原生库保留；下次启动会自动重新下载',
                style: hintStyle,
              ),
              SettingBarRow(
                title: '状态',
                control: Text(
                  isReady ? '已就绪' : '不齐（缺件）',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isReady ? colors.itemPrimary : colors.error,
                  ),
                ),
              ),
              ReboundButton(
                onTap: _clear,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('清理运行环境'),
                ),
              ),
            ],
          ),
        ),
        if (!Platform.isAndroid)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '注意：这份运行环境只在 Android 上用得上，当前平台是${Platform.operatingSystem}',
              style: hintStyle,
            ),
          ),
      ],
    );
  }
}
