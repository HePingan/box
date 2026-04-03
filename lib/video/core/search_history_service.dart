import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索历史服务 —— 持久化存储最近搜索词
class SearchHistoryService {
  SearchHistoryService._();
  static final SearchHistoryService instance = SearchHistoryService._();

  static const _key = 'video_search_history_v1';
  static const _maxCount = 15;

  List<String> _history = [];
  bool _loaded = false;

  List<String> get history => List.unmodifiable(_history);

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<String>();
        _history = list;
      } catch (_) {
        _history = [];
      }
    }
    _loaded = true;
  }

  Future<List<String>> load() async {
    await _ensureLoaded();
    return history;
  }

  Future<void> add(String keyword) async {
    if (keyword.trim().isEmpty) return;
    await _ensureLoaded();
    _history.remove(keyword);
    _history.insert(0, keyword);
    if (_history.length > _maxCount) _history = _history.sublist(0, _maxCount);
    await _persist();
  }

  Future<void> remove(String keyword) async {
    await _ensureLoaded();
    _history.remove(keyword);
    await _persist();
  }

  Future<void> clear() async {
    await _ensureLoaded();
    _history.clear();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_history));
  }

  /// 根据当前输入返回联想词（从历史中模糊匹配）
  List<String> suggest(String input) {
    if (input.trim().isEmpty) return List.unmodifiable(_history);
    final q = input.trim().toLowerCase();
    return _history.where((h) => h.toLowerCase().contains(q)).toList();
  }
}
