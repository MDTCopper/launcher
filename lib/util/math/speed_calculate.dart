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

  void _updateSpeed(Timer timer) {

    if(_timeList.length != _dataList.length){
      _dataList.clear();
      _timeList.clear();
      speed = 0.0;
      return;
    }
    int sampleQuantity = 16;

    final now = DateTime.now();

    _timeList.insert(0,now);
    _dataList.insert(0,dataNotifier.value);


    final length = _timeList.length;

    if (length < 2 ) return;
    if (length > sampleQuantity){
      _timeList.removeAt(sampleQuantity);
      _dataList.removeAt(sampleQuantity);
    }

    double timeDiff = 0.0;
    double dataDiff = 0.0;

    final half = (length/2).floor();

    for (int i = 0; i < half; i++) {
      dataDiff += _dataList[i + half] - _dataList[i];
      timeDiff +=
          _timeList[i + half].difference(_timeList[i]).inMilliseconds / 1000;
    }

    speed = dataDiff/timeDiff;
    updateCallback.call(speed);
  }

  void cancel() {
    _timer.cancel();
  }
}
