import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// OAuth PKCE 的纯计算（[verifier] / [challenge] / [state]）
///
/// MindAuth **只接受 S256**，不接受 plain；每次登录都要重新生成，
/// 不复用上一次留下的值
class Pkce {
  Pkce._();

  /// `code_verifier`：43–128 字符；32 随机字节 base64url 去填充正好 43 个
  static String createVerifier() => _base64UrlWithoutPadding(_randomBytes(32));

  /// `state`：回调时原样比对，不规则一律拒绝
  static String createState() => _base64UrlWithoutPadding(_randomBytes(32));

  /// `code_challenge` = BASE64URL(SHA256(UTF8(verifier)))
  static String challengeOf(String verifier) =>
      _base64UrlWithoutPadding(sha256.convert(utf8.encode(verifier)).bytes);

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static String _base64UrlWithoutPadding(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
