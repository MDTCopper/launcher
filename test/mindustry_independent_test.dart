// ============================================================
// Mindustry 独立模式测试（使用 ProcessLauncher）
// 用法: dart run test\mindustry_independent_test.dart
// ============================================================

import 'dart:io';
import 'package:copperlauncher_main/util/io/process_launcher.dart';

void main() async {
  print('=== Mindustry 独立模式测试 (ProcessLauncher) ===\n');

  final jarPath = r'C:\Users\ASUS\Desktop\mindustry-v158.1.jar';
  final jarFile = File(jarPath);

  if (!await jarFile.exists()) {
    print('❌ 找不到 $jarPath');
    return;
  }

  final launcher = ProcessLauncher();

  launcher.stdoutStream.listen((s) => print('  [stdout] $s'));
  launcher.stderrStream.listen((s) => print('  [stderr] $s'));

  print('启动: java -jar $jarPath (independent: true)\n');

  final result = await launcher.start(
    exePath: 'java',
    args: ['-jar', jarPath],
    independent: true,
  );

  if (result == null) {
    print('❌ 启动失败');
    return;
  }

  print('✅ 已启动, PID = ${result.pid}');

  // 等 5 秒
  print('等待 5 秒...\n');
  await Future.delayed(const Duration(seconds: 5));

  print('dispose()...');
  launcher.dispose();

  await Future.delayed(const Duration(seconds: 2));

  // 检查存活
  final r = Process.runSync('tasklist', ['/FI', 'PID eq ${result.pid}']);
  if (r.stdout.toString().contains('${result.pid}')) {
    print('✅ 游戏进程存活 (PID=${result.pid})');
    print('   手动关闭游戏, 或: taskkill /F /PID ${result.pid}');
  } else {
    print('❌ 游戏进程已退出');
  }
}
