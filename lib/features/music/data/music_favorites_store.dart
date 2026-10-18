import 'package:box/core/storage/cache_store.dart';

/// 一条音乐收藏：一个音频地址 + 它的显示名。
///
/// 为什么只存「URL + 名称」这么少：目前音乐区的能力就是「贴一个音频地址，
/// 下载后播」。没有歌单、没有歌手元数据、没有在线源检索 —— 存多了都是猜的。
/// 等真有来源（订阅源 / 本地扫描）时再加字段，那时才知道该加什么。
class MusicFavorite {
  const MusicFavorite({
    required this.url,
    required this.title,
    required this.savedAt,
  });

  /// 音频地址（用户贴进来的那条）。
  final String url;

  /// 显示名。默认取 URL 的文件名，用户可改。
  final String title;

  /// 收藏时间（毫秒时间戳，用于排序与显示）。
  final int savedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'title': title,
    'savedAt': savedAt,
  };

  /// 从存储里读回一条。字段缺失/类型不对时返回 null（跳过坏条目，
  /// 不让一条脏数据把整个收藏库读崩）。
  static MusicFavorite? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = (raw['url'] ?? '').toString().trim();
    if (url.isEmpty) return null;
    final title = (raw['title'] ?? '').toString().trim();
    final savedAtRaw = raw['savedAt'];
    final savedAt = savedAtRaw is int
        ? savedAtRaw
        : int.tryParse('${savedAtRaw ?? ''}') ?? 0;
    return MusicFavorite(
      url: url,
      title: title.isEmpty ? _titleFromUrl(url) : title,
      savedAt: savedAt,
    );
  }

  /// 从 URL 末段取个像样的名字（`.../song.mp3` → `song`）。
  ///
  /// 取不到就回落成域名 —— 总比显示一整条几十字符的 URL 强。
  static String _titleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segs = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
      if (segs.isNotEmpty) {
        final last = segs.last;
        final dot = last.lastIndexOf('.');
        final name = dot > 0 ? last.substring(0, dot) : last;
        if (name.trim().isNotEmpty) return name.trim();
      }
      if (uri.host.isNotEmpty) return uri.host;
    } catch (_) {
      // 解析失败就用原串
    }
    return url;
  }
}

/// 音乐收藏的本地存储。
///
/// 为什么用 [CacheStore] 而不是新开一个 Hive box：
/// 漫画收藏（`comic_library`）和这个（`music_favorites`）是同一类东西 ——
/// 纯本地的用户数据、结构简单、需要 JSON 序列化。CacheStore 已经解决了
/// 「命名空间隔离 + 原子写 + 读坏时回落到空」这几件事，再开一个 Hive box
/// 只是多一种存储形态要维护。
class MusicFavoritesStore {
  MusicFavoritesStore({CacheStore? cacheStore})
    : _cache = cacheStore ?? CacheStore(namespace: 'music_favorites');

  final CacheStore _cache;

  /// 存储键。改这个字符串会让老用户的收藏读不出来。
  static const String storageKey = 'items';

  /// 读全部收藏，按收藏时间倒序（最近收的排前面）。
  ///
  /// 读失败/内容坏掉一律返回空列表：收藏库是只读展示，
  /// 不该因为存储异常把整页弄崩。
  Future<List<MusicFavorite>> load() async {
    try {
      final raw = await _cache.read(storageKey);
      // 返回的必须是**可变**列表：add() 要往里 insert。
      // 这里曾经写成 `return const <MusicFavorite>[]`，于是"收藏第二条"直接
      // 抛 Unsupported operation（const 列表不可变）—— 单测当场抓到。
      if (raw is! List) return <MusicFavorite>[];
      final items = raw
          .map(MusicFavorite.fromJson)
          .whereType<MusicFavorite>()
          .toList();
      items.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return items;
    } catch (_) {
      return <MusicFavorite>[];
    }
  }

  /// 是否已收藏同一个地址（用于「已收藏」状态与去重）。
  Future<bool> contains(String url) async {
    final target = url.trim();
    if (target.isEmpty) return false;
    final items = await load();
    return items.any((e) => e.url == target);
  }

  /// 收藏一条。同一个 URL 重复收藏视为幂等（不报错，也不产生两条）。
  ///
  /// 返回 true 表示这次真的新增了；false 表示已存在或参数非法。
  Future<bool> add({required String url, String? title}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;

    final items = await load();
    if (items.any((e) => e.url == trimmed)) return false;

    final item = MusicFavorite(
      url: trimmed,
      title: (title ?? '').trim().isEmpty
          ? MusicFavorite.fromJson(<String, dynamic>{'url': trimmed})!.title
          : title!.trim(),
      savedAt: DateTime.now().millisecondsSinceEpoch,
    );
    items.insert(0, item);
    await _persist(items);
    return true;
  }

  /// 取消收藏（按 URL 精确匹配）。返回是否真的删掉了。
  Future<bool> remove(String url) async {
    final target = url.trim();
    final items = await load();
    final before = items.length;
    items.removeWhere((e) => e.url == target);
    if (items.length == before) return false;
    await _persist(items);
    return true;
  }

  Future<void> _persist(List<MusicFavorite> items) {
    return _cache.write(
      storageKey,
      items.map((e) => e.toJson()).toList(growable: false),
    );
  }
}
