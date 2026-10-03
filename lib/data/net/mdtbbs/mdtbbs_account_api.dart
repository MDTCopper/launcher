import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_config.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/util/io/copper_io.dart';

/// MindAuth 的 OAuth 流程与论坛账号接口
///
/// token / revoke / userinfo 在 **issuer**（auth.mdtbbs.cn）上，论坛接口在
/// [MdtbbsConfig.apiBase]；[MdtbbsClient.urlOf] 对绝对地址原样放行，两类走同一个出入口。
///
/// Public Client **不持有 client_secret**，只传公开的 `client_id`
class MdtbbsAccountApi {
  MdtbbsAccountApi._();

  /// 拼授权地址：要用**系统浏览器**打开，登录与「同意授权」都在 MindAuth 页面上完成，
  /// 启动器不接触密码与验证码
  static String authorizeUrl({
    required String redirectUri,
    required String state,
    required String codeChallenge,
    String? clientId,
    List<String>? scopes,
  }) {
    final query = <String, String>{
      'response_type': 'code',
      'client_id': clientId ?? MdtbbsConfig.clientId,
      'redirect_uri': redirectUri,
      'scope': (scopes ?? MdtbbsConfig.scopes).join(' '),
      'state': state,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    };
    // 手动拼而非 Uri.replace：Dart 把空格编成 `+`，官方示例是 `%20`，统一成后者
    final encoded = query.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&')
        .replaceAll('+', '%20');
    return '${MdtbbsConfig.authorizeEndpoint}?$encoded';
  }

  /// 授权码换 token：授权码五分钟有效、只能兑换一次，且绑定 client / redirect / PKCE
  static Future<MdtbbsTokens> exchangeCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
    String? clientId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      MdtbbsConfig.tokenEndpoint,
      body: {
        'grant_type': 'authorization_code',
        'client_id': clientId ?? MdtbbsConfig.clientId,
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
      },
      cancelToken: cancelToken,
    );
    return _tokensOf(data);
  }

  /// 刷新 token
  ///
  /// [idempotencyKey] 必传，且**要在发请求前先持久化**：超时或 5xx 时结果未知，
  /// 得用**原 refresh token + 同一个 key** 在 10 分钟内重试；换 key 重放旧 token
  /// 会被判重放并撤销该账号对该客户端的全部 refresh token。
  /// 每次刷新都会轮换 refresh token，成功后要原子保存新的那份
  static Future<MdtbbsTokens> refresh({
    required String refreshToken,
    required String idempotencyKey,
    String? clientId,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.postJson(
      MdtbbsConfig.tokenEndpoint,
      body: {
        'grant_type': 'refresh_token',
        'client_id': clientId ?? MdtbbsConfig.clientId,
        'refresh_token': refreshToken,
      },
      headers: {'Idempotency-Key': idempotencyKey},
      cancelToken: cancelToken,
    );
    return _tokensOf(data);
  }

  /// 撤销 token（退出登录时调用；失败不该拦住本地清理）
  static Future<void> revoke({
    required String token,
    String? clientId,
    CancelToken? cancelToken,
  }) async {
    await MdtbbsClient.postJson(
      MdtbbsConfig.revokeEndpoint,
      body: {'client_id': clientId ?? MdtbbsConfig.clientId, 'token': token},
      cancelToken: cancelToken,
    );
  }

  /// 当前账号（论坛侧）：除了资料还带 `permissions`，用来决定要不要显示写入口
  ///
  /// 官方明确 `permissions` **只是界面提示**，每个写接口仍会独立校验
  static Future<MdtbbsAccount> me({
    required String accessToken,
    CancelToken? cancelToken,
  }) async {
    final data = await MdtbbsClient.getJson(
      '/me',
      accessToken: accessToken,
      cancelToken: cancelToken,
    );
    if (data is! Map) {
      throw const MdtbbsException(message: '账号信息响应不是 JSON 对象');
    }
    return MdtbbsAccount.fromJson(data.cast<String, dynamic>());
  }

  static MdtbbsTokens _tokensOf(Object? data) {
    if (data is! Map) {
      throw const MdtbbsException(message: 'token 响应不是 JSON 对象');
    }
    return MdtbbsTokens.fromJson(data.cast<String, dynamic>());
  }
}
