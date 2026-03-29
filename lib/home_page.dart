import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'daily_news_page.dart';
import 'globals.dart';
import 'novel/core/bookshelf_manager.dart';
import 'novel/core/cache_store.dart';
import 'novel/pages/novel_detail_page.dart';
import 'novel_module.dart' hide NovelTabArea;
import 'plugin_market_page.dart';
import 'video_module.dart';
import 'package:flutter/foundation.dart'; // 添加这一行来提供 ValueListenable
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

/// ===============================
/// 插件系统模型
/// ===============================

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
        return '打开视频列表';
    }
  }
}

HomePluginArea _areaFromName(String name) {
  for (final v in HomePluginArea.values) {
    if (v.name == name) return v;
  }
  return HomePluginArea.recommend;
}

HomePluginActionType _actionFromName(String name) {
  for (final v in HomePluginActionType.values) {
    if (v.name == name) return v;
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
      createdAt: _asInt(json['createdAt'], DateTime.now().millisecondsSinceEpoch),
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
            final cfg = HomeCustomPluginConfig.fromJson(Map<String, dynamic>.from(item));
            if (cfg.isValid) customPlugins.add(cfg);
          } catch (_) {
            // 忽略单条解析错误
          }
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
  static const _snapshotKey = 'plugin_snapshot_v1';

  Future<HomePluginSnapshot> readSnapshot() async {
    final raw = await _cache.read(_snapshotKey);

    try {
      if (raw is String) {
        if (raw.trim().isEmpty) return const HomePluginSnapshot.empty();
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return HomePluginSnapshot.fromJson(Map<String, dynamic>.from(decoded));
        }
        return const HomePluginSnapshot.empty();
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
    final text = jsonEncode(snapshot.toJson());
    await _cache.write(_snapshotKey, text);
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

/// ===============================
/// 插件中心（单例）
/// 支持：默认插件 + 持久化 + 导入导出 JSON
/// ===============================

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
    final list = _notifier.value.where((p) {
      if (p.area != area) return false;
      if (onlyEnabled && !p.enabled) return false;
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
    final index = list.indexWhere((e) => e.id == normalized.id);

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
    final index = list.indexWhere((e) => e.id == id);
    if (index < 0) return;
    if (list[index].builtIn) return; // 内置插件不可删除

    list.removeAt(index);
    _notifier.value = _sorted(list);
    await _persist();
  }

  Future<void> toggleEnabled(String id, bool enabled) async {
    await bootstrap();

    final list = List<HomePlugin>.from(_notifier.value);
    final index = list.indexWhere((e) => e.id == id);
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

  /// 导出当前插件快照为 JSON 文本
  Future<String> exportSnapshotJson({bool pretty = true}) async {
    await bootstrap();
    final snapshot = _buildCurrentSnapshot();
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(snapshot.toJson());
    }
    return jsonEncode(snapshot.toJson());
  }

  /// 从 JSON 文本导入插件快照
  /// merge=false：覆盖当前快照
  /// merge=true：合并导入（导入项覆盖同 ID 项）
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

    final incoming = HomePluginSnapshot.fromJson(Map<String, dynamic>.from(decoded));

    final finalSnapshot = merge ? _mergeSnapshot(_buildCurrentSnapshot(), incoming) : incoming;

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

    final map = <String, HomeCustomPluginConfig>{
      for (final c in base.customPlugins) c.id: c,
    };

    for (final c in incoming.customPlugins) {
      if (!c.isValid) continue;
      map[c.id] = c;
    }

    return HomePluginSnapshot(
      enabledMap: enabled,
      customPlugins: map.values.toList(),
    );
  }

  HomePluginSnapshot _buildCurrentSnapshot() {
    final enabled = <String, bool>{};
    final custom = <HomeCustomPluginConfig>[];

    for (final p in _notifier.value) {
      enabled[p.id] = p.enabled;
      if (!p.builtIn) {
        final cfg = (p.customConfig ?? _fallbackConfigFromPlugin(p)).copyWith(enabled: p.enabled);
        if (cfg.isValid) custom.add(cfg);
      }
    }

    return HomePluginSnapshot(enabledMap: enabled, customPlugins: custom);
  }

  void _applySnapshot(HomePluginSnapshot snapshot) {
    final result = <HomePlugin>[];

    // 1) 默认插件
    final defaults = _buildDefaultPlugins();
    for (final p in defaults) {
      final enabled = snapshot.enabledMap[p.id] ?? p.enabled;
      result.add(p.copyWith(enabled: enabled));
    }

    // 2) 自定义插件
    for (final config in snapshot.customPlugins) {
      if (!config.isValid) continue;
      final enabled = snapshot.enabledMap[config.id] ?? config.enabled;
      final plugin = _pluginFromCustomConfig(config.copyWith(enabled: enabled));
      result.add(plugin);
    }

    _notifier.value = _sorted(result);
  }

  HomePlugin _normalizeForRegister(HomePlugin plugin) {
    if (plugin.builtIn) return plugin;

    final cfg = plugin.customConfig ?? _fallbackConfigFromPlugin(plugin);
    return plugin.copyWith(
      enabled: cfg.enabled,
      customConfig: cfg,
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
              MaterialPageRoute(builder: (_) => NovelListPage()),
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
    } catch (_) {
      // 忽略持久化异常，避免影响主流程
    }
  }

  List<HomePlugin> _sorted(Iterable<HomePlugin> input) {
    final list = List<HomePlugin>.from(input);
    list.sort((a, b) {
      final c = a.sort.compareTo(b.sort);
      if (c != 0) return c;
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
            MaterialPageRoute(builder: (_) => NovelListPage()),
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
            builder: (ctx) => AlertDialog(
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
            ),
          );
        },
      ),
    ];
  }
}

/// 可选对外 API
class HomePluginApi {
  HomePluginApi._();

  static Future<void> register(HomePlugin plugin, {bool replace = true}) {
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
    return HomePluginHost.instance.importSnapshotJson(jsonText, merge: merge);
  }
}

/// ===============================
/// 首页
/// ===============================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  final HomePluginHost _pluginHost = HomePluginHost.instance;

  @override
  bool get wantKeepAlive => true;

  String _todayDateStr = "";
  bool _isLoadingNews = true;
  List<String> _newsList = [];

  @override
  void initState() {
    super.initState();
    _pluginHost.bootstrap(); // 恢复插件快照
    _initDate();
    _fetchDailyNews();
  }

  void _initDate() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    _todayDateStr = "$month月$day日";
  }

  Future<void> _fetchDailyNews() async {
    setState(() => _isLoadingNews = true);

    try {
      await Future.delayed(const Duration(milliseconds: 1200));
      final random = Random().nextInt(100);
      _newsList = [
        "漂白鸡爪掀行业震荡 多品牌回应",
        "商务部回应美方对华发起301调查",
        "又被曝！曼玲粥铺被扒“糊弄式”堂食",
        "编号：$random 备用内容",
      ];
    } catch (_) {
      _newsList = ["网络加载失败，请稍后重试"];
    } finally {
      if (mounted) {
        setState(() => _isLoadingNews = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      body: DefaultTabController(
        length: 6,
        child: SafeArea(
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return <Widget>[
                SliverToBoxAdapter(child: _buildTopHeader()),
                SliverToBoxAdapter(child: _buildDailyNewsCard()),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverAppBarDelegate(_buildTabBar()),
                ),
              ];
            },
            body: TabBarView(
              children: [
                _buildRecommendGrid(),
                _buildMusicGrid(),
                _buildVideoTab(),
                _buildComicGrid(),
                NovelTabArea(pluginHost: _pluginHost),
                PluginCenterTab(pluginHost: _pluginHost),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TabBar _buildTabBar() {
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: Colors.blue[700],
      indicatorSize: TabBarIndicatorSize.label,
      indicatorWeight: 3.0,
      labelColor: Colors.blue[700],
      unselectedLabelColor: Colors.black54,
      dividerColor: Colors.grey[300],
      tabs: const [
        Tab(
          child: Row(
            children: [
              Icon(Icons.local_fire_department_outlined, size: 20),
              SizedBox(width: 4),
              Text(
                "推荐",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Tab(
          child: Row(
            children: [
              Icon(Icons.music_note_outlined, size: 20),
              SizedBox(width: 4),
              Text("音乐", style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
        Tab(
          child: Row(
            children: [
              Icon(Icons.play_circle_outline, size: 20),
              SizedBox(width: 4),
              Text("影视", style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
        Tab(
          child: Row(
            children: [
              Icon(Icons.image_outlined, size: 20),
              SizedBox(width: 4),
              Text("漫画", style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
        Tab(
          child: Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 20),
              SizedBox(width: 4),
              Text("小说", style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
        Tab(
          child: Row(
            children: [
              Icon(Icons.extension_outlined, size: 20),
              SizedBox(width: 4),
              Text("插件", style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => appScaffoldKey.currentState?.openDrawer(),
            child: const Icon(Icons.menu, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Geek工具箱',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  '计划赶不上变化😭',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 24),
            onPressed: _fetchDailyNews,
            tooltip: '刷新日报',
          ),
        ],
      ),
    );
  }

  Widget _buildDailyNewsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF2C3228),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '视界日报',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Daily News - $_todayDateStr',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (_isLoadingNews)
                  const Padding(
                    padding: EdgeInsets.only(top: 20.0),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white70,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  )
                else
                  ..._newsList.take(3).map(
                        (newsText) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.radio_button_checked,
                                color: Colors.white70,
                                size: 14,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Tooltip(
                                  message: newsText,
                                  child: Text(
                                    newsText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ],
            ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '刷新',
                  icon: const Icon(
                    Icons.refresh,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: _fetchDailyNews,
                ),
                IconButton(
                  tooltip: '查看详情',
                  icon: const Icon(
                    Icons.remove_red_eye_outlined,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DailyNewsPage()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendGrid() {
    final items = <_GridCardItem>[
      _GridCardItem(
        id: 'recommend_sniff',
        title: '资源嗅探',
        sub: '嗅探网页中的\n音视图片等资源',
        icon: Icons.travel_explore_outlined,
        color: Colors.amber,
        onTap: (ctx) => _showSnack(ctx, '资源嗅探开发中...'),
      ),
      _GridCardItem(
        id: 'recommend_apps',
        title: '应用中心',
        sub: '海量实用软件\n游戏下载工具集',
        icon: Icons.apps_outlined,
        color: Colors.blue,
        onTap: (ctx) => _showSnack(ctx, '应用中心开发中...'),
      ),
      _GridCardItem(
        id: 'recommend_game',
        title: '怀旧游戏',
        sub: '街机、FC等\n童年怀旧游戏',
        icon: Icons.sports_esports_outlined,
        color: Colors.blue.shade700,
        onTap: (ctx) => _showSnack(ctx, '怀旧游戏开发中...'),
      ),
      _GridCardItem(
        id: 'recommend_video_parse',
        title: '短视频解析',
        sub: '短视频工具\n（需合法使用）',
        icon: Icons.downloading_outlined,
        color: Colors.lightGreen,
        onTap: (ctx) => _showSnack(ctx, '短视频解析开发中...'),
      ),
    ];

    return _buildTabGridWithPlugins(
      area: HomePluginArea.recommend,
      baseItems: items,
      emptyTip: '推荐功能开发中...',
    );
  }

  Widget _buildMusicGrid() {
    final items = <_GridCardItem>[
      _GridCardItem(
        id: 'music_search',
        title: '音乐搜索',
        sub: '搜索公开音乐资源',
        icon: Icons.search,
        color: Colors.purple,
        onTap: (ctx) => _showSnack(ctx, '音乐搜索开发中...'),
      ),
      _GridCardItem(
        id: 'music_playlist',
        title: '歌单管理',
        sub: '收藏、创建、导入歌单',
        icon: Icons.playlist_play,
        color: Colors.pink,
        onTap: (ctx) => _showSnack(ctx, '歌单管理开发中...'),
      ),
    ];

    return _buildTabGridWithPlugins(
      area: HomePluginArea.music,
      baseItems: items,
      emptyTip: '音乐功能区开发中...',
    );
  }

  Widget _buildComicGrid() {
    final items = <_GridCardItem>[
      _GridCardItem(
        id: 'comic_rank',
        title: '漫画排行',
        sub: '热门漫画榜单',
        icon: Icons.emoji_emotions_outlined,
        color: Colors.teal,
        onTap: (ctx) => _showSnack(ctx, '漫画排行开发中...'),
      ),
      _GridCardItem(
        id: 'comic_search',
        title: '漫画搜索',
        sub: '按关键词检索漫画',
        icon: Icons.manage_search_outlined,
        color: Colors.green,
        onTap: (ctx) => _showSnack(ctx, '漫画搜索开发中...'),
      ),
    ];

    return _buildTabGridWithPlugins(
      area: HomePluginArea.comic,
      baseItems: items,
      emptyTip: '漫画功能区开发中...',
    );
  }

  Widget _buildVideoTab() {
    return ValueListenableBuilder<List<HomePlugin>>(
      valueListenable: _pluginHost.listenable,
      builder: (context, _, __) {
        final videoPlugins = _pluginHost.pluginsOf(HomePluginArea.video);

        if (videoPlugins.isEmpty) {
          return VideoTabArea();
        }

        return Column(
          children: [
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                itemCount: videoPlugins.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final plugin = videoPlugins[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      try {
                        await plugin.onTap(context);
                      } catch (e) {
                        await _showSnack(context, '插件执行失败: $e');
                      }
                    },
                    child: Container(
                      width: 170,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: plugin.color.withOpacity(0.15),
                            child: Icon(plugin.icon, color: plugin.color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  plugin.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  plugin.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(child: VideoTabArea()),
          ],
        );
      },
    );
  }

  Widget _buildTabGridWithPlugins({
    required HomePluginArea area,
    required List<_GridCardItem> baseItems,
    required String emptyTip,
  }) {
    return ValueListenableBuilder<List<HomePlugin>>(
      valueListenable: _pluginHost.listenable,
      builder: (context, _, __) {
        final pluginItems = _pluginHost.pluginsOf(area).map(_GridCardItem.fromPlugin).toList();

        final merged = <String, _GridCardItem>{};
        for (final item in baseItems) {
          merged[item.id] = item;
        }
        for (final item in pluginItems) {
          merged[item.id] = item;
        }

        final all = merged.values.toList();

        if (all.isEmpty) {
          return Center(
            child: Text(
              emptyTip,
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }

        return _buildGridView(all);
      },
    );
  }

  Widget _buildGridView(List<_GridCardItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12.0,
        mainAxisSpacing: 12.0,
        childAspectRatio: 2.1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16.0),
          onTap: () async {
            if (item.onTap != null) {
              await item.onTap!(context);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEDEEF0),
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 12,
                  top: 12,
                  right: 52,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.sub,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(item.icon, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ===============================
/// 插件中心 Tab（新增/删除/开关/恢复 + 导入导出 JSON + 插件市场）
/// ===============================

class PluginCenterTab extends StatefulWidget {
  const PluginCenterTab({
    super.key,
    required this.pluginHost,
  });

  final HomePluginHost pluginHost;

  @override
  State<PluginCenterTab> createState() => _PluginCenterTabState();
}

class _PluginCenterTabState extends State<PluginCenterTab> {
  static const String _marketRemoteUrl = String.fromEnvironment(
    'PLUGIN_MARKET_URL',
    defaultValue: '',
  );

  static const String _marketChannelEnv = String.fromEnvironment(
    'PLUGIN_MARKET_CHANNEL',
    defaultValue: 'stable',
  );

  static const String _marketSignModeEnv = String.fromEnvironment(
    'PLUGIN_MARKET_SIGN_MODE',
    defaultValue: 'none',
  );

  static const String _marketSignSecret = String.fromEnvironment(
    'PLUGIN_MARKET_SIGN_SECRET',
    defaultValue: '',
  );

  static const bool _marketAllowUnsigned = bool.fromEnvironment(
    'PLUGIN_MARKET_ALLOW_UNSIGNED',
    defaultValue: false,
  );

  HomePluginArea _areaFromCode(String code) {
    switch (code.trim()) {
      case 'music':
        return HomePluginArea.music;
      case 'video':
        return HomePluginArea.video;
      case 'comic':
        return HomePluginArea.comic;
      case 'novel':
        return HomePluginArea.novel;
      case 'recommend':
      default:
        return HomePluginArea.recommend;
    }
  }

  HomePluginActionType _actionFromCode(String code) {
    switch (code.trim()) {
      case 'openDailyNews':
        return HomePluginActionType.openDailyNews;
      case 'openNovelList':
        return HomePluginActionType.openNovelList;
      case 'openVideoList':
        return HomePluginActionType.openVideoList;
      case 'toast':
      default:
        return HomePluginActionType.toast;
    }
  }

  PluginMarketChannel _marketChannelFromEnv() {
    switch (_marketChannelEnv.trim().toLowerCase()) {
      case 'beta':
        return PluginMarketChannel.beta;
      case 'stable':
      default:
        return PluginMarketChannel.stable;
    }
  }

  PluginMarketSignMode _marketSignModeFromEnv() {
    switch (_marketSignModeEnv.trim().toLowerCase()) {
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

  Future<void> _openPluginMarket() async {
    final installedIds = widget.pluginHost.allPlugins
        .where((p) => !p.builtIn)
        .map((e) => e.id)
        .toSet();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PluginMarketPage(
          initialInstalledIds: installedIds,
          remoteConfigUrl: _marketRemoteUrl.trim().isEmpty ? null : _marketRemoteUrl.trim(),
          initialChannel: _marketChannelFromEnv(),
          securityConfig: PluginMarketSecurityConfig(
            mode: _marketSignModeFromEnv(),
            secret: _marketSignSecret,
            allowUnsigned: _marketAllowUnsigned,
          ),
          onInstall: (tpl) async {
            final config = HomeCustomPluginConfig(
              id: tpl.id,
              title: tpl.title,
              subtitle: tpl.subtitle,
              iconCodePoint: tpl.icon.codePoint,
              iconFontFamily: tpl.icon.fontFamily ?? 'MaterialIcons',
              iconFontPackage: tpl.icon.fontPackage,
              colorValue: tpl.color.value,
              area: _areaFromCode(tpl.areaCode),
              actionType: _actionFromCode(tpl.actionCode),
              payload: tpl.payload,
              enabled: true,
              sort: tpl.sort,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            );
            await widget.pluginHost.addCustomPlugin(config);
          },
          onUninstall: (pluginId) async {
            await widget.pluginHost.unregister(pluginId);
          },
        ),
      ),
    );
  }

  Future<void> _showAddPluginDialog() async {
    final titleController = TextEditingController();
    final subController = TextEditingController();
    final payloadController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    HomePluginArea selectedArea = HomePluginArea.recommend;
    HomePluginActionType selectedAction = HomePluginActionType.toast;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final payloadHint = selectedAction == HomePluginActionType.toast
                ? '弹窗内容（为空则默认）'
                : '可选参数（当前动作可忽略）';

            return AlertDialog(
              title: const Text('新增自定义插件'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: titleController,
                          decoration: const InputDecoration(
                            labelText: '插件名称',
                            hintText: '例如：我的导航',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return '请输入插件名称';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: subController,
                          decoration: const InputDecoration(
                            labelText: '插件描述',
                            hintText: '一句简短描述',
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<HomePluginArea>(
                          value: selectedArea,
                          decoration: const InputDecoration(labelText: '挂载区域'),
                          items: HomePluginArea.values
                              .where((e) => e != HomePluginArea.center)
                              .map(
                                (area) => DropdownMenuItem<HomePluginArea>(
                                  value: area,
                                  child: Text(area.label),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() => selectedArea = v);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<HomePluginActionType>(
                          value: selectedAction,
                          decoration: const InputDecoration(labelText: '点击动作'),
                          items: HomePluginActionType.values
                              .map(
                                (action) => DropdownMenuItem<HomePluginActionType>(
                                  value: action,
                                  child: Text(action.label),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() => selectedAction = v);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: payloadController,
                          decoration: InputDecoration(
                            labelText: '动作参数',
                            hintText: payloadHint,
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;

                    final title = titleController.text.trim();
                    final sub = subController.text.trim();
                    final payload = payloadController.text.trim();
                    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';

                    final icon = _iconForArea(selectedArea);
                    final color = _colorForArea(selectedArea);

                    final config = HomeCustomPluginConfig(
                      id: id,
                      title: title,
                      subtitle: sub.isEmpty ? '自定义插件' : sub,
                      iconCodePoint: icon.codePoint,
                      iconFontFamily: icon.fontFamily ?? 'MaterialIcons',
                      iconFontPackage: icon.fontPackage,
                      colorValue: color.value,
                      area: selectedArea,
                      actionType: selectedAction,
                      payload: payload,
                      enabled: true,
                      sort: 9999,
                      createdAt: DateTime.now().millisecondsSinceEpoch,
                    );

                    await widget.pluginHost.addCustomPlugin(config);

                    if (!mounted) return;
                    Navigator.pop(dialogCtx);
                  },
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    subController.dispose();
    payloadController.dispose();
  }

  Future<void> _showExportJsonDialog() async {
    final jsonText = await widget.pluginHost.exportSnapshotJson(pretty: true);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('导出插件 JSON'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '可复制保存，或用于导入到其它设备。',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 320,
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      jsonText,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('关闭'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: jsonText));
                if (!mounted) return;
                await _showSnack(context, '已复制到剪贴板');
              },
              icon: const Icon(Icons.copy),
              label: const Text('复制'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showImportJsonDialog() async {
    final controller = TextEditingController();
    bool merge = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('导入插件 JSON'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '粘贴之前导出的 JSON 配置：',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              final data = await Clipboard.getData('text/plain');
                              final text = data?.text ?? '';
                              if (text.trim().isEmpty) {
                                if (!mounted) return;
                                await _showSnack(context, '剪贴板为空');
                                return;
                              }
                              controller.text = text;
                              controller.selection = TextSelection.fromPosition(
                                TextPosition(offset: controller.text.length),
                              );
                            },
                            icon: const Icon(Icons.content_paste),
                            label: const Text('从剪贴板粘贴'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: controller,
                        minLines: 8,
                        maxLines: 14,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '{"enabledMap": {...}, "customPlugins": [...]}',
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: merge,
                        title: const Text('合并导入（关闭则覆盖当前配置）'),
                        onChanged: (v) {
                          setDialogState(() => merge = v);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final raw = controller.text.trim();
                    if (raw.isEmpty) {
                      await _showSnack(context, '请输入 JSON');
                      return;
                    }

                    try {
                      await widget.pluginHost.importSnapshotJson(raw, merge: merge);
                      if (!mounted) return;
                      Navigator.pop(dialogCtx);
                      await _showSnack(
                        context,
                        merge ? '导入成功（已合并）' : '导入成功（已覆盖）',
                      );
                    } catch (e) {
                      await _showSnack(context, '导入失败：$e');
                    }
                  },
                  child: const Text('开始导入'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Color _colorForArea(HomePluginArea area) {
    switch (area) {
      case HomePluginArea.recommend:
        return Colors.deepPurple;
      case HomePluginArea.music:
        return Colors.pink;
      case HomePluginArea.video:
        return Colors.indigo;
      case HomePluginArea.comic:
        return Colors.teal;
      case HomePluginArea.novel:
        return Colors.orange;
      case HomePluginArea.center:
        return Colors.blueGrey;
    }
  }

  IconData _iconForArea(HomePluginArea area) {
    switch (area) {
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

  Widget _buildPluginSection(
    BuildContext context,
    HomePluginArea area,
    List<HomePlugin> plugins,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(area.icon, size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(
                  area.label,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${plugins.length} 个',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (plugins.isEmpty)
              Text('暂无插件', style: TextStyle(color: Colors.grey[600], fontSize: 12))
            else
              Column(
                children: plugins.map((plugin) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      onTap: () async {
                        try {
                          await plugin.onTap(context);
                        } catch (e) {
                          await _showSnack(context, '插件执行失败: $e');
                        }
                      },
                      leading: CircleAvatar(
                        backgroundColor: plugin.color.withOpacity(0.15),
                        child: Icon(plugin.icon, color: plugin.color, size: 18),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              plugin.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (plugin.builtIn)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text('内置', style: TextStyle(fontSize: 10)),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        plugin.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: SizedBox(
                        width: plugin.builtIn ? 62 : 102,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: plugin.enabled,
                              onChanged: (value) async {
                                await widget.pluginHost.toggleEnabled(plugin.id, value);
                              },
                            ),
                            if (!plugin.builtIn)
                              IconButton(
                                tooltip: '删除',
                                onPressed: () async {
                                  await widget.pluginHost.unregister(plugin.id);
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<HomePlugin>>(
      valueListenable: widget.pluginHost.listenable,
      builder: (context, plugins, _) {
        final grouped = <HomePluginArea, List<HomePlugin>>{
          for (final area in HomePluginArea.values) area: <HomePlugin>[],
        };

        for (final plugin in plugins) {
          grouped[plugin.area]!.add(plugin);
        }

        for (final area in grouped.keys) {
          grouped[area]!.sort((a, b) {
            final c = a.sort.compareTo(b.sort);
            if (c != 0) return c;
            return a.title.compareTo(b.title);
          });
        }

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '插件中心',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '支持运行时注册、持久化，以及 JSON 导入导出。',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: _showAddPluginDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('新增自定义插件'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openPluginMarket,
                          icon: const Icon(Icons.storefront_outlined),
                          label: const Text('插件市场'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _showExportJsonDialog,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('导出 JSON'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _showImportJsonDialog,
                          icon: const Icon(Icons.download_for_offline_outlined),
                          label: const Text('导入 JSON'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await widget.pluginHost.restoreDefaults();
                            if (!mounted) return;
                            await _showSnack(context, '已恢复默认插件');
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('恢复默认'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (final area in HomePluginArea.values) _buildPluginSection(context, area, grouped[area]!),
          ],
        );
      },
    );
  }
}

/// ===============================
/// 小说 Tab（书架 + 书源 + 小说插件）
/// ===============================

class NovelTabArea extends StatefulWidget {
  const NovelTabArea({
    super.key,
    required this.pluginHost,
  });

  final HomePluginHost pluginHost;

  @override
  State<NovelTabArea> createState() => _NovelTabAreaState();
}

class _NovelTabAreaState extends State<NovelTabArea> {
  List<_BookshelfUiBook> _savedBooks = [];
  bool _isLoadingBooks = true;

  bool _isBookshelfExpanded = true;
  bool _isSourcesExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadBookshelf();
  }

  Future<void> _loadBookshelf() async {
    setState(() => _isLoadingBooks = true);

    try {
      final books = await BookshelfManager.getBookshelf();
      final list = <_BookshelfUiBook>[];

      for (final b in books) {
        final bookId = _asString(b.id);
        final progress = await NovelModule.repository.getProgress(bookId);

        list.add(
          _BookshelfUiBook(
            bookId: bookId,
            title: _asString(b.title, '未知书名'),
            cover: _asString(b.coverUrl),
            chapter: _asString(progress?.chapterTitle, '未读此书'),
            rawBook: b,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _savedBooks = list;
          _isLoadingBooks = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingBooks = false);
      }
    }
  }

  Widget _buildSectionHeader({
    required String title,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            AnimatedRotation(
              turns: isExpanded ? 0.25 : 0.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBookshelfSection(),
          _buildNovelSourcesSection(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildBookshelfSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: '我的书架',
          isExpanded: _isBookshelfExpanded,
          onTap: () => setState(() => _isBookshelfExpanded = !_isBookshelfExpanded),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _isBookshelfExpanded
              ? (_isLoadingBooks
                  ? const SizedBox(
                      height: 160,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : (_savedBooks.isEmpty ? _buildEmptyBookshelf() : _buildBookshelfList()))
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  Widget _buildEmptyBookshelf() {
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories_outlined, size: 36, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              '书架空空如也，快去寻宝吧',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookshelfList() {
    return SizedBox(
      height: 170,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _savedBooks.length,
        itemBuilder: (context, index) {
          final book = _savedBooks[index];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NovelDetailPage(entryBook: book.rawBook),
                ),
              ).then((_) => _loadBookshelf());
            },
            child: SizedBox(
              width: 100,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: Colors.grey[300],
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 4,
                              offset: const Offset(2, 2),
                            ),
                          ],
                        ),
                        child: _buildBookCover(book.cover),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      book.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      book.chapter,
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBookCover(String url) {
    if (url.trim().isEmpty) {
      return Container(
        color: const Color(0xFFE6E8EC),
        child: Center(
          child: Icon(Icons.book_outlined, color: Colors.grey[500]),
        ),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return Container(
          color: const Color(0xFFE6E8EC),
          child: Center(
            child: Icon(Icons.book_outlined, color: Colors.grey[500]),
          ),
        );
      },
    );
  }

  Widget _buildNovelSourcesSection() {
    final baseItems = <_GridCardItem>[
      _GridCardItem(
        id: 'novel_qimao',
        title: '猫眼看书',
        sub: '猫眼看书🐱\n免费小说平台',
        icon: Icons.pets,
        color: Colors.orange,
        onTap: (ctx) async {
          await Navigator.push(
            ctx,
            MaterialPageRoute(builder: (_) => NovelListPage()),
          );
          if (mounted) _loadBookshelf();
        },
      ),
      _GridCardItem(
        id: 'novel_wait_1',
        title: '等待添加',
        sub: '多种分类\n免费小说平台',
        icon: Icons.auto_stories,
        color: Colors.blueGrey,
        onTap: (ctx) => _showSnack(ctx, '开发中...'),
      ),
      _GridCardItem(
        id: 'novel_wait_2',
        title: '等待添加',
        sub: '多种分类\n免费小说平台',
        icon: Icons.menu_book,
        color: Colors.teal,
        onTap: (ctx) => _showSnack(ctx, '开发中...'),
      ),
      _GridCardItem(
        id: 'novel_wait_3',
        title: '等待添加',
        sub: '全本完结\nTXT小说下载',
        icon: Icons.file_download,
        color: Colors.deepPurple,
        onTap: (ctx) => _showSnack(ctx, '开发中...'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: '精选书源',
          isExpanded: _isSourcesExpanded,
          onTap: () => setState(() => _isSourcesExpanded = !_isSourcesExpanded),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _isSourcesExpanded
              ? ValueListenableBuilder<List<HomePlugin>>(
                  valueListenable: widget.pluginHost.listenable,
                  builder: (context, _, __) {
                    final pluginItems = widget.pluginHost
                        .pluginsOf(HomePluginArea.novel)
                        .map(_GridCardItem.fromPlugin)
                        .toList();

                    final merged = <String, _GridCardItem>{};
                    for (final item in baseItems) {
                      merged[item.id] = item;
                    }
                    for (final item in pluginItems) {
                      merged[item.id] = item;
                    }

                    return _buildSourceGrid(merged.values.toList());
                  },
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  Widget _buildSourceGrid(List<_GridCardItem> items) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text('暂无书源', style: TextStyle(color: Colors.grey[600])),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12.0,
        mainAxisSpacing: 12.0,
        childAspectRatio: 2.1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16.0),
          onTap: () async {
            if (item.onTap != null) {
              await item.onTap!(context);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEDEEF0),
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 12,
                  top: 12,
                  right: 52,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.sub,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(item.icon, color: Colors.white, size: 20),
                    ),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ===============================
/// 通用模型 & 工具
/// ===============================

class _GridCardItem {
  final String id;
  final String title;
  final String sub;
  final IconData icon;
  final Color color;
  final HomePluginTap? onTap;

  const _GridCardItem({
    required this.id,
    required this.title,
    required this.sub,
    required this.icon,
    required this.color,
    this.onTap,
  });

  factory _GridCardItem.fromPlugin(HomePlugin plugin) {
    return _GridCardItem(
      id: plugin.id,
      title: plugin.title,
      sub: plugin.subtitle,
      icon: plugin.icon,
      color: plugin.color,
      onTap: plugin.onTap,
    );
  }
}

class _BookshelfUiBook {
  final String bookId;
  final String title;
  final String cover;
  final String chapter;
  final dynamic rawBook;

  const _BookshelfUiBook({
    required this.bookId,
    required this.title,
    required this.cover,
    required this.chapter,
    required this.rawBook,
  });
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;

  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: const Color(0xFFF7F8FA),
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}

Future<void> _showSnack(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text)),
  );
}