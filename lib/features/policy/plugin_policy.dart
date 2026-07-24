import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../account/data/account_store.dart';
import '../account/domain/account_models.dart';

/// 内置插件 ID（与首页 HomePlugin.id / 服务端策略一致）
class PluginIds {
  static const quizAnswer = 'builtin_quiz_plugin';
  static const quizEntry = 'builtin_quiz_entry';
  static const quizBankView = 'builtin_quiz_bank_view';
}

class PluginFeature {
  static const overlay = 'overlay';
  static const probe = 'probe';
  static const ocr = 'ocr';
  static const search = 'search';
  static const entry = 'entry';
  static const view = 'view';
  static const cloudPush = 'cloud_push';
  static const cloudPull = 'cloud_pull';
}

class PluginPolicySnapshot {
  const PluginPolicySnapshot({
    required this.version,
    required this.ttlSec,
    required this.fetchedAt,
    required this.pluginsAllowed,
    required this.globalMessage,
    required this.minAppVersion,
    required this.forceLogout,
    required this.plugins,
    required this.userPluginsAllowed,
    required this.deniedPluginIds,
    required this.userMessage,
    this.fromCache = false,
    this.stale = false,
  });

  factory PluginPolicySnapshot.allowAll() => PluginPolicySnapshot(
        version: 0,
        ttlSec: 300,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
        pluginsAllowed: true,
        globalMessage: '',
        minAppVersion: '',
        forceLogout: false,
        plugins: const {},
        userPluginsAllowed: true,
        deniedPluginIds: const {},
        userMessage: '',
      );

  factory PluginPolicySnapshot.fromJson(
    Map<String, dynamic> json, {
    DateTime? fetchedAt,
    bool fromCache = false,
  }) {
    final global = json['global'] is Map
        ? Map<String, dynamic>.from(json['global'] as Map)
        : <String, dynamic>{};
    final user = json['user'] is Map
        ? Map<String, dynamic>.from(json['user'] as Map)
        : <String, dynamic>{};
    final plugins = <String, PluginPolicyEntry>{};
    final rawPlugins = json['plugins'];
    if (rawPlugins is Map) {
      rawPlugins.forEach((key, value) {
        if (value is Map) {
          plugins[key.toString()] = PluginPolicyEntry.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }
    final denied = <String>{};
    final rawDenied = user['deniedPluginIds'];
    if (rawDenied is List) {
      for (final item in rawDenied) {
        final id = item.toString().trim();
        if (id.isNotEmpty) denied.add(id);
      }
    }
    return PluginPolicySnapshot(
      version: _asInt(json['version'], 0),
      ttlSec: _asInt(json['ttlSec'], 300).clamp(30, 86400),
      fetchedAt: fetchedAt ??
          DateTime.tryParse(json['fetchedAt']?.toString() ?? '') ??
          DateTime.now(),
      pluginsAllowed: global['pluginsAllowed'] != false,
      globalMessage: (global['message'] ?? json['globalMessage'] ?? '')
          .toString(),
      minAppVersion: json['minAppVersion']?.toString() ?? '',
      forceLogout: json['forceLogout'] == true,
      plugins: plugins,
      userPluginsAllowed: user['pluginsAllowed'] != false,
      deniedPluginIds: denied,
      userMessage: user['message']?.toString() ?? '',
      fromCache: fromCache,
    );
  }

  final int version;
  final int ttlSec;
  final DateTime fetchedAt;
  final bool pluginsAllowed;
  final String globalMessage;
  final String minAppVersion;
  final bool forceLogout;
  final Map<String, PluginPolicyEntry> plugins;
  final bool userPluginsAllowed;
  final Set<String> deniedPluginIds;
  final String userMessage;
  final bool fromCache;
  final bool stale;

  bool get isExpired {
    // 从未成功拉到策略：不按过期拒绝（首次安装/无网仍可用本地能力，API 由服务端再拦）
    if (version <= 0 && fetchedAt.millisecondsSinceEpoch == 0) {
      return false;
    }
    return DateTime.now().isAfter(
      fetchedAt.add(Duration(seconds: ttlSec)),
    );
  }

  PluginPolicySnapshot copyWith({bool? stale, bool? fromCache}) =>
      PluginPolicySnapshot(
        version: version,
        ttlSec: ttlSec,
        fetchedAt: fetchedAt,
        pluginsAllowed: pluginsAllowed,
        globalMessage: globalMessage,
        minAppVersion: minAppVersion,
        forceLogout: forceLogout,
        plugins: plugins,
        userPluginsAllowed: userPluginsAllowed,
        deniedPluginIds: deniedPluginIds,
        userMessage: userMessage,
        fromCache: fromCache ?? this.fromCache,
        stale: stale ?? this.stale,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'ttlSec': ttlSec,
        'fetchedAt': fetchedAt.toIso8601String(),
        'forceLogout': forceLogout,
        'minAppVersion': minAppVersion,
        'global': {
          'pluginsAllowed': pluginsAllowed,
          'message': globalMessage,
        },
        'plugins': plugins.map((k, v) => MapEntry(k, v.toJson())),
        'user': {
          'pluginsAllowed': userPluginsAllowed,
          'deniedPluginIds': deniedPluginIds.toList(),
          'message': userMessage,
        },
      };

  /// 返回 null 表示允许；非 null 为拒绝原因。
  String? denialFor(String pluginId, {String? feature, bool highRisk = true}) {
    if (forceLogout) {
      return globalMessage.isNotEmpty ? globalMessage : '需要重新登录';
    }
    // 高风险能力：缓存过期则拒绝（防离线绕过）
    if (highRisk && isExpired) {
      return '插件策略已过期，请联网后重试';
    }
    if (!pluginsAllowed) {
      return globalMessage.isNotEmpty ? globalMessage : '管理员已禁止使用插件';
    }
    if (!userPluginsAllowed) {
      return userMessage.isNotEmpty ? userMessage : '账号未授权使用插件';
    }
    if (deniedPluginIds.contains(pluginId)) {
      return userMessage.isNotEmpty ? userMessage : '账号未授权使用该插件';
    }
    final entry = plugins[pluginId];
    if (entry != null) {
      if (!entry.allowed) {
        return entry.message.isNotEmpty ? entry.message : '该插件已被管理员停用';
      }
      if (feature != null &&
          feature.isNotEmpty &&
          entry.features.containsKey(feature) &&
          entry.features[feature] == false) {
        return entry.message.isNotEmpty ? entry.message : '该功能已被管理员停用';
      }
    }
    return null;
  }

  bool canUse(String pluginId, {String? feature, bool highRisk = true}) =>
      denialFor(pluginId, feature: feature, highRisk: highRisk) == null;

  static int _asInt(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class PluginPolicyEntry {
  const PluginPolicyEntry({
    required this.allowed,
    required this.message,
    required this.features,
  });

  factory PluginPolicyEntry.fromJson(Map<String, dynamic> json) {
    final features = <String, bool>{};
    final raw = json['features'];
    if (raw is Map) {
      raw.forEach((key, value) {
        features[key.toString()] = value == true;
      });
    }
    return PluginPolicyEntry(
      allowed: json['allowed'] != false,
      message: json['message']?.toString() ?? '',
      features: features,
    );
  }

  final bool allowed;
  final String message;
  final Map<String, bool> features;

  Map<String, dynamic> toJson() => {
        'allowed': allowed,
        'message': message,
        'features': features,
      };
}

/// 策略缓存 + 刷新。
class PluginPolicyStore {
  PluginPolicyStore._();
  static final instance = PluginPolicyStore._();

  static const _cacheKey = 'plugin_policy_cache_v1';
  static const Duration _minRefreshGap = Duration(seconds: 20);

  PluginPolicySnapshot _snapshot = PluginPolicySnapshot.allowAll();
  DateTime? _lastFetchAttempt;
  bool _loaded = false;

  PluginPolicySnapshot get snapshot => _snapshot;

  Future<PluginPolicySnapshot> ensureLoaded() async {
    if (_loaded) return _snapshot;
    await _loadCache();
    _loaded = true;
    return _snapshot;
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _snapshot = PluginPolicySnapshot.fromJson(
        Map<String, dynamic>.from(decoded),
        fromCache: true,
      ).copyWith(stale: true);
    } catch (_) {}
  }

  Future<void> _saveCache(PluginPolicySnapshot snap) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(snap.toJson()));
  }

  /// 拉取策略。force=true 忽略节流。
  Future<PluginPolicySnapshot> refresh({bool force = false}) async {
    await ensureLoaded();
    final now = DateTime.now();
    if (!force &&
        _lastFetchAttempt != null &&
        now.difference(_lastFetchAttempt!) < _minRefreshGap) {
      return _snapshot;
    }
    _lastFetchAttempt = now;

    final session = await BoxAccountStore().loadSession();
    final serverUrl = session?.serverUrl ?? BoxAccountDefaults.serverUrl;
    final uri = Uri.parse(
      '${serverUrl.replaceAll(RegExp(r'/+$'), '')}/api/policy/plugins',
    );
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      final token = session?.token.trim() ?? '';
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          final snap = PluginPolicySnapshot.fromJson(
            Map<String, dynamic>.from(decoded),
            fetchedAt: DateTime.now(),
          );
          _snapshot = snap;
          await _saveCache(snap);
          return snap;
        }
      }
    } catch (_) {
      // 保持缓存；高风险路径由 isExpired 拒绝
    }
    if (_snapshot.version > 0) {
      _snapshot = _snapshot.copyWith(stale: true, fromCache: true);
    }
    return _snapshot;
  }
}

/// 统一闸门：远程禁止 > 本地启用。
class PluginGate {
  PluginGate._();

  static Future<PluginPolicySnapshot> _ready() async {
    final store = PluginPolicyStore.instance;
    await store.ensureLoaded();
    // 过期则尝试刷新（不 force 可被节流）
    if (store.snapshot.isExpired) {
      await store.refresh();
    }
    return store.snapshot;
  }

  static Future<String?> denial(
    String pluginId, {
    String? feature,
    bool highRisk = true,
  }) async {
    final snap = await _ready();
    return snap.denialFor(pluginId, feature: feature, highRisk: highRisk);
  }

  static Future<bool> canUse(
    String pluginId, {
    String? feature,
    bool highRisk = true,
  }) async {
    return (await denial(pluginId, feature: feature, highRisk: highRisk)) ==
        null;
  }

  /// 同步读取最近缓存（不 await 网络）。用于原生路径快速判断。
  static String? denialCached(
    String pluginId, {
    String? feature,
    bool highRisk = true,
  }) {
    return PluginPolicyStore.instance.snapshot.denialFor(
      pluginId,
      feature: feature,
      highRisk: highRisk,
    );
  }
}

/// 管理端策略客户端。
class PluginPolicyAdminClient {
  PluginPolicyAdminClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  Uri _uri(String serverUrl, String path) {
    final base = serverUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Map<String, String> _headers(String token) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> fetchAdmin({
    required String serverUrl,
    required String token,
  }) async {
    final resp = await _http
        .get(
          _uri(serverUrl, '/admin/policy/plugins'),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 15));
    return _decodeMap(resp);
  }

  Future<Map<String, dynamic>> putGlobal({
    required String serverUrl,
    required String token,
    required Map<String, dynamic> body,
  }) async {
    final resp = await _http
        .put(
          _uri(serverUrl, '/admin/policy/plugins'),
          headers: _headers(token),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return _decodeMap(resp);
  }

  Future<Map<String, dynamic>> putUserPlugins({
    required String serverUrl,
    required String token,
    required String userId,
    required Map<String, dynamic> body,
  }) async {
    final resp = await _http
        .put(
          _uri(serverUrl, '/admin/accounts/$userId/plugins'),
          headers: _headers(token),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return _decodeMap(resp);
  }

  Map<String, dynamic> _decodeMap(http.Response resp) {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final msg = body?['error'] is Map
          ? (body!['error'] as Map)['message']?.toString()
          : body?['message']?.toString();
      throw BoxAccountException(
        msg?.isNotEmpty == true ? msg! : '策略接口失败 HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    return body ?? <String, dynamic>{};
  }
}
