import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/account_models.dart';

// A stable, non-secret derivation key so encrypted values differ per install
// but remain consistent within the same app installation.
const _encryptionSalt = 'box-account-store-v1';

/// Derive a deterministic 32-byte AES key from the installation salt.
enc.Key _deriveKey() {
  final digest = sha256.convert(utf8.encode(_encryptionSalt)).bytes;
  return enc.Key(Uint8List.fromList(digest));
}

/// Encrypt [plainText] using AES-256-CBC with a random IV.
/// Returns base64-encoded prefix + suffix.
String _encrypt(String plainText) {
  final key = _deriveKey();
  final iv = enc.IV.fromSecureRandom(16);
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  final encrypted = encrypter.encrypt(plainText, iv: iv);
  // Combine IV and ciphertext, encode as base64
  final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
  combined.setRange(0, iv.bytes.length, iv.bytes);
  combined.setRange(iv.bytes.length, combined.length, encrypted.bytes);
  return base64.encode(combined);
}

/// Decrypt a base64-encoded prefix + suffix string produced by [_encrypt].
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

/// 全局登录状态广播 — AppDrawer 等远端组件可自动响应
final ValueNotifier<BoxAccountSession?> globalSessionNotifier =
    ValueNotifier<BoxAccountSession?>(null);

class BoxAccountStore {
  static const _serverUrlKey = 'boxAccount.serverUrl';
  static const _tokenKey = 'boxAccount.tokenEnc';
  static const _userJsonKey = 'boxAccount.userJsonEnc';

  Future<BoxAccountSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedServerUrl = prefs.getString(_serverUrlKey) ?? '';
    final serverUrl = BoxAccountDefaults.normalizeServerUrl(savedServerUrl);
    if (savedServerUrl.trim().isNotEmpty &&
        savedServerUrl.trim() != serverUrl) {
      await prefs.setString(_serverUrlKey, serverUrl);
    }
    final tokenEnc = prefs.getString(_tokenKey);
    final userJsonEnc = prefs.getString(_userJsonKey);
    if (serverUrl.isEmpty || tokenEnc == null || userJsonEnc == null) {
      return null;
    }

    final token = _decrypt(tokenEnc);
    final userText = _decrypt(userJsonEnc);
    if (token == null ||
        token.isEmpty ||
        userText == null ||
        userText.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(userText);
      if (decoded is! Map<String, dynamic>) return null;
      return BoxAccountSession(
        serverUrl: serverUrl,
        token: token,
        user: BoxAccountUser.fromJson(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  /// 加载会话并同步到全局通知器
  Future<BoxAccountSession?> loadSessionAndNotify() async {
    final session = await loadSession();
    globalSessionNotifier.value = session;
    return session;
  }

  Future<String> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_serverUrlKey) ?? '';
    final normalized = BoxAccountDefaults.normalizeServerUrl(saved);
    if (saved.trim().isNotEmpty && saved.trim() != normalized) {
      await prefs.setString(_serverUrlKey, normalized);
    }
    return normalized;
  }

  Future<void> saveServerUrl(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _serverUrlKey,
      BoxAccountDefaults.normalizeServerUrl(serverUrl),
    );
  }

  Future<void> saveSession(BoxAccountSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _serverUrlKey,
      BoxAccountDefaults.normalizeServerUrl(session.serverUrl),
    );
    await prefs.setString(_tokenKey, _encrypt(session.token));
    await prefs.setString(
      _userJsonKey,
      _encrypt(jsonEncode(session.user.toJson())),
    );
    globalSessionNotifier.value = session;
  }

  Future<void> clearSession({bool keepServerUrl = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!keepServerUrl) await prefs.remove(_serverUrlKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_userJsonKey);
    globalSessionNotifier.value = null;
  }
}
