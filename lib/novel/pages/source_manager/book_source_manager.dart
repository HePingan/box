import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book_source_model.dart';

class BookSourceManager extends ChangeNotifier {
  BookSourceManager(this._prefs);

  final SharedPreferences _prefs;

  static const String storageKey = 'novel_book_sources_v1';
  static const String currentSourceKey = 'novel_current_book_source_id_v1';

  final List<BookSourceModel> _items = [];
  String? _currentSourceId;

  List<BookSourceModel> get items => List.unmodifiable(_items);

  List<BookSourceModel> get enabledItems =>
      _items.where((e) => e.enabled).toList();

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

  List<BookSourceModel> _parseSources(String text) {
    final t = text.trim();
    if (t.isEmpty) return [];

    try {
      if (t.startsWith('[')) {
        final decoded = jsonDecode(t);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => BookSourceModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } else if (t.startsWith('{')) {
        final decoded = jsonDecode(t);
        if (decoded is Map) {
          return [
            BookSourceModel.fromJson(Map<String, dynamic>.from(decoded)),
          ];
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
          result.add(BookSourceModel.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {}
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
}