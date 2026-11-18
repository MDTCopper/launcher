import 'dart:async';
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/generated/android_call.g.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/system_info.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

/// 刷新率诊断写进运行日志（`[debug]` 等级，按 `Display` tag 过滤）。
///
/// 帧率的**控制**由设置页通过 `flutter_displaymode` 完成（自动 = 不请求；手动 = 指定系统模式），
/// 这里只负责把「现在实际是什么状态」留下来，方便出问题时对照：
///
/// - 冷启动 `startup`、切回前台 `resume`：立刻记一次，2 秒后再记一次并做一次帧节奏测量
///   （测量会强制连续出帧，只能证明 vsync 的节奏）；
/// - 设置页切档：`设置切换` / `+2s` / `+10s` 三次，看请求有没有落地、系统会不会又降回去；
/// - 每 10 秒一条 `实时`：**不强制出帧**，按真实帧算 fps 与光栅分布 —— 这条才对应手感。
class DisplayRateProbe with WidgetsBindingObserver {
  DisplayRateProbe._();

  /// 日志里统一用这个 tag 过滤：`Display`
  static const _tag = 'Display';

  /// 采样间隔：模式切换 / 首帧合成要几十到几百毫秒，2 秒足够看到稳态
  static const _settle = Duration(seconds: 2);

  /// 帧率测量窗口：太短会被启动期抖动带偏，太长会一直占着渲染
  static const _cadenceWindow = Duration(seconds: 1);

  /// 实时统计间隔
  static const _realtimeEvery = Duration(seconds: 10);

  static DisplayRateProbe? _instance;

  /// 前台周期令牌：切前台的顺序一变，旧序列就作废，免得两份时间线交叉写
  int _token = 0;

  /// 最近一批帧时序（强制测量用）
  final List<FrameTiming> _timings = [];

  /// 最近几批帧时序（每批约 1 秒）：实时统计用，不强制出帧
  final List<List<FrameTiming>> _recentBatches = [];

  void _onTimings(List<FrameTiming> timings) {
    _timings
      ..clear()
      ..addAll(timings);
    _recentBatches.add(timings);
    if (_recentBatches.length > 10) _recentBatches.removeAt(0);
  }

  /// 只在 Android 上挂观察者：其它平台没有这个宿主通道
  static void start() {
    if (!Platform.isAndroid || _instance != null) return;
    final probe = DisplayRateProbe._();
    _instance = probe;
    WidgetsBinding.instance.addObserver(probe);
    SchedulerBinding.instance.addTimingsCallback(probe._onTimings);
    unawaited(probe._run('startup'));
    probe._startRealtime();
  }

  /// 设置页切档后调用：立刻记一次，+2 秒 / +10 秒各再记一次
  static Future<void> reportModeChange() async {
    final probe = _instance;
    if (probe == null) return;
    await probe._write('设置切换');
    await Future<void>.delayed(_settle);
    await probe._write('设置切换+2s');
    await Future<void>.delayed(_settle * 4);
    await probe._write('设置切换+10s');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_run('resume'));
  }

  Future<void> _run(String reason) async {
    final token = ++_token;
    await _write(reason);

    await Future<void>.delayed(_settle);
    if (token != _token) return;
    await _write('$reason+2s');
    await _measure('$reason+2s');
  }

  /// 实时统计：每 10 秒按**真实帧**汇总一次（不强制出帧）
  ///
  /// 界面静止时帧很少（会注明），滚动 / 切页时才看得出实际帧率。
  void _startRealtime() {
    Timer.periodic(_realtimeEvery, (_) {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      unawaited(_writeRealtime());
    });
  }

  Future<void> _writeRealtime() async {
    if (!Log.ready || _recentBatches.isEmpty) return;
    final frames = _recentBatches.expand((batch) => batch).toList();
    if (frames.isEmpty) return;
    final start = frames.first.timestampInMicroseconds(FramePhase.vsyncStart);
    final end = frames.last.timestampInMicroseconds(FramePhase.rasterFinish);
    final seconds = (end - start) / Duration.microsecondsPerSecond;
    final fps = seconds > 0 ? frames.length / seconds : 0.0;
    final raster = frames
        .map((frame) => frame.rasterDuration.inMicroseconds / 1000)
        .toList()
      ..sort();
    double at(double q) => raster[((raster.length - 1) * q).round()];
    final note = frames.length < 10 ? '（界面基本静止）' : '';
    final background = config.setting.personalizationOptions.colorfulBackground;
    addLog(
      .debug,
      '刷新率[实时] 近 ${seconds.toStringAsFixed(1)}s ${fps.toStringAsFixed(1)} fps'
          ' · ${frames.length} 帧$note'
          ' · 光栅 p50 ${at(.5).toStringAsFixed(1)} / p90 ${at(.9).toStringAsFixed(1)}'
          ' / max ${at(1).toStringAsFixed(1)} ms'
          ' · 多彩背景 ${background ? '开' : '关'}',
      tag: _tag,
    );
  }

  Future<void> _write(String reason) async {
    if (!Log.ready) return;
    final info = await SysInfo.getDisplayFrameRate();
    if (info == null) {
      addLog(.debug, '刷新率[$reason] 读不到显示信息', tag: _tag);
      return;
    }
    addLog(
      .debug,
      '刷新率[$reason] ${_describe(info, await _preferredModeLabel())}',
      tag: _tag,
    );
  }

  /// 设置里选的显示模式（flutter_displaymode 的口径）；读不到就返回「未知」
  Future<String> _preferredModeLabel() async {
    try {
      return _modeLabel(await FlutterDisplayMode.preferred);
    } on Object {
      return '未知';
    }
  }

  String _modeLabel(DisplayMode mode) => mode.id == 0
      ? '自动'
      : '${mode.width}×${mode.height} @ ${mode.refreshRate.round()}Hz';

  String _describe(DisplayFrameRateInfo info, String preferredMode) {
    return [
      '当前 ${_hz(info.current)} / 设置 $preferredMode / 面板最高 ${_hz(info.peak)}',
      '显示模式 ${_hz(info.modeRate)}（id ${info.modeId}）'
          ' · API ${info.apiLevel}'
          ' · ${info.arrSupported ? '支持 ARR' : '无 ARR'}'
          ' · 省电 ${info.powerSave ? '开' : '关'}'
          ' · isGame ${info.gameApp ? '是' : '否'}',
    ].join('\n');
  }

  /// 实测 Flutter 的帧节奏：Ticker 每个 vsync 回调一次，取帧间隔中位数换算出实际 Hz
  ///
  /// 中位数而不是平均数：启动期的卡顿只会丢帧，不会拉长 vsync 间隔。
  Future<void> _measure(String label) async {
    if (!Log.ready) return;
    final gaps = <int>[];
    _timings.clear();
    var frames = 0;
    var last = Duration.zero;
    final ticker = Ticker((elapsed) {
      if (last != Duration.zero) {
        final gap = elapsed - last;
        if (gap.inMicroseconds > 0) gaps.add(gap.inMicroseconds);
      }
      last = elapsed;
      frames++;
    });
    final watch = Stopwatch()..start();
    ticker.start();
    await Future<void>.delayed(_cadenceWindow);
    ticker.dispose();
    watch.stop();
    if (!Log.ready) return;

    final seconds = watch.elapsedMicroseconds / Duration.microsecondsPerSecond;
    final fps = seconds > 0 ? frames / seconds : 0.0;
    final medianMs = gaps.isEmpty
        ? 0.0
        : (gaps..sort())[gaps.length ~/ 2] / 1000.0;
    final vsync = medianMs > 0 ? 1000 / medianMs : 0.0;
    addLog(
      .debug,
      '刷新率[$label] 强制出帧 ${fps.toStringAsFixed(1)} fps'
          ' · 帧间隔中位数 ${medianMs.toStringAsFixed(2)} ms（≈${vsync.toStringAsFixed(1)} Hz）'
          '${_budgetNote(vsync)}',
      tag: _tag,
    );
  }

  /// 帧开销分布：光栅是主要成本，预算 = 一个 vsync 周期
  ///
  /// `p50` 常年超预算说明「每帧都贵」（重绘范围大），只有 `max` 高则是偶发（管线编译 / 弹窗）。
  String _budgetNote(double vsync) {
    if (_timings.isEmpty) return '';
    double at(List<double> sorted, double q) =>
        sorted[((sorted.length - 1) * q).round()];
    final raster = _timings
        .map((timing) => timing.rasterDuration.inMicroseconds / 1000)
        .toList()
      ..sort();
    final total = _timings
        .map((timing) => timing.totalSpan.inMicroseconds / 1000)
        .toList()
      ..sort();
    final budgetMs = vsync > 0 ? 1000 / vsync : 0.0;
    final over = budgetMs <= 0
        ? 0
        : raster.where((ms) => ms > budgetMs).length;
    return ' · 光栅 p50 ${at(raster, .5).toStringAsFixed(1)}'
        ' / p90 ${at(raster, .9).toStringAsFixed(1)}'
        ' / max ${at(raster, 1).toStringAsFixed(1)} ms'
        '，总时长 p50 ${at(total, .5).toStringAsFixed(1)} ms'
        '（${_timings.length} 帧，超预算 $over 帧）';
  }

  String _hz(double value) {
    if (value <= 0) return '未知';
    final rounded = value.roundToDouble();
    final text = (value - rounded).abs() < 0.05
        ? rounded.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text Hz';
  }
}
