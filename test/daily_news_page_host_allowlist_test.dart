import 'package:box/daily_news_url_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// AI 热点「点击查看详情看不了」的回归测试。
///
/// 现象：点任何一条 AI 热点，打开的都是视界日报门户页，看不到那条热点。
/// 根因：DailyNewsPage 的主机白名单只有视界日报 + 知乎日报四个域名
/// （这页最早只给「今日热闻」用），AI 热点复用了同一个页面但
/// aihot.virxact.com 不在名单里，于是 initialUrl 被判为不允许，
/// 静默 fallback 到门户页，且不给任何提示。
void main() {
  group('AI HOT 详情页可以打开', () {
    test('permalink 站内详情页允许通过', () {
      // 真实 permalink 形态（实测 /api/public/items 响应）
      final uri = Uri.parse(
        'https://aihot.virxact.com/items/cmtjkp6dc02j5rori29u5h7kl',
      );
      expect(DailyNewsUrlPolicy.isAllowed(uri), isTrue);
    });

    test('站点根域允许通过（onOpenAll 走这里）', () {
      expect(
        DailyNewsUrlPolicy.isAllowed(Uri.parse('https://aihot.virxact.com/')),
        isTrue,
      );
    });

    test('resolve 不会把 AI 热点 permalink 吞成 fallback', () {
      const raw = 'https://aihot.virxact.com/items/cmtjkp6dc02j5rori29u5h7kl';
      expect(DailyNewsUrlPolicy.resolve(raw).toString(), raw);
    });
  });

  group('原有白名单不受影响', () {
    test('视界日报仍允许', () {
      expect(
        DailyNewsUrlPolicy.isAllowed(
          Uri.parse('https://actcpc.heytapimage.com/oh5/3/1/index.html#/'),
        ),
        isTrue,
      );
    });

    test('知乎日报及其子域仍允许', () {
      for (final host in const [
        'daily.zhihu.com',
        'news-at.zhihu.com',
        'news-at-cdn.zhihu.com',
      ]) {
        expect(
          DailyNewsUrlPolicy.isAllowed(Uri.parse('https://$host/story/1')),
          isTrue,
          reason: host,
        );
      }
    });
  });

  group('白名单没有被放开成任意站点', () {
    test('站外原文链接不允许在内嵌 WebView 打开', () {
      // AI 热点的 url 字段常是 x.com / 论文站，属于站外，
      // 不进白名单是有意的：内嵌 WebView 打不开也不该打开。
      for (final raw in const [
        'https://x.com/Meituan_LongCat/status/2094996391387111865',
        'https://arxiv.org/abs/2501.00001',
        'https://evil.example.com/',
      ]) {
        expect(
          DailyNewsUrlPolicy.isAllowed(Uri.parse(raw)),
          isFalse,
          reason: raw,
        );
      }
    });

    test('后缀相似的仿冒域名不允许', () {
      // endsWith('.$allowed') 不能被 'notaihot.virxact.com.evil.com' 之类骗过
      for (final raw in const [
        'https://aihot.virxact.com.evil.com/',
        'https://evil-aihot.virxact.com.attacker.net/',
        'https://xaihot.virxact.com/',
      ]) {
        expect(
          DailyNewsUrlPolicy.isAllowed(Uri.parse(raw)),
          isFalse,
          reason: raw,
        );
      }
    });

    test('非 http(s) scheme 不允许', () {
      for (final raw in const [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'intent://aihot.virxact.com/#Intent;scheme=https;end',
      ]) {
        expect(
          DailyNewsUrlPolicy.isAllowed(Uri.parse(raw)),
          isFalse,
          reason: raw,
        );
      }
    });

    test('子域允许但要真的是子域', () {
      expect(
        DailyNewsUrlPolicy.isAllowed(Uri.parse('https://cdn.aihot.virxact.com/x')),
        isTrue,
      );
    });
  });

  group('resolve 兜底行为', () {
    test('空/非法 initialUrl 回落到门户页', () {
      for (final raw in <String?>[null, '', '   ', '::::not a uri']) {
        expect(
          DailyNewsUrlPolicy.resolve(raw),
          DailyNewsUrlPolicy.fallbackUri,
          reason: '$raw',
        );
      }
    });

    test('不在白名单的地址回落到门户页', () {
      expect(
        DailyNewsUrlPolicy.resolve('https://evil.example.com/'),
        DailyNewsUrlPolicy.fallbackUri,
      );
    });
  });
}
