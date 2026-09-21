import 'package:flutter/material.dart';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/content/domain/warehouse_cleanup.dart'
    show warehouseNamespace;

enum WarehouseCategory { books, comics, videos, music }

extension WarehouseCategoryX on WarehouseCategory {
  String get label {
    switch (this) {
      case WarehouseCategory.books:
        return '书籍';
      case WarehouseCategory.comics:
        return '漫画';
      case WarehouseCategory.videos:
        return '影视';
      case WarehouseCategory.music:
        return '音乐';
    }
  }

  String get hubLabel {
    switch (this) {
      case WarehouseCategory.books:
        return '我的书架';
      case WarehouseCategory.comics:
        return '漫画收藏';
      case WarehouseCategory.videos:
        return '影视收藏';
      case WarehouseCategory.music:
        return '音乐收藏';
    }
  }

  IconData get icon {
    switch (this) {
      case WarehouseCategory.books:
        return Icons.auto_stories_outlined;
      case WarehouseCategory.comics:
        return Icons.collections_bookmark_outlined;
      case WarehouseCategory.videos:
        return Icons.movie_outlined;
      case WarehouseCategory.music:
        return Icons.library_music_outlined;
    }
  }

  Color get color {
    switch (this) {
      case WarehouseCategory.books:
        return Colors.orange;
      case WarehouseCategory.comics:
        return Colors.pink;
      case WarehouseCategory.videos:
        return Colors.indigo;
      case WarehouseCategory.music:
        return Colors.teal;
    }
  }
}

class WarehouseItem {
  const WarehouseItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.detailUrl,
    required this.meta,
    required this.category,
    required this.sourceLabel,
    required this.createdAt,
    this.raw,
  });

  final String id;
  final String title;
  final String subtitle;
  final String coverUrl;
  final String detailUrl;
  final String meta;
  final WarehouseCategory category;
  final String sourceLabel;
  final int createdAt;
  final dynamic raw;

  String get uniqueKey {
    final detail = detailUrl.trim();
    if (detail.isNotEmpty) return '${category.name}_$detail';
    return '${category.name}_${id.trim()}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'coverUrl': coverUrl,
      'detailUrl': detailUrl,
      'meta': meta,
      'category': category.name,
      'sourceLabel': sourceLabel,
      'createdAt': createdAt,
    };
  }

  factory WarehouseItem.fromJson(Map<String, dynamic> json) {
    final categoryName = json['category']?.toString() ?? 'books';
    final category = WarehouseCategory.values.firstWhere(
      (e) => e.name == categoryName,
      orElse: () => WarehouseCategory.books,
    );

    return WarehouseItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      detailUrl: json['detailUrl']?.toString() ?? '',
      meta: json['meta']?.toString() ?? '',
      category: category,
      sourceLabel: json['sourceLabel']?.toString() ?? manualSourceLabel,
      createdAt: _asInt(
        json['createdAt'],
        DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class WarehouseStore {
  WarehouseStore({CacheStore? cache})
    : _cache = cache ?? CacheStore(namespace: warehouseNamespace);

  final CacheStore _cache;

  String _key(WarehouseCategory category) => 'items_${category.name}';

  Future<List<WarehouseItem>> load(WarehouseCategory category) async {
    final raw = await _cache.read(_key(category));
    // 必须返回可变空列表：add()/remove() 会直接对返回值 removeWhere/insert，
    // 返回 const [] 会在「首次收藏（缓存里还没有这个 key）」时抛
    // Unsupported operation: Cannot remove from an unmodifiable list。
    if (raw is! List) return <WarehouseItem>[];

    final list = <WarehouseItem>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          list.add(WarehouseItem.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // ignore
        }
      }
    }

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> save(
    WarehouseCategory category,
    List<WarehouseItem> items,
  ) async {
    final normalized = <WarehouseItem>[];
    final seen = <String>{};

    for (final item in items) {
      if (seen.add(item.uniqueKey)) {
        normalized.add(item);
      }
    }

    normalized.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _cache.write(
      _key(category),
      normalized.map((e) => e.toJson()).toList(),
    );
  }

  Future<void> add(WarehouseItem item) async {
    final list = await load(item.category);
    list.removeWhere((e) => e.uniqueKey == item.uniqueKey);
    list.insert(0, item);
    await save(item.category, list);
  }

  Future<void> remove(WarehouseCategory category, String key) async {
    final list = await load(category);
    list.removeWhere((e) => e.uniqueKey == key);
    await save(category, list);
  }

  /// 手填收藏入口下线后的一次性清理。
  ///
  /// 手填对话框（`_showAddDialog`）是内容页 ＋ 和「导入资源」卡背后的同一个
  /// 实现，写出的条目 `sourceLabel == '手动收藏'`。入口撤掉后这些条目再没有
  /// 任何可维护它们的界面 —— 既不能编辑也不能新增，只能看着，属于死数据。
  ///
  /// 清理只动 `warehouse_center` 这个 namespace 里 `sourceLabel == '手动收藏'`
  /// 的条目。书架条目（`sourceLabel == '书架'`）来自
  /// `NovelModule.bookshelf` 实时同步，压根不落在这个 store 里，因此不受影响；
  /// 万一历史数据里混进了非手填条目，这里也会原样保留，不做连带删除。
  ///
  /// 幂等：重复调用只会返回 0。返回实际清理的条目数。
  Future<int> purgeManualEntries() async {
    var removed = 0;
    for (final category in WarehouseCategory.values) {
      final list = await load(category);
      if (list.isEmpty) continue;
      final kept = list
          .where((e) => e.sourceLabel != manualSourceLabel)
          .toList();
      final delta = list.length - kept.length;
      if (delta == 0) continue;
      await save(category, kept);
      removed += delta;
    }
    return removed;
  }
}

/// 手填收藏的来源标记。
///
/// 以前这个字符串在对话框构造处和 `fromJson` 兜底处各写一遍字面量，
/// 清理逻辑要认这个值，散着写迟早对不上。
const String manualSourceLabel = '手动收藏';

int _asInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}
