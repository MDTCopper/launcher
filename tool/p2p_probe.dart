import 'dart:io';

import 'package:copper_launcher/util/net/p2p_probe.dart';

/// P2P 打洞可行性探针（不碰启动器联机代码）
///
/// 用法：
///   1. 两台机器各跑一次 `dart run tool/p2p_probe.dart`
///   2. 它会打印本机 STUN 公网端点，然后等你输入对方的
///   3. 两边都输入对方端点后回车，看是否「双向打通」
///
/// 判断：不同 STUN 服务器给出不同端口 ⇒ 对称 NAT，打洞大概率失败；
/// 只拿到一个结果 ⇒ 判断不了，需要再找能通的 STUN。
Future<void> main(List<String> args) async {
  String? peer;
  var token = 'copper-p2p';
  for (var index = 0; index < args.length; index++) {
    switch (args[index]) {
      case '--peer':
        peer = args[++index];
      case '--token':
        token = args[++index];
    }
  }

  final probe = P2pProbe();
  stdout.writeln('正在查询本机公网端点（STUN）…');
  final discovery = await probe.discover();
  if (!discovery.ok) {
    stdout.writeln('一个 STUN 都没返回。检查 UDP 出网 / 防火墙 / DNS。');
    await probe.close();
    exitCode = 2;
    return;
  }
  for (final endpoint in discovery.endpoints) {
    stdout.writeln('  ${endpoint.server} → ${endpoint.text}');
  }
  if (discovery.multipleAddresses) {
    stdout.writeln('⚠ 不同 STUN 看到的公网 IP 都不一样：多出口 / 负载均衡，打洞更难。');
  }
  if (discovery.symmetric) {
    stdout.writeln('⚠ 不同 STUN 看到的端口不同：大概率是对称 NAT，打洞成功率低。');
  } else if (discovery.undetermined) {
    stdout.writeln('只拿到一个结果，判断不了 NAT 类型。');
  } else {
    stdout.writeln('✓ 多个 STUN 看到同一个端点：锥形 NAT，打洞有希望。');
  }

  peer ??= _prompt('输入对方公网端点（ip:port）：');
  if (peer == null || peer.isEmpty) {
    stdout.writeln('没有对方端点，退出。');
    await probe.close();
    return;
  }
  final parts = peer.split(':');
  if (parts.length != 2 || int.tryParse(parts[1]) == null) {
    stdout.writeln('端点格式不对，要 ip:port');
    await probe.close();
    exitCode = 2;
    return;
  }

  stdout.writeln('开始向 $peer 打洞（最多 20 秒）…');
  final result = await probe.punch(
    peerHost: parts[0],
    peerPort: int.parse(parts[1]),
    token: token,
    log: (line) => stdout.writeln('  $line'),
  );
  if (result.ok) {
    stdout.writeln(
      '✅ 双向打通：${result.peer}，RTT ${result.rtt?.inMilliseconds} ms',
    );
  } else {
    stdout.writeln('❌ 失败：${result.message}');
  }
  await probe.close();
}

String? _prompt(String text) {
  stdout.write(text);
  return stdin.readLineSync();
}
