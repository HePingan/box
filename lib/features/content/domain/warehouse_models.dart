import 'package:flutter/material.dart';

import 'package:box/core/storage/cache_store.dart';

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
      sourceLabel: json['sourceLabel']?.toString() ?? '手动收藏',
      createdAt: _asInt(
        json['createdAt'],
        DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class WarehouseStore {
  WarehouseStore({CacheStore? cache})
    : _cache = cache ?? CacheStore(namespace: 'warehouse_center');

  final CacheStore _cache;

  String _key(WarehouseCategory category) => 'items_${category.name}';

  Future<List<WarehouseItem>> load(WarehouseCategory category) async {
    final raw = await _cache.read(_key(category));
    if (raw is! List) return const [];

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
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}
