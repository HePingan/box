// 远程存储账户的本地持久化：沿用账号同款 AES-CBC（随机 IV）加密，
// 独立 salt；密码/用户名仅以密文形态落 SharedPreferences。
//
// 与 account_store.dart 的差异仅在 salt 常量；算法保持一致，便于统一审计。

import 'dart:convert';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/remote_storage_models.dart';

// 独立于账号存储的盐，避免跨模块密钥复用。
const _encryptionSalt = 'box-remote-storage-v1';

enc.Key _deriveKey() {
  final digest = sha256.convert(utf8.encode(_encryptionSalt)).bytes;
  return enc.Key(Uint8List.fromList(digest));
}

/// AES-CBC 加密（随机 IV 前缀 + 密文，整体 base64），与账号存储同构。
String _encrypt(String plainText) {
  final key = _deriveKey();
  final iv = enc.IV.fromSecureRandom(16);
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  final encrypted = encrypter.encrypt(plainText, iv: iv);
  final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
  combined.setRange(0, iv.bytes.length, iv.bytes);
  combined.setRange(iv.bytes.length, combined.length, encrypted.bytes);
  return base64.encode(combined);
}

String? _decrypt(String encoded) {
  try {
    final raw = base64.decode(encoded);
    if (raw.length < 17) return null;
    final iv = enc.IV(Uint8List.fromList(raw.sublist(0, 16)));
    final ciphertext = enc.Encrypted(Uint8List.fromList(raw.sublist(16)));
    final key = _deriveKey();
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt(ciphertext, iv: iv);
  } catch (_) {
    return null;
  }
}

/// 账户仓库（SharedPreferences 单键密文）。
class RemoteStorageStore {
  static const String accountsKey = 'remoteStorage.accountsEnc';

  Future<List<RemoteStorageAccount>> loadAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(accountsKey);
      if (raw == null || raw.isEmpty) return <RemoteStorageAccount>[];
      final plain = _decrypt(raw);
      if (plain == null || plain.isEmpty) return <RemoteStorageAccount>[];
      final decoded = jsonDecode(plain);
      if (decoded is! List) return <RemoteStorageAccount>[];
      return decoded
          .map(RemoteStorageAccount.fromJson)
          .whereType<RemoteStorageAccount>()
          .toList();
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取账户失败: $e',
        level: LogLevel.error,
      );
      return <RemoteStorageAccount>[];
    }
  }

  Future<void> saveAccounts(List<RemoteStorageAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    final plain = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await prefs.setString(accountsKey, _encrypt(plain));
  }
}
