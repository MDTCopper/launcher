import 'package:copper_launcher/domain/bridge_installer.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';
import 'package:copper_launcher/ui/components/percent_bar.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:flutter/material.dart';

/// 首次运行：装桥的运行环境（Android 上跑桌面版本体要的那份真 JVM + 桥）
///
/// **装完才让进主页**：没有这份载荷游戏根本起不来，所以这里只给「重试」、
/// 不给跳过；arc 原生库跟着具体游戏版本走，不在这里装
class BridgeInstallPage extends StatefulWidget {
  const BridgeInstallPage({super.key, required this.onReady});

  /// 装好了：让上层切到主页
  final VoidCallback onReady;

  @override
  State<BridgeInstallPage> createState() => _BridgeInstallPageState();
}

enum _InstallPhase { installing, failed }

class _BridgeInstallPageState extends State<BridgeInstallPage> {
  _InstallPhase _phase = _InstallPhase.installing;
  String _status = '正在检查运行环境…';
  HttpDownloadState? _download;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 首帧之后再动手：检查与下载都是异步的，别在 build 里起
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (BridgeInstaller.isRuntimeReady()) {
      widget.onReady();
      return;
    }

    setState(() {
      _phase = _InstallPhase.installing;
      _status = '正在识别设备…';
      _error = null;
      _download = null;
    });

    try {
      final abi = await BridgeInstaller.detectDeviceAbi();
      if (abi == null) {
        throw StateError('认不出这台设备的 ABI，选不了对应的 Java 运行环境');
      }

      await BridgeInstaller.installRuntime(
        abi: abi,
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _status = status);
        },
        onProgress: (state) {
          if (!mounted) return;
          setState(() => _download = state);
        },
      );

      if (!mounted) return;
      // 复核一遍：两项都在才算装好（只解了一个 JRE 包的半成品会被拦下）
      if (!BridgeInstaller.isRuntimeReady()) {
        throw StateError('装完了但运行环境还不齐，请重试');
      }
      widget.onReady();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _InstallPhase.failed;
        _error = removeNewlines('$error');
      });
    }
  }

  /// 已下载 / 总量 · 速度（总量还没探到时只报已下载与速度）
  String _progressText(HttpDownloadState state) {
    final downloaded = formatBytes(state.downloaded);
    final speed = state.speedText;
    if (state.total <= 0) return '$downloaded · $speed';
    return '$downloaded / ${formatBytes(state.total)} · $speed';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final download = _download;
    final isFailed = _phase == _InstallPhase.failed;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      body: Center(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(
                '准备运行环境',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              Text(
                'Android 上要跑桌面版游戏，需要一份 Java 运行环境与 Copper 桥。'
                '只在首次启动下载一次，装好后自动进入启动器。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.itemSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              PercentBar(
                total: 1,
                dataList: [
                  PercentBarData(value: download?.progress ?? 0),
                ],
              ),
              Text(
                _status,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (download != null && download.progress > 0)
                Text(
                  _progressText(download),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.itemHint,
                  ),
                  textAlign: TextAlign.center,
                ),
              if (isFailed) ...[
                Text(
                  _error ?? '安装失败',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                ReboundButton(
                  onTap: _start,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Text('重试'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
