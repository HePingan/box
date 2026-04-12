import 'dart:async';

import 'package:flutter/material.dart';

import '../models/aggregate_result.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';
import '../video_module.dart';

/// 多源聚合搜索控制器
class AggregateSearchController extends ChangeNotifier {
  List<AggregateResult> _allResults = [];
  List<AggregateResult> get allResults => List.unmodifiable(_allResults);

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  int _requestVersion = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool _isCurrent(int version) => !_disposed && version == _requestVersion;

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> searchAllSources(
    List<VideoSource> sources,
    String keyword,
  ) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      _requestVersion++;
      _allResults = [];
      _isSearching = false;
      _safeNotify();
      return;
    }

    await VideoModule.ensureVisibilityLoaded();

    final activeSources = VideoModule.visibleSourcesOf(sources);

    final version = ++_requestVersion;

    _isSearching = true;
    _allResults = [];
    _safeNotify();

    try {
      final tasks = activeSources.map((source) async {
        try {
          final items = await VideoApiService.searchVideo(source.url, query)
              .timeout(const Duration(seconds: 8));

          return items
              .map((video) => AggregateResult(source: source, video: video))
              .toList();
        } catch (e) {
          debugPrint('${source.name} 搜索失败: $e');
          return <AggregateResult>[];
        }
      }).toList();

      final nested = await Future.wait(tasks);

      if (!_isCurrent(version)) return;

      final merged = nested.expand((e) => e).toList();

      merged.sort((a, b) {
        final sourceCmp = a.source.name.compareTo(b.source.name);
        if (sourceCmp != 0) return sourceCmp;
        return b.video.vodId.compareTo(a.video.vodId);
      });

      _allResults = merged;
    } finally {
      if (_isCurrent(version)) {
        _isSearching = false;
        _safeNotify();
      }
    }
  }
}