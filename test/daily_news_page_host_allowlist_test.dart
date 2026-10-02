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
// /api/v1/items 响应，只截到前两条，字段字节未改）。
import 'dart:convert';

import 'package:box/daily_news_url_policy.dart';
import 'package:box/features/home/data/ai_hot_models.dart';
import 'package:box/features/home/data/ai_hot_service.dart';
import 'package:box/features/home/data/daily_news_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实响应快照：AIHOT v1（/api/v1/items?mode=selected&window=7d&limit=2）。
const String kRealV1Response = r'''
{
 "schemaVersion": 1,
 "items": [
  {
   "id": "nab0yosxdtyh7sbvoo0usb1iq",
   "title": "Bloomberg：Anthropic 为可能估值近 2 万亿美元的 IPO 邀请机构投资者质询高管",
   "originalTitle": "Bloomberg: Anthropic has invited institutional investors to question its executives ahead of the possible IPO they value near $2T.",
   "summary": "Bloomberg 报道，Anthropic 已邀请机构投资者在其可能估值近 2 万亿美元的 IPO 前质询高管。10 月 14 日的会议之后，最早 11 月 9 日当周启动正式路演，感恩节前上市；按 SEC 规则需在 10 月下旬公布 S-1 文件。OpenAI 则相反，以安全担忧为由排除 2026 年上市，正以约 1.4 万亿美元估值私下寻求至少 300 亿美元融资。",
   "source": {
    "name": "X：Rohan Paul (@rohanpaul_ai)"
   },
   "links": {
    "aihot": "https://aihot.news/items/nab0yosxdtyh7sbvoo0usb1iq",
    "original": "https://x.com/rohanpaul_ai/status/2105921530211508488"
   },
   "publishedAt": "2026-10-02T07:23:13.000Z",
   "discoveredAt": "2026-10-02T07:36:32.395Z",
   "category": "industry",
   "score": 76,
   "selected": true,
   "reason": "原文梳理了 Anthropic 上市时间线和 OpenAI 的相反选择，读者可以对照两家头部 AI 公司的资本路径差异。",
   "attribution": {
    "name": "AIHOT",
    "url": "https://aihot.news/items/nab0yosxdtyh7sbvoo0usb1iq"
   }
  },
  {
   "id": "rn5q4m7qlqukq9q8g4ne975lj",
   "title": "Manus 分享视频生成与时间线编辑工作流",
   "originalTitle": "推出 Manus 2.0 视频编辑器：人人都能制作值得分享的视频",
   "summary": "Manus 分享使用既有视频能力的创作经验：先由 AI 搜索参考、制作镜头与代码视觉元素，再在 Manus Studio 的视频编辑器中逐轨调整画面、字幕、配乐和音效。教程还演示导入本地素材、自动转录与编排初剪，以及将长视频剪成短片；作者以 125 段旅行素材整理成约 11 分钟成片为例，说明如何把生成初稿继续打磨为可发布作品。",
   "source": {
    "name": "Manus：Blog（网页）"
   },
   "links": {
    "aihot": "https://aihot.news/items/rn5q4m7qlqukq9q8g4ne975lj",
    "original": "https://manus.im/zh-cn/blog/introducing-video-editor"
   },
   "publishedAt": "2026-09-30T16:00:00.000Z",
   "discoveredAt": "2026-10-02T03:59:23.719Z",
   "category": "tip",
   "score": 72,
   "selected": true,
   "reason": "作者结合真实项目，介绍从导入素材、转录和编排初剪，到逐轨调整字幕、画面与音频的工作流，读者可将这些方法用于自己的视频制作。",
   "attribution": {
    "name": "AIHOT",
    "url": "https://aihot.news/items/rn5q4m7qlqukq9q8g4ne975lj"
   }
  }
 ],
 "page": {
  "count": 4,
  "hasMore": true,
  "nextCursor": "it3.eyJhIjoxNzkwOTAxMjAzODk4LCJpIjoidWtrMnF3NWwxcjlqcWhzeWtxYWkyY2YzMCIsImMiOiJjMDlkODMzNGQ0M2MifQ"
 }
}
''';

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
