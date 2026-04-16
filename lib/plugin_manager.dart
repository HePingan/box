import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'daily_news_page.dart';
import 'novel/core/cache_store.dart';

import 'novel/pages/novel_list_page.dart';
import 'video_module.dart';

String _asString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) {
    final v = value.trim();
    return v.isEmpty ? fallback : v;
  }
  final v = value.toString().trim();
  return v.isEmpty ? fallback : v;
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

bool _asBool(dynamic value, [bool fallback = false]) {
  if (value == null) return fallback;
  if (value is bool) return value;
  final text = value.toString().toLowerCase().trim();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

enum HomePluginArea {
  recommend,
  music,
  video,
  comic,
  novel,
  center,
}

extension HomePluginAreaX on HomePluginArea {
  String get label {
    switch (this) {
      case HomePluginArea.recommend:
        return '推荐';
      case HomePluginArea.music:
        return '音乐';
      case HomePluginArea.video:
        return '影视';
      case HomePluginArea.comic:
        return '漫画';
      case HomePluginArea.novel:
        return '小说';
      case HomePluginArea.center:
        return '插件中心';
    }
  }

  IconData get icon {
    switch (this) {
      case HomePluginArea.recommend:
        return Icons.local_fire_department_outlined;
      case HomePluginArea.music:
        return Icons.music_note_outlined;
      case HomePluginArea.video:
        return Icons.play_circle_outline;
      case HomePluginArea.comic:
        return Icons.image_outlined;
      case HomePluginArea.novel:
        return Icons.menu_book_outlined;
      case HomePluginArea.center:
        return Icons.extension_outlined;
    }
  }
}

enum HomePluginActionType {
  toast,
  openDailyNews,
  openNovelList,
  openVideoList,
}

extension HomePluginActionTypeX on HomePluginActionType {
  String get label {
    switch (this) {
      case HomePluginActionType.toast:
        return '弹出提示';
      case HomePluginActionType.openDailyNews:
        return '打开日报详情';
      case HomePluginActionType.openNovelList:
        return '打开小说列表';
      case HomePluginActionType.openVideoList:
        return '打开影视列表';
    }
  }
}

HomePluginArea _areaFromName(String name) {
  for (final value in HomePluginArea.values) {
    if (value.name == name) {
      return value;
    }
  }
  return HomePluginArea.recommend;
}

HomePluginActionType _actionFromName(String name) {
  for (final value in HomePluginActionType.values) {
    if (value.name == name) {
      return value;
    }
  }
  return HomePluginActionType.toast;
}

typedef HomePluginTap = Future<void> Function(BuildContext context);

class HomeCustomPluginConfig {
  final String id;
  final String title;
  final String subtitle;
  final int iconCodePoint;
  final String iconFontFamily;
  final String? iconFontPackage;
  final int colorValue;
  final HomePluginArea area;
  final HomePluginActionType actionType;
  final String payload;
  final bool enabled;
  final int sort;
  final int createdAt;

  const HomeCustomPluginConfig({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconCodePoint,
    this.iconFontFamily = 'MaterialIcons',
    this.iconFontPackage,
    required this.colorValue,
    required this.area,
    required this.actionType,
    this.payload = '',
    this.enabled = true,
    this.sort = 9999,
    required this.createdAt,
  });

  bool get isValid => id.trim().isNotEmpty && title.trim().isNotEmpty;

  IconData get iconData => IconData(
        iconCodePoint,
        fontFamily: iconFontFamily,
        fontPackage: iconFontPackage,
      );

  Color get color => Color(colorValue);

  HomeCustomPluginConfig copyWith({
    String? id,
    String? title,
    String? subtitle,
    int? iconCodePoint,
    String? iconFontFamily,
    String? iconFontPackage,
    int? colorValue,
    HomePluginArea? area,
    HomePluginActionType? actionType,
    String? payload,
    bool? enabled,
    int? sort,
    int? createdAt,
  }) {
    return HomeCustomPluginConfig(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      iconFontFamily: iconFontFamily ?? this.iconFontFamily,
      iconFontPackage: iconFontPackage ?? this.iconFontPackage,
      colorValue: colorValue ?? this.colorValue,
      area: area ?? this.area,
      actionType: actionType ?? this.actionType,
      payload: payload ?? this.payload,
      enabled: enabled ?? this.enabled,
      sort: sort ?? this.sort,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'iconCodePoint': iconCodePoint,
      'iconFontFamily': iconFontFamily,
      'iconFontPackage': iconFontPackage,
      'colorValue': colorValue,
      'area': area.name,
      'actionType': actionType.name,
      'payload': payload,
      'enabled': enabled,
      'sort': sort,
      'createdAt': createdAt,
    };
  }

  factory HomeCustomPluginConfig.fromJson(Map<String, dynamic> json) {
    return HomeCustomPluginConfig(
      id: _asString(json['id']),
      title: _asString(json['title']),
      subtitle: _asString(json['subtitle']),
      iconCodePoint: _asInt(json['iconCodePoint'], Icons.extension.codePoint),
      iconFontFamily: _asString(json['iconFontFamily'], 'MaterialIcons'),
      iconFontPackage:
          json['iconFontPackage'] == null ? null : _asString(json['iconFontPackage']),
      colorValue: _asInt(json['colorValue'], Colors.blue.value),
      area: _areaFromName(_asString(json['area'], HomePluginArea.recommend.name)),
      actionType: _actionFromName(
        _asString(json['actionType'], HomePluginActionType.toast.name),
      ),
      payload: _asString(json['payload']),
      enabled: _asBool(json['enabled'], true),
      sort: _asInt(json['sort'], 9999),
      createdAt: _asInt(
        json['createdAt'],
        DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class HomePluginSnapshot {
  final Map<String, bool> enabledMap;
  final List<HomeCustomPluginConfig> customPlugins;

  const HomePluginSnapshot({
    required this.enabledMap,
    required this.customPlugins,
  });

  const HomePluginSnapshot.empty()
      : enabledMap = const {},
        customPlugins = const [];

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'enabledMap': enabledMap,
      'customPlugins': customPlugins.map((e) => e.toJson()).toList(),
    };
  }

  factory HomePluginSnapshot.fromJson(Map<String, dynamic> json) {
    final enabledMap = <String, bool>{};
    final enabledRaw = json['enabledMap'];
    if (enabledRaw is Map) {
      enabledRaw.forEach((key, value) {
        enabledMap[key.toString()] = _asBool(value, true);
      });
    }

    final customPlugins = <HomeCustomPluginConfig>[];
    final customRaw = json['customPlugins'];
    if (customRaw is List) {
      for (final item in customRaw) {
        if (item is Map) {
          try {
            final config = HomeCustomPluginConfig.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (config.isValid) {
              customPlugins.add(config);
            }
          } catch (_) {}
        }
      }
    }

    return HomePluginSnapshot(
      enabledMap: enabledMap,
      customPlugins: customPlugins,
    );
  }
}

class HomePluginPersistence {
  HomePluginPersistence({CacheStore? cache})
      : _cache = cache ?? CacheStore(namespace: 'home_plugin_center');

  final CacheStore _cache;

  static const String _snapshotKey = 'plugin_snapshot_v1';

  Future<HomePluginSnapshot> readSnapshot() async {
    final raw = await _cache.read(_snapshotKey);

    try {
      if (raw is String) {
        if (raw.trim().isEmpty) {
          return const HomePluginSnapshot.empty();
        }
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return HomePluginSnapshot.fromJson(Map<String, dynamic>.from(decoded));
        }
      }

      if (raw is Map) {
        return HomePluginSnapshot.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (_) {
      return const HomePluginSnapshot.empty();
    }

    return const HomePluginSnapshot.empty();
  }

  Future<void> writeSnapshot(HomePluginSnapshot snapshot) async {
    await _cache.write(_snapshotKey, jsonEncode(snapshot.toJson()));
  }
}

class HomePlugin {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final HomePluginArea area;
  final HomePluginTap onTap;
  final bool builtIn;
  final bool enabled;
  final int sort;
  final HomeCustomPluginConfig? customConfig;

  const HomePlugin({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.area,
    required this.onTap,
    this.builtIn = false,
    this.enabled = true,
    this.sort = 1000,
    this.customConfig,
  });

  HomePlugin copyWith({
    String? id,
    String? title,
    String? subtitle,
    IconData? icon,
    Color? color,
    HomePluginArea? area,
    HomePluginTap? onTap,
    bool? builtIn,
    bool? enabled,
    int? sort,
    HomeCustomPluginConfig? customConfig,
  }) {
    return HomePlugin(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      area: area ?? this.area,
      onTap: onTap ?? this.onTap,
      builtIn: builtIn ?? this.builtIn,
      enabled: enabled ?? this.enabled,
      sort: sort ?? this.sort,
      customConfig: customConfig ?? this.customConfig,
    );
  }
}

class HomePluginHost {
  HomePluginHost._();

  static final HomePluginHost instance = HomePluginHost._();

  final ValueNotifier<List<HomePlugin>> _notifier =
      ValueNotifier<List<HomePlugin>>(<HomePlugin>[]);

  final HomePluginPersistence _persistence = HomePluginPersistence();

  Future<void>? _bootFuture;
  bool _bootstrapped = false;

  ValueListenable<List<HomePlugin>> get listenable => _notifier;

  List<HomePlugin> get allPlugins => _sorted(_notifier.value);

  Future<void> bootstrap() {
    if (_bootstrapped) return Future.value();
    if (_bootFuture != null) return _bootFuture!;
    _bootFuture = _bootstrapInternal();
    return _bootFuture!;
  }

  Future<void> _bootstrapInternal() async {
    try {
      _notifier.value = _sorted(_buildDefaultPlugins());
      final snapshot = await _persistence.readSnapshot();
      _applySnapshot(snapshot);
    } catch (_) {
      _notifier.value = _sorted(_buildDefaultPlugins());
    } finally {
      _bootstrapped = true;
      _bootFuture = null;
    }
  }

  List<HomePlugin> pluginsOf(
    HomePluginArea area, {
    bool onlyEnabled = true,
  }) {
    final list = _notifier.value.where((plugin) {
      if (plugin.area != area) return false;
      if (onlyEnabled && !plugin.enabled) return false;
      return true;
    }).toList();

    return _sorted(list);
  }

  Future<void> register(
    HomePlugin plugin, {
    bool replace = true,
  }) async {
    await bootstrap();

    final normalized = _normalizeForRegister(plugin);
    final list = List<HomePlugin>.from(_notifier.value);
    final index = list.indexWhere((item) => item.id == normalized.id);

    if (index >= 0) {
      if (replace) {
        list[index] = normalized;
      } else {
        return;
      }
    } else {
      list.add(normalized);
    }

    _notifier.value = _sorted(list);
    await _persist();
  }

  Future<void> addCustomPlugin(HomeCustomPluginConfig config) async {
    if (!config.isValid) return;
    await register(_pluginFromCustomConfig(config), replace: true);
  }

  Future<void> unregister(String id) async {
    await bootstrap();

    final list = List<HomePlugin>.from(_notifier.value);
    final index = list.indexWhere((item) => item.id == id);
    if (index < 0) return;
    if (list[index].builtIn) return;

    list.removeAt(index);
    _notifier.value = _sorted(list);
    await _persist();
  }

  Future<void> toggleEnabled(String id, bool enabled) async {
    await bootstrap();

    final list = List<HomePlugin>.from(_notifier.value);
    final index = list.indexWhere((item) => item.id == id);
    if (index < 0) return;

    final current = list[index];
    list[index] = current.copyWith(
      enabled: enabled,
      customConfig: current.customConfig?.copyWith(enabled: enabled),
    );

    _notifier.value = _sorted(list);
    await _persist();
  }

  Future<void> restoreDefaults() async {
    await bootstrap();
    _notifier.value = _sorted(_buildDefaultPlugins());
    await _persist();
  }

  Future<String> exportSnapshotJson({bool pretty = true}) async {
    await bootstrap();
    final snapshot = _buildCurrentSnapshot();
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(snapshot.toJson());
    }
    return jsonEncode(snapshot.toJson());
  }

  Future<void> importSnapshotJson(
    String jsonText, {
    bool merge = false,
  }) async {
    await bootstrap();

    final raw = jsonText.trim();
    if (raw.isEmpty) {
      throw const FormatException('JSON 内容为空');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const FormatException('JSON 格式错误');
    }

    if (decoded is! Map) {
      throw const FormatException('JSON 根节点必须是对象');
    }

    final incoming = HomePluginSnapshot.fromJson(
      Map<String, dynamic>.from(decoded),
    );

    final finalSnapshot = merge
        ? _mergeSnapshot(_buildCurrentSnapshot(), incoming)
        : incoming;

    _applySnapshot(finalSnapshot);
    await _persist();
  }

  HomePluginSnapshot _mergeSnapshot(
    HomePluginSnapshot base,
    HomePluginSnapshot incoming,
  ) {
    final enabled = <String, bool>{
      ...base.enabledMap,
      ...incoming.enabledMap,
    };

    final customMap = <String, HomeCustomPluginConfig>{
      for (final item in base.customPlugins) item.id: item,
    };

    for (final item in incoming.customPlugins) {
      if (!item.isValid) continue;
      customMap[item.id] = item;
    }

    return HomePluginSnapshot(
      enabledMap: enabled,
      customPlugins: customMap.values.toList(),
    );
  }

  HomePluginSnapshot _buildCurrentSnapshot() {
    final enabledMap = <String, bool>{};
    final customPlugins = <HomeCustomPluginConfig>[];

    for (final plugin in _notifier.value) {
      enabledMap[plugin.id] = plugin.enabled;
      if (!plugin.builtIn) {
        final config = (plugin.customConfig ?? _fallbackConfigFromPlugin(plugin))
            .copyWith(enabled: plugin.enabled);
        if (config.isValid) {
          customPlugins.add(config);
        }
      }
    }

    return HomePluginSnapshot(
      enabledMap: enabledMap,
      customPlugins: customPlugins,
    );
  }

  void _applySnapshot(HomePluginSnapshot snapshot) {
    final result = <HomePlugin>[];

    final defaults = _buildDefaultPlugins();
    for (final plugin in defaults) {
      final enabled = snapshot.enabledMap[plugin.id] ?? plugin.enabled;
      result.add(plugin.copyWith(enabled: enabled));
    }

    for (final config in snapshot.customPlugins) {
      if (!config.isValid) continue;
      final enabled = snapshot.enabledMap[config.id] ?? config.enabled;
      result.add(
        _pluginFromCustomConfig(
          config.copyWith(enabled: enabled),
        ),
      );
    }

    _notifier.value = _sorted(result);
  }

  HomePlugin _normalizeForRegister(HomePlugin plugin) {
    if (plugin.builtIn) return plugin;

    final config = plugin.customConfig ?? _fallbackConfigFromPlugin(plugin);
    return plugin.copyWith(
      enabled: config.enabled,
      customConfig: config,
    );
  }

  HomeCustomPluginConfig _fallbackConfigFromPlugin(HomePlugin plugin) {
    return HomeCustomPluginConfig(
      id: plugin.id,
      title: plugin.title,
      subtitle: plugin.subtitle,
      iconCodePoint: plugin.icon.codePoint,
      iconFontFamily: plugin.icon.fontFamily ?? 'MaterialIcons',
      iconFontPackage: plugin.icon.fontPackage,
      colorValue: plugin.color.value,
      area: plugin.area,
      actionType: HomePluginActionType.toast,
      payload: plugin.subtitle,
      enabled: plugin.enabled,
      sort: plugin.sort,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  HomePlugin _pluginFromCustomConfig(HomeCustomPluginConfig config) {
    return HomePlugin(
      id: config.id,
      title: config.title,
      subtitle: config.subtitle,
      icon: config.iconData,
      color: config.color,
      area: config.area,
      builtIn: false,
      enabled: config.enabled,
      sort: config.sort,
      customConfig: config,
      onTap: (context) async {
        switch (config.actionType) {
          case HomePluginActionType.toast:
            await _showSnack(
              context,
              config.payload.trim().isEmpty ? '点击了 ${config.title}' : config.payload.trim(),
            );
            return;
          case HomePluginActionType.openDailyNews:
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DailyNewsPage()),
            );
            return;
          case HomePluginActionType.openNovelList:
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => NovelListPageWithProvider()),
            );
            return;
          case HomePluginActionType.openVideoList:
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => VideoListPage()),
            );
            return;
        }
      },
    );
  }

  Future<void> _persist() async {
    try {
      await _persistence.writeSnapshot(_buildCurrentSnapshot());
    } catch (_) {}
  }

  List<HomePlugin> _sorted(Iterable<HomePlugin> input) {
    final list = List<HomePlugin>.from(input);
    list.sort((a, b) {
      final sortCompare = a.sort.compareTo(b.sort);
      if (sortCompare != 0) return sortCompare;
      return a.title.compareTo(b.title);
    });
    return list;
  }

  List<HomePlugin> _buildDefaultPlugins() {
    return <HomePlugin>[
      HomePlugin(
        id: 'builtin_daily_news',
        title: '日报详情',
        subtitle: '查看完整热闻列表',
        icon: Icons.newspaper_outlined,
        color: Colors.deepPurple,
        area: HomePluginArea.recommend,
        builtIn: true,
        sort: 10,
        onTap: (context) async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DailyNewsPage()),
          );
        },
      ),
      HomePlugin(
        id: 'builtin_music_rank',
        title: '音乐榜单',
        subtitle: '音乐插件入口示例',
        icon: Icons.queue_music_outlined,
        color: Colors.pinkAccent,
        area: HomePluginArea.music,
        builtIn: true,
        sort: 10,
        onTap: (context) async {
          await _showSnack(context, '音乐榜单插件开发中...');
        },
      ),
      HomePlugin(
        id: 'builtin_video_search',
        title: '公共影视搜索',
        subtitle: '合法免费片源检索',
        icon: Icons.video_collection_outlined,
        color: Colors.indigo,
        area: HomePluginArea.video,
        builtIn: true,
        sort: 10,
        onTap: (context) async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => VideoListPage()),
          );
        },
      ),
      HomePlugin(
        id: 'builtin_comic_rank',
        title: '漫画排行',
        subtitle: '漫画插件入口示例',
        icon: Icons.collections_bookmark_outlined,
        color: Colors.teal,
        area: HomePluginArea.comic,
        builtIn: true,
        sort: 10,
        onTap: (context) async {
          await _showSnack(context, '漫画排行插件开发中...');
        },
      ),
      HomePlugin(
        id: 'builtin_novel_search',
        title: '快速找书',
        subtitle: '进入小说列表页',
        icon: Icons.search,
        color: Colors.orange,
        area: HomePluginArea.novel,
        builtIn: true,
        sort: 8,
        onTap: (context) async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => NovelListPageWithProvider()),
          );
        },
      ),
      HomePlugin(
        id: 'builtin_plugin_help',
        title: '插件接入说明',
        subtitle: '查看注册方式与示例',
        icon: Icons.help_outline,
        color: Colors.blueGrey,
        area: HomePluginArea.center,
        builtIn: true,
        sort: 1,
        onTap: (context) async {
          await showDialog<void>(
            context: context,
            builder: (ctx) {
              return AlertDialog(
                title: const Text('插件接入说明'),
                content: const SelectableText(
                  '可在任意模块中调用：\n\n'
                  'HomePluginHost.instance.register(\n'
                  '  HomePlugin(\n'
                  "    id: 'my_plugin_id',\n"
                  "    title: '我的插件',\n"
                  "    subtitle: '一句描述',\n"
                  '    icon: Icons.extension,\n'
                  '    color: Colors.teal,\n'
                  '    area: HomePluginArea.recommend,\n'
                  '    onTap: (context) async { ... },\n'
                  '  ),\n'
                  ');\n',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('知道了'),
                  ),
                ],
              );
            },
          );
        },
      ),
    ];
  }
}

class HomePluginApi {
  HomePluginApi._();

  static Future<void> register(
    HomePlugin plugin, {
    bool replace = true,
  }) {
    return HomePluginHost.instance.register(plugin, replace: replace);
  }

  static Future<void> unregister(String id) {
    return HomePluginHost.instance.unregister(id);
  }

  static Future<void> toggleEnabled(String id, bool enabled) {
    return HomePluginHost.instance.toggleEnabled(id, enabled);
  }

  static Future<void> restoreDefaults() {
    return HomePluginHost.instance.restoreDefaults();
  }

  static Future<String> exportSnapshotJson({bool pretty = true}) {
    return HomePluginHost.instance.exportSnapshotJson(pretty: pretty);
  }

  static Future<void> importSnapshotJson(
    String jsonText, {
    bool merge = false,
  }) {
    return HomePluginHost.instance.importSnapshotJson(
      jsonText,
      merge: merge,
    );
  }
}

Future<void> _showSnack(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text)),
  );
}