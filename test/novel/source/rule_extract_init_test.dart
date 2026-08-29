import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/core/rule_novel_source.dart';
import 'package:box/novel/core/novel_http_client.dart';
import 'package:box/novel/core/rules/crypto_utils.dart';
import 'package:box/novel/core/rules/json_parser.dart';
import 'package:box/novel/core/rules/regex_applier.dart';
import 'package:box/novel/core/rules/rule_engine_v2.dart';
import 'package:box/novel/core/rules/template_renderer.dart';
import 'package:box/novel/core/rules/url_resolver.dart';

/// 回归：`ruleBookInfo/ruleToc` 里的 `init` 规则（如 `"$.data"`）必须真正把上下文
/// scope 到子对象。
///
/// 历史 bug：extractInit 走 resolveStringRule，先把解析出的 Map 用 toString()
/// 变成 Dart 字面量（`{novelName: 斗罗大陆}` —— 键值都没有引号），再喂给
/// tryDecodeJson。那不是合法 JSON，解析失败后 catch 静默回退成整个 decoded，
/// init 形同虚设。
///
/// 症状具有欺骗性：书名/作者仍然正确，因为 _pickField 有「context 落空退 root」
/// 的兜底链能把它们捞回来；但 _parseChapters 的 chapterList 只解析一次，
/// 落空即返回空列表 —— 表现为「详情页正常但章节列表为空」。
void main() {
  group('RuleEngineV2.extractInit — init 必须真正 scope', () {
    final engine = RuleEngineV2.defaults();

    const body = '{"code":0,"data":{"novelName":"斗罗大陆",'
        '"list":[{"chapterName":"第一章","chapterUrl":"/c/1"}]}}';

    test(r'init = "$.data" 把上下文 scope 到子对象（而非回退成整个根）', () {
      final decoded = engine.tryDecodeJson(body);
      final init = engine.extractInit(decoded, {'init': r'$.data'});

      expect(init, isA<Map>());
      expect(
        identical(init, decoded),
        isFalse,
        reason: 'init 不应回退成整个根对象',
      );
      expect((init as Map)['novelName'], '斗罗大陆');
      expect(init['code'], isNull, reason: 'scope 后不应还能看到根层字段');
    });

    test('没有 init 规则时原样返回整个根对象', () {
      final decoded = engine.tryDecodeJson(body);
      final init = engine.extractInit(decoded, const {});
      expect(identical(init, decoded), isTrue);
    });

    test(r'init 指向数组时也应 scope（$.data.list）', () {
      final decoded = engine.tryDecodeJson(body);
      final init = engine.extractInit(decoded, {'init': r'$.data.list'});
      expect(init, isA<List>());
      expect((init as List).length, 1);
    });

    test('init 指向内嵌 JSON 字符串时仍支持二次解析', () {
      final decoded = engine.tryDecodeJson(
        '{"payload":"{\\"novelName\\":\\"斗罗大陆\\"}"}',
      );
      final init = engine.extractInit(decoded, {'init': r'$.payload'});
      expect(init, isA<Map>());
      expect((init as Map)['novelName'], '斗罗大陆');
    });

    test('init 指向不存在的路径时安全回退成整个根对象', () {
      final decoded = engine.tryDecodeJson(body);
      final init = engine.extractInit(decoded, {'init': r'$.nope'});
      expect(identical(init, decoded), isTrue);
    });
  });

  group('端到端：init + 相对路径章节规则', () {
    test('详情页用 init scope 后，相对路径 chapterList 能解析出章节', () async {
      // 这是「详情页正常但章节列表为空」的最小复现：
      // ruleBookInfo.init 把上下文切到 $.data，章节规则用相对路径 list[*]。
      final source = RuleNovelSource(
        baseUrl: 'http://api.lfdapengu.com',
        searchUrl: '/search?keyword={{key}}',
        ruleBookInfo: const {
          'init': r'$.data',
          'name': r'$.novelName',
          'author': r'$.authorName',
        },
        ruleToc: const {
          // 相对 init scope 的路径 —— init 失效时这里必然落空
          'chapterList': 'list[*]',
          'chapterName': r'$.chapterName',
          'chapterUrl': r'$.chapterUrl',
        },
        ruleContent: const {'content': r'$.data.content'},
        engine: _StubEngine(
          response: '{"code":0,"data":{"novelName":"斗罗大陆",'
              '"authorName":"唐家三少","list":['
              '{"chapterName":"第一章 斗罗大陆","chapterUrl":"/c/1"},'
              '{"chapterName":"第二章 废柴少年","chapterUrl":"/c/2"}'
              ']}}',
        ),
      );

      final detail = await source.fetchDetail(
        bookId: '88',
        detailUrl: '/novel/88',
      );

      expect(detail.book.title, '斗罗大陆');
      expect(detail.book.author, '唐家三少');
      expect(
        detail.chapters.length,
        2,
        reason: 'init scope 生效后相对路径章节规则应能解析',
      );
      expect(detail.chapters.first.title, contains('斗罗大陆'));
    });
  });
}

class _StubEngine extends RuleEngineV2 {
  _StubEngine({required this.response})
      : super(
          urlResolver: const UrlResolver(),
          renderer: const TemplateRenderer(),
          regexApplier: const RegexApplier(),
          jsonParser: const JsonParser(),
          crypto: const CryptoUtils(),
          httpClient: NovelHttpClient.create(),
        );

  final String response;

  @override
  Future<String> request(
    String path, {
    String? base,
    required String defaultBaseUrl,
    Map<String, String>? headers,
  }) async =>
      response;
}
