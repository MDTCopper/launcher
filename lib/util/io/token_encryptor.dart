import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:copper_launcher/util/io/log.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';

class TokenEncryptor {
  static late final Encrypter _encrypter;
  static late final IV _iv;

  /// 系统安全存储是否可用：Linux 上没有 keyring（精简桌面 / 容器 / WSL）时为 false，
  /// 此时加密器不初始化，token 明文直存
  static bool _storageAvailable = false;

  static const _storage = FlutterSecureStorage();
  static const _keyStorageKey = 'copper_aes_key';
  static const _ivStorageKey = 'copper_aes_iv';

  /// 初始化加密器。从 OS 安全存储加载 AES key，首次运行时自动生成。
  /// 必须在应用启动时调用，且需 await 完成后再使用其他方法。
  ///
  /// 安全存储不可用时**不往外抛**（那会中断整个 `_initialize`，表现为窗口空着、进程不退），
  /// 只记日志并降级成明文直存
  static Future<void> init() async {
    try {
      String? keyBase64 = await _storage.read(key: _keyStorageKey);
      String? ivBase64 = await _storage.read(key: _ivStorageKey);

      if (keyBase64 == null || ivBase64 == null) {
        // 首次运行：生成随机 key + IV 并持久化到安全存储
        final key = _generateRandomKey();
        final iv = _generateRandomIV();

        keyBase64 = base64.encode(key.bytes);
        ivBase64 = base64.encode(iv.bytes);

        await _storage.write(key: _keyStorageKey, value: keyBase64);
        await _storage.write(key: _ivStorageKey, value: ivBase64);
      }

      final keyBytes = base64.decode(keyBase64);
      final ivBytes = base64.decode(ivBase64);

      _encrypter = Encrypter(
        AES(Key(Uint8List.fromList(keyBytes)), mode: AESMode.cbc),
      );
      _iv = IV(Uint8List.fromList(ivBytes));
      _storageAvailable = true;
    } catch (error) {
      addLog(
        .warning,
        '系统安全存储不可用，token 改为明文保存：${removeNewlines('$error')}',
        tag: 'Token',
      );
    }
  }

  /// 生成随机 AES-256 key（32 字节）
  static Key _generateRandomKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return Key(Uint8List.fromList(bytes));
  }

  /// 生成随机 IV
  static IV _generateRandomIV() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return IV(Uint8List.fromList(bytes));
  }

  /// 加密 token
  static String encryptToken(String token) {
    final encrypted = _encrypter.encrypt(token, iv: _iv);
    return encrypted.base64;
  }

  /// 解密 token
  static String decryptToken(String encryptedToken) {
    final encrypted = Encrypted.fromBase64(encryptedToken);
    return _encrypter.decrypt(encrypted, iv: _iv);
  }

  static bool isEncrypted(String token) {
    try {
      final decoded = base64.decode(token);
      return decoded.length % 16 == 0;
    } catch (e) {
      return false;
    }
  }

  /// 按需加密：如果未加密则加密，已加密则原样返回
  static String encryptIfNeeded(String token) {
    if (token.isEmpty) return token;
    if (!_storageAvailable) return token;
    if (isEncrypted(token)) return token;
    return encryptToken(token);
  }

  /// 按需解密：如果是密文则解密，明文则原样返回
  ///
  /// 解不开时按「没有 token」处理、不往外抛：secure storage 的目录是
  /// `%APPDATA%\<CompanyName>\<ProductName>`，改过应用标识就会整体搬家，
  /// 新目录里读不到 key 会重新生成一把，旧密文随即解不开——
  /// 抛出去会在 `initAppConfig` 里变成整个启动崩溃
  static String decryptIfNeeded(String token) {
    if (token.isEmpty) return token;
    final looksEncrypted = isEncrypted(token);
    if (!_storageAvailable) {
      // 没有加密器，密文一律解不开；明文（降级期间存下的）照常返回
      if (!looksEncrypted) return token;
      addLog(.warning, '系统安全存储不可用，已保存的 token 无法解密，按未设置处理', tag: 'Token');
      return '';
    }
    if (!looksEncrypted) return token;
    try {
      return decryptToken(token);
    } catch (error) {
      addLog(.warning, '已保存的 token 无法解密，按未设置处理：${removeNewlines('$error')}', tag: 'Token');
      return '';
    }
  }
}
