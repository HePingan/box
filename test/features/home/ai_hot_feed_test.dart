// AI HOT 数据层契约测试。
//
// 用的是 2026-09-01 从 aihot.virxact.com 实测抓下来的真实响应片段，
// 不是我编的样例——字段名/类型/时间格式都以真实上游为准。
import 'dart:convert';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/home/data/ai_hot_models.dart';
import 'package:box/features/home/data/ai_hot_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 真实响应片段（take=2，已保留原始字段与类型）。
const String kRealResponse = '''
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
      final feed = AiHotFeed.fromJson(jsonDecode(kRealResponse));

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
      final feed = AiHotFeed.fromJson(jsonDecode(kRealResponse));
      final at = feed.items.first.publishedAt;
      expect(at, isNotNull);
      expect(at!.toUtc().year, 2026);
      expect(at.toUtc().month, 9);
      expect(at.toUtc().day, 1);
    });

    test('openUrl 优先站内 permalink 而不是站外原文', () {
      final feed = AiHotFeed.fromJson(jsonDecode(kRealResponse));
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

  group('AiHotService 缓存与降级', () {
    test('200 正常响应写入缓存并返回条目', () async {
      var calls = 0;
      final service = AiHotService(
        client: _stubClient((request) {
          calls++;
          expect(request.url.host, 'aihot.virxact.com');
          expect(
            request.url.queryParameters['mode'],
            'selected',
            reason: '首页应走每日精选，不是量大且杂的全量池',
          );
          return _json(kRealResponse);
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
          return _json(kRealResponse);
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

    test('take 参数被夹在合法区间内', () async {
      String? sentTake;
      final service = AiHotService(
        client: _stubClient((request) {
          sentTake = request.url.queryParameters['take'];
          return _json(kRealResponse);
        }),
        cache: CacheStore.inMemory('ai_hot_test_take'),
      );

      await service.fetchSelected(take: 999);
      expect(int.parse(sentTake!), lessThanOrEqualTo(50));
    });
  });
}

class _NetDown implements Exception {
  const _NetDown();
}
