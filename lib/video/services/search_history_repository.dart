import 'package:hive_flutter/hive_flutter.dart';

/// 聚合搜索历史 + 热词记忆（Hive 持久化）。
///
/// - 最近搜索：按最后一次搜索时间倒序，去重、限量。
/// - 热门搜索：按累计搜索次数倒序，反映高频关键词。
class SearchHistoryRepository {
  /// Hive box 名。默认聚合搜索历史；源内搜索传入独立名字，两者互不污染。
  final String _boxName;

  SearchHistoryRepository({String boxName = 'video_search_history_box'})
    : _boxName = boxName;

  /// 最多保留的历史条数
  static const int maxHistory = 20;

  /// 热词展示上限
  static const int maxHotWords = 10;

  Box<dynamic>? get _box {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<dynamic>(_boxName);
    }
    return null;
  }

  Future<Box<dynamic>> _ensureBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<dynamic>(_boxName);
    }
    return Hive.openBox<dynamic>(_boxName);
  }

  Future<void> init() => _ensureBox();

  List<_SearchRecord> _readAll() {
    final box = _box;
    if (box == null) return const [];

    final records = <_SearchRecord>[];
    for (final value in box.values) {
      if (value is Map) {
        final record = _SearchRecord.fromMap(Map<dynamic, dynamic>.from(value));
        if (record.keyword.isNotEmpty) records.add(record);
      }
    }
    return records;
  }

  /// 最近搜索（时间倒序）
  List<String> recentKeywords() {
    final records = _readAll()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return records
        .map((e) => e.keyword)
        .take(maxHistory)
        .toList(growable: false);
  }

  /// 热门搜索（次数倒序，次数相同再按时间倒序）
  List<String> hotKeywords() {
    final records = _readAll()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return records
        .where((e) => e.count > 1)
        .map((e) => e.keyword)
        .take(maxHotWords)
        .toList(growable: false);
  }

  /// 记录一次搜索：存在则次数 +1 并刷新时间，否则新建。
  Future<void> record(String rawKeyword) async {
    final keyword = rawKeyword.trim();
    if (keyword.isEmpty) return;

    final box = await _ensureBox();
    final key = keyword.toLowerCase();
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = box.get(key);
    if (existing is Map) {
      final record = _SearchRecord.fromMap(
        Map<dynamic, dynamic>.from(existing),
      );
      await box.put(
        key,
        record
            .copyWith(count: record.count + 1, updatedAt: now, keyword: keyword)
            .toMap(),
      );
    } else {
      await box.put(
        key,
        _SearchRecord(keyword: keyword, count: 1, updatedAt: now).toMap(),
      );
    }

    await _trim(box);
  }

  /// 删除单条历史
  Future<void> remove(String rawKeyword) async {
    final key = rawKeyword.trim().toLowerCase();
    if (key.isEmpty) return;
    final box = await _ensureBox();
    await box.delete(key);
  }

  /// 清空全部历史
  Future<void> clear() async {
    final box = await _ensureBox();
    await box.clear();
  }

  /// 超出上限时，按时间淘汰最旧的历史条目。
  Future<void> _trim(Box<dynamic> box) async {
    if (box.length <= maxHistory) return;
    final records = _readAll()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final removeCount = box.length - maxHistory;
    for (var i = 0; i < removeCount && i < records.length; i++) {
      await box.delete(records[i].keyword.toLowerCase());
    }
  }
}

class _SearchRecord {
  final String keyword;
  final int count;
  final int updatedAt;

  const _SearchRecord({
    required this.keyword,
    required this.count,
    required this.updatedAt,
  });

  _SearchRecord copyWith({String? keyword, int? count, int? updatedAt}) {
    return _SearchRecord(
      keyword: keyword ?? this.keyword,
      count: count ?? this.count,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'keyword': keyword,
    'count': count,
    'updatedAt': updatedAt,
  };

  factory _SearchRecord.fromMap(Map<dynamic, dynamic> map) {
    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return _SearchRecord(
      keyword: (map['keyword'] ?? '').toString().trim(),
      count: asInt(map['count']),
      updatedAt: asInt(map['updatedAt']),
    );
  }
}
