// test/features/home/daily_news_service_test.dart
//
// 今日热闻数据层契约。
//
// 抽出来之前这段逻辑长在 _fetchDailyNews 里，有四个问题，每条对应下面一组测试：
//   1. Future.wait 任一请求抛异常 → 两个都丢，即使另一个已经成功返回
//   2. allItems.shuffle() → 每次下拉刷新顺序全变，用户读到一半的位置就没了
//   3. 无缓存 → 每次重建页面都打网络，离线时首页热闻直接空白
//   4. 错误文案被塞成一条 _NewsItem(isPlaceholder: true) → 数据和错误态混在一个列表里
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/home/data/daily_news_service.dart';

/// 造一条知乎日报格式的 stories 响应。
String _body(List<Map<String, String>> stories) {
  return jsonEncode(<String, dynamic>{
    'stories': stories
        .map((s) => <String, dynamic>{'title': s['title'], 'url': s['url']})
        .toList(),
  });
}

/// bytes 而不是 String：http.Response(String, ...) 按 latin1 编码，
/// 中文标题会被拆成乱码，解析出来的断言就跟真实行为不符了。
http.Response _ok(String body) =>
    http.Response.bytes(utf8.encode(body), 200);

void main() {
  group('部分成功不该丢数据', () {
    test('第二个请求抛异常时，第一个的结果仍然要用上', () async {
      var calls = 0;
      final service = DailyNewsService(
        cache: CacheStore.inMemory('news_partial_throw'),
        get: (uri) async {
          calls++;
          if (uri.path.contains('before')) {
            throw http.ClientException('boom');
          }
          return _ok(_body([
            {'title': '今日头条一', 'url': 'https://a.example/1'},
          ]));
        },
      );

      final feed = await service.fetch();

      expect(calls, 2, reason: '两个端点都该被请求');
      expect(feed.hasError, isFalse, reason: '有数据就不算失败');
      expect(feed.items.map((e) => e.title), ['今日头条一']);
    });

    test('第一个请求超时时，第二个的结果仍然要用上', () async {
      final service = DailyNewsService(
        cache: CacheStore.inMemory('news_partial_timeout'),
        get: (uri) async {
          if (uri.path.contains('latest')) {
            throw http.ClientException('timeout');
          }
          return _ok(_body([
            {'title': '昨日头条一', 'url': 'https://a.example/2'},
          ]));
        },
      );

      final feed = await service.fetch();
      expect(feed.items.map((e) => e.title), ['昨日头条一']);
      expect(feed.hasError, isFalse);
    });

    test('一个返回非 200、另一个正常时，正常那个要保留', () async {
      final service = DailyNewsService(
        cache: CacheStore.inMemory('news_partial_500'),
        get: (uri) async {
          if (uri.path.contains('before')) {
            return http.Response.bytes(utf8.encode('server error'), 500);
          }
          return _ok(_body([
            {'title': '仅今日', 'url': 'https://a.example/3'},
          ]));
        },
      );

      final feed = await service.fetch();
      expect(feed.items.map((e) => e.title), ['仅今日']);
    });

    test('两个都失败才算错误，且不返回任何条目', () async {
      final service = DailyNewsService(
        cache: CacheStore.inMemory('news_all_fail'),
        get: (_) async => throw http.ClientException('down'),
      );

      final feed = await service.fetch();
      expect(feed.hasError, isTrue);
      expect(feed.items, isEmpty);
      // 错误态是 feed 上的一个标志，不是伪装成新闻的一条 item。
      expect(feed.errorMessage, isNotEmpty);
    });
  });

  group('排序必须稳定', () {
    test('同样的响应连续取两次，顺序完全一致', () async {
      String body() => _body([
            {'title': 'A', 'url': 'https://a.example/a'},
            {'title': 'B', 'url': 'https://a.example/b'},
            {'title': 'C', 'url': 'https://a.example/c'},
            {'title': 'D', 'url': 'https://a.example/d'},
            {'title': 'E', 'url': 'https://a.example/e'},
          ]);

      Future<List<String>> once(String ns) async {
        final service = DailyNewsService(
          cache: CacheStore.inMemory(ns),
          get: (_) async => _ok(body()),
        );
        final feed = await service.fetch();
        return feed.items.map((e) => e.title).toList();
      }

      // 不同 namespace，排除缓存命中造成的「假稳定」。
      final first = await once('news_stable_1');
      final second = await once('news_stable_2');

      expect(first, second, reason: 'shuffle 会让这条随机失败');
      expect(first, isNotEmpty);
    });

    test('今日的条目排在昨日之前', () async {
      final service = DailyNewsService(
        cache: CacheStore.inMemory('news_today_first'),
        get: (uri) async {
          if (uri.path.contains('before')) {
            return _ok(_body([
              {'title': '昨日一', 'url': 'https://a.example/y1'},
            ]));
          }
          return _ok(_body([
            {'title': '今日一', 'url': 'https://a.example/t1'},
          ]));
        },
      );

      final feed = await service.fetch();
      expect(feed.items.first.title, '今日一', reason: '新的应该在前');
      expect(feed.items.map((e) => e.title), ['今日一', '昨日一']);
    });
  });

  group('去重与条数', () {
    test('两个端点返回同一条新闻时只保留一条', () async {
      final service = DailyNewsService(
        cache: CacheStore.inMemory('news_dedup'),
        get: (_) async => _ok(_body([
          {'title': '重复标题', 'url': 'https://a.example/same'},
        ])),
      );

      final feed = await service.fetch();
      expect(feed.items.length, 1);
    });

    test('取回条数不超过 take', () async {
      final service = DailyNewsService(
        cache: CacheStore.inMemory('news_take'),
        get: (_) async => _ok(_body([
          for (var i = 0; i < 20; i++)
            {'title': '标题$i', 'url': 'https://a.example/$i'},
        ])),
      );

      final feed = await service.fetch(take: 3);
      expect(feed.items.length, 3);
    });

    test('标题为空的条目被跳过', () async {
      final service = DailyNewsService(
        cache: CacheStore.inMemory('news_empty_title'),
        get: (_) async => _ok(_body([
          {'title': '', 'url': 'https://a.example/blank'},
          {'title': '正常一条', 'url': 'https://a.example/ok'},
        ])),
      );

      final feed = await service.fetch();
      expect(feed.items.map((e) => e.title), ['正常一条']);
    });
  });

  group('缓存与降级', () {
    test('TTL 内第二次调用不再打网络', () async {
      var calls = 0;
      final cache = CacheStore.inMemory('news_cache_hit');
      DailyNewsService build() => DailyNewsService(
            cache: cache,
            get: (_) async {
              calls++;
              return _ok(_body([
                {'title': '缓存内容', 'url': 'https://a.example/c'},
              ]));
            },
          );

      await build().fetch();
      final hits = calls;
      final feed = await build().fetch();

      expect(calls, hits, reason: 'TTL 内不该再请求');
      expect(feed.items.map((e) => e.title), ['缓存内容']);
      expect(feed.fromCache, isTrue);
    });

    test('forceRefresh 绕过缓存', () async {
      var calls = 0;
      final cache = CacheStore.inMemory('news_force');
      DailyNewsService build() => DailyNewsService(
            cache: cache,
            get: (_) async {
              calls++;
              return _ok(_body([
                {'title': '第$calls次', 'url': 'https://a.example/$calls'},
              ]));
            },
          );

      await build().fetch();
      final before = calls;
      await build().fetch(forceRefresh: true);

      expect(calls, greaterThan(before), reason: '强制刷新必须打网络');
    });

    test('网络全挂但有旧缓存时，返回旧内容而不是错误', () async {
      final cache = CacheStore.inMemory('news_stale');

      // 先成功一次，把内容写进缓存。
      await DailyNewsService(
        cache: cache,
        get: (_) async => _ok(_body([
          {'title': '离线可读', 'url': 'https://a.example/off'},
        ])),
      ).fetch();

      // 再强制刷新且网络全挂 —— 此时不该把首页热闻清空。
      final feed = await DailyNewsService(
        cache: cache,
        get: (_) async => throw http.ClientException('offline'),
      ).fetch(forceRefresh: true);

      expect(feed.items.map((e) => e.title), ['离线可读']);
      expect(feed.fromCache, isTrue);
      expect(feed.hasError, isFalse, reason: '有内容可展示就不该报错');
    });

    test('响应体不是 JSON 时不抛异常', () async {
      final service = DailyNewsService(
        cache: CacheStore.inMemory('news_bad_json'),
        get: (_) async => http.Response.bytes(utf8.encode('<html>'), 200),
      );

      final feed = await service.fetch();
      expect(feed.hasError, isTrue);
      expect(feed.items, isEmpty);
    });

    test('stories 字段缺失时不抛异常', () async {
      final service = DailyNewsService(
        cache: CacheStore.inMemory('news_no_stories'),
        get: (_) async => _ok(jsonEncode(<String, dynamic>{'other': 1})),
      );

      final feed = await service.fetch();
      expect(feed.items, isEmpty);
      expect(feed.hasError, isTrue, reason: '拿不到任何内容等同失败');
    });
  });

  group('错误态与数据分离', () {
    test('失败的 feed 里没有伪装成新闻的提示条', () async {
      final service = DailyNewsService(
        cache: CacheStore.inMemory('news_no_placeholder'),
        get: (_) async => throw http.ClientException('down'),
      );

      final feed = await service.fetch();
      // 老实现会往 items 里塞一条「网络异常，请下拉刷新重试」。
      expect(feed.items, isEmpty);
      expect(
        feed.items.any((e) => e.title.contains('下拉刷新')),
        isFalse,
        reason: '提示文案不该出现在数据列表里',
      );
    });

    test('成功的 feed 上 errorMessage 为空', () async {
      final service = DailyNewsService(
        cache: CacheStore.inMemory('news_ok_no_error'),
        get: (_) async => _ok(_body([
          {'title': '正常', 'url': 'https://a.example/n'},
        ])),
      );

      final feed = await service.fetch();
      expect(feed.hasError, isFalse);
      expect(feed.errorMessage, isEmpty);
    });
  });
}
