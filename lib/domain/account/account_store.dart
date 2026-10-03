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
class StoredAccount {
  const StoredAccount({
    this.clientId,
    this.subject,
    this.username,
    this.refreshToken,
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
    String? pendingRefreshKey,
    String? pendingRefreshToken,
    DateTime? pendingRefreshAt,
    bool clearPendingRefresh = false,
  }) => StoredAccount(
    clientId: clientId ?? this.clientId,
    subject: subject ?? this.subject,
    username: username ?? this.username,
    refreshToken: refreshToken ?? this.refreshToken,
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
    'pendingRefreshKey': ?pendingRefreshKey,
    'pendingRefreshToken': ?pendingRefreshToken,
    'pendingRefreshAt': ?pendingRefreshAt?.toIso8601String(),
  };

  factory StoredAccount.fromJson(Map<String, dynamic> json) => StoredAccount(
    clientId: json['clientId'] as String?,
    subject: json['subject'] as String?,
    username: json['username'] as String?,
    refreshToken: json['refreshToken'] as String?,
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
      return account.copyWith(
        refreshToken: _restore(
          account.refreshToken,
          json['refreshTokenEncrypted'] == true,
        ),
        pendingRefreshToken: _restore(
          account.pendingRefreshToken,
          json['pendingRefreshTokenEncrypted'] == true,
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
      final payload = account.copyWith(
        refreshToken: refresh.value,
        pendingRefreshToken: pending.value,
      );

      final json = payload.toJson()
        ..['refreshTokenEncrypted'] = refresh.encrypted
        ..['pendingRefreshTokenEncrypted'] = pending.encrypted;

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
