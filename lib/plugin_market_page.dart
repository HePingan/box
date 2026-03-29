import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'novel/core/cache_store.dart';

typedef MarketInstallHandler = Future<void> Function(
  MarketPluginTemplate template,
);

typedef MarketUninstallHandler = Future<void> Function(String pluginId);

String _safeString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

int _safeInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

bool _safeBool(dynamic value, [bool fallback = false]) {
  if (value == null) return fallback;
  if (value is bool) return value;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

DateTime? _tryParseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

Color _parseColor(dynamic value, [Color fallback = const Color(0xFF4F46E5)]) {
  if (value == null) return fallback;
  if (value is int) return Color(value);

  var raw = value.toString().trim();
  if (raw.isEmpty) return fallback;

  raw = raw.toUpperCase();
  if (raw.startsWith('#')) raw = raw.substring(1);
  if (raw.startsWith('0X')) raw = raw.substring(2);

  if (raw.length == 6) raw = 'FF$raw';
  if (raw.length != 8) return fallback;

  final parsed = int.tryParse(raw, radix: 16);
  if (parsed == null) return fallback;
  return Color(parsed);
}

enum PluginMarketChannel {
  stable,
  beta,
}

extension PluginMarketChannelX on PluginMarketChannel {
  String get label {
    switch (this) {
      case PluginMarketChannel.stable:
        return 'Stable';
      case PluginMarketChannel.beta:
        return 'Beta';
    }
  }

  String get code => name;
}

PluginMarketChannel _channelFromName(String raw) {
  final text = raw.trim().toLowerCase();
  if (text == 'beta') return PluginMarketChannel.beta;
  return PluginMarketChannel.stable;
}

enum PluginMarketSignMode {
  none,
  sha256,
  hmacSha256,
}

String _signModeWireName(PluginMarketSignMode mode) {
  switch (mode) {
    case PluginMarketSignMode.none:
      return 'none';
    case PluginMarketSignMode.sha256:
      return 'sha256';
    case PluginMarketSignMode.hmacSha256:
      return 'hmac-sha256';
  }
}

PluginMarketSignMode _signModeFromWireName(String raw) {
  final text = raw.trim().toLowerCase();
  switch (text) {
    case 'sha256':
      return PluginMarketSignMode.sha256;
    case 'hmac-sha256':
    case 'hmac_sha256':
    case 'hmacsha256':
      return PluginMarketSignMode.hmacSha256;
    case 'none':
    default:
      return PluginMarketSignMode.none;
  }
}

class PluginMarketSecurityConfig {
  final PluginMarketSignMode mode;

  /// mode = hmacSha256 时需要设置
  final String secret;

  /// true: 验签失败也允许放行远程
  /// false: 验签失败直接拒绝远程，走缓存/内置回退
  final bool allowUnsigned;

  const PluginMarketSecurityConfig({
    this.mode = PluginMarketSignMode.none,
    this.secret = '',
    this.allowUnsigned = false,
  });
}

class PluginMarketVerifyResult {
  final bool passed;
  final String message;
  final String expected;
  final String actual;

  const PluginMarketVerifyResult({
    required this.passed,
    required this.message,
    required this.expected,
    required this.actual,
  });
}

dynamic _canonicalizeJsonValue(dynamic value) {
  if (value is Map) {
    final entries = <MapEntry<String, dynamic>>[];
    value.forEach((key, val) {
      entries.add(MapEntry(key.toString(), val));
    });
    entries.sort((a, b) => a.key.compareTo(b.key));

    final result = <String, dynamic>{};
    for (final e in entries) {
      result[e.key] = _canonicalizeJsonValue(e.value);
    }
    return result;
  }

  if (value is List) {
    return value.map(_canonicalizeJsonValue).toList(growable: false);
  }

  return value;
}

String _canonicalJson(dynamic value) {
  return jsonEncode(_canonicalizeJsonValue(value));
}

String _sha256Hex(String text) {
  return sha256.convert(utf8.encode(text)).toString();
}

String _hmacSha256Hex(String text, String secret) {
  final mac = Hmac(sha256, utf8.encode(secret));
  return mac.convert(utf8.encode(text)).toString();
}

PluginMarketVerifyResult _verifySignatureForPayload({
  required PluginMarketSecurityConfig security,
  required PluginMarketChannel channel,
  required int version,
  required List<dynamic> plugins,
  required String signature,
}) {
  if (security.mode == PluginMarketSignMode.none) {
    return const PluginMarketVerifyResult(
      passed: true,
      message: '验签关闭',
      expected: '',
      actual: '',
    );
  }

  final actual = signature.trim().toLowerCase();
  if (actual.isEmpty) {
    return const PluginMarketVerifyResult(
      passed: false,
      message: '缺少 signature',
      expected: '',
      actual: '',
    );
  }

  final payload = <String, dynamic>{
    'channel': channel.name,
    'version': version <= 0 ? 1 : version,
    'plugins': plugins,
  };

  final canonical = _canonicalJson(payload);

  String expected = '';
  switch (security.mode) {
    case PluginMarketSignMode.none:
      expected = '';
      break;
    case PluginMarketSignMode.sha256:
      expected = _sha256Hex(canonical);
      break;
    case PluginMarketSignMode.hmacSha256:
      if (security.secret.trim().isEmpty) {
        return const PluginMarketVerifyResult(
          passed: false,
          message: 'HMAC 模式缺少 secret',
          expected: '',
          actual: '',
        );
      }
      expected = _hmacSha256Hex(canonical, security.secret);
      break;
  }

  final passed = actual == expected.toLowerCase();

  return PluginMarketVerifyResult(
    passed: passed,
    message: passed ? '验签通过' : '签名不匹配',
    expected: expected,
    actual: actual,
  );
}

class _MarketIconRegistry {
  static final Map<String, IconData> _icons = {
    'extension_outlined': Icons.extension_outlined,
    'newspaper_outlined': Icons.newspaper_outlined,
    'edit_note_outlined': Icons.edit_note_outlined,
    'graphic_eq': Icons.graphic_eq,
    'nightlight_round': Icons.nightlight_round,
    'video_collection_outlined': Icons.video_collection_outlined,
    'watch_later_outlined': Icons.watch_later_outlined,
    'wallpaper_outlined': Icons.wallpaper_outlined,
    'auto_stories_outlined': Icons.auto_stories_outlined,
    'menu_book_outlined': Icons.menu_book_outlined,
    'task_alt_outlined': Icons.task_alt_outlined,
    'tips_and_updates_outlined': Icons.tips_and_updates_outlined,
    'movie_outlined': Icons.movie_outlined,
    'smart_toy_outlined': Icons.smart_toy_outlined,
    'search': Icons.search,
    'bookmark_border_outlined': Icons.bookmark_border_outlined,
    'download_outlined': Icons.download_outlined,
    'travel_explore_outlined': Icons.travel_explore_outlined,
    'music_note_outlined': Icons.music_note_outlined,
    'play_circle_outline': Icons.play_circle_outline,
    'image_outlined': Icons.image_outlined,
    'local_fire_department_outlined': Icons.local_fire_department_outlined,
  };

  static IconData byName(String? name) {
    final key = _safeString(name).toLowerCase();
    if (key.isEmpty) return Icons.extension_outlined;
    return _icons[key] ?? Icons.extension_outlined;
  }
}

const Set<String> _allowedAreaCodes = {
  'recommend',
  'music',
  'video',
  'comic',
  'novel',
};

const Set<String> _allowedActionCodes = {
  'toast',
  'openDailyNews',
  'openNovelList',
  'openVideoList',
};

String _normalizeAreaCode(String areaCode) {
  final code = areaCode.trim();
  if (_allowedAreaCodes.contains(code)) return code;
  return 'recommend';
}

String _normalizeActionCode(String actionCode) {
  final code = actionCode.trim();
  if (_allowedActionCodes.contains(code)) return code;
  return 'toast';
}

IconData _defaultIconForArea(String areaCode) {
  switch (_normalizeAreaCode(areaCode)) {
    case 'music':
      return Icons.music_note_outlined;
    case 'video':
      return Icons.play_circle_outline;
    case 'comic':
      return Icons.image_outlined;
    case 'novel':
      return Icons.menu_book_outlined;
    case 'recommend':
    default:
      return Icons.local_fire_department_outlined;
  }
}

Color _defaultColorForArea(String areaCode) {
  switch (_normalizeAreaCode(areaCode)) {
    case 'music':
      return const Color(0xFFEC4899);
    case 'video':
      return const Color(0xFF4F46E5);
    case 'comic':
      return const Color(0xFF0D9488);
    case 'novel':
      return const Color(0xFFF59E0B);
    case 'recommend':
    default:
      return const Color(0xFF7C3AED);
  }
}

List<MarketPluginTemplate> _dedupTemplates(
  Iterable<MarketPluginTemplate> input,
) {
  final map = <String, MarketPluginTemplate>{};

  for (final t in input) {
    if (!t.isValid) continue;
    map[t.id] = t;
  }

  final list = map.values.toList();
  list.sort((a, b) {
    final c = a.sort.compareTo(b.sort);
    if (c != 0) return c;
    return a.title.compareTo(b.title);
  });
  return list;
}

class MarketPluginTemplate {
  final String id;
  final String title;
  final String subtitle;
  final String areaCode;
  final String actionCode;
  final String payload;
  final IconData icon;
  final Color color;
  final int sort;

  const MarketPluginTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.areaCode,
    required this.actionCode,
    required this.payload,
    required this.icon,
    required this.color,
    this.sort = 9999,
  });

  bool get isValid => id.trim().isNotEmpty && title.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'areaCode': areaCode,
      'actionCode': actionCode,
      'payload': payload,
      'iconCodePoint': icon.codePoint,
      'iconFontFamily': icon.fontFamily,
      'iconFontPackage': icon.fontPackage,
      'colorValue': color.value,
      'sort': sort,
    };
  }

  static MarketPluginTemplate? tryFromJson(Map<String, dynamic> json) {
    final id = _safeString(json['id']);
    if (id.isEmpty) return null;

    final title = _safeString(json['title'], id);
    final subtitle = _safeString(json['subtitle'], _safeString(json['desc']));
    final areaCode = _normalizeAreaCode(
      _safeString(json['areaCode'], _safeString(json['area'], 'recommend')),
    );
    final actionCode = _normalizeActionCode(
      _safeString(json['actionCode'], _safeString(json['action'], 'toast')),
    );
    final payload = _safeString(json['payload']);
    final sort = _safeInt(json['sort'], 9999);

    IconData icon;
    if (json['iconCodePoint'] != null) {
      final cp = _safeInt(
        json['iconCodePoint'],
        _defaultIconForArea(areaCode).codePoint,
      );
      final ff = _safeString(json['iconFontFamily'], 'MaterialIcons');
      final fp = _safeString(json['iconFontPackage']);
      icon = IconData(
        cp,
        fontFamily: ff,
        fontPackage: fp.isEmpty ? null : fp,
      );
    } else {
      final iconName = _safeString(
        json['iconName'],
        _safeString(json['icon']),
      );
      icon = iconName.isEmpty
          ? _defaultIconForArea(areaCode)
          : _MarketIconRegistry.byName(iconName);
    }

    final colorRaw = json.containsKey('colorValue')
        ? json['colorValue']
        : json['color'];
    final color = _parseColor(colorRaw, _defaultColorForArea(areaCode));

    return MarketPluginTemplate(
      id: id,
      title: title,
      subtitle: subtitle,
      areaCode: areaCode,
      actionCode: actionCode,
      payload: payload,
      icon: icon,
      color: color,
      sort: sort,
    );
  }

  static final List<MarketPluginTemplate> defaults = [
    MarketPluginTemplate(
      id: 'market_daily_digest',
      title: '今日热闻',
      subtitle: '一键进入日报详情页',
      areaCode: 'recommend',
      actionCode: 'openDailyNews',
      payload: '',
      icon: Icons.newspaper_outlined,
      color: const Color(0xFF6A5AE0),
      sort: 10,
    ),
    MarketPluginTemplate(
      id: 'market_quick_note',
      title: '快速便签',
      subtitle: '首页快捷记录灵感',
      areaCode: 'recommend',
      actionCode: 'toast',
      payload: '快速便签：后续可接入本地记事模块',
      icon: Icons.edit_note_outlined,
      color: const Color(0xFF7F56D9),
      sort: 20,
    ),
    MarketPluginTemplate(
      id: 'market_music_focus',
      title: '专注白噪音',
      subtitle: '工作学习沉浸模式',
      areaCode: 'music',
      actionCode: 'toast',
      payload: '白噪音插件开发中...',
      icon: Icons.graphic_eq,
      color: const Color(0xFFEC4899),
      sort: 10,
    ),
    MarketPluginTemplate(
      id: 'market_music_sleep',
      title: '睡眠电台',
      subtitle: '夜间轻音乐播放入口',
      areaCode: 'music',
      actionCode: 'toast',
      payload: '睡眠电台插件开发中...',
      icon: Icons.nightlight_round,
      color: const Color(0xFFDB2777),
      sort: 20,
    ),
    MarketPluginTemplate(
      id: 'market_video_archive_search',
      title: '影视快速检索',
      subtitle: '直达公共影视搜索页',
      areaCode: 'video',
      actionCode: 'openVideoList',
      payload: '',
      icon: Icons.video_collection_outlined,
      color: const Color(0xFF4F46E5),
      sort: 10,
    ),
    MarketPluginTemplate(
      id: 'market_video_watch_later',
      title: '稍后再看',
      subtitle: '收藏稍后观看片单',
      areaCode: 'video',
      actionCode: 'toast',
      payload: '稍后再看功能开发中...',
      icon: Icons.watch_later_outlined,
      color: const Color(0xFF4338CA),
      sort: 20,
    ),
    MarketPluginTemplate(
      id: 'market_comic_wallpaper',
      title: '动漫壁纸',
      subtitle: '二次元壁纸入口',
      areaCode: 'comic',
      actionCode: 'toast',
      payload: '动漫壁纸插件开发中...',
      icon: Icons.wallpaper_outlined,
      color: const Color(0xFF0D9488),
      sort: 10,
    ),
    MarketPluginTemplate(
      id: 'market_comic_week_rank',
      title: '本周漫画榜',
      subtitle: '热门漫画推荐',
      areaCode: 'comic',
      actionCode: 'toast',
      payload: '本周漫画榜插件开发中...',
      icon: Icons.auto_stories_outlined,
      color: const Color(0xFF0F766E),
      sort: 20,
    ),
    MarketPluginTemplate(
      id: 'market_novel_pick',
      title: '今日推荐书单',
      subtitle: '直达小说列表页',
      areaCode: 'novel',
      actionCode: 'openNovelList',
      payload: '',
      icon: Icons.menu_book_outlined,
      color: const Color(0xFFF59E0B),
      sort: 10,
    ),
    MarketPluginTemplate(
      id: 'market_novel_checkin',
      title: '阅读打卡',
      subtitle: '保持每日阅读习惯',
      areaCode: 'novel',
      actionCode: 'toast',
      payload: '阅读打卡功能开发中...',
      icon: Icons.task_alt_outlined,
      color: const Color(0xFFD97706),
      sort: 20,
    ),
  ];
}

class PluginMarketManifest {
  final int version;
  final List<MarketPluginTemplate> templates;
  final String source; // remote/cache/builtin
  final DateTime fetchedAt;
  final PluginMarketChannel channel;

  final bool signatureVerified;
  final PluginMarketSignMode signatureMode;
  final String signatureMessage;
  final String signatureValue;

  const PluginMarketManifest({
    required this.version,
    required this.templates,
    required this.source,
    required this.fetchedAt,
    required this.channel,
    required this.signatureVerified,
    required this.signatureMode,
    required this.signatureMessage,
    required this.signatureValue,
  });

  PluginMarketManifest copyWith({
    int? version,
    List<MarketPluginTemplate>? templates,
    String? source,
    DateTime? fetchedAt,
    PluginMarketChannel? channel,
    bool? signatureVerified,
    PluginMarketSignMode? signatureMode,
    String? signatureMessage,
    String? signatureValue,
  }) {
    return PluginMarketManifest(
      version: version ?? this.version,
      templates: templates ?? this.templates,
      source: source ?? this.source,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      channel: channel ?? this.channel,
      signatureVerified: signatureVerified ?? this.signatureVerified,
      signatureMode: signatureMode ?? this.signatureMode,
      signatureMessage: signatureMessage ?? this.signatureMessage,
      signatureValue: signatureValue ?? this.signatureValue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'source': source,
      'fetchedAt': fetchedAt.toIso8601String(),
      'channel': channel.name,
      'signatureVerified': signatureVerified,
      'signatureMode': _signModeWireName(signatureMode),
      'signatureMessage': signatureMessage,
      'signatureValue': signatureValue,
      'plugins': templates.map((e) => e.toJson()).toList(),
    };
  }

  factory PluginMarketManifest.fromCacheJson(
    Map<String, dynamic> json, {
    required PluginMarketChannel defaultChannel,
  }) {
    final version = _safeInt(json['version'], 1);
    final fetchedAt = _tryParseDate(json['fetchedAt']) ?? DateTime.now();

    final templates = <MarketPluginTemplate>[];
    final rawList = json['plugins'];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          final tpl = MarketPluginTemplate.tryFromJson(
            Map<String, dynamic>.from(item),
          );
          if (tpl != null) templates.add(tpl);
        }
      }
    }

    return PluginMarketManifest(
      version: version <= 0 ? 1 : version,
      templates: _dedupTemplates(templates),
      source: 'cache',
      fetchedAt: fetchedAt,
      channel: _channelFromName(_safeString(json['channel'], defaultChannel.name)),
      signatureVerified: _safeBool(json['signatureVerified'], false),
      signatureMode: _signModeFromWireName(
        _safeString(json['signatureMode'], 'none'),
      ),
      signatureMessage: _safeString(json['signatureMessage']),
      signatureValue: _safeString(json['signatureValue']),
    );
  }
}

class _ResolvedRemotePayload {
  final PluginMarketChannel channel;
  final Map<String, dynamic> node;

  const _ResolvedRemotePayload({
    required this.channel,
    required this.node,
  });
}

class PluginMarketRepository {
  PluginMarketRepository._();

  static final PluginMarketRepository instance = PluginMarketRepository._();

  final CacheStore _cache = CacheStore(namespace: 'plugin_market');

  String _cacheManifestKey(PluginMarketChannel channel) {
    return 'remote_manifest_v3_${channel.name}';
  }

  Future<PluginMarketManifest> loadManifest({
    required List<MarketPluginTemplate> fallbackTemplates,
    required PluginMarketChannel channel,
    required PluginMarketSecurityConfig security,
    String? remoteConfigUrl,
    bool forceRefresh = false,
  }) async {
    final builtin = PluginMarketManifest(
      version: 1,
      templates: _dedupTemplates(fallbackTemplates),
      source: 'builtin',
      fetchedAt: DateTime.now(),
      channel: channel,
      signatureVerified: security.mode == PluginMarketSignMode.none,
      signatureMode: security.mode,
      signatureMessage: security.mode == PluginMarketSignMode.none ? '验签关闭' : '内置清单',
      signatureValue: '',
    );

    final cached = await _readCache(channel);
    final url = _safeString(remoteConfigUrl);

    // 未配置远程：缓存优先
    if (url.isEmpty) {
      return cached ?? builtin;
    }

    // 配置远程：尝试远程
    final remote = await _fetchRemote(
      url,
      requestedChannel: channel,
      security: security,
    );

    if (remote != null) {
      if (!forceRefresh && cached != null && cached.version > remote.version) {
        return cached.copyWith(source: 'cache');
      }

      await _writeCache(channel, remote);
      return remote;
    }

    // 远程失败，回退
    return cached ?? builtin;
  }

  Future<PluginMarketManifest?> _fetchRemote(
    String url, {
    required PluginMarketChannel requestedChannel,
    required PluginMarketSecurityConfig security,
  }) async {
    try {
      final uri = Uri.parse(url);
      final text = await NetworkAssetBundle(uri)
          .loadString(url)
          .timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(text);

      // 兼容老格式：直接数组
      if (decoded is List) {
        final plugins = decoded;
        final verify = _verifySignatureForPayload(
          security: security,
          channel: requestedChannel,
          version: 1,
          plugins: plugins,
          signature: '',
        );

        if (!verify.passed && !security.allowUnsigned) {
          return null;
        }

        final templates = _parseTemplates(plugins);
        return PluginMarketManifest(
          version: 1,
          templates: templates,
          source: 'remote',
          fetchedAt: DateTime.now(),
          channel: requestedChannel,
          signatureVerified: verify.passed,
          signatureMode: security.mode,
          signatureMessage: verify.passed
              ? verify.message
              : '${verify.message}${security.allowUnsigned ? '（已放行）' : ''}',
          signatureValue: '',
        );
      }

      if (decoded is! Map) {
        return null;
      }

      final root = Map<String, dynamic>.from(decoded);
      final resolved = _resolveChannelPayload(
        root,
        requestedChannel: requestedChannel,
      );
      if (resolved == null) return null;

      final actualChannel = resolved.channel;
      final node = resolved.node;

      final version = _safeInt(
        node['version'],
        _safeInt(root['version'], 1),
      );

      final rawPluginsValue = node['plugins'] ??
          node['data'] ??
          node['list'] ??
          root['plugins'] ??
          root['data'] ??
          root['list'] ??
          const [];

      final rawPlugins = rawPluginsValue is List ? rawPluginsValue : const [];

      String signature = _safeString(
        node['signature'],
        _safeString(node['sign']),
      );

      if (signature.isEmpty) {
        final signs = root['signatures'];
        if (signs is Map) {
          signature = _safeString(signs[actualChannel.name]);
        }
      }

      final verify = _verifySignatureForPayload(
        security: security,
        channel: actualChannel,
        version: version,
        plugins: rawPlugins,
        signature: signature,
      );

      if (!verify.passed && !security.allowUnsigned) {
        return null;
      }

      final templates = _parseTemplates(rawPlugins);
      final fetchedAt = _tryParseDate(node['fetchedAt']) ??
          _tryParseDate(node['updatedAt']) ??
          _tryParseDate(root['fetchedAt']) ??
          _tryParseDate(root['updatedAt']) ??
          DateTime.now();

      return PluginMarketManifest(
        version: version <= 0 ? 1 : version,
        templates: templates,
        source: 'remote',
        fetchedAt: fetchedAt,
        channel: actualChannel,
        signatureVerified: verify.passed,
        signatureMode: security.mode,
        signatureMessage: verify.passed
            ? verify.message
            : '${verify.message}${security.allowUnsigned ? '（已放行）' : ''}',
        signatureValue: signature,
      );
    } catch (_) {
      return null;
    }
  }

  _ResolvedRemotePayload? _resolveChannelPayload(
    Map<String, dynamic> root, {
    required PluginMarketChannel requestedChannel,
  }) {
    final channelsRaw = root['channels'];

    // 新格式：{ channels: { stable: {...}, beta: {...} } }
    if (channelsRaw is Map) {
      final channels = Map<String, dynamic>.from(channelsRaw);

      dynamic node = channels[requestedChannel.name];
      PluginMarketChannel actual = requestedChannel;

      if (node is! Map && requestedChannel == PluginMarketChannel.beta) {
        final stable = channels['stable'];
        if (stable is Map) {
          node = stable;
          actual = PluginMarketChannel.stable;
        }
      }

      if (node is! Map) {
        for (final entry in channels.entries) {
          if (entry.value is Map) {
            node = entry.value;
            actual = _channelFromName(entry.key);
            break;
          }
        }
      }

      if (node is Map) {
        return _ResolvedRemotePayload(
          channel: actual,
          node: Map<String, dynamic>.from(node),
        );
      }

      return null;
    }

    // 旧格式：根节点即清单
    return _ResolvedRemotePayload(
      channel: requestedChannel,
      node: root,
    );
  }

  List<MarketPluginTemplate> _parseTemplates(dynamic raw) {
    if (raw is! List) return const [];

    final list = <MarketPluginTemplate>[];
    for (final item in raw) {
      if (item is Map) {
        final tpl = MarketPluginTemplate.tryFromJson(
          Map<String, dynamic>.from(item),
        );
        if (tpl != null) list.add(tpl);
      }
    }

    return _dedupTemplates(list);
  }

  Future<PluginMarketManifest?> _readCache(PluginMarketChannel channel) async {
    try {
      final raw = await _cache.read(_cacheManifestKey(channel));

      if (raw is String) {
        if (raw.trim().isEmpty) return null;
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return PluginMarketManifest.fromCacheJson(
            Map<String, dynamic>.from(decoded),
            defaultChannel: channel,
          );
        }
      }

      if (raw is Map) {
        return PluginMarketManifest.fromCacheJson(
          Map<String, dynamic>.from(raw),
          defaultChannel: channel,
        );
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(
    PluginMarketChannel channel,
    PluginMarketManifest manifest,
  ) async {
    final text = jsonEncode(manifest.toJson());
    await _cache.write(_cacheManifestKey(channel), text);
  }
}

class PluginMarketPage extends StatefulWidget {
  const PluginMarketPage({
    super.key,
    required this.initialInstalledIds,
    required this.onInstall,
    required this.onUninstall,
    this.templates = const [],
    this.remoteConfigUrl,
    this.initialChannel = PluginMarketChannel.stable,
    this.securityConfig = const PluginMarketSecurityConfig(),
  });

  final Set<String> initialInstalledIds;
  final MarketInstallHandler onInstall;
  final MarketUninstallHandler onUninstall;
  final List<MarketPluginTemplate> templates;

  /// 远程清单 URL
  final String? remoteConfigUrl;

  /// 初始频道
  final PluginMarketChannel initialChannel;

  /// 验签配置
  final PluginMarketSecurityConfig securityConfig;

  @override
  State<PluginMarketPage> createState() => _PluginMarketPageState();
}

class _PluginMarketPageState extends State<PluginMarketPage> {
  List<MarketPluginTemplate> _allTemplates = [];
  late Set<String> _installedIds;

  final Set<String> _loadingIds = {};
  bool _bulkRunning = false;
  bool _marketLoading = true;

  String _keyword = '';
  String _areaFilter = 'all';

  late PluginMarketChannel _currentChannel;

  String _marketSource = 'builtin';
  int _marketVersion = 1;
  DateTime? _marketFetchedAt;

  bool _signatureVerified = false;
  PluginMarketSignMode _signatureMode = PluginMarketSignMode.none;
  String _signatureMessage = '';

  @override
  void initState() {
    super.initState();
    _installedIds = {...widget.initialInstalledIds};
    _currentChannel = widget.initialChannel;
    _loadMarket(forceRefresh: false);
  }

  Future<void> _loadMarket({required bool forceRefresh}) async {
    setState(() => _marketLoading = true);

    try {
      final fallback = widget.templates.isEmpty
          ? MarketPluginTemplate.defaults
          : widget.templates;

      final manifest = await PluginMarketRepository.instance.loadManifest(
        fallbackTemplates: fallback,
        channel: _currentChannel,
        security: widget.securityConfig,
        remoteConfigUrl: widget.remoteConfigUrl,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;

      setState(() {
        _allTemplates = manifest.templates;
        _marketSource = manifest.source;
        _marketVersion = manifest.version;
        _marketFetchedAt = manifest.fetchedAt;
        _signatureVerified = manifest.signatureVerified;
        _signatureMode = manifest.signatureMode;
        _signatureMessage = manifest.signatureMessage;
        _currentChannel = manifest.channel;
        _marketLoading = false;
      });

      final hasRemote = _safeString(widget.remoteConfigUrl).isNotEmpty;
      if (forceRefresh && hasRemote && manifest.source != 'remote') {
        _showSnack('远程拉取失败，已回退到${_sourceLabel(manifest.source)}');
      }

      if (manifest.source == 'remote' &&
          widget.securityConfig.mode != PluginMarketSignMode.none &&
          !manifest.signatureVerified) {
        _showSnack('远程清单验签未通过：${manifest.signatureMessage}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _marketLoading = false);
      _showSnack('加载插件市场失败：$e');
    }
  }

  Future<void> _switchChannel(PluginMarketChannel channel) async {
    if (_currentChannel == channel) return;

    setState(() {
      _currentChannel = channel;
      _keyword = '';
      _areaFilter = 'all';
    });

    await _loadMarket(forceRefresh: false);
  }

  List<MarketPluginTemplate> get _visibleTemplates {
    final keyword = _keyword.trim().toLowerCase();

    final list = _allTemplates.where((item) {
      final areaOk = _areaFilter == 'all' || item.areaCode == _areaFilter;
      if (!areaOk) return false;

      if (keyword.isEmpty) return true;

      final joined = '${item.title} ${item.subtitle} ${item.payload}'.toLowerCase();
      return joined.contains(keyword);
    }).toList();

    list.sort((a, b) {
      final c = a.sort.compareTo(b.sort);
      if (c != 0) return c;
      return a.title.compareTo(b.title);
    });

    return list;
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'remote':
        return '远程';
      case 'cache':
        return '缓存';
      case 'builtin':
      default:
        return '内置';
    }
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '--';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _verifyLabel() {
    if (_signatureMode == PluginMarketSignMode.none) return '关闭';
    return _signatureVerified ? '通过' : '未通过';
  }

  String _areaLabel(String code) {
    switch (code) {
      case 'recommend':
        return '推荐';
      case 'music':
        return '音乐';
      case 'video':
        return '影视';
      case 'comic':
        return '漫画';
      case 'novel':
        return '小说';
      default:
        return code;
    }
  }

  String _actionLabel(String code) {
    switch (code) {
      case 'toast':
        return '提示动作';
      case 'openDailyNews':
        return '打开日报';
      case 'openNovelList':
        return '打开小说';
      case 'openVideoList':
        return '打开影视';
      default:
        return code;
    }
  }

  Future<void> _install(MarketPluginTemplate item) async {
    if (_loadingIds.contains(item.id) || _bulkRunning) return;

    setState(() => _loadingIds.add(item.id));
    try {
      await widget.onInstall(item);
      if (!mounted) return;
      setState(() => _installedIds.add(item.id));
      _showSnack('安装成功：${item.title}');
    } catch (e) {
      _showSnack('安装失败：$e');
    } finally {
      if (mounted) setState(() => _loadingIds.remove(item.id));
    }
  }

  Future<void> _uninstall(MarketPluginTemplate item) async {
    if (_loadingIds.contains(item.id) || _bulkRunning) return;

    setState(() => _loadingIds.add(item.id));
    try {
      await widget.onUninstall(item.id);
      if (!mounted) return;
      setState(() => _installedIds.remove(item.id));
      _showSnack('已卸载：${item.title}');
    } catch (e) {
      _showSnack('卸载失败：$e');
    } finally {
      if (mounted) setState(() => _loadingIds.remove(item.id));
    }
  }

  Future<void> _installVisible() async {
    if (_bulkRunning) return;

    final target = _visibleTemplates
        .where((e) => !_installedIds.contains(e.id))
        .toList();

    if (target.isEmpty) {
      _showSnack('当前筛选下没有可安装插件');
      return;
    }

    setState(() => _bulkRunning = true);

    var success = 0;
    for (final item in target) {
      try {
        await widget.onInstall(item);
        _installedIds.add(item.id);
        success++;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _bulkRunning = false);
    _showSnack('批量安装完成：$success / ${target.length}');
  }

  Future<void> _removeVisible() async {
    if (_bulkRunning) return;

    final target = _visibleTemplates
        .where((e) => _installedIds.contains(e.id))
        .toList();

    if (target.isEmpty) {
      _showSnack('当前筛选下没有已安装插件');
      return;
    }

    setState(() => _bulkRunning = true);

    var success = 0;
    for (final item in target) {
      try {
        await widget.onUninstall(item.id);
        _installedIds.remove(item.id);
        success++;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _bulkRunning = false);
    _showSnack('批量卸载完成：$success / ${target.length}');
  }

  Widget _buildAreaChip(String code, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _areaFilter == code,
      onSelected: (_) => setState(() => _areaFilter = code),
    );
  }

  Widget _buildChannelSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Stable'),
            selected: _currentChannel == PluginMarketChannel.stable,
            onSelected: (_) => _switchChannel(PluginMarketChannel.stable),
          ),
          ChoiceChip(
            label: const Text('Beta'),
            selected: _currentChannel == PluginMarketChannel.beta,
            onSelected: (_) => _switchChannel(PluginMarketChannel.beta),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaCard() {
    final remote = _safeString(widget.remoteConfigUrl);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAF2)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _TagChip(text: '来源：${_sourceLabel(_marketSource)}'),
          _TagChip(text: '频道：${_currentChannel.label}'),
          _TagChip(text: '版本：v$_marketVersion'),
          _TagChip(text: '验签：${_verifyLabel()}'),
          _TagChip(text: '模式：${_signModeWireName(_signatureMode)}'),
          _TagChip(text: '插件：${_allTemplates.length}'),
          _TagChip(text: '更新时间：${_fmtTime(_marketFetchedAt)}'),
          _TagChip(text: remote.isEmpty ? '远程：未配置' : '远程：已配置'),
        ],
      ),
    );
  }

  Widget _buildSignatureWarning() {
    final shouldWarn = _marketSource == 'remote' &&
        widget.securityConfig.mode != PluginMarketSignMode.none &&
        !_signatureVerified;

    if (!shouldWarn) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '远程清单验签未通过：$_signatureMessage'
              '\n策略：${widget.securityConfig.allowUnsigned ? '允许放行' : '严格拒绝'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(MarketPluginTemplate item) {
    final installed = _installedIds.contains(item.id);
    final loading = _loadingIds.contains(item.id) || _bulkRunning;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: item.color.withOpacity(0.15),
              child: Icon(item.icon, color: item.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _TagChip(text: _areaLabel(item.areaCode)),
                      _TagChip(text: _actionLabel(item.actionCode)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (loading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (installed)
              OutlinedButton.icon(
                onPressed: () => _uninstall(item),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('卸载'),
              )
            else
              FilledButton.icon(
                onPressed: () => _install(item),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('安装'),
              ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleTemplates;

    return Scaffold(
      appBar: AppBar(
        title: Text('插件市场（${_currentChannel.label}）'),
        actions: [
          IconButton(
            tooltip: '刷新远程配置',
            onPressed: _marketLoading ? null : () => _loadMarket(forceRefresh: true),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) {
              switch (value) {
                case 'switch_stable':
                  _switchChannel(PluginMarketChannel.stable);
                  break;
                case 'switch_beta':
                  _switchChannel(PluginMarketChannel.beta);
                  break;
                case 'install_visible':
                  _installVisible();
                  break;
                case 'remove_visible':
                  _removeVisible();
                  break;
                case 'copy_url':
                  final url = _safeString(widget.remoteConfigUrl);
                  if (url.isEmpty) {
                    _showSnack('未配置远程地址');
                  } else {
                    Clipboard.setData(ClipboardData(text: url));
                    _showSnack('远程地址已复制');
                  }
                  break;
                case 'reset_filter':
                  setState(() {
                    _keyword = '';
                    _areaFilter = 'all';
                  });
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'switch_stable',
                child: Text(
                  _currentChannel == PluginMarketChannel.stable
                      ? '当前频道：Stable'
                      : '切换到 Stable',
                ),
              ),
              PopupMenuItem(
                value: 'switch_beta',
                child: Text(
                  _currentChannel == PluginMarketChannel.beta
                      ? '当前频道：Beta'
                      : '切换到 Beta',
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'install_visible',
                child: Text('安装当前筛选结果'),
              ),
              const PopupMenuItem(
                value: 'remove_visible',
                child: Text('卸载当前筛选已安装'),
              ),
              const PopupMenuItem(
                value: 'copy_url',
                child: Text('复制远程配置地址'),
              ),
              const PopupMenuItem(
                value: 'reset_filter',
                child: Text('重置筛选'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_marketLoading) const LinearProgressIndicator(minHeight: 2),
          _buildMetaCard(),
          _buildSignatureWarning(),
          _buildChannelSwitch(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _keyword = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索插件名称/描述',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _keyword.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => setState(() => _keyword = ''),
                        icon: const Icon(Icons.clear),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildAreaChip('all', '全部'),
                _buildAreaChip('recommend', '推荐'),
                _buildAreaChip('music', '音乐'),
                _buildAreaChip('video', '影视'),
                _buildAreaChip('comic', '漫画'),
                _buildAreaChip('novel', '小说'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadMarket(forceRefresh: true),
              child: visible.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            _marketLoading ? '正在加载插件市场...' : '没有匹配结果',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) => _buildCard(visible[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
      ),
    );
  }
}