// AI HOT 数据层契约测试。
//
// 两份夹具都是**实测抓下来的真实响应**，不是我编的样例：
//   - kRealLegacyResponse：2026-09-01 从旧接口 /api/public/items 抓的（take=2）
//   - kRealV1Response：从 test/fixtures/ai_hot_selected_v1.json 读（上游真实快照，
//     每个分类一条；用 tool/refresh_ai_hot_fixture.py 刷新）
// 两份都要能解析：上游 2.0 换了接口与字段路径（2026-10-31 旧接口停用），
// 而**老版本 App 写进本机缓存的快照是旧形状**，升级后不能变成一片空白。
import 'dart:convert';
import 'dart:io';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/home/data/ai_hot_models.dart';
import 'package:box/features/home/data/ai_hot_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 真实响应片段（旧接口 take=2，已保留原始字段与类型）。
const String kRealLegacyResponse = '''
{
  "count": 2,
  "hasNext": true,
  "nextCursor": "eyJhIjoiMSJ9",
  "items": [
    {
      "id": "cmthxigqm04c1rofqqmk7pkqi",
      "title": "Anthropic 研究：训练一个错位的奖励寻求者模型",
      "title_en": "New research: Training a Misaligned Reward Seeker",
      "url": "https://x.com/AnthropicAI/status/2094577944056430865",
      "permalink": "https://aihot.virxact.com/items/cmthxigqm04c1rofqqmk7pkqi",
      "source": "X：Anthropic (@AnthropicAI)",
      "publishedAt": "2026-09-01T00:07:51.000Z",
      "discoveredAt": "2026-09-01T00:28:28.757Z",
      "summary": "Anthropic 发布新研究，探究奖励作弊是否会让模型学会不择手段追求奖励。",
      "category": "paper",
      "score": 73,
      "selected": true,
      "attribution": {
        "source": "AIHOT",
        "canonical": "https://aihot.virxact.com/items/cmthxigqm04c1rofqqmk7pkqi"
      }
    },
    {
      "id": "cmthxigqm04c2rofqqmk7pkqj",
      "title": "第二条测试标题",
      "url": "https://example.com/a",
      "permalink": "https://aihot.virxact.com/items/cmthxigqm04c2rofqqmk7pkqj",
      "source": "测试源",
      "publishedAt": "2026-08-31T22:00:00.000Z",
      "category": "ai-models",
      "score": 60,
      "selected": true,
      "attribution": {
        "source": "AIHOT",
        "canonical": "https://aihot.virxact.com/items/cmthxigqm04c2rofqqmk7pkqj"
      }
    }
  ]
}
''';

/// 真实响应快照（v1）：**从上游抓的，不是手写的**。
///
/// 353 的 bug 就坏在夹具是手写的 —— 那份「真实 permalink 形态」
/// （https://aihot.virxact.com/items/…）在上游响应里从来不出现，
/// 用例锁的是我们的假设而不是上游的事实，于是白名单写错主机也一路绿。
///
/// 现在夹具放在 test/fixtures/ai_hot_selected_v1.json，由
/// `python3 tool/refresh_ai_hot_fixture.py` 从 /api/v1/items 抓取
/// （每个分类留一条，字段字节未改）；刷新时 diff 直接看得出上游变了什么。
/// 发版前的活体闸门（tool/check_ai_hot_live.dart）再拿当天真响应复核一次。
final String kRealV1Response =
    File('test/fixtures/ai_hot_selected_v1.json').readAsStringSync();

/// 构造一个带 UTF-8 正文的响应。
///
/// 坑：`http.Response(String, ...)` 在没有 charset 的情况下用 **latin1**
/// 编码正文，正文里只要有中文就直接抛 `Invalid argument (string)`。
/// 真实服务端返回的是字节流（解码走 UTF-8，实测中文正常），
/// 所以这里必须用 `Response.bytes(utf8.encode(...))` 才能复现真实链路。
http.Response _json(String body, [int status = 200]) {
  return http.Response.bytes(
    utf8.encode(body),
    status,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

http.Client _stubClient(
  http.Response Function(http.Request request) handler,
) {
  return MockClient((request) async => handler(request));
}

void main() {
  group('AiHotFeed 解析真实响应', () {
    test('解析出全部条目与署名', () {
      final feed = AiHotFeed.fromJson(jsonDecode(kRealLegacyResponse));

      expect(feed.items, hasLength(2));
      expect(feed.items.first.title, contains('Anthropic'));
      expect(feed.items.first.category, 'paper');
      expect(feed.items.first.categoryLabel, '论文');
      expect(feed.items.first.score, 73);
      expect(
        feed.attributionSource,
        'AIHOT',
        reason: '使用 AI HOT 数据必须能拿到署名，UI 要展示出来',
      );
    });

    test('publishedAt 解析为时间且转本地时区', () {
      final feed = AiHotFeed.fromJson(jsonDecode(kRealLegacyResponse));
      final at = feed.items.first.publishedAt;
      expect(at, isNotNull);
      expect(at!.toUtc().year, 2026);
      expect(at.toUtc().month, 9);
      expect(at.toUtc().day, 1);
    });

    test('openUrl 优先站内 permalink 而不是站外原文', () {
      final feed = AiHotFeed.fromJson(jsonDecode(kRealLegacyResponse));
      expect(
        feed.items.first.openUrl,
        startsWith('https://aihot.virxact.com/items/'),
        reason: '回链应指向 AI HOT 站内页，既是署名要求也便于白名单管控',
      );
    });

    test('单条坏数据只跳过那条，不让整批丢失', () {
      final payload = <String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'id': 'ok', 'title': '正常一条'},
          <String, dynamic>{'id': 'no-title'},
          'not-a-map',
          <String, dynamic>{'title': '缺 id'},
          42,
        ],
      };

      final feed = AiHotFeed.fromJson(payload);
      expect(
        feed.items.map((e) => e.id),
        <String>['ok'],
        reason: '外部 JSON 必须逐条容错，一条坏数据不能连坐整批',
      );
    });

    test('score 为 double 或字符串时不崩', () {
      final feed = AiHotFeed.fromJson(<String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'id': 'a', 'title': 'A', 'score': 73.6},
          <String, dynamic>{'id': 'b', 'title': 'B', 'score': '42'},
          <String, dynamic>{'id': 'c', 'title': 'C', 'score': <int>[1]},
        ],
      });

      expect(feed.items, hasLength(3));
      expect(feed.items[0].score, 74);
      expect(feed.items[1].score, 42);
      expect(feed.items[2].score, isNull);
    });

    test('未知分类回显原值而不是硬编码「其它」', () {
      final feed = AiHotFeed.fromJson(<String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'id': 'a', 'title': 'A', 'category': 'brand-new'},
        ],
      });
      expect(feed.items.first.categoryLabel, 'brand-new');
    });

    test('attributionLabel 在上游没给署名时仍有回落值', () {
      final feed = AiHotFeed.fromJson(<String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'id': 'a', 'title': 'A'},
        ],
      });
      expect(feed.attributionLabel, isNotEmpty);
    });
  });

  group('AiHotFeed 解析 v1 真实响应', () {
    test('v1 的 links / source / attribution 都能读出来', () {
      final feed = AiHotFeed.fromJson(jsonDecode(kRealV1Response));
      expect(feed.items, isNotEmpty, reason: '夹具空了，下面的断言就是空的');

      for (final AiHotItem item in feed.items) {
        expect(item.title, isNotEmpty);
        expect(
          item.permalink,
          startsWith('https://aihot.news/items/'),
          reason: 'v1 把站内条目页挪到了 links.aihot',
        );
        expect(
          item.source,
          isNotEmpty,
          reason: 'v1 把来源挪到了 source.name，读不到就会少一行信息',
        );
      }
      expect(
        feed.attributionLabel,
        'AIHOT',
        reason: '署名在 attribution.name（旧接口叫 source）',
      );
    });

    test('快照里出现的每个分类都有中文标签（否则行上直接显示英文 slug）', () {
      final feed = AiHotFeed.fromJson(jsonDecode(kRealV1Response));
      expect(feed.items, isNotEmpty);

      final Map<String, String> seen = <String, String>{};
      for (final AiHotItem item in feed.items) {
        final String? category = item.category;
        if (category == null || category.isEmpty) continue;
        seen[category] = item.categoryLabel;
        expect(
          item.categoryLabel,
          isNot(category),
          reason: '分类 $category 没有中文标签 —— 上游新增分类时要在这里补一档',
        );
      }

      // 2026-10-02 实测上游精选在用的全部取值（名字照抄 /api/v1/agent 的官方说法）。
      // 这一行是这次修复的判据：修复前 ai-products / tip / industry 三档都落到
      // default、行上写着英文 slug。
      expect(
        seen.keys,
        containsAll(<String>['ai-models', 'ai-products', 'industry', 'paper', 'tip']),
      );
      expect(seen['ai-products'], '产品');
      expect(seen['industry'], '行业');
      expect(seen['tip'], '教程');
    });

    test('openUrl 在 v1 形状下仍优先站内条目页而不是原文', () {
      final feed = AiHotFeed.fromJson(jsonDecode(kRealV1Response));
      expect(
        feed.items.first.openUrl,
        startsWith('https://aihot.news/items/'),
        reason: '回链要指向 AI HOT 站内页（署名要求），原文链接只在没有站内页时用',
      );
    });

    test('老形状（旧接口/老缓存）照样能解析', () {
      final feed = AiHotFeed.fromJson(jsonDecode(kRealLegacyResponse));
      expect(feed.items, hasLength(2));
      expect(feed.items.first.permalink, startsWith('https://aihot.virxact.com/items/'));
    });
  });

  group('AiHotService 缓存与降级', () {
    test('200 正常响应写入缓存并返回条目', () async {
      var calls = 0;
      final service = AiHotService(
        client: _stubClient((request) {
          calls++;
          expect(request.url.host, 'aihot.news');
          expect(request.url.path, '/api/v1/items');
          expect(
            request.url.queryParameters['mode'],
            'selected',
            reason: '首页应走每日精选，不是量大且杂的全量池',
          );
          expect(
            request.url.queryParameters['window'],
            '7d',
            reason: '窗口必须是上游认的枚举值（实测 1h/6h/30d 直接 400）',
          );
          return _json(kRealLegacyResponse);
        }),
        cache: CacheStore.inMemory('ai_hot_test_ok'),
      );

      final feed = await service.fetchSelected();
      expect(feed.items, hasLength(2));
      expect(feed.fromCache, isFalse);
      expect(calls, 1);

      // 第二次应命中缓存，不再打网络（上游有限流，客户端别乱刷）。
      final again = await service.fetchSelected();
      expect(again.items, hasLength(2));
      expect(calls, 1, reason: 'TTL 内重复请求必须命中缓存');
    });

    test('网络 500 时降级到上次成功的缓存并标记 fromCache', () async {
      final cache = CacheStore.inMemory('ai_hot_test_fallback');
      var fail = false;

      final service = AiHotService(
        client: _stubClient((request) {
          if (fail) return _json('boom', 500);
          return _json(kRealLegacyResponse);
        }),
        cache: cache,
      );

      final first = await service.fetchSelected();
      expect(first.items, hasLength(2));

      fail = true;
      final second = await service.fetchSelected(forceRefresh: true);
      expect(
        second.items,
        hasLength(2),
        reason: '网络挂了应回落到上次内容，首页不该因为它空掉',
      );
      expect(
        second.fromCache,
        isTrue,
        reason: 'UI 需要知道这是离线内容才能给出提示',
      );
    });

    test('无缓存且网络异常时返回空而不抛异常', () async {
      final service = AiHotService(
        client: _stubClient((_) => throw const _NetDown()),
        cache: CacheStore.inMemory('ai_hot_test_empty'),
      );

      final feed = await service.fetchSelected();
      expect(feed.isEmpty, isTrue);
    });

    test('响应是合法 JSON 但 items 为空时也走降级', () async {
      final service = AiHotService(
        client: _stubClient((_) => _json('{"items":[]}')),
        cache: CacheStore.inMemory('ai_hot_test_emptyitems'),
      );
      final feed = await service.fetchSelected();
      expect(feed.isEmpty, isTrue);
    });

    test('响应体不是 JSON 时不抛异常', () async {
      final service = AiHotService(
        client: _stubClient((_) => _json('<html>502</html>')),
        cache: CacheStore.inMemory('ai_hot_test_html'),
      );
      final feed = await service.fetchSelected();
      expect(feed.isEmpty, isTrue);
    });

    test('limit 参数被夹在合法区间内，且不带旧参数名 take', () async {
      Map<String, String>? sentQuery;
      final service = AiHotService(
        client: _stubClient((request) {
          sentQuery = request.url.queryParameters;
          return _json(kRealV1Response);
        }),
        cache: CacheStore.inMemory('ai_hot_test_limit'),
      );

      await service.fetchSelected(take: 999);
      expect(int.parse(sentQuery!['limit']!), lessThanOrEqualTo(50));
      expect(
        sentQuery!.containsKey('take'),
        isFalse,
        reason: 'v1 只接受 OpenAPI 里声明过的参数，多带一个 take 就是 400',
      );
    });
  });
}

class _NetDown implements Exception {
  const _NetDown();
}
