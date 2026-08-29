import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/core/models.dart';
import 'package:box/novel/core/novel_http_client.dart';
import 'package:box/novel/core/rule_novel_source.dart';
import 'package:box/novel/core/rules/crypto_utils.dart';
import 'package:box/novel/core/rules/json_parser.dart';
import 'package:box/novel/core/rules/regex_applier.dart';
import 'package:box/novel/core/rules/rule_engine_v2.dart';
import 'package:box/novel/core/rules/template_renderer.dart';
import 'package:box/novel/core/rules/url_resolver.dart';

/// 回归：章节正文必须保留自然段，不能整章挤成一行。
///
/// 根因（已修）：`_cleanContent` 调 `TextCleaner.cleanRaw`，它把 `\s+` 折叠成
/// 单空格，而 `\s` 包含 `\n` —— 段落换行全被消灭。紧随其后的 `split('\n')`
/// 想重建段落，但换行已经不存在了，只切出 1 段。
void main() {
  RuleNovelSource buildSource(String body, {String replaceRegex = ''}) {
    return RuleNovelSource(
      baseUrl: 'http://api.lfdapengu.com',
      searchUrl: '/search?keyword={{key}}',
      ruleSearch: const {'bookList': r'$.data[*]', 'name': r'$.novelName'},
      ruleBookInfo: const {'name': r'$.data.novelName'},
      ruleToc: const {'chapterList': r'$.data.list[*]'},
      ruleContent: {
        'content': r'$.data.content',
        if (replaceRegex.isNotEmpty) 'replaceRegex': replaceRegex,
      },
      engine: _StubEngine(body: body),
    );
  }

  NovelDetail detailWith(String url) => NovelDetail(
        book: NovelBook(
          id: 'b1',
          title: '测试书',
          author: '作者',
          intro: '',
          coverUrl: '',
          detailUrl: '/novel/b1',
        ),
        chapters: [NovelChapter(title: '第一章', url: url)],
      );

  group('正文分段', () {
    test('真换行的正文保留分段（回归：以前整章挤成一行）', () async {
      // 形态：JSON 字符串里带真换行（tryDecodeJson 解析后就是 \n）
      const body = '{"code":0,"data":{"content":'
          '"第一段开头。\\n第二段开头。\\n第三段开头。"}}';
      final source = buildSource(body);

      final c = await source.fetchChapter(
        detail: detailWith('/chapter/1'),
        chapterIndex: 0,
      );

      final paras = c.content.split('\n\n').where((e) => e.isNotEmpty).toList();
      expect(paras.length, 3, reason: '实际内容：${c.content}');
      expect(paras[0], '第一段开头。');
      expect(paras[1], '第二段开头。');
      expect(paras[2], '第三段开头。');
    });

    test('HTML <br> 与 <p> 分段被还原', () async {
      const body = '{"code":0,"data":{"content":'
          '"<p>第一段。</p><p>第二段。</p>第三段甲。<br/>第三段乙。"}}';
      final source = buildSource(body);

      final c = await source.fetchChapter(
        detail: detailWith('/chapter/1'),
        chapterIndex: 0,
      );

      final paras = c.content.split('\n\n').where((e) => e.isNotEmpty).toList();
      expect(paras.length, 4, reason: '实际内容：${c.content}');
      expect(paras.first, '第一段。');
      expect(paras.last, '第三段乙。');
      expect(c.content.contains('<'), isFalse, reason: 'HTML 标签应被剥离');
    });

    test('双重转义的 \\n 字面量也能还原成分段', () async {
      // 部分源把 \n 双重转义，解析出来是字面两个字符 \ + n
      const body = r'{"code":0,"data":{"content":"甲段。\\n乙段。\\n丙段。"}}';
      final source = buildSource(body);

      final c = await source.fetchChapter(
        detail: detailWith('/chapter/1'),
        chapterIndex: 0,
      );

      final paras = c.content.split('\n\n').where((e) => e.isNotEmpty).toList();
      expect(paras.length, 3, reason: '实际内容：${c.content}');
    });

    test('全角空格缩进的无换行长文本按段首缩进分段', () async {
      const body = '{"code":0,"data":{"content":'
          '"\u3000\u3000甲段内容。\u3000\u3000乙段内容。\u3000\u3000丙段内容。"}}';
      final source = buildSource(body);

      final c = await source.fetchChapter(
        detail: detailWith('/chapter/1'),
        chapterIndex: 0,
      );

      final paras = c.content.split('\n\n').where((e) => e.isNotEmpty).toList();
      expect(paras.length, 3, reason: '实际内容：${c.content}');
      expect(paras[0], '甲段内容。');
    });

    test('完全无换行无缩进时按句末标点兜底分段', () async {
      // 正文需超过 TextCleaner.flatContentMinLength(200) 才触发兜底断段：
      // 短的无换行文本（「本章内容为空」这类提示）不该被强行拆开。
      final long = '他站起来。她问道：「你去哪？」他没回答……夜色很深。' * 10;
      final body = '{"code":0,"data":{"content":"$long"}}';
      final source = buildSource(body);

      final c = await source.fetchChapter(
        detail: detailWith('/chapter/1'),
        chapterIndex: 0,
      );

      final paras = c.content.split('\n\n').where((e) => e.isNotEmpty).toList();
      expect(paras.length, greaterThan(1),
          reason: '整章不应糊成一块：${c.content}');
      // 不能把 」和 …… 拆坏
      expect(c.content.contains('\n」'), isFalse);
      expect(c.content.contains('…\n…'), isFalse);
    });

    test('replaceRegex 生效且不破坏分段', () async {
      const body = '{"code":0,"data":{"content":'
          '"第一段。7017k\\n第二段。一秒记住xx网精彩阅读。\\n第三段。"}}';
      final source = buildSource(
        body,
        replaceRegex: '##一秒记住.*精彩阅读。|7017k',
      );

      final c = await source.fetchChapter(
        detail: detailWith('/chapter/1'),
        chapterIndex: 0,
      );

      expect(c.content.contains('7017k'), isFalse);
      expect(c.content.contains('一秒记住'), isFalse);
      final paras = c.content.split('\n\n').where((e) => e.isNotEmpty).toList();
      expect(paras.length, 3, reason: '广告清洗后仍应保留 3 段：${c.content}');
    });

    test('段间多余空行被折叠，段内不留空白行', () async {
      const body = '{"code":0,"data":{"content":'
          '"甲段。\\n\\n\\n\\n乙段。\\n   \\n丙段。"}}';
      final source = buildSource(body);

      final c = await source.fetchChapter(
        detail: detailWith('/chapter/1'),
        chapterIndex: 0,
      );

      expect(c.content.contains('\n\n\n'), isFalse,
          reason: '不应出现三个以上连续换行：${c.content.replaceAll("\n", "\\n")}');
      final paras = c.content.split('\n\n').where((e) => e.isNotEmpty).toList();
      expect(paras.length, 3);
    });
  });
}

class _StubEngine extends RuleEngineV2 {
  _StubEngine({required this.body})
      : super(
          urlResolver: const UrlResolver(),
          renderer: const TemplateRenderer(),
          regexApplier: const RegexApplier(),
          jsonParser: const JsonParser(),
          crypto: const CryptoUtils(),
          httpClient: NovelHttpClient.create(),
        );

  final String body;

  @override
  Future<String> request(
    String path, {
    String? base,
    required String defaultBaseUrl,
    Map<String, String>? headers,
  }) async =>
      body;
}
