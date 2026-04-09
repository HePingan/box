import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../models/history_item.dart';

class HistoryController extends ChangeNotifier {
  static const String _boxName = 'play_history';

  Box<dynamic>? _box;
  final Map<String, int> _lastSavedPosition = {};

  List<HistoryItem> _historyList = [];
  List<HistoryItem> get historyList => List.unmodifiable(_historyList);

  Future<Box<dynamic>> _ensureBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    if (Hive.isBoxOpen(_boxName)) {
      _box = Hive.box<dynamic>(_boxName);
      return _box!;
    }
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

    final items = <HistoryItem>[];
    for (final value in box.values) {
      try {
        if (value is HistoryItem) {
          items.add(value);
        } else if (value is Map) {
          items.add(HistoryItem.fromMap(Map<dynamic, dynamic>.from(value)));
        }
      } catch (_) {
        // 跳过坏数据
      }
    }

    final dedup = <String, HistoryItem>{};
    for (final item in items) {
      dedup[item.storageKey] = item;
    }

    _historyList = dedup.values.toList()
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
    if (vodId.trim().isEmpty) return;
    if (position <= 0 || duration <= 0) return;

    final item = HistoryItem(
      vodId: vodId,
      vodName: vodName,
      vodPic: vodPic,
      sourceId: sourceId,
      sourceName: sourceName,
      episodeName: episodeName,
      episodeUrl: episodeUrl,
      position: position,
      duration: duration,
      updateTime: DateTime.now().millisecondsSinceEpoch,
    );

    final key = item.storageKey;

    // 同一位置短时间重复写入时，避免频繁落库
    final lastPosition = _lastSavedPosition[key];
    if (lastPosition != null && (position - lastPosition).abs() < 1000) {
      return;
    }

    final box = await _ensureBox();

    try {
      final existingRaw = box.get(key) ?? (key != vodId ? box.get(vodId) : null);
      if (existingRaw is Map) {
        final oldItem = HistoryItem.fromMap(Map<dynamic, dynamic>.from(existingRaw));
        final sameEpisode = oldItem.episodeUrl == item.episodeUrl;
        final sameDuration = oldItem.duration == item.duration;
        final closePosition = (oldItem.position - item.position).abs() < 1000;

        if (sameEpisode && sameDuration && closePosition) {
          _lastSavedPosition[key] = position;
          return;
        }
      } else if (existingRaw is HistoryItem) {
        final sameEpisode = existingRaw.episodeUrl == item.episodeUrl;
        final sameDuration = existingRaw.duration == item.duration;
        final closePosition = (existingRaw.position - item.position).abs() < 1000;

        if (sameEpisode && sameDuration && closePosition) {
          _lastSavedPosition[key] = position;
          return;
        }
      }

      await box.put(key, item.toMap());

      // 兼容旧 schema：旧数据以 vodId 作为 key
      if (key != vodId && box.containsKey(vodId)) {
        await box.delete(vodId);
      }

      _lastSavedPosition[key] = position;
      _upsertLocal(item);
    } catch (_) {
      // 保存失败不影响播放
    }
  }

  Future<void> deleteHistory(HistoryItem item) async {
    final box = await _ensureBox();

    try {
      await box.delete(item.storageKey);
      if (item.storageKey != item.vodId) {
        await box.delete(item.vodId);
      }
    } catch (_) {}

    _lastSavedPosition.remove(item.storageKey);
    _lastSavedPosition.remove(item.vodId);

    _historyList.removeWhere(
      (e) => e.storageKey == item.storageKey || (e.vodId == item.vodId && e.sourceId == item.sourceId),
    );
    notifyListeners();
  }

  Future<void> clearHistory() async {
    final box = await _ensureBox();
    await box.clear();
    _historyList = [];
    _lastSavedPosition.clear();
    notifyListeners();
  }
}