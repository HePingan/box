// 内嵌 WebView 地址策略的回归测试。
//
// 用户报的现象：「首页资讯的 AI 页签，点进去内容不对」——点任何一条 AI 热点，
// 打开的都是「视界日报」门户页，看不到那条热点。
// 根因：DailyNewsPage 的主机白名单里写的是**接口**主机 aihot.virxact.com，
// 而上游给的每条热点链接（links.aihot / permalink）主机是 aihot.news；
// 被判为不在白名单之后静默回落到门户页，一个字的提示都没有。
//
// 这个 bug 骗过上一版用例的地方值得留在这里：上一版用例自己手写了一个
// 'https://aihot.virxact.com/items/…' 当作「真实 permalink 形态」，
// 而真实响应里从来没有这个地址 —— 用例锁的是我们的假设，不是上游的事实。
// 所以本文件的主机/字段全部从下面这份**真实响应快照**里取（2026-10-02 抓的
// /api/v1/items 响应，每个分类一条，字段字节未改）。
import 'dart:convert';
import 'dart:io';

import 'package:box/daily_news_url_policy.dart';
import 'package:box/features/home/data/ai_hot_models.dart';
import 'package:box/features/home/data/ai_hot_service.dart';
import 'package:box/features/home/data/daily_news_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实响应快照：AIHOT v1（上游 /api/v1/items?mode=selected&window=7d&limit=50，
/// 每个分类留一条，字段字节未改）。**由 tool/refresh_ai_hot_fixture.py 抓取写盘**，
/// 不要再手写 —— 手写的那份正是 353 漏网的原因（见文件头）。
final String kRealV1Response =
    File('test/fixtures/ai_hot_selected_v1.json').readAsStringSync();

void main() {
  final AiHotFeed feed = AiHotFeed.fromJson(jsonDecode(kRealV1Response));

  group('真实响应里的每一条热点都必须能打开', () {
    test('快照本身有内容（否则下面的断言是空的）', () {
      expect(feed.items, isNotEmpty);
      expect(feed.attributionLabel, 'AIHOT');
    });

    test('每条 item 的 openUrl 原样通过白名单，不被换成门户页', () {
      for (final AiHotItem item in feed.items) {
        final String? openUrl = item.openUrl;
        expect(openUrl, isNotNull, reason: item.title);
        final DailyNewsTarget target = DailyNewsUrlPolicy.decide(openUrl);
        expect(
          target.isBlocked,
          isFalse,
          reason: '${item.title} 被判成站外链接（原地址 $openUrl）',
        );
        expect(
          target.uri.toString(),
          openUrl,
          reason: '${item.title} 被换成了 ${target.uri}，用户点进去就不是这条了',
        );
      }
    });

    test('快照里的 permalink 主机确实在白名单里', () {
      for (final AiHotItem item in feed.items) {
        final Uri uri = Uri.parse(item.permalink!);
        expect(
          DailyNewsUrlPolicy.allowedHosts,
          contains(uri.host),
          reason: '上游给的主机是 ${uri.host}；白名单漏了它就是这个 bug 复发',
        );
      }
    });

    test('解析出来的 permalink 是上游的 links.aihot，不是别的字段', () {
      final Map<String, dynamic> raw =
          jsonDecode(kRealV1Response) as Map<String, dynamic>;
      final List<dynamic> rawItems = raw['items'] as List<dynamic>;
      for (int i = 0; i < feed.items.length; i++) {
        final Map<String, dynamic> rawItem =
            Map<String, dynamic>.from(rawItems[i] as Map);
        expect(
          feed.items[i].permalink,
          (rawItem['links'] as Map)['aihot'],
          reason: 'v1 把 permalink 挪到了 links.aihot',
        );
        expect(
          feed.items[i].url,
          (rawItem['links'] as Map)['original'],
          reason: 'v1 把原文链接挪到了 links.original',
        );
      }
    });
  });

  group('「更多」的落点', () {
    test('AI HOT 站点首页能站内打开', () {
      final DailyNewsTarget target =
          DailyNewsUrlPolicy.decide(AiHotService.siteUrl);
      expect(target.isBlocked, isFalse);
      expect(target.uri.toString(), AiHotService.siteUrl);
    });

    test('知乎日报站点首页能站内打开（热闻「更多」的落点）', () {
      final DailyNewsTarget target =
          DailyNewsUrlPolicy.decide(DailyNewsService.siteUrl);
      expect(target.isBlocked, isFalse);
      expect(target.uri.toString(), DailyNewsService.siteUrl);
    });
  });

  group('打不开的地址要如实说明，不许静默换成别的站点', () {
    test('站外原文（x.com / 论文站）标成 blocked 并原样回传地址', () {
      for (final String raw in const <String>[
        'https://x.com/rohanpaul_ai/status/2105921530211508488',
        'https://arxiv.org/abs/2501.00001',
        'https://manus.im/zh-cn/blog/introducing-video-editor',
      ]) {
        final DailyNewsTarget target = DailyNewsUrlPolicy.decide(raw);
        expect(target.isBlocked, isTrue, reason: raw);
        expect(
          target.blockedUrl,
          raw,
          reason: '必须把用户点的那条地址原样交给他复制，不能吞掉',
        );
      }
    });

    test('resolve 在站外地址上仍回落到门户页（旧调用点的行为不变）', () {
      expect(
        DailyNewsUrlPolicy.resolve('https://evil.example.com/'),
        DailyNewsUrlPolicy.fallbackUri,
      );
    });
  });

  group('白名单没有被放开成任意站点', () {
    test('后缀相似的仿冒域名不允许', () {
      for (final String raw in const <String>[
        'https://aihot.news.evil.com/items/x',
        'https://notaihot.news/items/x',
        'https://xaihot.news/items/x',
        'https://aihot.virxact.com.evil.com/',
        'https://evil-daily.zhihu.com.story.com/',
      ]) {
        expect(
          DailyNewsUrlPolicy.isAllowed(Uri.parse(raw)),
          isFalse,
          reason: raw,
        );
      }
    });

    test('真子域允许', () {
      for (final String raw in const <String>[
        'https://cdn.aihot.news/items/x',
        'https://news-at-cdn.zhihu.com/story/1',
      ]) {
        expect(DailyNewsUrlPolicy.isAllowed(Uri.parse(raw)), isTrue, reason: raw);
      }
    });

    test('非 http(s) scheme 不允许', () {
      for (final String raw in const <String>[
        'javascript:alert(1)',
        'file:///etc/passwd',
        'intent://aihot.news/#Intent;scheme=https;end',
      ]) {
        expect(
          DailyNewsUrlPolicy.isAllowed(Uri.parse(raw)),
          isFalse,
          reason: raw,
        );
      }
    });
  });

  group('只有「没有地址」时才用门户页', () {
    test('空/非法 initialUrl 回落门户页且不标 blocked', () {
      for (final String? raw in <String?>[null, '', '   ', '::::not a uri']) {
        final DailyNewsTarget target = DailyNewsUrlPolicy.decide(raw);
        expect(target.uri, DailyNewsUrlPolicy.fallbackUri, reason: '$raw');
        expect(target.isBlocked, isFalse, reason: '$raw');
      }
    });

    test('视界日报门户本身仍在白名单里（插件入口在用）', () {
      expect(
        DailyNewsUrlPolicy.isAllowed(DailyNewsUrlPolicy.fallbackUri),
        isTrue,
      );
    });
  });
}
