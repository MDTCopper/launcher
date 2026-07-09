import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:copperlauncher_main/core/app_config.dart';
import 'package:copperlauncher_main/core/app_constant.dart';
import 'package:copperlauncher_main/data/local_asset.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_button.dart';
import 'package:copperlauncher_main/util/format/byte_unit.dart';
import 'package:copperlauncher_main/util/io/file_reader.dart';
import 'package:copperlauncher_main/util/io/http_helper.dart';
import 'package:copperlauncher_main/util/math/range.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:copperlauncher_main/data/mindustry_settings.dart';
import 'package:copperlauncher_main/ui/util/widget/feature_text_field.dart';

class Test extends StatefulWidget {
  const Test({super.key});

  @override
  State<StatefulWidget> createState() => _Test();
}

class _Test extends State<Test> {
  var t = false;

  static MindustrySettings? setting;

  //todo标记
  void _test() async {}

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DownloadSpeedTestWidget(),
        ReboundIconButton(
          icon: Icons.e_mobiledata,
          content: 'a===++',
          onTap: _test,
        ),
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
    controller1 = TextEditingController(text: real.toString())..addListener(() {
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
                    children:
                        _chunks.map((c) {
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
