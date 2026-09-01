// lib/features/home/data/home_quick_action_prefs.dart
//
// 首页「快捷入口」的用户自选清单。
//
// 背景：原先快捷入口是 4 个硬编码卡片（工具/内容/AI 生图/扩展），
// 用户改不了。现在改成从已注册插件里自选，这里只负责存「选了哪些 id、
// 什么顺序」——插件的标题/图标/点击行为仍然由 HomePluginHost 提供，
// 避免同一份信息存两处后不一致（插件更名/下架时首页会显示脏数据）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:box/core/storage/cache_store.dart';

class HomeQuickActionPrefs {
  HomeQuickActionPrefs({CacheStore? cache})
    : _cache = cache ?? CacheStore(namespace: 'home_quick_actions');

  final CacheStore _cache;

  @visibleForTesting
  static const String storageKey = 'quick_action_ids_v1';

  /// 首页最多摆几个快捷入口。
  ///
  /// 定 8 个的理由：两列布局下正好 4 行，再多首屏就会把「今日热闻」
  /// 挤出可视区——首页的重点是内容，不是入口墙。
  static const int maxSlots = 8;

  /// 全新安装时的默认入口。
  ///
  /// 取的是内置插件里最常用的几个（id 必须与 HomePluginHost 内置插件一致，
  /// 对不上会在首页被过滤掉，由 home_quick_action_default_ids_test 钉住）。
  static const List<String> defaultIds = <String>[
    'builtin_quiz_plugin',
    'builtin_video_search',
    'builtin_novel_search',
    'builtin_image_generator',
  ];

  /// 是否已经有用户显式保存过（决定读不到时是否回落默认）。
  static const String _touchedKey = 'quick_action_touched_v1';

  List<String> _normalize(Iterable<String> raw) {
    final out = <String>[];
    for (final item in raw) {
      final id = item.trim();
      if (id.isEmpty) continue;
      if (out.contains(id)) continue;
      out.add(id);
      if (out.length >= maxSlots) break;
    }
    return out;
  }

  Future<List<String>> readSelectedIds() async {
    try {
      final raw = await _cache.read(storageKey);
      if (raw == null) {
        // 从未保存过 → 给默认；保存过又读不到（被清了）→ 也给默认。
        return _normalize(defaultIds);
      }

      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return _normalize(defaultIds);

      final ids = decoded['ids'];
      if (ids is! List) return _normalize(defaultIds);

      final parsed = <String>[];
      for (final entry in ids) {
        if (entry is String) parsed.add(entry);
      }

      // 空列表要区分「用户主动清空」和「数据坏了」：
      // 前者必须尊重（返回空），后者回落默认。靠 touched 标记区分。
      if (parsed.isEmpty) {
        final touched = await _cache.read(_touchedKey);
        if (touched == true || touched == 'true') return <String>[];
        return _normalize(defaultIds);
      }

      return _normalize(parsed);
    } catch (_) {
      return _normalize(defaultIds);
    }
  }

  Future<void> saveSelectedIds(List<String> ids) async {
    final normalized = _normalize(ids);
    try {
      await _cache.write(
        storageKey,
        jsonEncode(<String, dynamic>{'version': 1, 'ids': normalized}),
      );
      await _cache.write(_touchedKey, 'true');
    } catch (_) {
      // 存储失败不该让调用方崩，UI 上这次改动就当没生效。
    }
  }

  Future<void> add(String id) async {
    final current = await readSelectedIds();
    if (current.length >= maxSlots) return;
    if (current.contains(id.trim())) return;
    await saveSelectedIds(<String>[...current, id]);
  }

  Future<void> remove(String id) async {
    final current = await readSelectedIds();
    final target = id.trim();
    if (!current.contains(target)) return;
    await saveSelectedIds(current.where((e) => e != target).toList());
  }

  Future<void> toggle(String id) async {
    final current = await readSelectedIds();
    if (current.contains(id.trim())) {
      await remove(id);
    } else {
      await add(id);
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = await readSelectedIds();
    if (oldIndex < 0 || oldIndex >= current.length) return;
    if (newIndex < 0 || newIndex >= current.length) return;
    final next = List<String>.from(current);
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    await saveSelectedIds(next);
  }
}
