import 'dart:async';

import 'package:flutter/material.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';
import '../../utils/app_logger.dart';

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

    AppLogger.instance.log(
      'search start source=${source.name} query="$query" url=${source.url}',
      tag: 'SEARCH',
    );

    if (query.isEmpty || source.url.trim().isEmpty) {
      _requestVersion++;
      _searchResults = [];
      _isSearching = false;
      _safeNotify();

      AppLogger.instance.log(
        'search cleared because query or source.url is empty',
        tag: 'SEARCH',
      );
      return;
    }

    final version = ++_requestVersion;

    _isSearching = true;
    _searchResults = [];
    _safeNotify();

    try {
      final results = await VideoApiService.searchVideo(source.url, query)
          .timeout(const Duration(seconds: 10));

      if (!_isCurrent(version)) {
        AppLogger.instance.log(
          'search ignored by version guard version=$version current=$_requestVersion',
          tag: 'SEARCH',
        );
        return;
      }

      _searchResults = results;

      AppLogger.instance.log(
        'search success source=${source.name} query="$query" count=${results.length}',
        tag: 'SEARCH',
      );
    } catch (e, st) {
      if (!_isCurrent(version)) {
        AppLogger.instance.log(
          'search failed but ignored by version guard version=$version current=$_requestVersion error=$e',
          tag: 'SEARCH',
        );
        return;
      }

      _searchResults = [];
      AppLogger.instance.log(
        'search failed source=${source.name} query="$query" error=$e',
        tag: 'SEARCH',
      );
      AppLogger.instance.log(
        st.toString(),
        tag: 'SEARCH',
      );
      debugPrint('搜索失败: $e');
    } finally {
      if (_isCurrent(version)) {
        _isSearching = false;
        _safeNotify();

        AppLogger.instance.log(
          'search finished source=${source.name} query="$query" isSearching=$_isSearching resultCount=${_searchResults.length}',
          tag: 'SEARCH',
        );
      }
    }
  }

  void clearSearch() {
    _requestVersion++;
    _searchResults = [];
    _isSearching = false;
    _safeNotify();

    AppLogger.instance.log(
      'search cleared manually',
      tag: 'SEARCH',
    );
  }
}