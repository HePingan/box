import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../../novel/pages/reader/reader_paginator.dart';

/// Clears only regenerable presentation caches.
///
/// Account credentials, preferences, downloaded/offline books and user-created
/// content intentionally remain untouched.
class PersonalCenterCacheService {
  PersonalCenterCacheService({
    Future<void> Function()? clearNetworkCache,
    void Function()? clearReaderMemoryCache,
  }) : _clearNetworkCache =
           clearNetworkCache ?? (() => DefaultCacheManager().emptyCache()),
       _clearReaderMemoryCache =
           clearReaderMemoryCache ?? ReaderPaginator.clearCache;

  final Future<void> Function() _clearNetworkCache;
  final void Function() _clearReaderMemoryCache;

  Future<void> clearRegenerableCaches() async {
    await _clearNetworkCache();
    _clearReaderMemoryCache();
  }
}
