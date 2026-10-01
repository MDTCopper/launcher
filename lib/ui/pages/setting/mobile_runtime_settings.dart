import 'package:copper_launcher/domain/bridge_installer.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/percent_bar.dart';
import 'package:copper_launcher/ui/components/setting_bar/setting_bar_row.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:flutter/material.dart';

/// 移动端运行环境设置（Android 专用，挂在启动设置的高级选项里）
///
/// 管的是**与游戏版本无关**的那份载荷：Java 运行环境、Copper 桥、模组加载器适配层；
/// arc 原生库按每个版本的 `archash` 分目录放，不在这里管（清理时也留着）
class MobileRuntimeSettings extends StatefulWidget {
  const MobileRuntimeSettings({super.key});

  @override
  State<MobileRuntimeSettings> createState() => _MobileRuntimeSettingsState();
}

class _MobileRuntimeSettingsState extends State<MobileRuntimeSettings> {
  BridgeRuntimeStatus? _status;
  String? _abi;

  /// 正在重装时的阶段文案与下载状态
  String? _workingStatus;
  HttpDownloadState? _download;
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final status = await BridgeInstaller.readRuntimeStatus();
    final abi = await BridgeInstaller.detectDeviceAbi();
    if (!mounted) return;
    setState(() {
      _status = status;
      _abi = abi;
    });
  }

  Future<void> _reinstall() async {
    setState(() {
      _isWorking = true;
      _workingStatus = '正在识别设备…';
      _download = null;
    });

    try {
      final abi = _abi ?? await BridgeInstaller.detectDeviceAbi();
      if (abi == null) {
        throw StateError('认不出这台设备的 ABI，选不了对应的 Java 运行环境');
      }
      await BridgeInstaller.installRuntime(
        abi: abi,
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _workingStatus = status);
        },
        onProgress: (state) {
          if (!mounted) return;
          setState(() => _download = state);
        },
      );
      addNotice(
        icon: Icons.check_circle_outline,
        title: '运行环境已就绪',
        content: '缺的与有更新的都装好了',
      );
    } catch (error) {
      addNotice(
        icon: Icons.close,
        title: '装运行环境失败',
        content: removeNewlines('$error'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
          _workingStatus = null;
          _download = null;
        });
        await _reload();
      }
    }
  }

  void _clear() {
    final size = formatBytes(_status?.totalBytes ?? 0);
    showConfirmationPopup(
      context: context,
      type: ConfirmationType.warning,
      title: '清理移动端运行环境？',
      content:
          '会删掉 Java 运行环境、Copper 桥与模组加载器适配层（当前共 $size），'
          'arc 原生库保留；下次启动会自动重新下载',
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

  /// 已下载 / 总量 · 速度（与安装页同一口径）
  String _progressText(HttpDownloadState state) {
    final downloaded = formatBytes(state.downloaded);
    final speed = state.speedText;
    if (state.total <= 0) return '$downloaded · $speed';
    return '$downloaded / ${formatBytes(state.total)} · $speed';
  }

  /// 一行「版本 · 占用」；没有版本时给「未安装」
  String _versionLine(String? version, int bytes, {String suffix = ''}) {
    if (version == null) return '未安装';
    return '$version · ${formatBytes(bytes)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final status = _status;
    final download = _download;

    final isReady = status?.isReady ?? false;
    final stateLine = status == null
        ? '正在检查…'
        : '${isReady ? '已就绪' : '不齐（缺件）'}${_abi == null ? '' : ' · $_abi'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text('移动端运行环境', style: theme.textTheme.titleSmall),
        Text(
          'Android 上跑桌面版游戏要的 Java 运行环境与 Copper 桥；'
          'arc 原生库按游戏版本走，不在这里',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.itemHint,
          ),
        ),
        SettingBarRow(
          title: '状态',
          control: Text(
            stateLine,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isReady ? colors.itemPrimary : colors.error,
            ),
          ),
        ),
        SettingBarRow(
          title: 'Java 运行环境',
          control: Text(
            _versionLine(status?.jreVersion, status?.jreBytes ?? 0),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        SettingBarRow(
          title: 'Copper 桥',
          control: Text(
            _versionLine(status?.bridgeTag, status?.bridgeBytes ?? 0),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        SettingBarRow(
          title: '模组加载器适配层',
          control: Text(
            _versionLine(
              status?.wrapperVersion,
              status?.wrapperBytes ?? 0,
              suffix: status?.wrapperVersion == null
                  ? ''
                  : '（启动走加载器的版本时会用到）',
            ),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Row(
          spacing: 8,
          children: [
            ReboundButton(
              onTap: _isWorking ? null : _reinstall,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(_isWorking ? '正在安装…' : '重新安装运行环境'),
              ),
            ),
            ReboundButton(
              onTap: _isWorking ? null : _clear,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('清理运行环境'),
              ),
            ),
          ],
        ),
        if (_isWorking) ...[
          PercentBar(
            total: 1,
            dataList: [PercentBarData(value: download?.progress ?? 0)],
          ),
          Text(
            _workingStatus ?? '正在安装…',
            style: theme.textTheme.labelMedium,
          ),
          if (download != null && download.progress > 0)
            Text(
              _progressText(download),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.itemHint,
              ),
            ),
        ],
      ],
    );
  }
}
