import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/core/kuaiyan_novel_source.dart';
import 'package:box/novel/core/maoyan_novel_source.dart';
import 'package:box/novel/core/novel_source_factory.dart';
import 'package:box/novel/core/rule_novel_source.dart';
import 'package:box/novel/core/rules/rule_engine_v2.dart';
import 'package:box/novel/core/rules/url_resolver.dart';
import 'package:box/novel/core/wtzw_novel_source.dart';

/// 书源路由回归测试
///
/// 背景：用户导入第三方源「猫眼看书（优++）」(http://api.lfdapengu.com) 后
/// 搜索/发现均无结果。根因是 MaoYanNovelSource.supportsBookSourceJson 把
/// `bookSourceName.contains('猫眼')` 当成充分条件，于是任何名字带「猫眼」的
/// 第三方源都被劫持到内置原生适配器上 —— 而该适配器硬编码 /search 路径、
/// 且只遍历 bookSourceComment 里提取的域名表，用户填的 bookSourceUrl 与
/// searchUrl 全部被丢弃，请求根本发不出去。
///
/// 这里锁死正确的路由契约：认证特征（comment）决定是否走原生适配器，
/// 光有名字不算。
void main() {
  /// 用户实际导入的那份源（明文 URL、无 comment、无认证）
  Map<String, dynamic> userMaoyanLikeSource() => {
        'bookSourceName': '猫眼看书（优++）',
        'bookSourceUrl': 'http://api.lfdapengu.com',
        'bookSourceGroup': '小说 书源',
        'enabled': true,
        'searchUrl':
            '{{source.bookSourceUrl}}/search?keyword={{key}}&page={{page}}',
        'exploreUrl': jsonEncode([
          {
            'title': '必读榜',
            'url':
                '{{source.bookSourceUrl}}/module/rank?type=1&channel=1&page={{page}}',
          },
        ]),
        'ruleSearch': {'bookList': r'$.data', 'name': r'$.novelName'},
        'ruleBookInfo': {'name': r'$.data.novelName'},
        'ruleToc': {'chapterList': r'$.data'},
        'ruleContent': {'content': r'$.data.content'},
      };

  group('第三方「猫眼」源不应被内置原生适配器劫持', () {
    test('supportsBookSourceJson 对无认证特征的同名源返回 false', () {
      final json = userMaoyanLikeSource();

      // 名字含「猫眼」，但没有 maoyankanshu / myweipin 认证特征
      expect(json['bookSourceName'].toString().contains('猫眼'), isTrue);
      expect(MaoYanNovelSource.supportsBookSourceJson(json), isFalse,
          reason: '仅凭书源名匹配会劫持第三方源，导致 bookSourceUrl 被忽略');
    });

    test('工厂把该源路由到通用 RuleNovelSource', () {
      final source = NovelSourceFactory.fromBookSourceJson(
        userMaoyanLikeSource(),
      );

      expect(source, isA<RuleNovelSource>(),
          reason: '明文 URL + 声明式规则的源必须走通用规则引擎');
      expect(source, isNot(isA<MaoYanNovelSource>()));
    });

    test('其他适配器也不应误抢该源', () {
      final json = userMaoyanLikeSource();
      expect(WtzwNovelSource.supportsBookSourceJson(json), isFalse);
      expect(KuaiYanNovelSource.supportsBookSourceJson(json), isFalse);
    });
  });

  group('路由修正后 URL 链路可用', () {
    // {{source.bookSourceUrl}} 不是 RuleEngineV2 已知变量，会被渲染成空串，
    // 留下相对路径 —— 再由 request(defaultBaseUrl: baseUrl) 拼回 bookSourceUrl。
    // 这是优雅退化而非缺陷，锁死它，避免以后有人"修"掉空串行为反而拼出错 URL。
    test('searchUrl 模板渲染后拼回 bookSourceUrl', () {
      final engine = RuleEngineV2.defaults();
      final path = engine.renderTemplate(
        '{{source.bookSourceUrl}}/search?keyword={{key}}&page={{page}}',
        {},
        {},
        vars: {'page': '1', 'key': 'test', 'keyword': 'test'},
      );

      expect(path, '/search?keyword=test&page=1',
          reason: '未知模板变量应渲染为空串，留下可解析的相对路径');

      const resolver = UrlResolver();
      expect(
        resolver.absUrl(path, defaultBaseUrl: 'http://api.lfdapengu.com'),
        'http://api.lfdapengu.com/search?keyword=test&page=1',
      );
    });

    test('发现页（榜单/分类）相对路径同样能拼回', () {
      const resolver = UrlResolver();
      const base = 'http://api.lfdapengu.com';

      expect(
        resolver.absUrl('/module/rank?type=1&channel=1&page=1',
            defaultBaseUrl: base),
        '$base/module/rank?type=1&channel=1&page=1',
      );
      expect(
        resolver.absUrl('/novel?sort=1&page=1&categoryId=lejRej',
            defaultBaseUrl: base),
        '$base/novel?sort=1&page=1&categoryId=lejRej',
      );
    });
  });

  group('内置猫眼源仍走原生适配器（不能改坏）', () {
    test('带 maoyankanshu 特征的源命中原生适配器', () {
      final json = {
        'bookSourceName': '猫眼看书（优++）',
        'bookSourceUrl': 'http://download.yichnmedia.com',
        'bookSourceComment':
            '["lfdapengu", 0]\n["f041c49714d39908", "bearer eyJhbGciOiJIUzI1NiJ9.test"]\n'
                '{"type":"maoyankanshu"}',
        'searchUrl':
            'data:;base64,{{java.base64Encode("/search?keyword="+key)}},{"type":"maoyankanshu"}',
      };

      expect(MaoYanNovelSource.supportsBookSourceJson(json), isTrue);
      expect(
        NovelSourceFactory.fromBookSourceJson(json),
        isA<MaoYanNovelSource>(),
      );
    });

    test('光提到 myweipin 域名不再命中（需真实域名表+token）', () {
      // 契约收紧：第三方源常在 comment 里列 api.myweipin.com 当备用接口说明，
      // 那只是文本，没有域名表和 token，本适配器跑不起来。详见
      // maoyan_two_sources_test.dart 里用户两份真实同名源的对照。
      final json = {
        'bookSourceName': '某马甲源',
        'bookSourceUrl': 'http://example.invalid',
        'bookSourceComment': 'domain myweipin backup',
      };
      expect(MaoYanNovelSource.supportsBookSourceJson(json), isFalse);
    });

    test('真实内置 asset 仍被识别为原生猫眼源', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final raw = await rootBundle.loadString(
        'assets/data/maoyan_book_source.json',
      );
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);

      expect(MaoYanNovelSource.supportsBookSourceJson(json), isTrue,
          reason: '内置源靠 comment 里的域名表+token 工作，必须继续走原生适配器');
      expect(
        NovelSourceFactory.fromBookSourceJson(json),
        isA<MaoYanNovelSource>(),
      );
    });
  });
}
