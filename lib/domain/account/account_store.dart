import 'dart:convert';
import 'dart:io';

import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/token_encryptor.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 落盘的账号态
///
/// **access token 只在内存**（一小时就过期，没必要写盘）；这里存的是能换回它的
/// refresh token，以及与刷新幂等性有关的那笔「未决尝试」
/// 联机会话的持久化片段
///
/// 状态曾经只存在页面里 ⇒ 切页就丢；而 **加入码服务端只在创建响应里给一次**，
/// 丢了找不回；恢复令牌又是一次性的、绑定用户与 OAuth 客户端，重启后恢复也要它
class StoredMultiplayerSession {
  const StoredMultiplayerSession({
    required this.sessionId,
    this.peerId,
    this.resumeToken,
    this.joinCode,
    this.activityName,
    this.savedAt,
  });

  /// 服务端给的不透明会话 ID（原样传回）
  final String sessionId;

  /// 自己在这个会话里的对端 ID（心跳要用）
  final String? peerId;

  /// 恢复令牌：秘密，落盘前加密
  final String? resumeToken;

  /// 加入码：服务端只在创建响应里给一次，必须自己存
  final String? joinCode;

  final String? activityName;
  final DateTime? savedAt;

  /// 超过这个时长就不再当作有效会话（服务端也会自己过期，这里只是别显示陈年数据）
  static const maxAge = Duration(hours: 6);

  bool isFresh(DateTime now) {
    final at = savedAt;
    if (at == null) return true;
    return now.difference(at) < maxAge;
  }

  StoredMultiplayerSession copyWith({
    String? peerId,
    String? resumeToken,
    String? joinCode,
    String? activityName,
    DateTime? savedAt,
  }) => StoredMultiplayerSession(
    sessionId: sessionId,
    peerId: peerId ?? this.peerId,
    resumeToken: resumeToken ?? this.resumeToken,
    joinCode: joinCode ?? this.joinCode,
    activityName: activityName ?? this.activityName,
    savedAt: savedAt ?? this.savedAt,
  );

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'peerId': ?peerId,
    'resumeToken': ?resumeToken,
    'joinCode': ?joinCode,
    'activityName': ?activityName,
    'savedAt': ?savedAt?.toIso8601String(),
  };

  factory StoredMultiplayerSession.fromJson(Map<String, dynamic> json) =>
      StoredMultiplayerSession(
        sessionId: '${json['sessionId'] ?? ''}',
        peerId: json['peerId'] as String?,
        resumeToken: json['resumeToken'] as String?,
        joinCode: json['joinCode'] as String?,
        activityName: json['activityName'] as String?,
        savedAt: DateTime.tryParse('${json['savedAt']}'),
      );
}

class StoredAccount {
  const StoredAccount({
    this.clientId,
    this.subject,
    this.username,
    this.refreshToken,
    this.lanlinkToken,
    this.multiplayerSession,
    this.pendingRefreshKey,
    this.pendingRefreshToken,
    this.pendingRefreshAt,
  });

  /// 记下是哪个 client 换来的：换了 client_id 这份 token 就不再有效
  final String? clientId;

  final String? subject;
  final String? username;

  /// 刷新时会轮换，成功必须原子覆盖这一份
  final String? refreshToken;

  /// 联机服务（LanLink 控制面）的令牌
  ///
  /// 它与 BBS 是同一个论坛账号，所以跟 refresh token 存一份；
  /// 退出 BBS 时整份账号文件被清掉，联机令牌自然跟着失效
  final String? lanlinkToken;

  /// 联机会话（官方 multiplayer）：与账号绑一份，退出账号即清
  final StoredMultiplayerSession? multiplayerSession;

  /// 上一次刷新用的幂等键与那次用的原 refresh token
  ///
  /// 超时或 5xx 时结果未知，要拿这两样**原样**重试；换 key 重放会被判重放，
  /// 后果是该账号对该客户端的全部 refresh token 被撤销
  final String? pendingRefreshKey;
  final String? pendingRefreshToken;
  final DateTime? pendingRefreshAt;

  /// 官方给的重试窗口
  static const retryWindow = Duration(minutes: 10);

  bool get hasPendingRefresh =>
      pendingRefreshKey != null && pendingRefreshToken != null;

  bool get isLoggedIn => refreshToken != null && refreshToken!.isNotEmpty;

  bool get hasLanlinkToken => lanlinkToken != null && lanlinkToken!.isNotEmpty;

  bool matchesClient(String id) => clientId == id;

  /// 这笔未决尝试还在重试窗口内
  bool isPendingRefreshFresh(DateTime now) {
    final at = pendingRefreshAt;
    if (at == null) return false;
    return now.difference(at) < retryWindow;
  }

  StoredAccount copyWith({
    String? clientId,
    String? subject,
    String? username,
    String? refreshToken,
    String? lanlinkToken,
    StoredMultiplayerSession? multiplayerSession,
    String? pendingRefreshKey,
    String? pendingRefreshToken,
    DateTime? pendingRefreshAt,
    bool clearPendingRefresh = false,
    bool clearLanlinkToken = false,
    bool clearMultiplayerSession = false,
  }) => StoredAccount(
    clientId: clientId ?? this.clientId,
    subject: subject ?? this.subject,
    username: username ?? this.username,
    refreshToken: refreshToken ?? this.refreshToken,
    lanlinkToken: clearLanlinkToken
        ? null
        : (lanlinkToken ?? this.lanlinkToken),
    multiplayerSession: clearMultiplayerSession
        ? null
        : (multiplayerSession ?? this.multiplayerSession),
    pendingRefreshKey: clearPendingRefresh
        ? null
        : (pendingRefreshKey ?? this.pendingRefreshKey),
    pendingRefreshToken: clearPendingRefresh
        ? null
        : (pendingRefreshToken ?? this.pendingRefreshToken),
    pendingRefreshAt: clearPendingRefresh
        ? null
        : (pendingRefreshAt ?? this.pendingRefreshAt),
  );

  Map<String, dynamic> toJson() => {
    'clientId': ?clientId,
    'subject': ?subject,
    'username': ?username,
    'refreshToken': ?refreshToken,
    'lanlinkToken': ?lanlinkToken,
    'multiplayerSession': ?multiplayerSession?.toJson(),
    'pendingRefreshKey': ?pendingRefreshKey,
    'pendingRefreshToken': ?pendingRefreshToken,
    'pendingRefreshAt': ?pendingRefreshAt?.toIso8601String(),
  };

  factory StoredAccount.fromJson(Map<String, dynamic> json) => StoredAccount(
    clientId: json['clientId'] as String?,
    subject: json['subject'] as String?,
    username: json['username'] as String?,
    refreshToken: json['refreshToken'] as String?,
    lanlinkToken: json['lanlinkToken'] as String?,
    multiplayerSession: (json['multiplayerSession'] as Map?) == null
        ? null
        : StoredMultiplayerSession.fromJson(
            (json['multiplayerSession'] as Map).cast<String, dynamic>(),
          ),
    pendingRefreshKey: json['pendingRefreshKey'] as String?,
    pendingRefreshToken: json['pendingRefreshToken'] as String?,
    pendingRefreshAt: DateTime.tryParse('${json['pendingRefreshAt']}'),
  );
}

/// 账号态的读写：落在数据根的 `mdtbbs_account.json`
///
/// - refresh token 经 [TokenEncryptor] 加密（Linux 无 keyring 时该项目已有的
///   降级路径会让它明文保存，与 GitHub token 同一套口径）
/// - 读写都**不抛**：账号态坏了只该是「未登录」，不该拦住启动
/// - 落盘先写 `.tmp` 再改名，避免半截文件
class AccountStore {
  AccountStore._();

  static const fileName = 'mdtbbs_account.json';

  /// 用例可指定目录，默认数据根
  @visibleForTesting
  static String? directoryOverride;

  static String get filePath =>
      p.join(directoryOverride ?? AppPaths.copperLauncher, fileName);

  static StoredAccount? load() {
    final file = File(filePath);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return null;
      final json = decoded.cast<String, dynamic>();
      final account = StoredAccount.fromJson(json);
      return account
          .copyWith(
            refreshToken: _restore(
              account.refreshToken,
              json['refreshTokenEncrypted'] == true,
            ),
            pendingRefreshToken: _restore(
              account.pendingRefreshToken,
              json['pendingRefreshTokenEncrypted'] == true,
            ),
          )
          .copyWith(
            lanlinkToken: _restore(
              account.lanlinkToken,
              json['lanlinkTokenEncrypted'] == true,
            ),
          )
          .copyWith(
            // 会话片段里的恢复令牌也是秘密，同一套解密
            multiplayerSession: account.multiplayerSession?.copyWith(
              resumeToken: _restore(
                account.multiplayerSession?.resumeToken,
                json['multiplayerResumeTokenEncrypted'] == true,
              ),
            ),
          );
    } catch (error) {
      addLog(
        .warning,
        '账号态读取失败，按未登录处理：${removeNewlines('$error')}',
        tag: 'Account',
      );
      return null;
    }
  }

  static void save(StoredAccount account) {
    try {
      final directory = Directory(p.dirname(filePath));
      if (!directory.existsSync()) directory.createSync(recursive: true);

      final refresh = _protect(account.refreshToken);
      final pending = _protect(account.pendingRefreshToken);
      final lanlink = _protect(account.lanlinkToken);
      final session = account.multiplayerSession;
      final resume = _protect(session?.resumeToken);
      final payload = account.copyWith(
        refreshToken: refresh.value,
        pendingRefreshToken: pending.value,
        lanlinkToken: lanlink.value,
        multiplayerSession: session?.copyWith(resumeToken: resume.value),
      );

      final json = payload.toJson()
        ..['refreshTokenEncrypted'] = refresh.encrypted
        ..['pendingRefreshTokenEncrypted'] = pending.encrypted
        ..['lanlinkTokenEncrypted'] = lanlink.encrypted
        ..['multiplayerResumeTokenEncrypted'] = resume.encrypted;

      final temporary = File('$filePath.tmp');
      temporary.writeAsStringSync(jsonEncode(json), flush: true);
      final target = File(filePath);
      if (target.existsSync()) target.deleteSync();
      temporary.renameSync(filePath);
    } catch (error) {
      addLog(.error, '账号态写入失败：${removeNewlines('$error')}', tag: 'Account');
    }
  }

  static void clear() {
    try {
      final file = File(filePath);
      if (file.existsSync()) file.deleteSync();
    } catch (error) {
      addLog(.warning, '账号态清除失败：${removeNewlines('$error')}', tag: 'Account');
    }
  }

  /// 按需加密，并**明确记下这一份到底加没加密**
  ///
  /// 不能靠 `TokenEncryptor.isEncrypted` 事后猜：那个判据是「base64 可解 +
  /// 长度是 16 的倍数」，而**十六进制形态的 refresh token 必然命中**
  /// （64 位十六进制 → 48 字节 → 48 % 16 == 0）⇒ 明文会被误判成密文，
  /// 在安全存储不可用的机器上被当成「解不开的密文」**直接丢弃**、登录态存不住
  static ({String? value, bool encrypted}) _protect(String? value) {
    if (value == null || value.isEmpty) return (value: value, encrypted: false);
    try {
      final encrypted = TokenEncryptor.encryptIfNeeded(value);
      // 加密器不可用时它会原样返回，那就是没加密
      return (value: encrypted, encrypted: encrypted != value);
    } catch (_) {
      return (value: value, encrypted: false);
    }
  }

  /// 按存下来的标记还原：没标记（老文件 / 明文）就原样用
  static String? _restore(String? value, bool encrypted) {
    if (value == null || value.isEmpty || !encrypted) return value;
    try {
      return TokenEncryptor.decryptToken(value);
    } catch (error) {
      // 真加密过却解不开：多半是安全存储的 key 换了（应用标识变过），
      // 这份密文已经没用，按未登录处理
      addLog(
        .warning,
        '已保存的登录凭证解不开，按未登录处理：${removeNewlines('$error')}',
        tag: 'Account',
      );
      return null;
    }
  }
}
