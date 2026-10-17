import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../../novel/pages/reader/reader_paginator.dart';
import '../../comic/domain/comic_image_cache.dart';
import '../../image_generator/data/ai_image_download_store.dart';

/// Clears only regenerable presentation caches.
///
/// Account credentials, preferences, downloaded/offline books and user-created
/// content intentionally remain untouched.
class PersonalCenterCacheService {
  PersonalCenterCacheService({
    Future<void> Function()? clearNetworkCache,
    void Function()? clearReaderMemoryCache,
    Future<int> Function()? clearComicImageCache,
    Future<int> Function()? clearAiImageDownloads,
  }) : _clearNetworkCache =
           clearNetworkCache ?? (() => DefaultCacheManager().emptyCache()),
       _clearReaderMemoryCache =
           clearReaderMemoryCache ?? ReaderPaginator.clearCache,
       _clearComicImageCache = clearComicImageCache ?? ComicImageCache.clearAll,
       _clearAiImageDownloads =
           clearAiImageDownloads ?? _defaultClearAiImageDownloads;

  final Future<void> Function() _clearNetworkCache;
  final void Function() _clearReaderMemoryCache;

  /// 在线漫画的图片缓存（返回清出多少字节）。
  ///
  /// 为什么单独一份而不是塞进上面的网络缓存：它**不归** `DefaultCacheManager` 管 ——
  /// 漫画那套图自己落在 `${临时目录}/comic_online_images`，于是「清理缓存」一直清不到它，
  /// 而它恰恰是涨得最快的那一类（单话最多 209 张 ≈ 10MB，翻几本书就上百 MB）。
  final Future<int> Function() _clearComicImageCache;

  /// AI 生图下载留下的中间文件（`应用文档目录/box_downloads`，返回清出多少字节）。
  ///
  /// 它同样不归 `DefaultCacheManager` 管。正常情况下保存到相册 / 分享之后会就地删掉，
  /// 但「进程被杀」「删文件失败」这两条路会留下残骸，所以清理入口也要收得到。
  final Future<int> Function() _clearAiImageDownloads;

  static Future<int> _defaultClearAiImageDownloads() =>
      AiImageDownloadStore().clear();

  /// 清可再生缓存，返回**清出多少字节**（界面用它说人话：清出 77.2 MB）。
  ///
  /// 只统计漫画图片那部分：`DefaultCacheManager` 与阅读器内存缓存都不给"释放了多少"，
  /// 编一个数字出来比不报更糟。
  Future<int> clearRegenerableCaches() async {
    await _clearNetworkCache();
    _clearReaderMemoryCache();
    return await _clearComicImageCache() + await _clearAiImageDownloads();
  }
}
