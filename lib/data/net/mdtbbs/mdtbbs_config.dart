import 'package:flutter/foundation.dart';

/// MDTBBS 社区的接入配置
///
/// **拿到 client_id 后只改 [clientId] 一处即可启用登录**，其余按官方文档固定
class MdtbbsConfig {
  MdtbbsConfig._();

  /// MindAuth 上登记的 Public Client ID（**唯一改动点**）
  ///
  /// Public Client **没有 client_secret** —— 这个 ID 本身是公开标识，
  /// 官方明确要求任何密钥都不该进客户端
  static const defaultClientId = 'a79f33a1f47f3cf21f9b4a38a9661536';

  static String? _clientIdOverride;

  static String get clientId => _clientIdOverride ?? defaultClientId;

  static bool get isConfigured => clientId.isNotEmpty;

  @visibleForTesting
  static set clientIdOverride(String? value) => _clientIdOverride = value;

  /// 论坛 API 基址与 MindAuth issuer
  ///
  /// 例常用 [apiBaseOverride] / [issuerOverride] 把地址指到**本地假服务端**：
  /// 真实接口要等管理员批准 scope 才能调，在那之前这是唯一能自动验证
  /// 请求构造与响应处理的办法
  static const _defaultApiBase = 'https://mdtbbs.cn/api/v1';
  static const _defaultIssuer = 'https://auth.mdtbbs.cn';

  static String? _apiBaseOverride;
  static String? _issuerOverride;

  static String get apiBase => _apiBaseOverride ?? _defaultApiBase;

  static String get issuer => _issuerOverride ?? _defaultIssuer;

  @visibleForTesting
  static set apiBaseOverride(String? value) => _apiBaseOverride = value;

  @visibleForTesting
  static set issuerOverride(String? value) => _issuerOverride = value;

  /// 站点源（`https://mdtbbs.cn`）
  ///
  /// 服务端在下载 / 上传会话里回的 `url` 是**带 `/api/v1` 前缀的站内路径**
  /// （如 `/api/v1/game-saves/uploads/<id>/file`），拼这个而不是 [apiBase]，
  /// 否则会拼成 `/api/v1/api/v1/...`
  static String get origin => Uri.parse(apiBase).origin;

  static String get authorizeEndpoint => '$issuer/api/authorize';
  static String get tokenEndpoint => '$issuer/api/token';
  static String get revokeEndpoint => '$issuer/api/revoke';
  static String get userInfoEndpoint => '$issuer/api/userinfo';

  /// 桌面回调登记形态：loopback + **端口 0**，运行时随机端口也匹配登记值
  static const registeredRedirectUri = 'http://127.0.0.1:0/oauth/callback';

  /// 运行时回调地址：主机 / path / query 必须与登记值一致，只把端口换成实际绑定的那个
  static String redirectUriFor(int port) =>
      'http://127.0.0.1:$port/oauth/callback';

  /// 申请的 scope
  ///
  /// 这一份**必须与 MindAuth 上该应用获批的 scope 对齐**：请求未获批的 scope
  /// 会直接在授权页报 `invalid_scope`（实测过）。本应用的获批清单见
  /// `GET https://auth.mdtbbs.cn/api/public/apps/<clientId>`（无需登录）
  ///
  /// - **不含 `openid`**：该应用未获批它，带上就登不进去；账号标识由 `profile`
  ///   与论坛 `/api/v1/me` 提供，够用
  /// - 一次申请全（`resource.*` 与联机那几项是给后续功能占位）：用户只授权一次，
  ///   后面新功能不必再弹一次授权页
  static const scopes = <String>[
    'profile',
    'game_content.saves.read',
    'game_content.saves.write',
    'game_content.saves.delete',
    'resource.read',
    'resource.download',
    'resource.upload',
    'friends.read',
    'presence.read',
    'presence.write',
    'multiplayer.read',
    'multiplayer.write',
  ];

  static String get scopeParam => scopes.join(' ');

  /// 用例收尾用：把改过的地址与 client_id 还原
  @visibleForTesting
  static void resetEndpoints() {
    _apiBaseOverride = null;
    _issuerOverride = null;
    _clientIdOverride = null;
  }
}
