import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/data/net/lanlink/lanlink_api.dart';
import 'package:copper_launcher/data/net/lanlink/lanlink_models.dart';
import 'package:copper_launcher/util/io/log.dart';

/// 房主侧的控制面连接（`/ws/mod`）
///
/// 协议见社区模组仓库的 `proto/PROTOCOL.md` §1；控制面只走信令，
/// 真正的游戏流量由端点中继转发（见 `lanlink_host_session.dart`）
class LanLinkHostClient {
  LanLinkHostClient._(this._socket);

  /// 控制面当前支持的协议版本；低于 3 时直连（P2P）不可用，只能走中继
  static const int protocolVersion = 3;

  final WebSocket _socket;

  LanLinkHostRoom? _room;
  Map<String, Object?>? _createPayload;

  final _closed = Completer<void>();
  final _roomClosed = Completer<String>();

  /// 开房结果；[open] 返回后一定非空
  LanLinkHostRoom get room => _room!;

  /// 控制面通知关房、或连接断开时完成
  Future<String> get onRoomClosed => _roomClosed.future;

  Future<void> get closed => _closed.future;

  /// 连上控制面并开房，拿到 `room_ok` 才返回
  ///
  /// [gamePort] 是本机游戏监听端口；端点会把接进来的客人流量中继到它
  static Future<LanLinkHostClient> open({
    required String roomName,
    required int gamePort,
    bool isPublic = false,
    String? token,
    String? controlUrl,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final base = LanLinkApi.normalizeBaseUrl(controlUrl);
    final wsUrl = '${base.replaceFirst(RegExp('^http'), 'ws')}/ws/mod';

    WebSocket socket;
    try {
      socket = await WebSocket.connect(wsUrl).timeout(timeout);
    } on Object catch (error) {
      throw LanLinkException(message: '连不上联机服务（$wsUrl）：$error');
    }

    final client = LanLinkHostClient._(socket);
    final ready = Completer<LanLinkHostRoom>();
    unawaited(client._pump(ready));

    // create_room 要等 hello_ok 才发，先把载荷挂上
    client._createPayload = {
      'op': 'create_room',
      'name': roomName,
      'public': isPublic,
      'vanilla_join': true,
      'game_port': gamePort,
    };
    socket.add(
      jsonEncode({
        'op': 'hello',
        'ver': protocolVersion,
        'platform': 'desktop',
        'mod_version': 'copper',
        'token': token ?? '',
      }),
    );

    try {
      client._room = await ready.future.timeout(
        timeout,
        onTimeout: () => throw const LanLinkException(message: '开房超时：控制面没有回应'),
      );
    } on Object {
      await client.close();
      rethrow;
    }
    return client;
  }

  Future<void> _pump(Completer<LanLinkHostRoom> ready) async {
    try {
      await for (final message in _socket) {
        if (message is! String) continue;
        Map<String, dynamic> json;
        try {
          json = (jsonDecode(message) as Map).cast<String, dynamic>();
        } on Object {
          continue;
        }
        switch ('${json['op'] ?? ''}') {
          case 'hello_ok':
            final payload = _createPayload;
            if (payload != null) _socket.add(jsonEncode(payload));
          case 'room_ok':
            if (!ready.isCompleted) {
              ready.complete(LanLinkHostRoom.fromJson(json));
            }
          case 'error':
            final text = '${json['msg'] ?? json['message'] ?? '控制面报错'}';
            final code = '${json['code'] ?? ''}';
            if (!ready.isCompleted) {
              ready.completeError(LanLinkException(code: code, message: text));
            } else {
              _finishRoom('$text${code.isEmpty ? '' : '（$code）'}');
            }
          case 'ping':
            _socket.add(jsonEncode({'op': 'pong'}));
          case 'room_closed':
            _finishRoom('${json['reason'] ?? '房间已关闭'}');
          default:
            break;
        }
      }
      _finishRoom('控制面连接已断开');
    } on Object catch (error) {
      if (!ready.isCompleted) {
        ready.completeError(LanLinkException(message: '控制面连接异常：$error'));
      } else {
        _finishRoom('控制面连接异常：$error');
      }
    } finally {
      if (!_closed.isCompleted) _closed.complete();
    }
  }

  void _finishRoom(String reason) {
    if (!_roomClosed.isCompleted) _roomClosed.complete(reason);
  }

  /// 主动关房：先告诉控制面，再断开
  Future<void> close() async {
    if (_socket.readyState == WebSocket.open) {
      try {
        // WebSocket 是 StreamSink，没有 flush；后面的 close 会把已入队的帧发出去
        _socket.add(jsonEncode({'op': 'close_room'}));
      } on Object catch (error) {
        addLog(.warning, '发送 close_room 失败：$error', tag: 'LanLink');
      }
    }
    try {
      await _socket.close();
    } on Object {
      // 已经断了
    }
    _finishRoom('已关房');
    if (!_closed.isCompleted) _closed.complete();
  }
}
