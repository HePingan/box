import 'package:flutter/material.dart';

import '../models/video_source.dart';
import '../services/favorites_repository.dart';

/// 收藏/追剧控制器（Hive 持久化，跨页共享状态）。
///
/// 详情页收藏切换后调用 [reload]（或 [setFavoriteLocally]）即可让收藏页、
/// 首页入口等监听方实时刷新。
class FavoritesController extends ChangeNotifier {
  FavoritesController({FavoritesRepository? repository})
      : _repo = repository ?? FavoritesRepository();

  final FavoritesRepository _repo;

  List<FavoriteItem> _items = const [];
  List<FavoriteItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;
  int get count => _items.length;

  Future<void> load() async {
    await _repo.init();
    _items = _repo.getAll();
    notifyListeners();
  }

  bool isFavorite(VideoSource source, int vodId) {
    return _repo.isFavorite(source, vodId);
  }

  /// 切换收藏，返回切换后的状态（true=已收藏）。
  Future<bool> toggle(
    VideoSource source,
    int vodId, {
    required String vodName,
    String? vodPic,
    String? vodRemarks,
    String? typeName,
  }) async {
    await _repo.init();
    final nowFav = !_repo.isFavorite(source, vodId);
    if (nowFav) {
      await _repo.add(
        source,
        vodId,
        vodName: vodName,
        vodPic: vodPic,
        vodRemarks: vodRemarks,
        typeName: typeName,
      );
    } else {
      await _repo.remove(source, vodId);
    }
    _items = _repo.getAll();
    notifyListeners();
    return nowFav;
  }

  Future<void> removeItem(FavoriteItem item) async {
    await _repo.init();
    await _repo.removeByKey('${item.sourceId}::${item.vodId}');
    _items = _repo.getAll();
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _repo.init();
    await _repo.clearAll();
    _items = const [];
    notifyListeners();
  }
}
