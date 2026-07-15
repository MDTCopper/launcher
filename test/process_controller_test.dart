// ============================================================
// WindowProcessController 独立测试脚本
// 用法: dart run test\process_controller_test.dart
// 无需 Flutter，纯 Dart 运行
// ============================================================

import 'dart:io';
import 'package:copper_launcher/util/io/process_controller.dart';

void main() async {
  print('=== WindowProcessController 测试 ===\n');

  await testNormalMode();
  await testIndependentMode();
  await testAttach();
  await testExplorer();

  print('\n=== 全部测试完成 ===');
}

// ----------------------------------------------------------
// 测试 1：普通模式 + 窗口控制 (notepad)
// ----------------------------------------------------------
Future<void> testNormalMode() async {
  print('--- 测试 1: 普通模式 (notepad.exe) ---');

  final ctrl = WindowProcessController();

  final ok = await ctrl.start(exePath: 'notepad.exe');
  print('  start() => $ok');
  print('  processId = ${ctrl.processId}');
  print('  hwndAddress = ${ctrl.hwndAddress}');
  print('  getTitle = ${ctrl.getTitle()}');
  print('  isVisible = ${ctrl.isVisible}');

  if (ctrl.processId == 0) {
    print('  ❌ PID 为 0！checking _process...');
  } else {
    print('  ✅ PID 正常');
  }

  if (ctrl.hwndAddress != 0) {
    // 测试窗口操作
    print('  测试最小化...');
    ctrl.minimize();
    await Future.delayed(const Duration(milliseconds: 500));
    print('  isMinimized = ${ctrl.isMinimized}');

    print('  测试还原...');
    ctrl.restore();
    await Future.delayed(const Duration(milliseconds: 500));

    print('  测试聚焦...');
    ctrl.focus();
    await Future.delayed(const Duration(milliseconds: 300));
    print('  ✅ 窗口操作完成');
  } else {
    print('  ❌ HWND 为 0，窗口控制不可用');
  }

  print('  发送 WM_CLOSE...');
  ctrl.closeWindow();
  await Future.delayed(const Duration(seconds: 1));
  print('  isRunning = ${ctrl.isRunning}');

  ctrl.dispose();
  print('--- 测试 1 结束 ---\n');
}

// ----------------------------------------------------------
// 测试 2：独立模式 + 模拟 Flutter 退出后进程存活
// ----------------------------------------------------------
Future<void> testIndependentMode() async {
  print('--- 测试 2: 独立模式 (ping localhost -n 20) ---');

  // 用 ping 作为测试子进程（运行约 20 秒，有 stdout 输出）
  final ctrl = WindowProcessController();

  // 监听输出
  ctrl.stdoutStream.listen((s) {
    print('  [stdout] $s');
  });

  final ok = await ctrl.start(
    exePath: 'ping',
    args: ['localhost', '-n', '20'],
    independent: true, // 关键：独立模式
  );

  print('  start() => $ok');
  print('  processId = ${ctrl.processId}');

  // 等几秒确认进程在跑
  await Future.delayed(const Duration(seconds: 3));
  print('  3秒后 isRunning = ${ctrl.isRunning}');
  print('  processId = ${ctrl.processId}');

  // 模拟 Flutter 退出：dispose 不杀进程
  final savedPid = ctrl.processId;
  print('  保存 PID = $savedPid');

  ctrl.dispose(); // 独立模式：不杀子进程
  print('  dispose() 完成');
  await Future.delayed(const Duration(milliseconds: 500));

  // 检查进程是否还活着
  try {
    final result = Process.runSync('tasklist', ['/FI', 'PID eq $savedPid']);
    final output = result.stdout.toString();
    final alive = output.contains('$savedPid');
    print('  tasklist 检查: ${alive ? "✅ 进程存活" : "❌ 进程已死"}');
    if (alive) {
      // 杀掉测试进程
      Process.runSync('taskkill', ['/F', '/PID', '$savedPid']);
      print('  已清理测试进程');
    }
  } catch (e) {
    print('  tasklist 检查失败: $e');
  }

  print('--- 测试 2 结束 ---\n');
}

// ----------------------------------------------------------
// 测试 3：attachToPid / attachToTitle
// ----------------------------------------------------------
Future<void> testAttach() async {
  print('--- 测试 3: attach ---');

  // 先启动一个 notepad
  final starter = WindowProcessController();
  await starter.start(exePath: 'notepad.exe');
  final pid = starter.processId;
  print('  启动 notepad, PID = $pid');

  await Future.delayed(const Duration(seconds: 1));

  // 用一个新 controller 通过 PID 连接
  final ctrl2 = WindowProcessController();
  final attached = ctrl2.attachToPid(pid);
  print('  attachToPid($pid) => $attached');
  print('  hwndAddress = ${ctrl2.hwndAddress}');
  print('  getTitle = ${ctrl2.getTitle()}');

  if (attached) {
    ctrl2.minimize();
    await Future.delayed(const Duration(milliseconds: 300));
    ctrl2.restore();
    print('  ✅ attach 后窗口操作成功');
  }

  // 按标题连接
  final ctrl3 = WindowProcessController();
  final byTitle = ctrl3.attachToTitle('记事本'); // 中文 Windows
  if (!byTitle) {
    final byTitleEn = ctrl3.attachToTitle('Notepad');
    print('  attachToTitle("Notepad") => $byTitleEn');
  } else {
    print('  attachToTitle("记事本") => $byTitle');
  }

  // 清理
  starter.closeWindow();
  await Future.delayed(const Duration(seconds: 1));
  ctrl2.dispose();
  ctrl3.dispose();
  starter.dispose();
  print('--- 测试 3 结束 ---\n');
}

// ----------------------------------------------------------
// 测试 4：资源管理器防重复打开
// ----------------------------------------------------------
Future<void> testExplorer() async {
  print('--- 测试 4: 资源管理器 ---');

  final testPath = Platform.environment['USERPROFILE'] ?? 'C:\\';
  print('  打开: $testPath');
  WindowProcessController.openExplorer(testPath);
  await Future.delayed(const Duration(seconds: 1));

  print('  再次打开同一路径（应激活已有窗口而非新建）...');
  WindowProcessController.openExplorer(testPath);

  print('--- 测试 4 结束 ---\n');
}
