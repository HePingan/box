import 'dart:async';

import 'package:flutter/material.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';

/// 单源搜索控制器
class VideoSearchController extends ChangeNotifier {
  List<VodItem> _searchResults = [];
  List<VodItem> get searchResults => List.unmodifiable(_searchResults);

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

  Future<void> search(VideoSource source, String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty || source.url.trim().isEmpty) {
      _requestVersion++;
      _searchResults = [];
      _isSearching = false;
      _safeNotify();
      return;
    }

    final version = ++_requestVersion;

    _isSearching = true;
    _searchResults = [];
    _safeNotify();

    try {
      final results = await VideoApiService.searchVideo(source.url, query)
          .timeout(const Duration(seconds: 10));

      if (!_isCurrent(version)) return;

      _searchResults = results;
    } catch (e) {
      if (!_isCurrent(version)) return;
      debugPrint('搜索失败: $e');
      _searchResults = [];
    } finally {
      if (_isCurrent(version)) {
        _isSearching = false;
        _safeNotify();
      }
    }
  }

  void clearSearch() {
    _requestVersion++;
    _searchResults = [];
    _isSearching = false;
    _safeNotify();
  }
}