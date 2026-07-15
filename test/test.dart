import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/ui/util/animation/animated_opacity_size.dart';
import 'package:copper_launcher/ui/util/widget/feature_button.dart';
import 'package:copper_launcher/util/format/byte_unit.dart';
import 'package:copper_launcher/util/io/file_reader.dart';
import 'package:copper_launcher/util/io/http_helper.dart';
import 'package:copper_launcher/util/io/process_controller.dart';
import 'package:copper_launcher/util/io/process_launcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:copper_launcher/data/mindustry_settings.dart';
import 'package:copper_launcher/ui/util/widget/feature_text_field.dart';

class Test extends StatefulWidget {
  const Test({super.key});

  @override
  State<StatefulWidget> createState() => _Test();
}

class _Test extends State<Test> {
  var t = false;

  static MindustrySettings? setting;

  void _test() async {
    // final list = <int>[];
    // for (int i = 0; i < 1000000; i++) {
    //   var n = 0;
    //   var r =Random().nextInt(2);
    //   while (r == 1) {
    //     r =Random().nextInt(2);
    //     n++;
    //   }
    //   list.add(n);
    // }
    //
    // final all = list.fold(0, (a,b)=>a+b);
    // print('${all/list.length/2}');
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ReboundIconButton(
          icon: Icons.eighteen_mp,
          content: '666',
          onTap: _test,
        ),
        AnimatedOpacitySize(
          alignment: Alignment.topCenter,
          child: t ? Text('666') : null,
        ),
        Text('data'),
      ],
    );
  }
}

class ElectricConverter extends StatefulWidget {
  const ElectricConverter({super.key});

  @override
  State<StatefulWidget> createState() => _ElectricConverterState();
}

class _ElectricConverterState extends State<ElectricConverter> {
  bool imaginaryToAngle = true;

  double imaginary = 6;
  double real = 8;
  double modulus = 0.0;
  double angle = 0.0;

  late final TextEditingController controller1;
  late final TextEditingController controller2;

  @override
  void initState() {
    super.initState();
    controller1 = TextEditingController(text: real.toString())
      ..addListener(() {
        setState(() {
          if (imaginaryToAngle) {
            real = double.parse(controller1.text);
          } else {
            modulus = double.parse(controller1.text);
          }
        });
      });
    controller2 = TextEditingController(text: imaginary.toString())
      ..addListener(() {
        setState(() {
          if (imaginaryToAngle) {
            imaginary = double.parse(controller2.text);
          } else {
            angle = double.parse(controller2.text);
          }
        });
      });
  }

  @override
  Widget build(BuildContext context) {
    if (imaginaryToAngle) {
      modulus = sqrt(imaginary * imaginary + real * real);
      angle = atan(imaginary / real) * 180 / pi;
      if (real.isNegative) {
        if (angle.isNegative) {
          angle += 180;
        } else {
          angle -= 180;
        }
      }
    } else {
      real = cos(angle * pi / 180) * modulus;
      imaginary = sin(angle * pi / 180) * modulus;
    }

    return Material(
      borderRadius: BorderRadius.circular(16),
      elevation: 8,
      child: Container(
        margin: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: 8,
          children: [
            ReboundIconButton(
              icon: Icons.refresh,
              content: imaginaryToAngle ? '代数式转为极坐标' : '极坐标转为代数式',
              onTap: () {
                imaginaryToAngle = !imaginaryToAngle;
                if (imaginaryToAngle) {
                  controller1.text = real.toStringAsFixed(3);
                  controller2.text = imaginary.toStringAsFixed(3);
                } else {
                  controller1.text = modulus.toStringAsFixed(3);
                  controller2.text = angle.toStringAsFixed(3);
                }
              },
            ),
            SizedBox(
              width: 200,
              child: Row(
                spacing: 8,
                children: [
                  Expanded(child: OutlinedTextField(controller: controller1)),
                  Text(imaginaryToAngle ? '+' : '∠'),
                  Expanded(child: OutlinedTextField(controller: controller2)),
                  Text(imaginaryToAngle ? 'j' : '°'),
                ],
              ),
            ),
            Text(
              imaginaryToAngle
                  ? '${modulus.toStringAsFixed(3)}∠${angle.toStringAsFixed(3)}'
                  : '${real.toStringAsFixed(3)}${imaginary.isNegative ? '' : '+'}${imaginary.toStringAsFixed(3)}j',
            ),
          ],
        ),
      ),
    );
  }
}

class DownloadSpeedTestWidget extends StatefulWidget {
  const DownloadSpeedTestWidget({super.key});

  @override
  State<StatefulWidget> createState() => _DownloadSpeedTestWidgetState();
}

class _DownloadSpeedTestWidgetState extends State<DownloadSpeedTestWidget> {
  final HttpHelper _http = HttpHelper();
  CancelToken? _cancelToken;

  bool _isDownloading = false;
  double _progress = 0;
  double _speed = 0;
  int _downloaded = 0;
  int _total = 0;
  HttpDownloadStatus _status = HttpDownloadStatus.idle;
  int _chunkCount = 0;
  int _completedChunks = 0;
  List<HttpChunkInfo> _chunks = [];

  late final TextEditingController _speedController;
  late final TextEditingController _urlController;

  static const _defaultUrl =
      'https://github.com/Anuken/Mindustry/releases/download/v158.1/Mindustry.jar';

  @override
  void initState() {
    super.initState();
    _speedController = TextEditingController(text: '256');
    _urlController = TextEditingController(text: _defaultUrl);
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _speedController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    _cancelToken = CancelToken();
    final sl = int.tryParse(_speedController.text) ?? 0;
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final savePath = p.join(
      p.current,
      'http_helper_speed_test_${DateTime.now().millisecondsSinceEpoch}.jar',
    );

    setState(() {
      _isDownloading = true;
      _progress = 0;
      _speed = 0;
      _downloaded = 0;
      _total = 0;
      _status = HttpDownloadStatus.connecting;
      _chunkCount = 0;
      _completedChunks = 0;
      _chunks = [];
    });

    try {
      await _http.download(
        url: url,
        savePath: savePath,
        speedLimit: sl > 0 ? sl * kb : null,
        chunkCount: 8,
        cancelToken: _cancelToken,
        deleteOnError: true,
        onStatus: (state) {
          if (!mounted) return;
          setState(() {
            _downloaded = state.downloaded;
            _total = state.total;
            _speed = state.speed;
            _progress = state.progress;
            _status = state.status;
            _chunkCount = state.chunkCount;
            _completedChunks = state.completedChunks;
            _chunks = state.chunks;
          });
        },
      );
      if (mounted) {
        setState(() => _isDownloading = false);
        // await File(savePath).delete();
      }
    } on DioException {
      if (mounted) {
        setState(() {
          _status = HttpDownloadStatus.cancelled;
          _isDownloading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = HttpDownloadStatus.failed;
          _isDownloading = false;
        });
      }
    }
  }

  void _stopDownload() {
    _cancelToken?.cancel();
  }

  String _formatBytes(int bytes) {
    if (bytes < kb) return '${bytes}B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)}KB';
    if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)}MB';
    return '${(bytes / gb).toStringAsFixed(2)}GB';
  }

  String _formatSpeed(double speed) {
    if (speed < kb) return '${speed.toStringAsFixed(1)} B/s';
    if (speed < mb) return '${(speed / kb).toStringAsFixed(1)} KB/s';
    return '${(speed / mb).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? Colors.grey[900]! : Colors.grey[100]!;

    return SizedBox(
      width: 500,
      height: 200,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // URL + speed limit row
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 28,
                      child: TextField(
                        controller: _urlController,
                        enabled: !_isDownloading,
                        style: const TextStyle(fontSize: 11),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          hintText: '下载URL',
                          hintStyle: const TextStyle(fontSize: 11),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 56,
                    height: 28,
                    child: TextField(
                      controller: _speedController,
                      enabled: !_isDownloading,
                      style: const TextStyle(fontSize: 11),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        hintText: 'KB/s',
                        hintStyle: const TextStyle(fontSize: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  ReboundIconButton(
                    icon: _isDownloading ? Icons.stop : Icons.play_arrow,
                    content: '',
                    onTap: _isDownloading ? _stopDownload : _startDownload,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: Colors.grey[300],
                ),
              ),
              const SizedBox(height: 4),
              // Chunk indicators
              if (_chunkCount > 1 && _chunks.isNotEmpty)
                SizedBox(
                  height: 14,
                  child: Row(
                    children: _chunks.map((c) {
                      Color color;
                      switch (c.status) {
                        case HttpChunkStatus.complete:
                          color = Colors.green;
                          break;
                        case HttpChunkStatus.downloading:
                          color = Colors.blue;
                          break;
                        case HttpChunkStatus.connecting:
                          color = Colors.orange;
                          break;
                        case HttpChunkStatus.failed:
                          color = Colors.red;
                          break;
                        case HttpChunkStatus.pending:
                          color = Colors.grey;
                      }
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              // Stats
              Row(
                children: [
                  Text(
                    _status == HttpDownloadStatus.idle
                        ? '等待开始'
                        : '${(_progress * 100).toStringAsFixed(1)}%',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _downloaded > 0 ? _formatBytes(_downloaded) : '',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (_total > 0) ...[
                    Text(' / ', style: theme.textTheme.bodySmall),
                    Text(
                      _formatBytes(_total),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (_chunkCount > 1) ...[
                    const SizedBox(width: 6),
                    Text(
                      '[$_completedChunks/$_chunkCount]',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const Spacer(),
                  Text(
                    switch (_status) {
                      HttpDownloadStatus.completed => '完成',
                      HttpDownloadStatus.failed => '失败',
                      HttpDownloadStatus.cancelled => '已取消',
                      HttpDownloadStatus.merging => '合并中',
                      HttpDownloadStatus.connecting => '连接中...',
                      _ when _speed > 0 => _formatSpeed(_speed),
                      _ => '',
                    },
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: switch (_status) {
                        HttpDownloadStatus.failed => Colors.red,
                        HttpDownloadStatus.completed => Colors.green,
                        _ => null,
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== WindowProcessController 测试页面 =====

class WindowProcessControllerTest extends StatefulWidget {
  const WindowProcessControllerTest({super.key});

  @override
  State<StatefulWidget> createState() => _WindowProcessControllerTestState();
}

class _WindowProcessControllerTestState
    extends State<WindowProcessControllerTest> {
  final WindowProcessController _ctrl = WindowProcessController();
  final TextEditingController _pathCtrl = TextEditingController(
    text: 'notepad.exe',
  );
  final TextEditingController _argsCtrl = TextEditingController();
  final TextEditingController _explorerCtrl = TextEditingController(
    text: 'C:\\',
  );
  final TextEditingController _attachPidCtrl = TextEditingController();
  final TextEditingController _attachTitleCtrl = TextEditingController();

  String _status = '未启动';
  String _logs = '';
  bool _independent = false;
  StreamSubscription<String>? _outSub;
  StreamSubscription<String>? _errSub;

  @override
  void initState() {
    super.initState();
  }

  void _listenLogs() {
    _outSub?.cancel();
    _errSub?.cancel();
    _outSub = _ctrl.stdoutStream.listen((s) {
      setState(() => _logs += s);
    });
    _errSub = _ctrl.stderrStream.listen((s) {
      setState(() => _logs += s);
    });
  }

  void _clearLogs() => setState(() => _logs = '');

  void _start() async {
    _listenLogs();
    final ok = await _ctrl.start(
      exePath: _pathCtrl.text,
      args: _argsCtrl.text.split('??').where((s) => s.isNotEmpty).toList(),
      independent: _independent,
    );
    setState(() => _status = ok ? '运行中 PID=${_ctrl.processId}' : '启动失败');
  }

  @override
  void dispose() {
    _outSub?.cancel();
    _errSub?.cancel();
    _ctrl.dispose();
    _pathCtrl.dispose();
    _argsCtrl.dispose();
    _explorerCtrl.dispose();
    _attachPidCtrl.dispose();
    _attachTitleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('WindowProcessController 测试', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('状态: $_status', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pathCtrl,
                decoration: const InputDecoration(
                  labelText: 'exePath',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _argsCtrl,
          decoration: const InputDecoration(
            labelText: 'args (空格分隔)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Checkbox(
              value: _independent,
              onChanged: (v) => setState(() => _independent = v ?? false),
            ),
            const Text('独立模式 (dispose 不杀进程)'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(onPressed: _start, child: const Text('启动')),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                _ctrl.stop();
                setState(() => _status = '已停止');
              },
              child: const Text('停止 (优雅)'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                _ctrl.kill();
                setState(() => _status = '已强制终止');
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('强制终止'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _btn('聚焦', _ctrl.focus),
            _btn('最大化', _ctrl.maximize),
            _btn('最小化', _ctrl.minimize),
            _btn('还原', _ctrl.restore),
            _btn('显示', _ctrl.showWindow),
            _btn('隐藏', _ctrl.hide),
            _btn('设位置', () => _ctrl.setRect(100, 100, 800, 600)),
            _btn(
              '获取标题',
              () => setState(() => _logs += '标题: ${_ctrl.getTitle() ?? "无"}\n'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 独立模式脱离测试
        ElevatedButton.icon(
          onPressed: _launchMindustryDetached,
          icon: const Icon(Icons.launch, size: 16),
          label: const Text('启动 Mindustry 并立即分离 (测试脱离)'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
        ),
        const SizedBox(height: 8),
        // Attach 控件
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _attachPidCtrl,
                decoration: const InputDecoration(
                  labelText: 'PID',
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: () {
                final pid = int.tryParse(_attachPidCtrl.text);
                if (pid != null) {
                  final ok = _ctrl.attachToPid(pid);
                  setState(() => _status = ok ? '已附加 PID=$pid' : '未找到窗口');
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
              ),
              child: const Text('Attach PID', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _attachTitleCtrl,
                decoration: const InputDecoration(
                  labelText: '窗口标题',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: () {
                final ok = _ctrl.attachToTitle(_attachTitleCtrl.text);
                setState(
                  () =>
                      _status = ok ? '已附加: ${_attachTitleCtrl.text}' : '未找到窗口',
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
              ),
              child: const Text('Attach 标题', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _explorerCtrl,
                decoration: const InputDecoration(
                  labelText: '路径',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () =>
                  WindowProcessController.openExplorer(_explorerCtrl.text),
              child: const Text('打开资源管理器'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('日志输出', style: theme.textTheme.bodyMedium),
            const Spacer(),
            TextButton(onPressed: _clearLogs, child: const Text('清空')),
          ],
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              child: Text(
                _logs.isEmpty ? '（无日志）' : _logs,
                style: const TextStyle(
                  color: Colors.lightGreenAccent,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _launchMindustryDetached() async {
    const jar = r'C:\Users\ASUS\Desktop\mindustry-v158.1.jar';
    final launcher = ProcessLauncher();
    final result = await launcher.start(
      exePath: 'java',
      args: ['-jar', jar],
      independent: true,
    );
    if (result == null) {
      setState(() => _status = 'Mind 启动失败');
      return;
    }
    final pid = result.pid;
    setState(() => _status = 'Mind PID=$pid — 已 dispose 启动器，游戏应脱离');
    // 立即释放启动器（不杀进程）
    launcher.dispose();
    _logs += '已启动 Mindustry PID=$pid，启动器已 dispose\n';
    _logs += '现在关闭 Flutter 窗口，游戏应继续运行\n';
    _listenLogs(); // 已 dispose 后流也关闭了，这里只是占位
  }

  Widget _btn(String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
