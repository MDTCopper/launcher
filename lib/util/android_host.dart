import 'dart:io';

import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/services.dart';

/// 安卓宿主（`MainActivity`）开给 Dart 侧的一条小通道
///
/// 只放 Dart 够不着的事：`moveTaskToBack` 是 Activity 的方法。
/// 桌面端没有这条通道，所以每个入口都先按平台挡掉
class AndroidHost {
  AndroidHost._();

  static const _channel = MethodChannel('io.github.copper.launcher/host');

  /// 把启动器移到后台：**不销毁进程**，再点图标回到原位
  ///
  /// 真正的结束交给系统（「最近任务」里划掉 / 系统回收）；
  /// 失败只记日志 —— 调用方是返回键回调，没有能吞下异常的地方
  static Future<void> moveTaskToBack() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('moveTaskToBack');
    } on Object catch (error) {
      addLog(.warning, '退到后台失败：${removeNewlines('$error')}', tag: 'Host');
    }
  }

  /// 结束游戏进程（`:mdt_process`）
  ///
  /// 游戏由桥跑在那个进程里，Dart 侧没有 [Process] 句柄；宿主那边走的是
  /// `io.github.copper.GameProcess`（桥启动前清上一局用的同一份）
  static Future<void> killGameProcess() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('killGameProcess');
    } on Object catch (error) {
      addLog(.warning, '结束游戏进程失败：${removeNewlines('$error')}', tag: 'Host');
    }
  }

  /// 游戏进程还在不在；**判不了时返回 null**
  ///
  /// 调用方拿 null 要按「已退出」处理 —— 宁可多报一次退出，也不要永远不报
  static Future<bool?> isGameProcessRunning() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<bool>('isGameProcessRunning');
    } on Object catch (error) {
      addLog(.warning, '查询游戏进程失败：${removeNewlines('$error')}', tag: 'Host');
      return null;
    }
  }
}
