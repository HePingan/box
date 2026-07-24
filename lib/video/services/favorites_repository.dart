import 'package:hive_flutter/hive_flutter.dart';

import '../models/video_source.dart';

/// 收藏/追剧仓库（Hive 持久化）。
///
/// 键：`sourceKey::vodId`
/// 值：记录影片基本信息 + 来源，供收藏列表直接渲染并回跳详情页。
///
/// 说明：
/// - 用 sourceKey + vodId 组合唯一定位一部影片，避免不同源的同名/同 id 冲突。
/// - 收藏列表按加入时间倒序（最近收藏在前）。
class FavoritesRepository {
  static const String _boxName = 'video_favorites_box';

  Box<dynamic>? get _box {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    }
    return null;
  }

  Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
  }

  String _sourceKey(VideoSource source) {
    final id = source.id;
    if (id.trim().isNotEmpty && id != 'null') {
      return id.trim();
    }
    return source.url.trim();
  }

  String keyOf(VideoSource source, int vodId) {
    return '${_sourceKey(source)}::$vodId';
  }

  bool isFavorite(VideoSource source, int vodId) {
    return _box?.containsKey(keyOf(source, vodId)) ?? false;
  }

  Future<void> add(
    VideoSource source,
    int vodId, {
    required String vodName,
    String? vodPic,
    String? vodRemarks,
    String? typeName,
  }) async {
    await init();
    await Hive.box(_boxName).put(keyOf(source, vodId), <String, dynamic>{
      'sourceId': _sourceKey(source),
      'sourceName': source.name,
      'sourceUrl': source.url,
      'vodId': vodId,
      'vodName': vodName.trim(),
      'vodPic': vodPic?.trim(),
      'vodRemarks': vodRemarks?.trim(),
      'typeName': typeName?.trim(),
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> remove(VideoSource source, int vodId) async {
    await init();
    await Hive.box(_boxName).delete(keyOf(source, vodId));
  }

  /// 直接按存储键删除（收藏列表里没有 VideoSource 实例时使用）。
  Future<void> removeByKey(String key) async {
    await init();
    await Hive.box(_boxName).delete(key);
  }

  /// 全部收藏，按加入时间倒序。
  List<FavoriteItem> getAll() {
    final box = _box;
    if (box == null) return const [];

    final items = <FavoriteItem>[];
    for (final raw in box.values) {
      if (raw is Map) {
        final item = FavoriteItem.fromMap(Map<String, dynamic>.from(raw));
        if (item != null) items.add(item);
      }
    }
    items.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return items;
  }

  Future<void> clearAll() async {
    await init();
    await Hive.box(_boxName).clear();
  }
}

class FavoriteItem {
  const FavoriteItem({
    required this.sourceId,
    required this.sourceName,
    required this.sourceUrl,
    required this.vodId,
    required this.vodName,
    this.vodPic,
    this.vodRemarks,
    this.typeName,
    required this.savedAt,
  });

  final String sourceId;
  final String sourceName;
  final String sourceUrl;
  final int vodId;
  final String vodName;
  final String? vodPic;
  final String? vodRemarks;
  final String? typeName;
  final int savedAt;

  static FavoriteItem? fromMap(Map<String, dynamic> map) {
    final vodId = (map['vodId'] as num?)?.toInt();
    final vodName = (map['vodName'] as String?)?.trim() ?? '';
    if (vodId == null || vodName.isEmpty) return null;

    return FavoriteItem(
      sourceId: (map['sourceId'] as String?)?.trim() ?? '',
      sourceName: (map['sourceName'] as String?)?.trim() ?? '',
      sourceUrl: (map['sourceUrl'] as String?)?.trim() ?? '',
      vodId: vodId,
      vodName: vodName,
      vodPic: (map['vodPic'] as String?)?.trim(),
      vodRemarks: (map['vodRemarks'] as String?)?.trim(),
      typeName: (map['typeName'] as String?)?.trim(),
      savedAt: (map['savedAt'] as num?)?.toInt() ?? 0,
    );
  }
}
