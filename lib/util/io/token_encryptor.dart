import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:system_info2/system_info2.dart';

class TokenEncryptor {
  static late final Encrypter _encrypter;
  static late final IV _iv;
  static late final String _machineId;

  static void init() {
    _machineId = _generateMachineId();

    final keyBytes = utf8.encode('copperlauncher_$_machineId');
    final keyDigest = sha256.convert(keyBytes);
    final key = Key(Uint8List.fromList(keyDigest.bytes));

    final ivBytes = utf8.encode('iv_$_machineId');
    _iv = IV(Uint8List.fromList(ivBytes).sublist(0, 16));

    _encrypter = Encrypter(AES(key, mode: AESMode.cbc));
  }

  static String _generateMachineId() {
    final machineInfo = <String>[];

    machineInfo.add(Platform.localHostname);
    machineInfo.add(SysInfo.operatingSystemName);
    machineInfo.add(SysInfo.operatingSystemVersion);

    // if (Platform.isWindows) {
    //   try {
    //     final result = Process.runSync('wmic', ['csproduct', 'get', 'UUID']);
    //     final output = result.stdout.toString().trim();
    //     final lines = output.split('\n');
    //     if (lines.length > 1) {
    //       machineInfo.add(lines[1].trim());
    //     }
    //   } catch (_) {}
    // } else if (Platform.isLinux) {
    //   try {
    //     final machineIdFile = File('/etc/machine-id');
    //     if (machineIdFile.existsSync()) {
    //       machineInfo.add(machineIdFile.readAsStringSync().trim());
    //     }
    //   } catch (_) {}
    // } else if (Platform.isMacOS) {
    //   try {
    //     final result = Process.runSync('ioreg', [
    //       '-rd1',
    //       '-c',
    //       'IOPlatformExpertDevice',
    //     ]);
    //     final output = result.stdout.toString();
    //     final uuidMatch = RegExp(
    //       r'"IOPlatformUUID" = "([^"]+)"',
    //     ).firstMatch(output);
    //     if (uuidMatch != null) {
    //       machineInfo.add(uuidMatch.group(1)!);
    //     }
    //   } catch (_) {}
    // }

    final combined = machineInfo.join('|');
    final hash = sha256.convert(utf8.encode(combined));
    return hash.toString().substring(0, 16);
  }

  /// 加密token
  static String encryptToken(String token) {
    try {
      final encrypted = _encrypter.encrypt(token, iv: _iv);
      return encrypted.base64;
    } catch (e) {
      throw Exception('Token encryption failed: $e');
    }
  }

  /// 解密token
  static String decryptToken(String encryptedToken) {
    try {
      final encrypted = Encrypted.fromBase64(encryptedToken);
      final decrypted = _encrypter.decrypt(encrypted, iv: _iv);
      return decrypted;
    } catch (e) {
      throw Exception('Token decryption failed: $e');
    }
  }

  static bool isEncrypted(String token) {
    try {
      final decoded = base64.decode(token);
      return decoded.length % 16 == 0;
    } catch (e) {
      return false;
    }
  }

  static String encryptIfNeeded(String token) {
    if (token.isEmpty) return token;
    if (isEncrypted(token)) return token;
    return encryptToken(token);
  }

  static String decryptIfNeeded(String token) {
    if (token.isEmpty) return token;
    if (!isEncrypted(token)) return token;
    return decryptToken(token);
  }
}
