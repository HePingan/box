import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/core/novel_http_client.dart';
import 'package:box/novel/core/rule_novel_source.dart';
import 'package:box/novel/core/rules/crypto_utils.dart';
import 'package:box/novel/core/rules/json_parser.dart';
import 'package:box/novel/core/rules/regex_applier.dart';
import 'package:box/novel/core/rules/rule_engine_v2.dart';
import 'package:box/novel/core/rules/template_renderer.dart';
import 'package:box/novel/core/rules/url_resolver.dart';

/// 回归：详情页与目录分属两个接口的书源（ruleBookInfo.tocUrl 指向独立目录接口）。
///
/// 用户实测「猫眼看书（优++）」http://api.lfdapengu.com：搜索成功 15 本，
/// 详情页成功但**章节列表为空**，正文测试因此被跳过。
///
/// 根因：RuleNovelSource.fetchDetail 只请求详情接口一次，就地用
/// ruleToc.chapterList 解析章节；从不读取 ruleBookInfo.tocUrl。
/// 对于把目录放在单独接口的源，章节数据根本不在详情响应里 → 永远解析为空。
void main() {
  group('RuleNovelSource — ruleBookInfo.tocUrl 独立目录接口', () {
    /// 伪造引擎：按 URL 分别返回详情响应与目录响应，并记录请求顺序。
    late List<String> requested;

    RuleNovelSource buildSource() {
      requested = [];
      final engine = _RecordingEngine(
        onRequest: (url) {
          requested.add(url);
          if (url.contains('/toc')) {
            // 目录接口：章节列表只存在于这份响应里
            return '''
{"code":0,"data":{"list":[
  {"chapterName":"第一章 斗罗大陆","chapterUrl":"/content?cid=1001"},
  {"chapterName":"第二章 唐门绝学","chapterUrl":"/content?cid=1002"},
  {"chapterName":"第三章 觉醒武魂","chapterUrl":"/content?cid=1003"}
]}}''';
          }
          // 详情接口：只有书籍元信息，没有任何章节字段
          return '''
{"code":0,"data":{
  "novelId":"88",
  "novelName":"斗罗大陆",
  "authorName":"唐家三少",
  "intro":"唐门外门弟子唐三...",
  "cover":"http://img.example.invalid/88.jpg",
  "tocId":"88"
}}''';
        },
      );

      return RuleNovelSource(
        name: '猫眼看书（优++）',
        baseUrl: 'http://api.lfdapengu.com',
        searchUrl: '{{source.bookSourceUrl}}/search?keyword={{key}}',
        ruleBookInfo: const {
          'name': r'$.data.novelName',
          'author': r'$.data.authorName',
          'intro': r'$.data.intro',
          'coverUrl': r'$.data.cover',
          // 关键：目录在另一个接口上
          'tocUrl': r'/toc?novelId={{$.data.tocId}}',
        },
        ruleToc: const {
          'chapterList': r'$.data.list[*]',
          'chapterName': r'$.chapterName',
          'chapterUrl': r'$.chapterUrl',
        },
        ruleContent: const {'content': r'$.data.content'},
        engine: engine,
      );
    }

    test('详情响应里没有章节时，应按 tocUrl 再请求一次目录接口', () async {
      final source = buildSource();
      final detail = await source.fetchDetail(
        bookId: '88',
        detailUrl: '/novel/88',
      );

      // 元信息来自详情接口
      expect(detail.book.title, '斗罗大陆');
      expect(detail.book.author, '唐家三少');

      // 章节必须来自目录接口 —— 这是用户报障的核心
      expect(
        detail.chapters.length,
        3,
        reason: '章节列表为空说明 tocUrl 没有被请求（用户实测的 bug）',
      );
      expect(detail.chapters.first.title, '第一章 斗罗大陆');
      expect(detail.chapters.last.title, '第三章 觉醒武魂');
    });

    test('确实发出了两次请求：先详情再目录', () async {
      final source = buildSource();
      await source.fetchDetail(bookId: '88', detailUrl: '/novel/88');

      expect(requested.length, 2, reason: '只请求 1 次 = tocUrl 被忽略');
      expect(requested[0], contains('/novel/88'));
      expect(requested[1], contains('/toc'));
    });

    test(r'tocUrl 模板里的 {{$.data.tocId}} 用详情响应的字段渲染', () async {
      final source = buildSource();
      await source.fetchDetail(bookId: '88', detailUrl: '/novel/88');

      expect(
        requested[1],
        contains('novelId=88'),
        reason: 'tocUrl 需要能引用详情响应里的字段（tocId=88）',
      );
    });

    test('章节 URL 仍被解析为可请求的地址', () async {
      final source = buildSource();
      final detail = await source.fetchDetail(
        bookId: '88',
        detailUrl: '/novel/88',
      );

      expect(detail.chapters.first.url, contains('/content?cid=1001'));
    });

    test('没有 tocUrl 的源不应产生第二次请求（不回归旧行为）', () async {
      requested = [];
      final engine = _RecordingEngine(
        onRequest: (url) {
          requested.add(url);
          // 详情响应里自带章节列表（同接口型书源）
          return '''
{"code":0,"data":{
  "novelName":"同接口书",
  "authorName":"某人",
  "list":[{"chapterName":"第一章","chapterUrl":"/c/1"}]
}}''';
        },
      );

      final source = RuleNovelSource(
        name: '同接口源',
        baseUrl: 'http://example.invalid',
        searchUrl: '/search?k={{key}}',
        ruleBookInfo: const {
          'name': r'$.data.novelName',
          'author': r'$.data.authorName',
        },
        ruleToc: const {
          'chapterList': r'$.data.list[*]',
          'chapterName': r'$.chapterName',
          'chapterUrl': r'$.chapterUrl',
        },
        engine: engine,
      );

      final detail = await source.fetchDetail(bookId: '1', detailUrl: '/b/1');

      expect(requested.length, 1, reason: '无 tocUrl 时不应多发请求');
      expect(detail.chapters.length, 1);
      expect(detail.chapters.first.title, '第一章');
    });

    test('目录接口请求失败时降级为空目录，不抛异常', () async {
      requested = [];
      final engine = _RecordingEngine(
        onRequest: (url) {
          requested.add(url);
          if (url.contains('/toc')) {
            throw Exception('目录接口 503');
          }
          return '''
{"code":0,"data":{"novelName":"降级书","authorName":"某人","tocId":"9"}}''';
        },
      );

      final source = RuleNovelSource(
        name: '降级源',
        baseUrl: 'http://example.invalid',
        searchUrl: '/search?k={{key}}',
        ruleBookInfo: const {
          'name': r'$.data.novelName',
          'tocUrl': r'/toc?id={{$.data.tocId}}',
        },
        ruleToc: const {
          'chapterList': r'$.data.list[*]',
          'chapterName': r'$.chapterName',
          'chapterUrl': r'$.chapterUrl',
        },
        engine: engine,
      );

      final detail = await source.fetchDetail(bookId: '9', detailUrl: '/b/9');

      // 书籍信息仍可用，目录为空但不崩
      expect(detail.book.title, '降级书');
      expect(detail.chapters, isEmpty);
    });
  });
}

/// 记录并伪造 HTTP 响应的引擎，避免测试触网。
class _RecordingEngine extends RuleEngineV2 {
  _RecordingEngine({required this.onRequest})
      : super(
          urlResolver: const UrlResolver(),
          renderer: const TemplateRenderer(),
          regexApplier: const RegexApplier(),
          jsonParser: const JsonParser(),
          crypto: const CryptoUtils(),
          httpClient: NovelHttpClient.create(),
        );

  final String Function(String url) onRequest;

  @override
  Future<String> request(
    String path, {
    String? base,
    required String defaultBaseUrl,
    Map<String, String>? headers,
  }) async {
    return onRequest(path);
  }
}
