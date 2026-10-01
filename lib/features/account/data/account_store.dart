// 账号凭据（token / 用户信息）的本地持久化。
//
// C1：算法由"固定盐 AES-CBC"升级为"每安装随机密钥 + AES-GCM"，
// 见 lib/utils/local_secret_codec.dart 顶部的说明。旧密文**仍可读**：
// 读到旧格式时用旧密钥解出来，随即按新格式重写（懒迁移），
// 用户升级后不会被登出。

import 'dart:async';
import 'dart:convert';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/local_secret_codec.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/account_models.dart';

/// 旧格式（固定盐 AES-CBC）的盐，仅用于迁移读取。
const _legacySalt = 'box-account-store-v1';

/// 模块 context：决定本模块用的密钥（与远程存储插件不共用）。
const _codecContext = 'account';

/// 全局「登录态已失效」广播。
///
/// 为什么需要它（2026-10-01 真机事故）：服务端的会话有 30 天 TTL，过期后**所有**
/// 账号接口都返回 401 —— 但 App 本地仍保留着会话，界面看起来"已登录"，
/// 于是各页面各说各话（个人中心显示「数据暂不可用」、读屏显示「凭证已失效」），
/// 没有一个地方告诉用户「你该重新登录了」。
///
/// 口径：任何账号接口拿到 401 都置 true；重新登录成功（[BoxAccountStore.saveSession]）
/// 或主动退出（[BoxAccountStore.clearSession]）清回 false。
final ValueNotifier<bool> globalSessionInvalidNotifier = ValueNotifier<bool>(false);

/// 标记登录态已失效（幂等；不重复通知）。
void markGlobalSessionInvalid() {
  if (globalSessionInvalidNotifier.value) return;
  globalSessionInvalidNotifier.value = true;
}

/// 清除登录态失效标记（幂等）。
void clearGlobalSessionInvalid() {
  if (!globalSessionInvalidNotifier.value) return;
  globalSessionInvalidNotifier.value = false;
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

    final codec = await LocalSecretCodec.openWithPrefs(prefs, _codecContext);
    final tokenResult = _decodeValue(codec, tokenEnc);
    final userResult = _decodeValue(codec, userJsonEnc);
    final token = tokenResult.plain;
    final userText = userResult.plain;
    if (token == null ||
        token.isEmpty ||
        userText == null ||
        userText.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(userText);
      if (decoded is! Map<String, dynamic>) return null;
      final session = BoxAccountSession(
        serverUrl: serverUrl,
        token: token,
        user: BoxAccountUser.fromJson(decoded),
      );
      if (tokenResult.wasLegacy || userResult.wasLegacy) {
        // 懒迁移：本次已经解出来了，顺手按新格式重写一次。
        // 写回失败不影响本次登录（下次读还会再走一遍迁移）。
        try {
          await saveSession(session);
          AppLogger.instance.logTo(
            LogChannel.account,
            '账号凭据已迁移到新格式（每安装密钥 + AES-GCM）',
          );
        } catch (e) {
          AppLogger.instance.logTo(
            LogChannel.account,
            '账号凭据迁移失败: $e',
            level: LogLevel.warn,
          );
        }
      }
      return session;
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
    final codec = await LocalSecretCodec.openWithPrefs(prefs, _codecContext);
    await prefs.setString(
      _serverUrlKey,
      BoxAccountDefaults.normalizeServerUrl(session.serverUrl),
    );
    await prefs.setString(_tokenKey, codec.encrypt(session.token));
    await prefs.setString(
      _userJsonKey,
      codec.encrypt(jsonEncode(session.user.toJson())),
    );
    globalSessionNotifier.value = session;
    // 重新登录/续期成功 = 会话恢复，清掉全局「登录已失效」标记。
    clearGlobalSessionInvalid();
  }

  Future<void> clearSession({bool keepServerUrl = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!keepServerUrl) await prefs.remove(_serverUrlKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_userJsonKey);
    globalSessionNotifier.value = null;
    // 主动退出不是「登录失效」，别把重登提示留在界面上。
    clearGlobalSessionInvalid();
  }

  /// 解密一个值：先按新格式，再退回旧格式（并标记需要迁移）。
  ({String? plain, bool wasLegacy}) _decodeValue(
    LocalSecretCodec codec,
    String encoded,
  ) {
    final plain = codec.decrypt(encoded);
    if (plain != null) return (plain: plain, wasLegacy: false);
    if (!LocalSecretCodec.looksLegacy(encoded)) {
      return (plain: null, wasLegacy: false);
    }
    final legacy = LocalSecretCodec.decryptLegacy(encoded, _legacySalt);
    return (plain: legacy, wasLegacy: legacy != null);
  }
}
