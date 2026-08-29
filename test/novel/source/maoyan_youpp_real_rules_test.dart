import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/core/novel_http_client.dart';
import 'package:box/novel/core/rule_novel_source.dart';
import 'package:box/novel/core/rules/crypto_utils.dart';
import 'package:box/novel/core/rules/json_parser.dart';
import 'package:box/novel/core/rules/regex_applier.dart';
import 'package:box/novel/core/rules/rule_engine_v2.dart';
import 'package:box/novel/core/rules/template_renderer.dart';
import 'package:box/novel/core/rules/url_resolver.dart';

/// 端到端回归：用「猫眼看书（优++）」诊断报告里的**真实规则原文**驱动。
///
/// 该源同时踩中三个坎，必须全部修好章节列表才出得来：
///   1. `init = $.data` —— extractInit 曾把 Map toString() 再解析，静默失效
///   2. `tocUrl = .../novel/{{$.novelId}}/chapters` —— 目录在独立接口，
///      且 novelId 取自 $.data，init 坏则渲染成 `/novel//chapters`
///   3. `chapterUrl = $.path @js:java.aesBase64DecodeToString(...);` ——
///      规则末尾带**分号**，AES 正则若要求以 `)` 收尾则匹配失败
void main() {
  group('猫眼看书（优++）真实规则', () {
    // 诊断报告原文照抄
    const ruleBookInfo = {
      'author': r'$.authorName',
      'canReName': 'true',
      'coverUrl': r'$.cover',
      'init': r'$.data',
      'kind': r'$..className',
      'lastChapter': r'{{$.lastChapter.chapterName}}•{{$.lastUpdatedAt}}',
      'name': r'$.novelName',
      'tocUrl': r'{{source.bookSourceUrl}}/novel/{{$.novelId}}/chapters',
      'wordCount': r'$.wordNum',
    };

    const ruleToc = {
      'chapterList': r'$.data.list[*]',
      'chapterName': r'$.chapterName',
      'chapterUrl': r'$.path @js:java.aesBase64DecodeToString(result,'
          '"f041c49714d39908","AES/CBC/PKCS5Padding","0123456789abcdef");',
      'updateTime': r'{{$.updatedAt}} | {{$.wordNum}}字',
    };

    // 详情响应：章节数据不在这里，只有书籍元信息 + novelId
    const detailBody = '{"code":0,"data":{'
        '"novelId":"aQ7lQ7","novelName":"斗罗之暗影斗罗",'
        '"authorName":"某某","cover":"http://x/c.jpg",'
        '"wordNum":"120万","summary":"简介文本",'
        '"lastChapter":{"chapterName":"第百章"},"lastUpdatedAt":"今天"'
        '}}';

    // 目录响应：独立接口返回，path 是 AES 密文
    const tocBody = '{"code":0,"data":{"list":['
        '{"chapterName":"第一章 暗影","path":"CIPHER_A","updatedAt":"昨天"},'
        '{"chapterName":"第二章 觉醒","path":"CIPHER_B","updatedAt":"今天"}'
        ']}}';

    late List<String> requested;

    RuleNovelSource buildSource() {
      requested = [];
      return RuleNovelSource(
        baseUrl: 'http://api.lfdapengu.com',
        searchUrl:
            '{{source.bookSourceUrl}}/search?keyword={{key}}&page={{page}}',
        ruleSearch: const {
          'bookList': r'$.data[*]',
          'name': r'$.novelName',
          'author': r'$.authorName',
          'bookUrl':
              r'{{source.bookSourceUrl}}/novel/{{$.novelId}}?isSearch=1',
        },
        ruleBookInfo: ruleBookInfo,
        ruleToc: ruleToc,
        ruleContent: const {'content': r'$.content'},
        engine: _RouteEngine(
          onRequest: (path) {
            requested.add(path);
            return path.contains('/chapters') ? tocBody : detailBody;
          },
        ),
      );
    }

    test('详情页能解析出章节列表（章节数不为 0）', () async {
      final source = buildSource();
      final detail = await source.fetchDetail(
        bookId: 'aQ7lQ7',
        detailUrl: '/novel/aQ7lQ7?isSearch=1',
      );

      expect(detail.book.title, '斗罗之暗影斗罗');
      expect(
        detail.chapters.length,
        2,
        reason: '这正是用户报障的现象：章节数 0',
      );
      expect(detail.chapters[0].title, contains('暗影'));
      expect(detail.chapters[1].title, contains('觉醒'));
    });

    test('tocUrl 里的 {{\$.novelId}} 必须渲染出真实 id（不能是 /novel//chapters）', () async {
      final source = buildSource();
      await source.fetchDetail(
        bookId: 'aQ7lQ7',
        detailUrl: '/novel/aQ7lQ7?isSearch=1',
      );

      expect(requested.length, 2, reason: '应发出详情 + 目录两次请求');
      final tocReq = requested[1];
      expect(tocReq, contains('/novel/aQ7lQ7/chapters'));
      expect(
        tocReq.contains('/novel//chapters'),
        isFalse,
        reason: 'init 失效会导致 novelId 渲染成空串',
      );
    });

    test('tocUrl 以 {{source.bookSourceUrl}} 开头时能解析成绝对地址', () async {
      final source = buildSource();
      await source.fetchDetail(
        bookId: 'aQ7lQ7',
        detailUrl: '/novel/aQ7lQ7?isSearch=1',
      );

      final tocReq = requested[1];
      // {{source.bookSourceUrl}} 渲染成空串后，request(defaultBaseUrl:) 应能拼回
      expect(
        tocReq.startsWith('http://api.lfdapengu.com') ||
            tocReq.startsWith('/novel/'),
        isTrue,
        reason: '实际请求路径：$tocReq',
      );
      // 绝不能残留未渲染的模板串
      expect(tocReq.contains('{{'), isFalse, reason: '模板未被渲染：$tocReq');
    });

    test('detailUrl 为 null 时会退化成请求 <base>/<bookId>（诊断工具旧行为）', () async {
      final source = buildSource();
      // 诊断 runner 旧代码没传 detailUrl，fetchDetail 里 path 退化成 bookId
      await source.fetchDetail(bookId: 'aQ7lQ7');

      expect(requested.first, 'aQ7lQ7',
          reason: '请求退化成 <base>/aQ7lQ7 这种不存在的端点，'
              '真实服务器会返回错误页，详情与章节必然全空');
    });

    test('传入搜索解析出的 detailUrl 时请求正确的详情端点', () async {
      final source = buildSource();
      await source.fetchDetail(
        bookId: 'aQ7lQ7',
        detailUrl: 'http://api.lfdapengu.com/novel/aQ7lQ7?isSearch=1',
      );

      expect(requested.first, contains('/novel/aQ7lQ7'));
      expect(requested.first, isNot('aQ7lQ7'));
    });

    test('AES 往返：末尾带分号的 @js: 规则能正确解密 path', () {
      const crypto = CryptoUtils();
      const key = 'f041c49714d39908';
      const iv = '0123456789abcdef';
      // 用同参数加密一个已知明文
      final cipher = _aesEncrypt('/chapter/12345', key, iv);

      const jsExpr = 'java.aesBase64DecodeToString(result,'
          '"f041c49714d39908","AES/CBC/PKCS5Padding","0123456789abcdef");';
      final plain = crypto.evalJs(jsExpr, cipher);

      expect(
        plain,
        '/chapter/12345',
        reason: '尾部分号导致正则不匹配时，这里会原样返回密文',
      );
    });
  });
}

/// 与 CryptoUtils.aesBase64DecodeToString 对称的加密（AES/CBC/PKCS7）
String _aesEncrypt(String plain, String key, String iv) {
  final encrypter = enc.Encrypter(
    enc.AES(enc.Key.fromUtf8(key), mode: enc.AESMode.cbc, padding: 'PKCS7'),
  );
  return encrypter.encrypt(plain, iv: enc.IV.fromUtf8(iv)).base64;
}

class _RouteEngine extends RuleEngineV2 {
  _RouteEngine({required this.onRequest})
      : super(
          urlResolver: const UrlResolver(),
          renderer: const TemplateRenderer(),
          regexApplier: const RegexApplier(),
          jsonParser: const JsonParser(),
          crypto: const CryptoUtils(),
          httpClient: NovelHttpClient.create(),
        );

  final String Function(String path) onRequest;

  @override
  Future<String> request(
    String path, {
    String? base,
    required String defaultBaseUrl,
    Map<String, String>? headers,
  }) async =>
      onRequest(path);
}
