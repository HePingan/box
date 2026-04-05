import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../models/history_item.dart';

class HistoryController extends ChangeNotifier {
  static const String _boxName = 'play_history';

  List<HistoryItem> _historyList = [];
  List<HistoryItem> get historyList => _historyList;

  Future<void> loadHistory() async {
    final box = await Hive.openBox(_boxName);
    _historyList = box.values
        .whereType<Map>()
        .map((e) => HistoryItem.fromMap(Map<dynamic, dynamic>.from(e)))
        .toList()
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

    final box = await Hive.openBox(_boxName);
    await box.put(vodId, item.toMap());

    _historyList = box.values
        .whereType<Map>()
        .map((e) => HistoryItem.fromMap(Map<dynamic, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => b.updateTime.compareTo(a.updateTime));

    notifyListeners();
  }

  Future<void> deleteHistory(String vodId) async {
    final box = await Hive.openBox(_boxName);
    await box.delete(vodId);
    await loadHistory();
  }

  Future<void> clearHistory() async {
    final box = await Hive.openBox(_boxName);
    await box.clear();
    _historyList = [];
    notifyListeners();
  }
}