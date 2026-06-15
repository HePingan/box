import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/account_models.dart';

class BoxAccountStore {
  static const _serverUrlKey = 'boxAccount.serverUrl';
  static const _tokenKey = 'boxAccount.token';
  static const _userJsonKey = 'boxAccount.userJson';

  Future<BoxAccountSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedServerUrl = prefs.getString(_serverUrlKey) ?? '';
    final serverUrl = BoxAccountDefaults.normalizeServerUrl(savedServerUrl);
    if (savedServerUrl.trim().isNotEmpty &&
        savedServerUrl.trim() != serverUrl) {
      await prefs.setString(_serverUrlKey, serverUrl);
    }
    final token = prefs.getString(_tokenKey) ?? '';
    final userText = prefs.getString(_userJsonKey) ?? '';
    if (serverUrl.isEmpty || token.isEmpty || userText.isEmpty) return null;
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
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_userJsonKey, jsonEncode(session.user.toJson()));
  }

  Future<void> clearSession({bool keepServerUrl = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!keepServerUrl) await prefs.remove(_serverUrlKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_userJsonKey);
  }
}
