import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/source_health_service.dart';
import 'book_source_model.dart';

class BookSourceManager extends ChangeNotifier {
  BookSourceManager(this._prefs);

  final SharedPreferences _prefs;

  static const String storageKey = 'novel_book_sources_v1';
  static const String currentSourceKey = 'novel_current_book_source_id_v1';

  final List<BookSourceModel> _items = [];
  String? _currentSourceId;

  late final SourceHealthService _healthService = SourceHealthService();

  List<BookSourceModel> get items => List.unmodifiable(_items);

  List<BookSourceModel> get enabledItems =>
      _items.where((e) => e.enabled).toList();

  /// 健康且启用的书源（用于搜索降级）
  List<BookSourceModel> get healthyEnabledItems {
    final now = DateTime.now();
    return _items.where((e) {
      if (!e.enabled) return false;
      final health = getHealth(e.id);
      if (health.status == SourceHealthStatus.unknown) return true; // 未检测时信任
      if (health.status == SourceHealthStatus.down) return false;
      // 缓存过期后也信任（可能只是临时故障）
      if (health.lastChecked != null &&
          now.difference(health.lastChecked!) > _healthService.cacheTtl) {
        return true;
      }
      return health.isUsable;
    }).toList();
  }

  String? get currentSourceId => _currentSourceId;

  BookSourceModel? get currentSource {
    final id = _currentSourceId;
    if (id == null || id.isEmpty) return null;

    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static List<BookSourceModel> decodeStoredList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <BookSourceModel>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <BookSourceModel>[];

      final result = <BookSourceModel>[];
      for (final e in decoded) {
        if (e is Map<String, dynamic>) {
          result.add(BookSourceModel.fromJson(e));
        } else if (e is Map) {
          result.add(BookSourceModel.fromJson(Map<String, dynamic>.from(e)));
        }
      }

      result.sort(sortComparator);
      return result;
    } catch (_) {
      return <BookSourceModel>[];
    }
  }

  static int sortComparator(BookSourceModel a, BookSourceModel b) {
    // 启用的排前面
    if (a.enabled != b.enabled) {
      return a.enabled ? -1 : 1;
    }

    // customOrder 越大越靠前
    final r2 = b.customOrder.compareTo(a.customOrder);
    if (r2 != 0) return r2;

    // weight 越大越靠前
    final r3 = b.weight.compareTo(a.weight);
    if (r3 != 0) return r3;

    // 名称升序
    return a.bookSourceName.compareTo(b.bookSourceName);
  }

  Future<void> load() async {
    final raw = _prefs.getString(storageKey);
    final savedCurrent = _prefs.getString(currentSourceKey);

    _items
      ..clear()
      ..addAll(decodeStoredList(raw));

    _currentSourceId = savedCurrent;
    _repairCurrentSourceId();

    notifyListeners();
  }

  Future<void> save() async {
    final raw = jsonEncode(_items.map((e) => e.toJson()).toList());
    await _prefs.setString(storageKey, raw);

    if (_currentSourceId == null || _currentSourceId!.trim().isEmpty) {
      await _prefs.remove(currentSourceKey);
    } else {
      await _prefs.setString(currentSourceKey, _currentSourceId!);
    }
  }

  Future<void> addOrUpdate(BookSourceModel source) async {
    final index = _items.indexWhere((e) => e.id == source.id);
    if (index >= 0) {
      _items[index] = source;
    } else {
      _items.add(source);
    }

    _sort();

    if (_currentSourceId == null && source.enabled) {
      _currentSourceId = source.id;
    }

    _repairCurrentSourceId();
    await save();
    notifyListeners();
  }

  Future<int> addMany(List<BookSourceModel> sources) async {
    var count = 0;

    for (final s in sources) {
      final index = _items.indexWhere((e) => e.id == s.id);
      if (index >= 0) {
        _items[index] = s;
      } else {
        _items.add(s);
      }
      count++;
    }

    _sort();

    _repairCurrentSourceId();
    await save();
    notifyListeners();
    return count;
  }

  Future<void> deleteById(String id) async {
    _items.removeWhere((e) => e.id == id);

    if (_currentSourceId == id) {
      _currentSourceId = null;
    }

    _repairCurrentSourceId();
    await save();
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final index = _items.indexWhere((e) => e.id == id);
    if (index < 0) return;

    _items[index] = _items[index].copyWith(enabled: enabled);

    if (!enabled && _currentSourceId == id) {
      _currentSourceId = null;
    }

    if (enabled && (_currentSourceId == null || _currentSourceId!.isEmpty)) {
      _currentSourceId = id;
    }

    _sort();
    _repairCurrentSourceId();
    await save();
    notifyListeners();
  }

  /// 批量增删书源：全部改完只写盘一次、只通知一次。
  ///
  /// 为什么需要它：[save] 是把整张书源表 jsonEncode 后写 SharedPreferences，
  /// 而 [addOrUpdate] / [deleteById] 每条都会调一次 save。云端同步 N 条时
  /// 就是 N 次全量序列化写盘（O(N²)）外加 N 次 notifyListeners 让列表抖 N 次。
  /// 实测 30 条 = 30 次写盘 / 12 条 = 12 次通知。
  ///
  /// [deleteIds] 先执行再应用 [upserts]，因为云端改名会让本地派生 id 变化，
  /// 调用方需要"先删旧 id 再写新条目"的顺序语义。
  ///
  /// 单条修改仍应走 [addOrUpdate] / [deleteById]，语义更直白。
  Future<void> applyBatch({
    Iterable<String> deleteIds = const <String>[],
    Iterable<BookSourceModel> upserts = const <BookSourceModel>[],
  }) async {
    final toDelete = deleteIds.toSet();
    var changed = false;

    if (toDelete.isNotEmpty) {
      final before = _items.length;
      _items.removeWhere((e) => toDelete.contains(e.id));
      if (_items.length != before) changed = true;
      if (_currentSourceId != null && toDelete.contains(_currentSourceId)) {
        _currentSourceId = null;
        changed = true;
      }
    }

    for (final source in upserts) {
      final index = _items.indexWhere((e) => e.id == source.id);
      if (index >= 0) {
        _items[index] = source;
      } else {
        _items.add(source);
      }
      changed = true;

      // 与 addOrUpdate 保持一致：没有选中源时，第一条可用书源自动成为当前源。
      if (_currentSourceId == null && source.enabled) {
        _currentSourceId = source.id;
      }
    }

    if (!changed) return;

    _sort();
    _repairCurrentSourceId();
    await save();
    notifyListeners();
  }

  Future<void> setCurrentSource(String id, {bool ensureEnabled = true}) async {
    final index = _items.indexWhere((e) => e.id == id);
    if (index < 0) return;

    if (ensureEnabled && !_items[index].enabled) {
      _items[index] = _items[index].copyWith(enabled: true);
    }

    _currentSourceId = id;

    _sort();
    _repairCurrentSourceId();
    await save();
    notifyListeners();
  }

  List<BookSourceModel> search(String keyword) {
    final q = keyword.trim().toLowerCase();
    if (q.isEmpty) return List.unmodifiable(_items);

    return _items.where((e) {
      return e.bookSourceName.toLowerCase().contains(q) ||
          e.bookSourceGroup.toLowerCase().contains(q) ||
          e.bookSourceUrl.toLowerCase().contains(q);
    }).toList();
  }

  Future<int> importFromText(String text) async {
    final sources = _parseSources(text);
    if (sources.isEmpty) return 0;
    return addMany(sources);
  }

  List<BookSourceModel> _parseSources(String text) => parseSources(text);

  /// 解析导入文本为书源列表。
  ///
  /// 逐条容错：数组里某一条畸形只跳过那一条，其余照常导入。
  /// 历史缺陷：`.map(fromJson)` 懒惰求值 + 外层 `catch (_)`，一条坏数据会让
  /// 整个 JSON 数组掉进「按段解析」兜底并得到 0 条 —— 用户导入 50 个源因为第 3
  /// 条字段类型错误导致一个都没进，且界面无任何提示。
  @visibleForTesting
  static List<BookSourceModel> parseSources(String text) {
    final t = text.trim();
    if (t.isEmpty) return [];

    try {
      if (t.startsWith('[')) {
        final decoded = jsonDecode(t);
        if (decoded is List) {
          // 逐条 try：跳过畸形条目而不是放弃整批。
          final parsed = <BookSourceModel>[];
          for (final e in decoded) {
            if (e is! Map) continue;
            try {
              parsed.add(BookSourceModel.fromJson(Map<String, dynamic>.from(e)));
            } catch (_) {
              // 单条畸形，跳过，不影响其余条目
            }
          }
          if (parsed.isNotEmpty) return parsed;
        }
      } else if (t.startsWith('{')) {
        final decoded = jsonDecode(t);
        if (decoded is Map) {
          return [BookSourceModel.fromJson(Map<String, dynamic>.from(decoded))];
        }
      }
    } catch (_) {
      // 如果不是标准 JSON，则继续尝试按段解析
    }

    final blocks = t.split(RegExp(r'\n\s*\n'));
    final result = <BookSourceModel>[];

    for (final block in blocks) {
      final b = block.trim();
      if (b.isEmpty) continue;
      try {
        final decoded = jsonDecode(b);
        if (decoded is Map) {
          result.add(
            BookSourceModel.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (e) {
        // 单条书源损坏只跳过这一条（不能让一条坏数据废掉整个书源列表），
        // 但要留线索：否则用户只看到「书源少了一个」而无从排查。
        debugPrint('[BookSourceManager] 跳过一条损坏的书源记录: $e');
      }
    }

    return result;
  }

  void _sort() {
    _items.sort(sortComparator);
  }

  void _repairCurrentSourceId() {
    final id = _currentSourceId;

    if (id != null && id.isNotEmpty) {
      for (final item in _items) {
        if (item.id == id && item.enabled) {
          return;
        }
      }
    }

    _currentSourceId = _pickFirstEnabledId();
  }

  String? _pickFirstEnabledId() {
    for (final item in _items) {
      if (item.enabled) return item.id;
    }
    return null;
  }

  // ── 健康检查 ──

  /// 获取指定书源的健康快照
  SourceHealthSnapshot getHealth(String sourceId) {
    return _healthService.getHealth(sourceId);
  }

  /// 检测所有已启用书源的健康状态
  Future<Map<String, SourceHealthSnapshot>> pingAll() async {
    final results = await _healthService.pingAll(enabledItems);
    notifyListeners();
    return results;
  }

  /// 检测单个书源的健康状态
  Future<SourceHealthSnapshot> ping(BookSourceModel source) async {
    final result = await _healthService.ping(source);
    notifyListeners();
    return result;
  }

  /// 清空健康缓存
  void clearHealthCache() {
    _healthService.clearCache();
    notifyListeners();
  }
}
