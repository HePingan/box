import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/core/maoyan_novel_source.dart';
import 'package:box/novel/core/novel_source_factory.dart';
import 'package:box/novel/core/rule_novel_source.dart';
import 'package:box/novel/pages/source_manager/book_source_model.dart';

/// 两个同名「猫眼看书（优++）」书源的区分测试
///
/// 用户实际持有两份同名源，必须走不同适配器：
///
/// A. 第三方明文源 —— bookSourceUrl=api.lfdapengu.com，group「小说 书源」，
///    searchUrl 是明文模板，规则是纯 JSONPath，comment 只是一段接口清单文本。
///    → 必须走通用 RuleNovelSource。
///
/// B. 内置 YSFly 源 —— bookSourceUrl=download.yichnmedia.com，group「优++」，
///    searchUrl 是 data:;base64 格式，规则全是 @js: + eval(comment) + run()，
///    comment 内含 13 域名表 + aesKey/Bearer token 对。
///    → 必须走原生 MaoYanNovelSource（Dart 侧重实现了那套 JS 认证）。
///
/// 陷阱：A 的 comment 里列了 `http://api.myweipin.com` 作为备用接口说明，
/// 因此"comment 含 myweipin/maoyankanshu 即判定为内置源"这种字符串嗅探会
/// 误判 A。判据必须看**适配器运行时真正依赖的素材**是否存在。
void main() {
  /// 源 A：用户导入的第三方明文源（comment 为真实原文，含 myweipin 字样）
  Map<String, dynamic> sourceA() => {
        'bookSourceName': '猫眼看书（优++）',
        'bookSourceUrl': 'http://api.lfdapengu.com',
        'bookSourceGroup': '小说 书源',
        'bookSourceType': 0,
        'enabled': true,
        'customOrder': 148,
        'enabledExplore': true,
        'bookSourceComment': '*By_聆听月与悦-2025/1/24\n'
            '*By_\n'
            '//这里提供部分接口\n'
            '*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-\n'
            'http://api.myweipin.com\n'
            'http://api.lfdapengu.com\n'
            'http://api.jmlldsc.com\n'
            'http://api.lemiyigou.com\n'
            'http://api.lfdapengu.com',
        'searchUrl':
            '{{source.bookSourceUrl}}/search?keyword={{key}}&page={{page}}',
        'exploreUrl': jsonEncode([
          {
            'title': '必读榜',
            'url':
                '{{source.bookSourceUrl}}/module/rank?type=1&channel=1&page={{page}}',
          },
          {
            'title': '玄幻',
            'url':
                '{{source.bookSourceUrl}}/novel?sort=1&page={{page}}&categoryId=lejRej',
          },
        ]),
        'ruleSearch': {
          'name': r'$.novelName',
          'author': r'$.authorName',
          'coverUrl': r'$.cover',
          'bookList': r'$.data',
          'summary': r'$.summary',
          'kind': r'$.className',
        },
        'ruleBookInfo': {'name': r'$.data.novelName'},
        'ruleToc': {'chapterList': r'$.data.list'},
        'ruleContent': {'content': r'$.data.content'},
      };

  /// 源 B：内置 YSFly 源（comment 含域名表 + aesKey/token 对，规则走 @js:）
  Map<String, dynamic> sourceB() => {
        'bookSourceName': '猫眼看书（优++）',
        'bookSourceUrl': 'http://download.yichnmedia.com',
        'bookSourceGroup': '优++',
        'enabled': true,
        'weight': 10,
        'customOrder': 0,
        'bookSourceComment': '// http://download.yichnmedia.com\n'
            '_path = {\n DownApp: "/client/version"\n};\n'
            'try {\n \$ = JSON.parse(source.getVariable());\n} catch (err) {\n'
            ' \$ = {\n  time: 20240202,\n  domains: [\n'
            '   ["longchunbajiao", 0],\n'
            '   ["yybhsl", 0],\n'
            '   ["myweipin", 0],\n'
            '   ["lemiyigou", 0],\n'
            '   ["xingliangglobal", 1],\n'
            '   ["xqjcool", 1]\n'
            '  ]\n }\n setv(\$);\n}\n'
            'getHost = i => {\n [domain, uType] = \$.domains[i];\n'
            ' [aesKey, Authorization] = [\n'
            '  ["f041c49714d39908", "bearereyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.PAYLOAD_A.SIG_A"],\n'
            '  ["4395daa50ad6baf7", "bearereyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.PAYLOAD_B.SIG_B"]\n'
            ' ][uType];\n}\n'
            'eurl = Path => `data:;base64,\${java.base64Encode(Path)},'
            '{"type":"maoyankanshu"}`;',
        'header': jsonEncode({
          'client-version': '2.3.0',
          'client-name': 'app.maoyankanshu.novel',
          'User-Agent': 'okhttp/4.9.2',
        }),
        'searchUrl':
            'data:;base64,{{java.base64Encode("/search?keyword="+key+"&page="+page)}},{"type":"maoyankanshu"}',
        'exploreUrl': '',
        'ruleSearch': {
          'name': r'$.novelName',
          'bookList': '@js:\neval(String(source.bookSourceComment));\n'
              'run("data").map((\$\$,i)=>{ return JSON.stringify(\$\$); });',
        },
        'ruleBookInfo': {
          'init': '@js:\neval(String(source.bookSourceComment));\nrun("data");',
        },
        'ruleToc': {
          'chapterList':
              '@js:\neval(String(source.bookSourceComment));\nList = run("data").list;',
        },
        'ruleContent': {
          'content': '@js:\neval(String(source.bookSourceComment));\nrun("content");',
        },
      };

  group('源 A（第三方明文）必须走通用规则引擎', () {
    test('comment 里出现 myweipin 字样不足以判定为内置源', () {
      final json = sourceA();

      // 真实 comment 确实含该字样 —— 这正是字符串嗅探会踩的坑
      expect(
        json['bookSourceComment'].toString().contains('myweipin'),
        isTrue,
        reason: '前置条件：源 A 的接口清单里列了 api.myweipin.com',
      );

      expect(
        MaoYanNovelSource.supportsBookSourceJson(json),
        isFalse,
        reason: '原生适配器需要域名表+token 对，源 A 一个都没有，声称支持只会让请求发不出去',
      );
    });

    test('工厂路由到 RuleNovelSource', () {
      expect(
        NovelSourceFactory.fromBookSourceJson(sourceA()),
        isA<RuleNovelSource>(),
      );
    });

    test('extractAuthFromComment 从源 A 提不出任何认证素材', () {
      final (domains, aesKeys, authTokens) =
          MaoYanNovelSource.extractAuthFromComment(
        sourceA()['bookSourceComment'].toString(),
      );

      expect(domains, isEmpty, reason: 'domains 为空 → _request 的轮询循环一次都不执行');
      expect(aesKeys, isEmpty);
      expect(authTokens, isEmpty);
    });
  });

  group('源 B（内置 YSFly）必须走原生适配器', () {
    test('supportsBookSourceJson 命中', () {
      expect(MaoYanNovelSource.supportsBookSourceJson(sourceB()), isTrue);
    });

    test('工厂路由到 MaoYanNovelSource', () {
      expect(
        NovelSourceFactory.fromBookSourceJson(sourceB()),
        isA<MaoYanNovelSource>(),
      );
    });

    test('认证素材可被提取（适配器运行的前提）', () {
      final (domains, aesKeys, authTokens) =
          MaoYanNovelSource.extractAuthFromComment(
        sourceB()['bookSourceComment'].toString(),
      );

      expect(domains, isNotEmpty);
      expect(domains.map((e) => e.$1), contains('myweipin'));
      expect(aesKeys, contains('f041c49714d39908'));
      expect(authTokens.length, greaterThanOrEqualTo(2));
      expect(authTokens.first, startsWith('Bearer '));
    });

    test('真实内置 asset 同样命中原生适配器', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final raw = await rootBundle.loadString(
        'assets/data/maoyan_book_source.json',
      );
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);

      expect(MaoYanNovelSource.supportsBookSourceJson(json), isTrue);
      expect(
        NovelSourceFactory.fromBookSourceJson(json),
        isA<MaoYanNovelSource>(),
      );
    });
  });

  group('两源可共存且在管理页可区分', () {
    test('id 不冲突（否则导入其一会顶掉另一个）', () {
      final a = BookSourceModel.fromJson(sourceA());
      final b = BookSourceModel.fromJson(sourceB());

      expect(a.id, isNot(b.id));
    });

    test('id 内含的 kind 段落正确反映适配器类型', () {
      final a = BookSourceModel.fromJson(sourceA());
      final b = BookSourceModel.fromJson(sourceB());

      expect(a.sourceKind, 'rule');
      expect(b.sourceKind, 'maoyan');
      expect(a.id, endsWith('|rule'));
      expect(b.id, endsWith('|maoyan'));
    });

    test('同名但 URL / 分组不同，UI 有可显示的区分依据', () {
      final a = BookSourceModel.fromJson(sourceA());
      final b = BookSourceModel.fromJson(sourceB());

      expect(a.bookSourceName, b.bookSourceName); // 同名是前提
      expect(a.bookSourceUrl, isNot(b.bookSourceUrl));
      expect(a.bookSourceGroup, isNot(b.bookSourceGroup));
    });
  });
}
