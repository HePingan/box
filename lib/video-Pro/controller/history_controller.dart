import 'package:flutter/material.dart';
import 'package:hive/hive.dart'; // 建议引入 hive 包，或用 SharedPreferences 代替
import '../models/history_item.dart';

/// 文件功能：播放历史状态管理
/// 实现：根据 vodId 更新进度、加载历史列表、清空历史
class HistoryController extends ChangeNotifier {
  static const String _boxName = "play_history";
  
  List<HistoryItem> _historyList = [];
  List<HistoryItem> get historyList => _historyList;

  // 1. 初始化并加载缓存的历史数据
  Future<void> loadHistory() async {
    var box = await Hive.openBox(_boxName);
    _historyList = box.values.map((e) => HistoryItem.fromMap(e)).toList();
    // 按时间倒序排列（最近看的排在前面）
    _historyList.sort((a, b) => b.updateTime.compareTo(a.updateTime));
    notifyListeners();
  }

  // 2. 保存或更新进度
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

    var box = await Hive.openBox(_boxName);
    // 以 vodId 为键，确保同一部片子只占一条历史记录
    await box.put(vodId, item.toMap());
    
    // 静默刷新内存中的列表，不一定要调 notifyListeners() 除非当前在历史页面
    _historyList = box.values.map((e) => HistoryItem.fromMap(e)).toList();
    _historyList.sort((a, b) => b.updateTime.compareTo(a.updateTime));
  }

  // 3. 删除某条历史
  Future<void> deleteHistory(String vodId) async {
    var box = await Hive.openBox(_boxName);
    await box.delete(vodId);
    await loadHistory();
  }
}