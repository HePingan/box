import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../../novel/pages/reader/reader_paginator.dart';
import '../../comic/domain/comic_image_cache.dart';

/// Clears only regenerable presentation caches.
///
/// Account credentials, preferences, downloaded/offline books and user-created
/// content intentionally remain untouched.
class PersonalCenterCacheService {
  PersonalCenterCacheService({
    Future<void> Function()? clearNetworkCache,
    void Function()? clearReaderMemoryCache,
    Future<int> Function()? clearComicImageCache,
  }) : _clearNetworkCache =
           clearNetworkCache ?? (() => DefaultCacheManager().emptyCache()),
       _clearReaderMemoryCache =
           clearReaderMemoryCache ?? ReaderPaginator.clearCache,
       _clearComicImageCache = clearComicImageCache ?? ComicImageCache.clearAll;

  final Future<void> Function() _clearNetworkCache;
  final void Function() _clearReaderMemoryCache;

  /// 在线漫画的图片缓存（返回清出多少字节）。
  ///
  /// 为什么单独一份而不是塞进上面的网络缓存：它**不归** `DefaultCacheManager` 管 ——
  /// 漫画那套图自己落在 `${临时目录}/comic_online_images`，于是「清理缓存」一直清不到它，
  /// 而它恰恰是涨得最快的那一类（单话最多 209 张 ≈ 10MB，翻几本书就上百 MB）。
  final Future<int> Function() _clearComicImageCache;

  /// 清可再生缓存，返回**清出多少字节**（界面用它说人话：清出 77.2 MB）。
  ///
  /// 只统计漫画图片那部分：`DefaultCacheManager` 与阅读器内存缓存都不给"释放了多少"，
  /// 编一个数字出来比不报更糟。
  Future<int> clearRegenerableCaches() async {
    await _clearNetworkCache();
    _clearReaderMemoryCache();
    return _clearComicImageCache();
  }
}
