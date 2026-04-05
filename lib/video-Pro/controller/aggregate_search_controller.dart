import 'package:flutter/material.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../models/aggregate_result.dart';
import '../services/video_api_service.dart';

/// 文件功能：多源聚合搜索控制
/// 实现：高并发请求、结果汇总、自动过滤无效源
class AggregateSearchController extends ChangeNotifier {
  List<AggregateResult> _allResults = [];
  List<AggregateResult> get allResults => _allResults;

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  // 核心方法：并发搜索所有源
  Future<void> searchAllSources(List<VideoSource> sources, String keyword) async {
    if (keyword.isEmpty) return;

    _isSearching = true;
    _allResults = [];
    notifyListeners();

    // 1. 构造并发任务列表
    // 只对已启用的源发起请求
    final activeSources = sources.where((s) => s.isEnabled).toList();

    // 2. 使用 Future.wait 同时启动所有 HTTP 请求
    // 我们将每个源的搜索包装成一个能容错的小任务
    List<Future<List<AggregateResult>>> searchTasks = activeSources.map((source) async {
      try {
        // 每个源的请求设置超时或捕获异常，防止一个坏站拖慢全局
        List<VodItem> results = await VideoApiService.searchVideo(source.url, keyword)
            .timeout(const Duration(seconds: 8)); // 8秒内没返回就放弃该源站
        
        // 将 VodItem 转换为带 Source 信息的 AggregateResult
        return results.map((v) => AggregateResult(source: source, video: v)).toList();
      } catch (e) {
        debugPrint("${source.name} 搜索失败或超时: $e");
        return <AggregateResult>[]; // 失败则返回空列表，不中断全局请求
      }
    }).toList();

    // 3. 并行执行并汇总结果
    List<List<AggregateResult>> allSubLists = await Future.wait(searchTasks);
    
    // 4. 将多维列表展平为单一结果集
    _allResults = allSubLists.expand((list) => list).toList();

    // 5. 排序优化（可选）：比如按更新时间排序，或按匹配度排序
    _allResults.sort((a, b) => (b.video.vodTime ?? "").compareTo(a.video.vodTime ?? ""));

    _isSearching = false;
    notifyListeners();
  }
}