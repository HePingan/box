import 'package:flutter/material.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';

class VideoController extends ChangeNotifier {
  List<VideoSource> _sources = [];
  List<VideoSource> get sources => _sources;

  VideoSource? _currentSource;
  VideoSource? get currentSource => _currentSource;

  List<VodItem> _videoList = [];
  List<VodItem> get videoList => _videoList;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  int _currentPage = 1;

  Future<void> initSources(String configUrl) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (configUrl.trim().isEmpty) {
        _sources = [];
        _currentSource = null;
        _videoList = [];
        _currentPage = 1;
        _isLoading = false;
        notifyListeners();
        return;
      }

      _sources = await VideoApiService.fetchSources(configUrl);
      _currentPage = 1;
      _videoList = [];
      _currentSource = _sources.isNotEmpty ? _sources.first : null;

      if (_currentSource == null) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      await fetchVideoList(isRefresh: true, force: true);
    } catch (_) {
      _sources = [];
      _currentSource = null;
      _videoList = [];
      _currentPage = 1;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setCurrentSource(VideoSource source) async {
    _currentSource = source;
    _currentPage = 1;
    _videoList = [];
    _isLoading = true;
    notifyListeners();

    await fetchVideoList(isRefresh: true, force: true);
  }

  Future<void> fetchVideoList({
    bool isRefresh = false,
    bool force = false,
  }) async {
    if (_currentSource == null || (_isLoading && !force)) return;

    if (isRefresh) {
      _currentPage = 1;
      _videoList = [];
    }

    _isLoading = true;
    notifyListeners();

    try {
      final List<VodItem> newList = await VideoApiService.fetchVideoList(
        baseUrl: _currentSource!.url,
        page: _currentPage,
      );

      if (newList.isNotEmpty) {
        _videoList.addAll(newList);
        _currentPage++;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}