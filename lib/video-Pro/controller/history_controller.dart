import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:collection/collection.dart'; // 建议引入 collection 包以便使用 firstWhereOrNull

import '../models/history_item.dart';

class HistoryController extends ChangeNotifier {
  static const String _boxName = 'play_history';

  Box<dynamic>? _box;
  final Map<String, int> _lastSavedPosition = {};

  List<HistoryItem> _historyList = [];
  List<HistoryItem> get historyList => List.unmodifiable(_historyList);

  Future<Box<dynamic>> _ensureBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox<dynamic>(_boxName);
    return _box!;
  }

  void _upsertLocal(HistoryItem item) {
    _historyList.removeWhere((e) => e.storageKey == item.storageKey);
    _historyList.insert(0, item);
    notifyListeners();
  }

  Future<void> loadHistory() async {
    final box = await _ensureBox();
    final items = <String, HistoryItem>{};

    // 🏆 优化：在加载阶段一次性处理完 Map 与 Object 的兼容性，后续就全是干净数据了
    for (final value in box.values) {
      if (value == null) continue;
      try {
        final item = value is HistoryItem
            ? value
            : HistoryItem.fromMap(Map<dynamic, dynamic>.from(value));
        items[item.storageKey] = item;
      } catch (_) {}
    }

    _historyList = items.values.toList()
      ..sort((a, b) => b.updateTime.compareTo(a.updateTime));
    notifyListeners();
  }

  Future<void> saveProgress({
    required String vodId,
    required String vodName,
    required String vodPic,
    required String sourceId,
    required String sourceName,
    required String episodeName,
    required String episodeUrl,
    required int position,
    required int duration,
  }) async {
    if (vodId.trim().isEmpty || position <= 0 || duration <= 0) return;

    final item = HistoryItem(
      vodId: vodId, vodName: vodName, vodPic: vodPic,
      sourceId: sourceId, sourceName: sourceName,
      episodeName: episodeName, episodeUrl: episodeUrl,
      position: position, duration: duration,
      updateTime: DateTime.now().millisecondsSinceEpoch,
    );

    final key = item.storageKey;

    // 🏆 优化：直接使用内存里的数据做对比，不再高频读取 Hive
    final existingItem = _historyList.firstWhere(
        (e) => e.storageKey == key, 
        orElse: () => HistoryItem(vodId: '', vodName: '', vodPic: '', sourceId: '', sourceName: '', episodeName: '', episodeUrl: '', position: -1, duration: -1, updateTime: 0)
    );

    if (existingItem.vodId.isNotEmpty) {
      final sameEpisode = existingItem.episodeUrl == item.episodeUrl;
      final sameDuration = existingItem.duration == item.duration;
      final closePosition = (existingItem.position - item.position).abs() < 1000;

      // 如果差距小于 1 秒，直接砍掉这次落库操作
      if (sameEpisode && sameDuration && closePosition) return;
    }

    final box = await _ensureBox();
    try {
      await box.put(key, item.toMap());
      // 兼容旧 schema 清理
      if (key != vodId && box.containsKey(vodId)) await box.delete(vodId);
      
      _upsertLocal(item);
    } catch (_) {}
  }

  Future<void> deleteHistory(HistoryItem item) async {
    final box = await _ensureBox();
    await box.delete(item.storageKey);
    if (item.storageKey != item.vodId) await box.delete(item.vodId);

    _historyList.removeWhere((e) => e.storageKey == item.storageKey || (e.vodId == item.vodId && e.sourceId == item.sourceId));
    notifyListeners();
  }

  Future<void> clearHistory() async {
    final box = await _ensureBox();
    await box.clear();
    _historyList.clear();
    notifyListeners();
  }
}