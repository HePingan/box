// 「随机一言 / 诗词一言」接线契约。
//
// 背景：工具页 112 个条目里只有 15 个可用（13.4%），`文本工具` 整类 23 条全是
// 占位——点了没反应。本轮把其中三条最容易落地的接上真实免费接口：
//
//   * 随机一言  → v1.hitokoto.cn      （本轮 curl 实测 5/5 成功，0.6~2.6s）
//   * 诗词一言  → v2.jinrishici.com   （本轮 curl 实测 5/5 成功，0.1~0.3s）
//
// 这两个都免密钥、无 quota 门槛。「六十秒读世界」同批实测只有 3/5，还撞到过
// 429 限流，所以这轮不接，留在占位区，免得给用户一个时常打不开的入口。
//
// 测试守的是「接线」这件事本身，不打真网：
//   1. registry 里有对应定义，id 唯一、分组合法；
//   2. `kToolTargets` 把中文条目名指到那个 id（可用性的唯一事实源）；
//   3. 面板 switch 有对应 case —— 缺 case 会掉进 `default:` 打开天气面板，
//      这正是之前「图书搜索开出天气」的原始 bug，必须钉死；
//   4. 客户端解析真实响应形状（用 mock 喂真样本，不裸连外网）。
library;

import 'dart:convert';

import 'package:box/features/api_hub/application/public_api_registry.dart';
import 'package:box/features/api_hub/data/public_api_client.dart';
import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 本轮 `curl https://v1.hitokoto.cn/` 的真实响应（原样保留字段）。
const _hitokotoSample = '''
{"id":9868,"uuid":"c291fbbe-4a0c-44e5-8a35-e2005889fb7c",
"hitokoto":"我们并不是什么童话故事，而是确确实实存在过。",
"type":"b","from":"葬送的芙莉莲","from_who":"辛美尔",
"creator":"Simon","creator_uid":17282,"reviewer":20537,
"commit_from":"web","created_at":"1713264360","length":22}
''';

/// 本轮 `curl https://v2.jinrishici.com/one.json` 的真实响应（截取必要字段）。
const _jinrishiciSample = '''
{"status":"success","data":{"id":"5b8b9572e116fb3714e6fa39",
"content":"白云一片去悠悠，青枫浦上不胜愁。","popularity":27500,
"origin":{"title":"春江花月夜","dynasty":"唐代","author":"张若虚",
"content":["春江潮水连海平，海上明月共潮生。","白云一片去悠悠，青枫浦上不胜愁。"],
"translate":["春天的江潮水势浩荡，与大海连成一片。"]},
"matchTags":["月"],"recommendedReason":"","cacheAt":"2026-09-09"}}
''';

http.Client _clientReturning(String body) {
  return MockClient((request) async {
    return http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

void main() {
  group('registry 定义', () {
    test('随机一言 / 诗词一言 都在 registry 里，且 id 不重复', () {
      final ids = PublicApiRegistry.all.map((e) => e.id).toList();

      expect(ids, contains('hitokoto'), reason: '随机一言缺 registry 定义');
      expect(ids, contains('poetry'), reason: '诗词一言缺 registry 定义');
      expect(ids.length, ids.toSet().length, reason: 'registry 有重复 id：$ids');
    });

    test('新条目的 group 必须是已声明的分组，否则分组筛选会漏掉它', () {
      for (final id in ['hitokoto', 'poetry']) {
        final tool = PublicApiRegistry.tryById(id);
        expect(tool, isNotNull, reason: '$id 不在 registry');
        expect(
          PublicApiRegistry.groups,
          contains(tool!.group),
          reason: '$id 的 group「${tool.group}」不在 groups 白名单，UI 筛不到',
        );
      }
    });
  });

  group('目录接线（唯一事实源）', () {
    test('中文条目名指向正确的 API Hub 面板 id', () {
      expect(kToolTargets['随机一言'], isA<ApiHubToolTarget>());
      expect((kToolTargets['随机一言']! as ApiHubToolTarget).toolId, 'hitokoto');

      expect(kToolTargets['诗词一言'], isA<ApiHubToolTarget>());
      expect((kToolTargets['诗词一言']! as ApiHubToolTarget).toolId, 'poetry');
    });

    test('接线后这两条从占位区消失，出现在可用名单里', () {
      expect(kAvailableToolNames, contains('随机一言'));
      expect(kAvailableToolNames, contains('诗词一言'));
    });

    test('所有 ApiHubToolTarget 的 id 在 registry 里真实存在', () {
      // 这条是通用护栏：防止再出现「图书搜索指向不存在的 books」那类拼错。
      for (final entry in kToolTargets.entries) {
        final target = entry.value;
        if (target is! ApiHubToolTarget) continue;
        final id = target.toolId;
        if (id == null) continue;
        expect(
          PublicApiRegistry.tryById(id),
          isNotNull,
          reason: '「${entry.key}」指向的 id「$id」在 registry 里不存在',
        );
      }
    });

    test('六十秒读世界 本轮复测 6/6 通过，已从占位区转正', () {
      // 上一轮实测 3/5 且撞过 429，当时按「稳了再接」原则留占位。
      // 本轮 A-1 用 tool/probe_60s.sh 间隔 4s 复测 6/6 全绿（HTTP 200，
      // 2328B 稳定载荷），失败原因是并发限流而非接口不稳定，故转正接线。
      // 若日后又出现大面积失败，把它从 kToolTargets 摘回占位区即可。
      expect(kAvailableToolNames, contains('六十秒读世界'));
    });
  });

  group('客户端解析真实响应形状', () {
    test('hitokoto：取出正文与出处', () async {
      final client = PublicApiClient(client: _clientReturning(_hitokotoSample));
      addTearDown(client.dispose);

      final result = await client.randomHitokoto();

      expect(result.text, '我们并不是什么童话故事，而是确确实实存在过。');
      expect(result.from, '葬送的芙莉莲');
      expect(result.fromWho, '辛美尔');
    });

    test('poetry：取出诗句、标题、朝代、作者', () async {
      final client = PublicApiClient(
        client: _clientReturning(_jinrishiciSample),
      );
      addTearDown(client.dispose);

      final result = await client.randomPoetry();

      expect(result.content, '白云一片去悠悠，青枫浦上不胜愁。');
      expect(result.title, '春江花月夜');
      expect(result.dynasty, '唐代');
      expect(result.author, '张若虚');
      expect(result.fullPoem, contains('春江潮水连海平，海上明月共潮生。'));
    });

    test('字段缺失或类型异常时不抛，退化成可展示的空值', () async {
      // 免费接口偶发返回残缺 JSON。裸 `as String` 会让整个面板炸掉，
      // 这里要求退化而不是崩。
      final client = PublicApiClient(
        client: _clientReturning('{"hitokoto":null,"from":123}'),
      );
      addTearDown(client.dispose);

      final result = await client.randomHitokoto();
      expect(result.text, isEmpty);
      expect(result.from, '123'); // 数字被 toString，不崩
    });

    test('HTTP 非 2xx 抛 ApiHubException，带可读文案', () async {
      final client = PublicApiClient(
        client: MockClient((_) async => http.Response('boom', 503)),
      );
      addTearDown(client.dispose);

      expect(
        () => client.randomHitokoto(),
        throwsA(
          isA<ApiHubException>().having(
            (e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });
  });
}
