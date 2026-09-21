import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'custom_site.dart';

/// 自定义网址的持久化。
///
/// 为什么用 SharedPreferences 而不是 Hive：这份数据要进备份，而备份服务
/// 对 prefs 是「往 BackupPrefKeys 加一个键」就自动覆盖导出与恢复；走 Hive
/// 则要另注册 box 并改 `_boxNames`。同样的效果，prefs 这条路的改动面更小。
class CustomSiteStore {
  /// 存储键。加进 `BackupPrefKeys.fixedKeys` 才会进备份 —— 有测试钉住。
  static const String prefsKey = 'tools_custom_sites_v1';

  /// 读写钩子。纯 Dart 测试环境没有 shared_preferences 的平台实现，
  /// 替换这两个钩子才能在单测里验证持久化链路。
  static Future<String?> Function() readRaw = defaultReadRaw;
  static Future<void> Function(String raw) writeRaw = defaultWriteRaw;

  static Future<String?> defaultReadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefsKey);
  }

  static Future<void> defaultWriteRaw(String raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, raw);
  }

  /// 还原钩子，避免替换过的钩子泄漏到后续用例。
  static void resetHooksForTest() {
    readRaw = defaultReadRaw;
    writeRaw = defaultWriteRaw;
  }

  Future<List<CustomSite>> load() async {
    String? raw;
    try {
      raw = await readRaw();
    } catch (_) {
      return <CustomSite>[];
    }
    if (raw == null || raw.trim().isEmpty) return <CustomSite>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <CustomSite>[];
      final sites = <CustomSite>[];
      for (final item in decoded) {
        final site = CustomSite.fromJson(item);
        if (site != null) sites.add(site);
      }
      // 新添加的排前面：用户刚存的网址应该立刻看得见。
      sites.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sites;
    } catch (_) {
      // 存储损坏时返回空列表而不是抛异常 —— 工具页不该因为一条坏数据打不开。
      return <CustomSite>[];
    }
  }

  Future<void> _persist(List<CustomSite> sites) async {
    await writeRaw(jsonEncode([for (final s in sites) s.toJson()]));
  }

  /// 添加一条。非法 URL 返回 null；同 URL 已存在时视为改标题。
  Future<CustomSite?> add({required String title, required String url}) async {
    final site = CustomSite.tryCreate(title: title, url: url);
    if (site == null) return null;

    final all = await load();
    final existingIndex = all.indexWhere((e) => e.url == site.url);
    if (existingIndex >= 0) {
      // 同一个网址重复添加，用户意图几乎总是「改个更好记的名字」，
      // 而不是想要两条一样的收藏。保留原 createdAt 以稳定排序。
      final updated = all[existingIndex].copyWith(title: site.title);
      all[existingIndex] = updated;
      await _persist(all);
      return updated;
    }

    all.insert(0, site);
    await _persist(all);
    return site;
  }

  Future<void> remove(String id) async {
    final all = await load();
    all.removeWhere((e) => e.id == id);
    await _persist(all);
  }

  /// 批量导入（朋友分享过来的）。返回真正新增的条数。
  Future<int> importAll(List<CustomSite> incoming) async {
    if (incoming.isEmpty) return 0;
    final all = await load();
    final known = all.map((e) => e.url).toSet();
    var added = 0;
    for (final site in incoming) {
      if (known.contains(site.url)) continue;
      all.insert(0, site);
      known.add(site.url);
      added++;
    }
    if (added > 0) await _persist(all);
    return added;
  }
}

/// 分享格式的编解码。
///
/// 刻意用可读 JSON 而不是压缩后的 base64：朋友那边导入失败时，
/// 用户能直接把内容贴过来给人看，排查成本低得多。
class CustomSiteShare {
  const CustomSiteShare._();

  static const int version = 1;

  static String encode(List<CustomSite> sites) => jsonEncode({
    'version': version,
    'kind': 'box_custom_sites',
    'sites': [for (final s in sites) s.toJson()],
  });

  /// 宽容解码：坏条目跳过，好条目保留。
  ///
  /// 也接受「只有一条裸对象」的形式 —— 用户很可能只把一条记录发过来。
  static List<CustomSite> decode(String raw) {
    if (raw.trim().isEmpty) return <CustomSite>[];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return <CustomSite>[];
    }

    Object? list;
    if (decoded is Map && decoded['sites'] is List) {
      list = decoded['sites'];
    } else if (decoded is List) {
      list = decoded;
    } else if (decoded is Map) {
      // 单条裸对象。
      final single = CustomSite.fromJson(decoded);
      return single == null ? <CustomSite>[] : <CustomSite>[single];
    }
    if (list is! List) return <CustomSite>[];

    final sites = <CustomSite>[];
    for (final item in list) {
      final site = CustomSite.fromJson(item);
      if (site != null) sites.add(site);
    }
    return sites;
  }
}
