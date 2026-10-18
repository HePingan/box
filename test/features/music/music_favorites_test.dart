// 音乐收藏：存储契约 + 收藏库接线。
//
// 这块的重点不是"能存能读"，而是几条容易漂的边界：
//   1. 同一个 URL 重复收藏必须幂等（不然收藏库会堆一串一模一样的条目）
//   2. 坏数据不能把整个收藏库读崩（跳过坏条目，其余照常）
//   3. 收藏库里的 `音乐收藏` 分区必须有数据源（以前 music 恒返回 const []）
import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/content/domain/warehouse_adapters.dart';
import 'package:box/features/content/domain/warehouse_models.dart';
import 'package:box/features/music/data/music_favorites_store.dart';
import 'package:flutter_test/flutter_test.dart';

MusicFavoritesStore _store(String ns) =>
    MusicFavoritesStore(cacheStore: CacheStore.inMemory(ns));

void main() {
  group('MusicFavorite 序列化', () {
    test('往返一致', () {
      const item = MusicFavorite(
        url: 'https://cdn.example.com/a.mp3',
        title: '歌名',
        savedAt: 1700000000000,
      );
      final back = MusicFavorite.fromJson(item.toJson())!;
      expect(back.url, item.url);
      expect(back.title, item.title);
      expect(back.savedAt, item.savedAt);
    });

    test('缺 url 的条目返回 null（跳过而不是崩）', () {
      expect(MusicFavorite.fromJson({'title': 'x'}), isNull);
      expect(MusicFavorite.fromJson({'url': '   '}), isNull);
      expect(MusicFavorite.fromJson('not a map'), isNull);
      expect(MusicFavorite.fromJson(null), isNull);
    });

    test('没给标题时从 URL 末段推断', () {
      final item = MusicFavorite.fromJson({
        'url': 'https://cdn.example.com/path/Song%20Name.mp3',
        'savedAt': 1,
      })!;
      expect(item.title, isNotEmpty);
      expect(item.title, isNot(contains('http')));
    });

    test('URL 解析失败也不抛', () {
      final item = MusicFavorite.fromJson({'url': 'not-a-url', 'savedAt': 1});
      expect(item, isNotNull);
      expect(item!.title, isNotEmpty);
    });

    test('savedAt 是字符串时也能读回', () {
      final item = MusicFavorite.fromJson({
        'url': 'https://a/b.mp3',
        'savedAt': '1700000000000',
      })!;
      expect(item.savedAt, 1700000000000);
    });
  });

  group('MusicFavoritesStore', () {
    test('空存储读出空列表', () async {
      expect(await _store('mf_empty').load(), isEmpty);
    });

    test('收藏后能读回，且最近的排前面', () async {
      final s = _store('mf_add');
      await s.add(url: 'https://a/1.mp3', title: '第一首');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await s.add(url: 'https://a/2.mp3', title: '第二首');

      final items = await s.load();
      expect(items.length, 2);
      expect(items.first.title, '第二首', reason: '按收藏时间倒序');
      expect(items.last.title, '第一首');
    });

    test('同一 URL 重复收藏是幂等的', () async {
      final s = _store('mf_dup');
      expect(await s.add(url: 'https://a/x.mp3'), isTrue);
      expect(await s.add(url: 'https://a/x.mp3'), isFalse,
          reason: '第二次不该新增，否则收藏库会堆重复条目');
      expect((await s.load()).length, 1);
    });

    test('空白 URL 不收藏', () async {
      final s = _store('mf_blank');
      expect(await s.add(url: '   '), isFalse);
      expect(await s.load(), isEmpty);
    });

    test('contains 判断按 URL 精确匹配', () async {
      final s = _store('mf_contains');
      await s.add(url: 'https://a/y.mp3');
      expect(await s.contains('https://a/y.mp3'), isTrue);
      expect(await s.contains('https://a/z.mp3'), isFalse);
      expect(await s.contains(''), isFalse);
    });

    test('remove 只删匹配项', () async {
      final s = _store('mf_remove');
      await s.add(url: 'https://a/1.mp3');
      await s.add(url: 'https://a/2.mp3');

      expect(await s.remove('https://a/1.mp3'), isTrue);
      expect((await s.load()).map((e) => e.url), ['https://a/2.mp3']);

      expect(await s.remove('https://a/不存在.mp3'), isFalse);
    });

    test('存储里是坏结构时读回空列表而不是抛', () async {
      final cache = CacheStore.inMemory('mf_corrupt');
      await cache.write(MusicFavoritesStore.storageKey, 'not-a-list');
      final s = MusicFavoritesStore(cacheStore: cache);
      expect(await s.load(), isEmpty);
    });

    test('列表里混了坏条目时，好的仍能读出来', () async {
      final cache = CacheStore.inMemory('mf_mixed');
      await cache.write(MusicFavoritesStore.storageKey, [
        {'url': 'https://a/good.mp3', 'title': '好的', 'savedAt': 2},
        {'title': '没有 url'},
        'garbage',
        null,
      ]);
      final s = MusicFavoritesStore(cacheStore: cache);
      final items = await s.load();
      expect(items.length, 1);
      expect(items.single.title, '好的');
    });
  });

  group('收藏库适配器', () {
    test('单条收藏 → WarehouseItem，分类是 music', () {
      const fav = MusicFavorite(
        url: 'https://cdn.example.com/song.mp3',
        title: '一首歌',
        savedAt: 42,
      );
      final item = warehouseItemFromMusicFavorite(fav);

      expect(item.category, WarehouseCategory.music);
      expect(item.title, '一首歌');
      expect(item.id, fav.url, reason: '音乐没有源+id，用 URL 当唯一键');
      expect(item.detailUrl, fav.url, reason: '点开即播，不是详情页');
      expect(item.sourceLabel, musicFavoriteSourceLabel);
      expect(item.subtitle, 'cdn.example.com', reason: '副标题显示域名，不是整条 URL');
      expect(item.createdAt, 42);
      expect(item.raw, same(fav));
    });

    test('批量转换保持顺序', () {
      final items = warehouseItemsFromMusicFavorites(const [
        MusicFavorite(url: 'https://a/1.mp3', title: '1', savedAt: 2),
        MusicFavorite(url: 'https://b/2.mp3', title: '2', savedAt: 1),
      ]);
      expect(items.map((e) => e.title), ['1', '2']);
    });

    test('分类标签与图标是音乐区的（不该退化成别的）', () {
      expect(WarehouseCategory.music.hubLabel, '音乐收藏');
      expect(WarehouseCategory.music.label, '音乐');
    });
  });
}
