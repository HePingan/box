// ignore_for_file: non_const_argument_for_const_parameter

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/extensions/core/builtin_plugin_catalog.dart';
import 'package:box/features/extensions/core/builtin_plugin_pages.dart';
import 'package:box/features/extensions/market/domain/plugin_market_manifest.dart';

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
  center;

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
        return '工具';
    }
  }

  /// 顺序即 UI 下拉/标签的展示顺序（供投稿页等复用，避免再抄一份）。
  static const List<HomePluginArea> displayOrder = [
    HomePluginArea.recommend,
    HomePluginArea.novel,
    HomePluginArea.video,
    HomePluginArea.music,
    HomePluginArea.comic,
  ];
}

/// 未知 area code 的统一回退值 —— 标签路径与落库路径**必须一致**。
///
/// 此前两份实现各回各的：`homePluginAreaFromCode` 回 center（标签说「工具」），
/// 而 `_areaFromName` 回 recommend（落库进「推荐」）。同一个 `center` 输入，
/// 标签和落库是两个区域。
const HomePluginArea kHomePluginAreaFallback = HomePluginArea.center;

/// 市场投稿**显式排除**的区域。
///
/// 排除 center（工具区）是刻意的产品决策：工具区只放 App 自带工具，不开放投稿。
/// 写成「枚举全集 - 排除集」而不是硬编码白名单 —— 硬编码那份（市场侧
/// `_allowedAreaCodes`）在给 `HomePluginArea` 加新枚举值时不会自动生效，
/// 新区域会被悄悄归一化掉，而单一事实源测试（只校验 label 与 displayOrder）
/// 不会失败。这正是该测试想防的那类漂移。
const Set<HomePluginArea> kMarketExcludedAreas = {HomePluginArea.center};

/// 市场投稿允许的区域 = 枚举全集 - 排除集（新增枚举值自动生效）。
Set<HomePluginArea> get marketAllowedAreas =>
    HomePluginArea.values.toSet().difference(kMarketExcludedAreas);

/// 由 code 解析区域；未知 code 记日志并回落到 [kHomePluginAreaFallback]。
HomePluginArea homePluginAreaFromCode(String code) {
  final text = code.trim();
  for (final area in HomePluginArea.values) {
    if (area.name == text) return area;
  }
  debugPrint('[plugin] 未知的 area code "$code"，已回落到 '
      '${kHomePluginAreaFallback.name}');
  return kHomePluginAreaFallback;
}

/// 区域 code → 中文标签（单一事实源入口）。
String homePluginAreaLabel(String code) => homePluginAreaFromCode(code).label;

enum HomePluginActionType {
  toast,
  navigate,
  openDailyNews,
  openNovelList,
  openVideoList,
  openImageGenerator,
  openGithubAccel,
  openRemoteStorage;

  /// 中文标签（单一事实源）。此前散落在市场页与投稿页各一份且已漂移
  /// （toast：提示动作 vs 弹出提示）。
  String get label {
    switch (this) {
      case HomePluginActionType.toast:
        return '提示动作';
      case HomePluginActionType.navigate:
        return '路由跳转';
      case HomePluginActionType.openDailyNews:
        return '打开日报';
      case HomePluginActionType.openNovelList:
        return '打开小说';
      case HomePluginActionType.openVideoList:
        return '打开影视';
      case HomePluginActionType.openImageGenerator:
        return '打开生图';
      case HomePluginActionType.openGithubAccel:
        return '打开加速';
      case HomePluginActionType.openRemoteStorage:
        return '打开远程存储';
    }
  }

  /// 顺序即 UI 下拉展示顺序（供投稿页复用）。
  /// 附录 A-1：补齐遗漏的 openGithubAccel（投稿页下拉此前选不到「打开加速」）。
  static const List<HomePluginActionType> displayOrder = [
    HomePluginActionType.toast,
    HomePluginActionType.navigate,
    HomePluginActionType.openDailyNews,
    HomePluginActionType.openNovelList,
    HomePluginActionType.openVideoList,
    HomePluginActionType.openImageGenerator,
    HomePluginActionType.openGithubAccel,
    HomePluginActionType.openRemoteStorage,
  ];
}

/// 由 code 解析动作；未知 code 记日志并回落 [HomePluginActionType.toast]。
HomePluginActionType homePluginActionTypeFromCode(String code) {
  final text = code.trim();
  for (final action in HomePluginActionType.values) {
    if (action.name == text) return action;
  }
  debugPrint('[plugin] 未知的 action code "$code"，已回落到 toast');
  return HomePluginActionType.toast;
}

/// 动作 code → 中文标签（单一事实源入口）。
String homePluginActionLabel(String code) =>
    homePluginActionTypeFromCode(code).label;


class HomePluginActionContext {
  final String pluginId;
  final String title;
  final String payload;
  final Map<String, dynamic> extra;

  const HomePluginActionContext({
    required this.pluginId,
    required this.title,
    this.payload = '',
    this.extra = const {},
  });
}

typedef HomePluginActionHandler =
    Future<void> Function(
      BuildContext? context,
      HomePluginActionContext actionContext,
    );

class HomePluginRouteRegistry {
  HomePluginRouteRegistry._();

  static final Map<String, WidgetBuilder> _routes = {};

  static void register(String routeCode, WidgetBuilder builder) {
    final code = routeCode.trim();
    if (code.isEmpty) return;
    _routes[code] = builder;
  }

  static bool contains(String routeCode) {
    return _routes.containsKey(routeCode.trim());
  }

  static WidgetBuilder? lookup(String routeCode) {
    return _routes[routeCode.trim()];
  }

  static void registerDefaults() {
    // P2-2：具体页面绑定已拆到 builtin_plugin_pages.dart，这里只做委托，
    // core 因此不再直接 import 任何具体 UI 页面。
    registerBuiltinRouteDefaults();
  }
}

String _payloadRouteCode(HomePluginActionContext actionContext) {
  final payload = actionContext.payload.trim();
  if (payload.isEmpty) {
    return actionContext.extra['route']?.toString().trim() ?? '';
  }

  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map) {
      final route = decoded['route'] ?? decoded['routeCode'] ?? decoded['page'];
      final text = route?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
  } catch (_) {}

  return payload;
}

/// 加速动作只接受 http/https 且带 host 的绝对 URL。
///
/// 插件的 payload 来自第三方清单或用户导入的快照 —— 不校验就等于让插件卡把
/// 流量导向任意主机，还借用「GitHub 加速」的信任外观；而 `javascript:` /
/// `file:` 这类没有 scheme 限制时也会继续往后走。
bool isAllowedAccelUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return false;
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  return uri.host.isNotEmpty;
}

/// 过一遍白名单：不合法则留痕，并当作「没给链接」处理
/// （面板照常打开，只是不预填 —— 不因为一条脏 payload 把功能整块停掉）。
String _allowedAccelUrlOrEmpty(String raw, {required String source}) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  if (isAllowedAccelUrl(text)) return text;
  debugPrint('[plugin] 加速动作拒绝非法 URL（$source）：$text');
  return '';
}

/// 从 payload 里取出链接。支持裸链接和 {"url": "..."} 两种形态。
String _payloadUrl(HomePluginActionContext actionContext) {
  final payload = actionContext.payload.trim();
  if (payload.isEmpty) {
    return _allowedAccelUrlOrEmpty(
      actionContext.extra['url']?.toString() ?? '',
      source: 'extra.url',
    );
  }
  if (payload.startsWith('{')) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final url = decoded['url'] ?? decoded['link'] ?? decoded['href'];
        final text = url?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          return _allowedAccelUrlOrEmpty(text, source: 'payload.url');
        }
      }
    } catch (e) {
      debugPrint('[HomePlugin] GitHub 加速 payload 解析失败: $e');
    }
    return '';
  }
  return _allowedAccelUrlOrEmpty(payload, source: 'payload');
}

class HomePluginActionRegistry {
  HomePluginActionRegistry._();

  /// 内置动作实现表：由 [registerDefaults] 通过**公开** [register] 填入。
  ///
  /// 此前这里是静态字面量地图，而公开的 `register()` 零生产调用 ——
  /// 「可扩展 Action 系统」看着完成、实际没有任何外部接入点被用过。
  static final Map<String, HomePluginActionHandler> _handlers = {};

  /// 注册全部内置动作。幂等，可重复调用。
  ///
  /// 键必须是 `HomePluginActionType.x.name`，**不得裸字符串** ——
  /// plugin_area_action_single_source_test.dart 会锁这一条。
  static void registerDefaults() {
    register(
      HomePluginActionType.toast.name,
      (context, actionContext) async {
      if (context == null) return;
      await _showSnack(
        context,
        actionContext.payload.trim().isEmpty
            ? '点击了 ${actionContext.title}'
            : actionContext.payload.trim(),
      );
    },
    );
    register(
      HomePluginActionType.navigate.name,
      (context, actionContext) async {
      if (context == null) return;
      HomePluginRouteRegistry.registerDefaults();
      final routeCode = _payloadRouteCode(actionContext);
      final builder = HomePluginRouteRegistry.lookup(routeCode);
      if (builder == null) return;
      await Navigator.push(context, MaterialPageRoute(builder: builder));
    },
    );
    register(
      HomePluginActionType.openDailyNews.name,
      (context, actionContext) async {
      if (context == null) return;
      HomePluginRouteRegistry.registerDefaults();
      final builder = HomePluginRouteRegistry.lookup('openDailyNews');
      if (builder == null) return;
      await Navigator.push(context, MaterialPageRoute(builder: builder));
    },
    );
    register(
      HomePluginActionType.openNovelList.name,
      (context, actionContext) async {
      if (context == null) return;
      HomePluginRouteRegistry.registerDefaults();
      final builder = HomePluginRouteRegistry.lookup('openNovelList');
      if (builder == null) return;
      await Navigator.push(context, MaterialPageRoute(builder: builder));
    },
    );
    register(
      HomePluginActionType.openVideoList.name,
      (context, actionContext) async {
      if (context == null) return;
      HomePluginRouteRegistry.registerDefaults();
      final builder = HomePluginRouteRegistry.lookup('openVideoList');
      if (builder == null) return;
      await Navigator.push(context, MaterialPageRoute(builder: builder));
    },
    );
    register(
      HomePluginActionType.openImageGenerator.name,
      (context, actionContext) async {
          if (context == null) return;
          HomePluginRouteRegistry.registerDefaults();
          final builder = HomePluginRouteRegistry.lookup('openImageGenerator');
          if (builder == null) return;
          await Navigator.push(context, MaterialPageRoute(builder: builder));
        },
    // GitHub 加速下载是个底部面板而不是整页，所以走 show 而不是 Navigator.push。
    // payload 若带链接就直接预填并自动转换，方便从别处「用加速下载打开」。
    // P2-2：具体页面/面板的依赖已拆到 builtin_plugin_pages.dart。,
    );
    register(
      HomePluginActionType.openGithubAccel.name,
      (context, actionContext) async {
      await showGithubAccelAction(context, _payloadUrl(actionContext));
    },
    );
    register(
      HomePluginActionType.openRemoteStorage.name,
      (context, actionContext) async {
      if (context == null) return;
      HomePluginRouteRegistry.registerDefaults();
      final builder = HomePluginRouteRegistry.lookup('openRemoteStorage');
      if (builder == null) return;
      await Navigator.push(context, MaterialPageRoute(builder: builder));
    },
    );
  }

  static bool contains(String actionCode) {
    registerDefaults();
    return _handlers.containsKey(actionCode.trim());
  }

  static void register(String actionCode, HomePluginActionHandler handler) {
    final code = actionCode.trim();
    if (code.isEmpty) return;
    _handlers[code] = handler;
  }

  static Future<bool> run(
    String actionCode,
    BuildContext? context,
    HomePluginActionContext actionContext,
  ) async {
    registerDefaults();
    final handler = _handlers[actionCode.trim()];
    if (handler == null) return false;
    await handler(context, actionContext);
    return true;
  }
}

/// 落库路径的区域解析 —— **委托**单一事实源，不再自己抄一份枚举遍历。
///
/// 此前这里回 recommend 而标签路径回 center，导致「标签说工具、落库存推荐」。
HomePluginArea _areaFromName(String name) => homePluginAreaFromCode(name);

HomePluginActionType _actionFromName(String name) {
  for (final value in HomePluginActionType.values) {
    if (value.name == name) {
      return value;
    }
  }
  // P2-5：未知值不再静默回退，打日志留痕（回退值保持 toast 不变）。
  debugPrint('[plugin] 未知 action code "$name"，已回落到 '
      '${HomePluginActionType.toast.name}');
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
  final String actionCode;
  final String payload;
  final bool enabled;
  final int sort;
  final int createdAt;
  /// market | local | ''
  final String origin;
  final String marketVersion;
  final String packageSha256;
  final String author;
  /// published | yanked | local_cache | ''
  final String marketStatus;
  final bool marketRisk;
  final String marketRiskNote;

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
    this.actionCode = '',
    this.payload = '',
    this.enabled = true,
    this.sort = 9999,
    required this.createdAt,
    this.origin = '',
    this.marketVersion = '',
    this.packageSha256 = '',
    this.author = '',
    this.marketStatus = '',
    this.marketRisk = false,
    this.marketRiskNote = '',
  });

  factory HomeCustomPluginConfig.fromMarketTemplate(
    MarketPluginTemplate template, {
    int? createdAt,
  }) {
    final payload = template.payloadData.isEmpty
        ? template.payload
        : jsonEncode(template.payloadData);
    final origin = template.tags.contains('用户投稿') ||
            template.author.trim().isNotEmpty
        ? 'user_market'
        : 'market';
    return HomeCustomPluginConfig(
      id: template.id,
      title: template.title,
      subtitle: template.subtitle,
      iconCodePoint: template.icon.codePoint,
      iconFontFamily: template.icon.fontFamily ?? 'MaterialIcons',
      iconFontPackage: template.icon.fontPackage,
      colorValue: template.color.toARGB32(),
      area: _areaFromName(template.areaCode),
      actionType: _actionFromName(template.actionCode),
      actionCode: template.actionCode,
      payload: payload,
      enabled: true,
      sort: template.sort,
      createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
      origin: origin,
      marketVersion: template.version,
      packageSha256: '',
      author: template.author,
      marketStatus: origin == 'user_market' ? 'published' : '',
      marketRisk: false,
      marketRiskNote: '',
    );
  }

  @visibleForTesting
  factory HomeCustomPluginConfig.fromMarketTemplateForTest(
    MarketPluginTemplate template, {
    int? createdAt,
  }) = HomeCustomPluginConfig.fromMarketTemplate;

  bool get isValid => id.trim().isNotEmpty && title.trim().isNotEmpty;

  String get effectiveActionCode {
    final code = actionCode.trim();
    return code.isEmpty ? actionType.name : code;
  }

  IconData get iconData {
    // 持久化配置里的图标 code point 均来自市场图标常量集合，
    // 通过反查常量表恢复，避免动态构造 IconData 破坏 release 图标 tree-shaking。
    return marketIconByCodePoint(iconCodePoint);
  }

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
    String? actionCode,
    String? payload,
    bool? enabled,
    int? sort,
    int? createdAt,
    String? origin,
    String? marketVersion,
    String? packageSha256,
    String? author,
    String? marketStatus,
    bool? marketRisk,
    String? marketRiskNote,
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
      actionCode: actionCode ?? this.actionCode,
      payload: payload ?? this.payload,
      enabled: enabled ?? this.enabled,
      sort: sort ?? this.sort,
      createdAt: createdAt ?? this.createdAt,
      origin: origin ?? this.origin,
      marketVersion: marketVersion ?? this.marketVersion,
      packageSha256: packageSha256 ?? this.packageSha256,
      author: author ?? this.author,
      marketStatus: marketStatus ?? this.marketStatus,
      marketRisk: marketRisk ?? this.marketRisk,
      marketRiskNote: marketRiskNote ?? this.marketRiskNote,
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
      'actionCode': effectiveActionCode,
      'payload': payload,
      'enabled': enabled,
      'sort': sort,
      'createdAt': createdAt,
      'origin': origin,
      'marketVersion': marketVersion,
      'packageSha256': packageSha256,
      'author': author,
      'marketStatus': marketStatus,
      'marketRisk': marketRisk,
      'marketRiskNote': marketRiskNote,
    };
  }

  factory HomeCustomPluginConfig.fromJson(Map<String, dynamic> json) {
    final rawActionCode = _asString(json['actionCode']);
    final fallbackActionName = rawActionCode.isEmpty
        ? HomePluginActionType.toast.name
        : rawActionCode;
    return HomeCustomPluginConfig(
      id: _asString(json['id']),
      title: _asString(json['title']),
      subtitle: _asString(json['subtitle']),
      iconCodePoint: _asInt(json['iconCodePoint'], Icons.extension.codePoint),
      iconFontFamily: _asString(json['iconFontFamily'], 'MaterialIcons'),
      iconFontPackage: json['iconFontPackage'] == null
          ? null
          : _asString(json['iconFontPackage']),
      colorValue: _asInt(json['colorValue'], Colors.blue.toARGB32()),
      // 键缺失/空串时的默认值也必须走统一回退值（center）：
      // 这里曾经写死 recommend，于是同一条脏数据在标签路径说「工具」、
      // 在落库路径进「推荐」。历史存档都带 area 字段，改它只影响破损数据。
      area: _areaFromName(
        _asString(json['area'], kHomePluginAreaFallback.name),
      ),
      actionType: _actionFromName(
        _asString(json['actionType'], fallbackActionName),
      ),
      actionCode: rawActionCode,
      payload: _asString(json['payload']),
      enabled: _asBool(json['enabled'], true),
      sort: _asInt(json['sort'], 9999),
      createdAt: _asInt(
        json['createdAt'],
        DateTime.now().millisecondsSinceEpoch,
      ),
      origin: _asString(json['origin']),
      marketVersion: _asString(json['marketVersion'], _asString(json['version'])),
      packageSha256: _asString(json['packageSha256']),
      author: _asString(json['author']),
      marketStatus: _asString(json['marketStatus']),
      marketRisk: _asBool(json['marketRisk'], false),
      marketRiskNote: _asString(json['marketRiskNote']),
    );
  }
}

/// 插件快照结构版本。`toJson` 写出、`importSnapshotJson` 校验，二者须同源。
///
/// v2 新增 `orderMap`（id → sort）：v1 只存 enabledMap，内置插件的排序信息
/// 没有任何落地位置 —— 拖动重排内置插件，重启后顺序还原，而自定义插件因为
/// 走 customPlugins 能保住顺序。同一交互两种结果。
const int kPluginSnapshotVersion = 2;

/// 兼容读取的历史版本：v1 没有 orderMap，读出来内置顺序回落默认值。
const Set<int> kSupportedPluginSnapshotVersions = {1, 2};

class HomePluginSnapshot {
  final Map<String, bool> enabledMap;

  /// id → sort，内置与自定义**统一**存这里（v2 新增）。
  final Map<String, int> orderMap;

  final List<HomeCustomPluginConfig> customPlugins;

  const HomePluginSnapshot({
    required this.enabledMap,
    required this.customPlugins,
    this.orderMap = const {},
  });

  const HomePluginSnapshot.empty()
    : enabledMap = const {},
      orderMap = const {},
      customPlugins = const [];

  Map<String, dynamic> toJson() {
    return {
      'version': kPluginSnapshotVersion,
      'enabledMap': enabledMap,
      'orderMap': orderMap,
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

    // v1 没有这个字段：读出来是空表，内置顺序回落各自默认值（向后兼容）。
    final orderMap = <String, int>{};
    final orderRaw = json['orderMap'];
    if (orderRaw is Map) {
      orderRaw.forEach((key, value) {
        if (value is num) orderMap[key.toString()] = value.toInt();
      });
    }

    return HomePluginSnapshot(
      enabledMap: enabledMap,
      orderMap: orderMap,
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
          return HomePluginSnapshot.fromJson(
            Map<String, dynamic>.from(decoded),
          );
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

abstract class HomePluginLifecycle {
  Future<void> onInitialize(HomePlugin plugin);

  Future<void> onEnabled(HomePlugin plugin);

  Future<void> onDisabled(HomePlugin plugin);

  Future<void> onUninstall(HomePlugin plugin);

  Future<bool> validate(HomePlugin plugin);
}

class NoopHomePluginLifecycle implements HomePluginLifecycle {
  const NoopHomePluginLifecycle();

  @override
  Future<void> onInitialize(HomePlugin plugin) async {}

  @override
  Future<void> onEnabled(HomePlugin plugin) async {}

  @override
  Future<void> onDisabled(HomePlugin plugin) async {}

  @override
  Future<void> onUninstall(HomePlugin plugin) async {}

  @override
  Future<bool> validate(HomePlugin plugin) async => true;
}

/// 插件事件名（单一事实源）：此前事件总线只有实现、没有任何生产 emit ——
/// App 从不知道"插件装了/停了/被判风险"，文档却把它列为已完成能力。
class PluginEvents {
  PluginEvents._();

  static const String installed = 'plugin.installed';
  static const String uninstalled = 'plugin.uninstalled';
  static const String enabled = 'plugin.enabled';
  static const String disabled = 'plugin.disabled';
  static const String riskFlagged = 'plugin.risk';

  /// 全部事件名（订阅/清理用，避免各处再抄一份）。
  static const List<String> all = [
    installed,
    uninstalled,
    enabled,
    disabled,
    riskFlagged,
  ];
}

/// 面向生产的生命周期实现 —— 三个扩展点的**第一个真实消费者**。
///
/// 接线前：单例写死 `NoopHomePluginLifecycle`，事件总线与动作注册表的公开
/// `register()` 全零生产调用；代码与单测都在，App 从未用过。
///
/// 这里只做"真能做的事"，不假装有沙箱：
///   - `validate`：真实校验（id/标题为空的行在 UI 上是空白，直接拒掉）；
///   - 四个回调：留一条**可查看的审计轨迹**（什么时候装/停/卸的）；
///   - 订阅事件总线，把事件也记进同一条轨迹。
///
/// 刻意不做运行时拦截：当前没有第三方代码在下游执行，没有可拦截的承载对象。
class HomePluginLifecycleObserver implements HomePluginLifecycle {
  HomePluginLifecycleObserver({int keepLast = 50}) : _keepLast = keepLast {
    for (final event in PluginEvents.all) {
      PluginEventBus.instance.subscribe(event, (data) => _record(event, data));
    }
  }

  static final HomePluginLifecycleObserver instance =
      HomePluginLifecycleObserver();

  final int _keepLast;
  final List<String> _trail = <String>[];

  /// 最近的生命周期/事件轨迹（最新的在末尾）。诊断用，别当数据源。
  List<String> get trail => List.unmodifiable(_trail);

  void _record(String event, dynamic data) {
    _trail.add(data == null ? event : '$event:${data.toString()}');
    while (_trail.length > _keepLast) {
      _trail.removeAt(0);
    }
  }

  void _log(String stage, HomePlugin plugin) {
    debugPrint('[plugin] $stage ${plugin.id}（${plugin.area.name}）');
  }

  @override
  Future<void> onInitialize(HomePlugin plugin) async {
    _log('初始化', plugin);
    _record(PluginEvents.installed, plugin.id);
  }

  @override
  Future<void> onEnabled(HomePlugin plugin) async {
    _log('启用', plugin);
    _record(PluginEvents.enabled, plugin.id);
  }

  @override
  Future<void> onDisabled(HomePlugin plugin) async {
    _log('停用', plugin);
    _record(PluginEvents.disabled, plugin.id);
  }

  @override
  Future<void> onUninstall(HomePlugin plugin) async {
    _log('卸载', plugin);
    _record(PluginEvents.uninstalled, plugin.id);
  }

  @override
  Future<bool> validate(HomePlugin plugin) async {
    if (plugin.id.trim().isEmpty || plugin.title.trim().isEmpty) {
      debugPrint('[plugin] 校验不通过：id 或标题为空，已拒绝注册');
      return false;
    }
    return true;
  }
}

class PluginEventBus {
  PluginEventBus();

  static final PluginEventBus instance = PluginEventBus();

  final Map<String, List<void Function(dynamic data)>> _listeners = {};

  void subscribe(String event, void Function(dynamic data) handler) {
    final name = event.trim();
    if (name.isEmpty) return;
    _listeners
        .putIfAbsent(name, () => <void Function(dynamic data)>[])
        .add(handler);
  }

  void unsubscribe(String event, void Function(dynamic data) handler) {
    _listeners[event.trim()]?.remove(handler);
  }

  void emit(String event, [dynamic data]) {
    final handlers = List<void Function(dynamic data)>.from(
      _listeners[event.trim()] ?? const [],
    );
    for (final handler in handlers) {
      handler(data);
    }
  }
}

class HomePluginHost {
  HomePluginHost({
    HomePluginPersistence? persistence,
    HomePluginLifecycle? lifecycle,
  }) : _persistence = persistence ?? HomePluginPersistence(),
       // 默认也用真实实现，与单例保持一致（注入仍可覆盖）。
       _lifecycle = lifecycle ?? HomePluginLifecycleObserver.instance;

  HomePluginHost._()
    : _persistence = HomePluginPersistence(),
      // 生产默认走真实实现（审计轨迹 + 真实校验），不再是 Noop。
      _lifecycle = HomePluginLifecycleObserver.instance;

  static final HomePluginHost instance = HomePluginHost._();

  final ValueNotifier<List<HomePlugin>> _notifier =
      ValueNotifier<List<HomePlugin>>(<HomePlugin>[]);

  /// 非 final：测试可注入，也可由 App 换成别的实现。
  HomePluginLifecycle _lifecycle;

  /// 换掉生命周期实现（接线点；测试与 App 定制都用它）。
  void configureLifecycle(HomePluginLifecycle lifecycle) =>
      _lifecycle = lifecycle;

  // 非 final：测试可注入内存实现（injectPersistenceForTesting）。
  HomePluginPersistence _persistence;

  Future<void>? _bootFuture;
  bool _bootstrapped = false;

  ValueListenable<List<HomePlugin>> get listenable => _notifier;

  List<HomePlugin> get allPlugins => _sorted(_notifier.value);

  /// 内置插件表（不含用户装的第三方插件，也不读任何持久化）。
  ///
  /// 给测试用：`bootstrap()` 会碰 path_provider / SharedPreferences，
  /// 在纯 widget 测试里没有平台实现会直接挂住（实测卡死 300s+）。
  /// 要校验「内置 id 是否存在」这类静态事实，用这个入口。
  ///
  /// 注意它**不是**纯函数：内部会调 QuizPluginEntry.initAutoSearch，
  /// 而那里 setMethodCallHandler 要求 binding 已初始化。调用方必须用
  /// `testWidgets`（自带 binding），普通 `test()` 会断言失败。
  @visibleForTesting
  List<HomePlugin> builtInPluginsForTesting() => _sorted(_buildDefaultPlugins());

  /// 直接把插件列表灌进 notifier，并标记为已 bootstrap。
  ///
  /// 给 widget 测试用：任何监听 [listenable] 的页面（首页快捷入口、
  /// 自选页）在测试里都拿不到数据，因为 `bootstrap()` 要读 path_provider
  /// 会挂住。用这个入口喂真实的内置插件表即可。
  ///
  /// 传 null 表示用内置插件表。测试之间记得调 [resetForTesting]，
  /// 否则单例状态会串到下一个用例。
  @visibleForTesting
  void seedForTesting([List<HomePlugin>? plugins]) {
    _notifier.value = _sorted(plugins ?? _buildDefaultPlugins());
    _bootstrapped = true;
    _bootFuture = null;
  }

  /// 测试专用：替换单例的持久化实现。
  ///
  /// 默认 [HomePluginPersistence] 走 path_provider（platform channel）+
  /// dart:io 真实文件 IO，在 widget 测试的 FakeAsync zone 里这些 await
  /// 永不完成 —— register / toggleEnabled 这类写路径会整体挂死
  /// （与 [seedForTesting] 的注释同源，实测卡死 300s+）。注入
  /// `CacheStore.inMemory` 支撑的 persistence 后写路径纯内存完成。
  ///
  /// [resetForTesting] 会恢复默认实现，避免用例间串扰。
  @visibleForTesting
  void injectPersistenceForTesting(HomePluginPersistence persistence) {
    _persistence = persistence;
  }

  /// 清掉单例里的插件状态，让下一个测试从干净的起点开始。
  @visibleForTesting
  void resetForTesting() {
    _notifier.value = <HomePlugin>[];
    _bootstrapped = false;
    _bootFuture = null;
    _persistence = HomePluginPersistence();
  }

  HomePlugin? findById(String id) {
    for (final plugin in _notifier.value) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

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

  List<HomePlugin> pluginsOf(HomePluginArea area, {bool onlyEnabled = true}) {
    final list = _notifier.value.where((plugin) {
      if (plugin.area != area) return false;
      if (onlyEnabled && !plugin.enabled) return false;
      return true;
    }).toList();

    return _sorted(list);
  }

  Future<void> register(HomePlugin plugin, {bool replace = true}) async {
    await bootstrap();

    final normalized = _normalizeForRegister(plugin);
    if (!await _lifecycle.validate(normalized)) return;
    final list = List<HomePlugin>.from(_notifier.value);
    final index = list.indexWhere((item) => item.id == normalized.id);
    final isNew = index < 0;

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
    if (isNew) {
      await _lifecycle.onInitialize(normalized);
    }
    PluginEventBus.instance.emit(
      isNew ? PluginEvents.installed : PluginEvents.enabled,
      normalized.id,
    );
    final cfg = normalized.customConfig;
    if (cfg != null && cfg.marketRisk) {
      PluginEventBus.instance.emit(PluginEvents.riskFlagged, normalized.id);
    }
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

    final removed = list.removeAt(index);
    _notifier.value = _sorted(list);
    await _persist();
    await _lifecycle.onUninstall(removed);
    PluginEventBus.instance.emit(PluginEvents.uninstalled, removed.id);
  }

  Future<void> toggleEnabled(String id, bool enabled) async {
    await bootstrap();

    final list = List<HomePlugin>.from(_notifier.value);
    final index = list.indexWhere((item) => item.id == id);
    if (index < 0) return;

    final current = list[index];
    // 下架插件禁止重新启用
    if (enabled) {
      final cfg = current.customConfig;
      if (cfg != null &&
          (cfg.marketRisk || cfg.marketStatus == 'yanked')) {
        return;
      }
    }
    final updated = current.copyWith(
      enabled: enabled,
      customConfig: current.customConfig?.copyWith(enabled: enabled),
    );
    list[index] = updated;

    _notifier.value = _sorted(list);
    await _persist();
    if (enabled) {
      await _lifecycle.onEnabled(updated);
    } else {
      await _lifecycle.onDisabled(updated);
    }
    PluginEventBus.instance.emit(
      enabled ? PluginEvents.enabled : PluginEvents.disabled,
      updated.id,
    );
  }

  Future<void> reorderPlugin(
    HomePluginArea area,
    int oldIndex,
    int newIndex,
  ) async {
    await bootstrap();
    final inArea = List<HomePlugin>.from(
      _notifier.value.where((p) => p.area == area),
    );
    inArea.sort((a, b) {
      final c = a.sort.compareTo(b.sort);
      if (c != 0) return c;
      return a.title.compareTo(b.title);
    });

    if (oldIndex < 0 || oldIndex >= inArea.length) return;
    if (newIndex < 0 || newIndex >= inArea.length) return;

    final moved = inArea.removeAt(oldIndex);
    inArea.insert(newIndex, moved);

    // 区域内顺序即 sort 升序：整段重排为 100/200/300…
    //
    // 此前这里先算「相邻中点」赋给 base，紧接着 `base = 100` 把它覆盖掉 ——
    // 整段是死代码（结果可用，但留下永不生效的逻辑，读的人会以为做了中点插入）。
    // 中点方案也无法多表达任何顺序：_sorted() 的二级排序本就是 title。
    const int base = 100;
    const int step = 100;
    final list = List<HomePlugin>.from(_notifier.value);
    for (int i = 0; i < inArea.length; i++) {
      final idx = list.indexWhere((p) => p.id == inArea[i].id);
      if (idx >= 0) {
        list[idx] = list[idx].copyWith(sort: base + i * step);
      }
    }

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

  /// 由 JSON 文本导入快照。
  ///
  /// 护栏（防止一次误粘/误拉远程内容静默清空用户配置）：
  ///  - `version` 必须存在且为 [kPluginSnapshotVersion]（toJson 会写，旧实现忽略）；
  ///  - 必须至少含 `enabledMap`(Map) 或 `customPlugins`(List) 之一；
  ///  - 覆盖模式（merge=false）下若解析结果「两表皆空」而当前快照非空，
  ///    除非显式 allowEmpty（清空即重置），否则拒绝。
  Future<void> importSnapshotJson(
    String jsonText, {
    bool merge = false,
    bool allowEmpty = false,
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

    // 1) 版本校验：缺失/不匹配一律拒绝，避免把无关 JSON 当成空快照。
    //    受支持版本是**集合**（v1 无 orderMap，仍要能读进来）。
    final versionRaw = decoded['version'];
    final version = versionRaw is num ? versionRaw.toInt() : null;
    if (version == null ||
        !kSupportedPluginSnapshotVersions.contains(version)) {
      throw FormatException(
        '快照版本不受支持（支持 '
        '${kSupportedPluginSnapshotVersions.join(' / ')}，'
        '实际 ${versionRaw ?? '缺失'}）',
      );
    }

    // 2) 必需字段校验：至少要有其中一个，否则视为无关 JSON。
    final hasEnabled = decoded['enabledMap'] is Map;
    final hasCustom = decoded['customPlugins'] is List;
    if (!hasEnabled && !hasCustom) {
      throw const FormatException('快照缺少必需字段（enabledMap / customPlugins）');
    }

    final incoming = HomePluginSnapshot.fromJson(
      Map<String, dynamic>.from(decoded),
    );

    // 3) 清库护栏：覆盖模式下不允许用空快照抹掉已有配置。
    if (!merge && !allowEmpty) {
      final emptiesIncoming =
          incoming.enabledMap.isEmpty && incoming.customPlugins.isEmpty;
      final current = _buildCurrentSnapshot();
      final currentHasData =
          current.enabledMap.isNotEmpty || current.customPlugins.isNotEmpty;
      if (emptiesIncoming && currentHasData) {
        throw const FormatException(
          '快照为空，导入会清空现有配置；如确需重置请显式允许清空',
        );
      }
    }

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
    final enabled = <String, bool>{...base.enabledMap, ...incoming.enabledMap};

    final customMap = <String, HomeCustomPluginConfig>{
      for (final item in base.customPlugins) item.id: item,
    };

    for (final item in incoming.customPlugins) {
      if (!item.isValid) continue;
      customMap[item.id] = item;
    }

    return HomePluginSnapshot(
      enabledMap: enabled,
      orderMap: <String, int>{...base.orderMap, ...incoming.orderMap},
      customPlugins: customMap.values.toList(),
    );
  }

  /// 当前生效快照（公开只读视图，供 UI 展示导入结果等）。
  HomePluginSnapshot snapshot() => _buildCurrentSnapshot();

  HomePluginSnapshot _buildCurrentSnapshot() {
    final enabledMap = <String, bool>{};
    final orderMap = <String, int>{};
    final customPlugins = <HomeCustomPluginConfig>[];

    for (final plugin in _notifier.value) {
      enabledMap[plugin.id] = plugin.enabled;
      // 顺序对**所有**插件都记（此前只写 enabledMap + 非内置的 customPlugins，
      // 内置插件的排序没有任何落地位置 —— 重排后重启即丢）。
      orderMap[plugin.id] = plugin.sort;
      if (!plugin.builtIn) {
        final config =
            (plugin.customConfig ?? _fallbackConfigFromPlugin(plugin)).copyWith(
              enabled: plugin.enabled,
            );
        if (config.isValid) {
          customPlugins.add(config);
        }
      }
    }

    return HomePluginSnapshot(
      enabledMap: enabledMap,
      orderMap: orderMap,
      customPlugins: customPlugins,
    );
  }

  void _applySnapshot(HomePluginSnapshot snapshot) {
    final result = <HomePlugin>[];

    final defaults = _buildDefaultPlugins();
    for (final plugin in defaults) {
      final enabled = snapshot.enabledMap[plugin.id] ?? plugin.enabled;
      result.add(
        plugin.copyWith(
          enabled: enabled,
          sort: snapshot.orderMap[plugin.id] ?? plugin.sort,
        ),
      );
    }

    for (final config in snapshot.customPlugins) {
      if (!config.isValid) continue;
      final enabled = snapshot.enabledMap[config.id] ?? config.enabled;
      result.add(
        _pluginFromCustomConfig(
          config.copyWith(
            enabled: enabled,
            sort: snapshot.orderMap[config.id] ?? config.sort,
          ),
        ),
      );
    }

    _notifier.value = _sorted(result);
  }

  HomePlugin _normalizeForRegister(HomePlugin plugin) {
    if (plugin.builtIn) return plugin;

    final config = plugin.customConfig ?? _fallbackConfigFromPlugin(plugin);
    return plugin.copyWith(enabled: config.enabled, customConfig: config);
  }

  HomeCustomPluginConfig _fallbackConfigFromPlugin(HomePlugin plugin) {
    return HomeCustomPluginConfig(
      id: plugin.id,
      title: plugin.title,
      subtitle: plugin.subtitle,
      iconCodePoint: plugin.icon.codePoint,
      iconFontFamily: plugin.icon.fontFamily ?? 'MaterialIcons',
      iconFontPackage: plugin.icon.fontPackage,
      colorValue: plugin.color.toARGB32(),
      area: plugin.area,
      actionType: HomePluginActionType.toast,
      actionCode:
          plugin.customConfig?.effectiveActionCode ??
          HomePluginActionType.toast.name,
      payload: plugin.subtitle,
      enabled: plugin.enabled,
      sort: plugin.sort,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      origin: plugin.customConfig?.origin ?? '',
      marketVersion: plugin.customConfig?.marketVersion ?? '',
      packageSha256: plugin.customConfig?.packageSha256 ?? '',
      author: plugin.customConfig?.author ?? '',
      marketStatus: plugin.customConfig?.marketStatus ?? '',
      marketRisk: plugin.customConfig?.marketRisk ?? false,
      marketRiskNote: plugin.customConfig?.marketRiskNote ?? '',
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
        final latest = _notifier.value
            .where((p) => p.id == config.id)
            .map((p) => p.customConfig)
            .firstOrNull;
        final risk = latest?.marketRisk == true ||
            latest?.marketStatus == 'yanked' ||
            config.marketRisk ||
            config.marketStatus == 'yanked';
        if (risk) {
          final note = (latest?.marketRiskNote.isNotEmpty == true)
              ? latest!.marketRiskNote
              : (config.marketRiskNote.isNotEmpty
                  ? config.marketRiskNote
                  : '该插件已被管理员下架，无法使用');
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(note)),
          );
          return;
        }
        if (!(latest?.enabled ?? config.enabled)) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('插件已禁用')),
          );
          return;
        }
        final ran = await HomePluginActionRegistry.run(
          (latest ?? config).effectiveActionCode,
          context,
          HomePluginActionContext(
            pluginId: config.id,
            title: (latest ?? config).title,
            payload: (latest ?? config).payload,
          ),
        );
        if (!ran && context.mounted) {
          await _showSnack(context, '插件动作未注册：${config.effectiveActionCode}');
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
    // P2-2：目录已拆到 builtin_plugin_catalog.dart，这里只做委托。
    // core 因此不再直接 import 具体 UI 页面。
    return buildDefaultPlugins();
  }
}

Future<void> _showSnack(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
