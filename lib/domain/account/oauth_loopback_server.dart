import 'dart:async';
import 'dart:io';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_config.dart';

/// 浏览器回调带回来的结果
class OAuthCallbackResult {
  const OAuthCallbackResult({
    this.code,
    this.state,
    this.error,
    this.errorDescription,
  });

  final String? code;
  final String? state;

  /// 失败原因：MindAuth 的 `error`，或本机判定的 `state_mismatch` / `timeout`
  final String? error;
  final String? errorDescription;

  bool get isSuccess => error == null && (code?.isNotEmpty ?? false);
}

/// 桌面端 OAuth 回调服务：只在 127.0.0.1 绑一个随机端口，收到一次回调就关
///
/// 登记的回调是 `http://127.0.0.1:0/oauth/callback`（端口 0 = 运行时随机），
/// 所以**只换端口**：主机与 path 必须与登记值一致，否则 MindAuth 会拒
class OAuthLoopbackServer {
  OAuthLoopbackServer._(this._server, this._expectedState);

  static const callbackPath = '/oauth/callback';

  final HttpServer _server;
  final String _expectedState;
  final Completer<OAuthCallbackResult> _completer = Completer();

  static Future<OAuthLoopbackServer> start({
    required String expectedState,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = OAuthLoopbackServer._(server, expectedState);
    instance._serve();
    return instance;
  }

  int get port => _server.port;

  /// 与登记值同主机、同 path，只换实际端口
  String get redirectUri => MdtbbsConfig.redirectUriFor(port);

  void _serve() {
    _server.listen((request) async {
      // 浏览器会顺手请求 favicon 之类，那些不算回调
      if (request.uri.path != callbackPath) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final result = _resultOf(request.uri);
      if (!_completer.isCompleted) _completer.complete(result);

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(_resultPage(result));
      await request.response.close();
    });
  }

  OAuthCallbackResult _resultOf(Uri uri) {
    final query = uri.queryParameters;

    final error = query['error'];
    if (error != null && error.isNotEmpty) {
      return OAuthCallbackResult(
        error: error,
        errorDescription: query['error_description'],
      );
    }

    // state 必须与发起时一致：不一致说明这次回调来路不对，不能拿去换 token
    if (query['state'] != _expectedState) {
      return const OAuthCallbackResult(
        error: 'state_mismatch',
        errorDescription: '回调的 state 与发起登录时不符',
      );
    }

    final code = query['code'];
    if (code == null || code.isEmpty) {
      return const OAuthCallbackResult(
        error: 'invalid_request',
        errorDescription: '回调里没有授权码',
      );
    }

    return OAuthCallbackResult(code: code, state: query['state']);
  }

  /// 等这一次回调；超时或用户直接关掉浏览器都算失败
  ///
  /// 无论成败都会关掉服务端，不留监听端口
  Future<OAuthCallbackResult> waitForCallback({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    try {
      return await _completer.future.timeout(timeout);
    } on TimeoutException {
      return const OAuthCallbackResult(
        error: 'timeout',
        errorDescription: '等待浏览器授权超时',
      );
    } finally {
      await close();
    }
  }

  Future<void> close() async {
    try {
      await _server.close(force: true);
    } catch (_) {
      // 已经关掉了就不管
    }
  }

  static String _resultPage(OAuthCallbackResult result) {
    final ok = result.isSuccess;
    final title = ok ? '已登录，可以返回启动器' : '授权未完成';
    final detail = ok
        ? '这个页面可以直接关闭。手机上请从最近任务切回 Copper 启动器，或者按返回键关掉浏览器，启动器会自动继续。'
        : _escape(result.errorDescription ?? result.error ?? '未知原因');
    final hint = ok
        ? '启动器会自动继续；如果它没反应，重新点一次「登录 BBS」即可'
        : '回到 Copper 启动器重新点一次「登录 BBS」';
    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>$title</title>
<style>
:root{color-scheme:dark}
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
background:#161619;color:#e8e8ec;font-family:system-ui,"Microsoft YaHei",sans-serif;
padding:max(16px,env(safe-area-inset-top)) 16px max(16px,env(safe-area-inset-bottom))}
main{text-align:center;max-width:34rem;width:100%}
.badge{width:64px;height:64px;margin:0 auto 20px;border-radius:50%;
display:flex;align-items:center;justify-content:center;font-size:34px;line-height:1;
background:${ok ? '#1f3a26' : '#3a1f22'};color:${ok ? '#5dd07a' : '#f2777a'}}
h1{font-size:clamp(1.15rem,4.5vw,1.45rem);font-weight:600;margin:0 0 12px}
p{margin:0;line-height:1.7;color:#a6a6b2;font-size:clamp(.9rem,3.6vw,1rem)}
.hint{margin-top:18px;padding-top:16px;border-top:1px solid #2b2b31;color:#7d7d8a;font-size:.85rem}
</style></head>
<body><main>
<div class="badge">${ok ? '✓' : '!'}</div>
<h1>$title</h1>
<p>$detail</p>
<div class="hint">$hint</div>
</main>
<script>if ($ok) { try { setTimeout(function () { window.close() }, 1200) } catch (e) {} }</script>
</body>
</html>
''';
  }
  /// 错误说明可能来自服务端，落到 HTML 里要先转义
  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
