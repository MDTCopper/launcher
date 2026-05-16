import 'dart:async';

import 'package:flutter/cupertino.dart';

class SpeedCalculator {
  final void Function(double) updateCallback;
  final Duration interval;
  ValueNotifier<int> dataNotifier;

  double speed = 0.0;
  late final Timer _timer;
  final List<int> _dataList = [];
  final List<DateTime> _timeList = [];

  SpeedCalculator({
    required this.dataNotifier,
    required this.updateCallback,
    this.interval = const Duration(milliseconds: 200),
  }) {
    _timer = Timer.periodic(interval, _updateSpeed);
  }

  void _updateSpeed(Timer _) {
    if (_timeList.length != _dataList.length) {
      _dataList.clear();
      _timeList.clear();
      speed = 0.0;
      return;
    }
    int sampleQuantity = 16;

    final now = DateTime.now();

    _timeList.add(now);
    _dataList.add(dataNotifier.value);

    final length = _timeList.length;

    if (length < 2) return;
    if (length > sampleQuantity) {
      _timeList.removeAt(0);
      _dataList.removeAt(0);
    }

    double timeDiff = 0.0;
    double dataDiff = 0.0;

    final half = (length / 2).floor();

    for (int i = 0; i < half; i++) {
      dataDiff += _dataList[i] - _dataList[i + half];
      timeDiff +=
          _timeList[i].difference(_timeList[i + half]).inMilliseconds / 1000;
    }

    speed = dataDiff / timeDiff;
    updateCallback.call(speed);
  }

  void cancel() {
    _timer.cancel();
  }
}
