import 'package:flutter/material.dart';

import '../../../../plugin_market/models/plugin_market_security.dart';

String safeMarketString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

int safeMarketInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

bool safeMarketBool(dynamic value, [bool fallback = false]) {
  if (value == null) return fallback;
  if (value is bool) return value;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

DateTime? tryParseMarketDate(dynamic value) {
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
    'auto_awesome_outlined': Icons.auto_awesome_outlined,
    'auto_fix_high_outlined': Icons.auto_fix_high_outlined,
    'palette_outlined': Icons.palette_outlined,
    'local_fire_department_outlined': Icons.local_fire_department_outlined,
  };

  static IconData byName(String? name) {
    final key = safeMarketString(name).toLowerCase();
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
  'openImageGenerator',
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

List<MarketPluginTemplate> dedupMarketPluginTemplates(
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

List<MarketPluginTemplate> parseMarketPluginTemplates(dynamic raw) {
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

  return dedupMarketPluginTemplates(list);
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
      'colorValue': color.toARGB32(),
      'sort': sort,
    };
  }

  static MarketPluginTemplate? tryFromJson(Map<String, dynamic> json) {
    final id = safeMarketString(json['id']);
    if (id.isEmpty) return null;

    final title = safeMarketString(json['title'], id);
    final subtitle = safeMarketString(
      json['subtitle'],
      safeMarketString(json['desc']),
    );
    final areaCode = _normalizeAreaCode(
      safeMarketString(
        json['areaCode'],
        safeMarketString(json['area'], 'recommend'),
      ),
    );
    final actionCode = _normalizeActionCode(
      safeMarketString(
        json['actionCode'],
        safeMarketString(json['action'], 'toast'),
      ),
    );
    final payload = safeMarketString(json['payload']);
    final sort = safeMarketInt(json['sort'], 9999);

    IconData icon;
    if (json['iconCodePoint'] != null) {
      final cp = safeMarketInt(
        json['iconCodePoint'],
        _defaultIconForArea(areaCode).codePoint,
      );
      final ff = safeMarketString(json['iconFontFamily'], 'MaterialIcons');
      final fp = safeMarketString(json['iconFontPackage']);
      icon = IconData(
        // ignore: non_const_argument_for_const_parameter
        cp,
        // ignore: non_const_argument_for_const_parameter
        fontFamily: ff,
        // ignore: non_const_argument_for_const_parameter
        fontPackage: fp.isEmpty ? null : fp,
      );
    } else {
      final iconName = safeMarketString(
        json['iconName'],
        safeMarketString(json['icon']),
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
    const MarketPluginTemplate(
      id: 'market_daily_digest',
      title: '今日热闻',
      subtitle: '一键进入日报详情页',
      areaCode: 'recommend',
      actionCode: 'openDailyNews',
      payload: '',
      icon: Icons.newspaper_outlined,
      color: Color(0xFF6A5AE0),
      sort: 10,
    ),
    const MarketPluginTemplate(
      id: 'market_image_generator',
      title: 'AI 生图工坊',
      subtitle: 'Prompt 模板、历史复用、OpenAI 兼容生图',
      areaCode: 'recommend',
      actionCode: 'openImageGenerator',
      payload: '',
      icon: Icons.auto_awesome_outlined,
      color: Color(0xFF8B5CF6),
      sort: 12,
    ),
    const MarketPluginTemplate(
      id: 'market_quick_note',
      title: '快速便签',
      subtitle: '首页快捷记录灵感',
      areaCode: 'recommend',
      actionCode: 'toast',
      payload: '快速便签：后续可接入本地记事模块',
      icon: Icons.edit_note_outlined,
      color: Color(0xFF7F56D9),
      sort: 20,
    ),
    const MarketPluginTemplate(
      id: 'market_music_focus',
      title: '专注白噪音',
      subtitle: '工作学习沉浸模式',
      areaCode: 'music',
      actionCode: 'toast',
      payload: '白噪音插件开发中...',
      icon: Icons.graphic_eq,
      color: Color(0xFFEC4899),
      sort: 10,
    ),
    const MarketPluginTemplate(
      id: 'market_music_sleep',
      title: '睡眠电台',
      subtitle: '夜间轻音乐播放入口',
      areaCode: 'music',
      actionCode: 'toast',
      payload: '睡眠电台插件开发中...',
      icon: Icons.nightlight_round,
      color: Color(0xFFDB2777),
      sort: 20,
    ),
    const MarketPluginTemplate(
      id: 'market_video_archive_search',
      title: '影视快速检索',
      subtitle: '直达公共影视搜索页',
      areaCode: 'video',
      actionCode: 'openVideoList',
      payload: '',
      icon: Icons.video_collection_outlined,
      color: Color(0xFF4F46E5),
      sort: 10,
    ),
    const MarketPluginTemplate(
      id: 'market_video_watch_later',
      title: '稍后再看',
      subtitle: '收藏稍后观看片单',
      areaCode: 'video',
      actionCode: 'toast',
      payload: '稍后再看功能开发中...',
      icon: Icons.watch_later_outlined,
      color: Color(0xFF4338CA),
      sort: 20,
    ),
    const MarketPluginTemplate(
      id: 'market_comic_wallpaper',
      title: '动漫壁纸',
      subtitle: '二次元壁纸入口',
      areaCode: 'comic',
      actionCode: 'toast',
      payload: '动漫壁纸插件开发中...',
      icon: Icons.wallpaper_outlined,
      color: Color(0xFF0D9488),
      sort: 10,
    ),
    const MarketPluginTemplate(
      id: 'market_comic_week_rank',
      title: '本周漫画榜',
      subtitle: '热门漫画推荐',
      areaCode: 'comic',
      actionCode: 'toast',
      payload: '本周漫画榜插件开发中...',
      icon: Icons.auto_stories_outlined,
      color: Color(0xFF0F766E),
      sort: 20,
    ),
    const MarketPluginTemplate(
      id: 'market_novel_pick',
      title: '今日推荐书单',
      subtitle: '直达小说列表页',
      areaCode: 'novel',
      actionCode: 'openNovelList',
      payload: '',
      icon: Icons.menu_book_outlined,
      color: Color(0xFFF59E0B),
      sort: 10,
    ),
    const MarketPluginTemplate(
      id: 'market_novel_checkin',
      title: '阅读打卡',
      subtitle: '保持每日阅读习惯',
      areaCode: 'novel',
      actionCode: 'toast',
      payload: '阅读打卡功能开发中...',
      icon: Icons.task_alt_outlined,
      color: Color(0xFFD97706),
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
      'signatureMode': pluginMarketSignModeWireName(signatureMode),
      'signatureMessage': signatureMessage,
      'signatureValue': signatureValue,
      'plugins': templates.map((e) => e.toJson()).toList(),
    };
  }

  factory PluginMarketManifest.fromCacheJson(
    Map<String, dynamic> json, {
    required PluginMarketChannel defaultChannel,
  }) {
    final version = safeMarketInt(json['version'], 1);
    final fetchedAt = tryParseMarketDate(json['fetchedAt']) ?? DateTime.now();

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
      templates: dedupMarketPluginTemplates(templates),
      source: 'cache',
      fetchedAt: fetchedAt,
      channel: pluginMarketChannelFromName(
        safeMarketString(json['channel'], defaultChannel.name),
      ),
      signatureVerified: safeMarketBool(json['signatureVerified'], false),
      signatureMode: pluginMarketSignModeFromWireName(
        safeMarketString(json['signatureMode'], 'none'),
      ),
      signatureMessage: safeMarketString(json['signatureMessage']),
      signatureValue: safeMarketString(json['signatureValue']),
    );
  }
}
