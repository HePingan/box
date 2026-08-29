import 'dart:convert';
import 'dart:io';

import 'package:box/novel/core/maoyan_novel_source.dart';
import 'package:box/novel/core/novel_source_factory.dart';
import 'package:flutter_test/flutter_test.dart';

/// MaoYanNovelSource 专用书源测试
///
/// 核心逻辑测试（不依赖网络）：
///   1. `decodeDataUrl` — data:;base64,... 格式解析
///   2. `encodeDataUrl` — 路径编码回 data: URL
///   3. `_extractAuthFromComment` — JS 认证信息提取
///   4. `decryptChapterPath` — AES/CBC 解密
///   5. `fromBookSourceJson` — 工厂方法正确解析内置 JSON
void main() {
  group('MaoYanNovelSource — URL 编解码', () {
    test('decodeDataUrl 提取普通 URL', () {
      expect(
        MaoYanNovelSource.decodeDataUrl('http://api.example.com/novel/123'),
        'http://api.example.com/novel/123',
      );
    });

    test('decodeDataUrl 解析 data:;base64,...', () {
      const path = '/search?keyword=斗破&page=1';
      final encoded = base64Encode(utf8.encode(path));
      final dataUrl = 'data:;base64,$encoded,{"type":"maoyankanshu"}';
      expect(MaoYanNovelSource.decodeDataUrl(dataUrl), path);
    });

    test('decodeDataUrl 解析带中文的 data: URL', () {
      const path = '/novel/12345/chapters';
      final encoded = base64Encode(utf8.encode(path));
      final dataUrl = 'data:;base64,$encoded,{"type":"maoyankanshu"}';
      expect(MaoYanNovelSource.decodeDataUrl(dataUrl), path);
    });

    test('decodeDataUrl 处理无效 base64 不崩溃', () {
      final result = MaoYanNovelSource.decodeDataUrl(
        'data:;base64,!!!invalid!!!,{"type":"maoyankanshu"}',
      );
      expect(result, isNotEmpty);
    });

    test('encodeDataUrl 生成正确的 data: URL', () {
      const path = '/novel/12345';
      final url = MaoYanNovelSource.encodeDataUrl(path);
      expect(url, startsWith('data:;base64,'));
      expect(url, endsWith(',{"type":"maoyankanshu"}'));
      // round-trip
      expect(MaoYanNovelSource.decodeDataUrl(url), path);
    });
  });

  group('MaoYanNovelSource — 认证信息提取', () {
    const dummyComment = r'''getHost = i => {
    [domain, uType] = $.domains[i];
    [aesKey, Authorization] = [
        ["f041c49714d39908", "beaererXXXXXXXX"],
        ["4395daa50ad6baf7", "beaererYYYYYYYY"]
    ][uType];
}
var domains = [["longchunbajiao", 0],["xingliangglobal", 1]];
''';

    test('提取域名列表', () {
      final (domains, _, _) =
          MaoYanNovelSource.extractAuthFromComment(dummyComment);
      expect(domains, hasLength(2));
      expect(domains[0].$1, 'longchunbajiao');
      expect(domains[0].$2, 0);
      expect(domains[1].$1, 'xingliangglobal');
      expect(domains[1].$2, 1);
    });

    test('提取 AES Key', () {
      final (_, aesKeys, _) =
          MaoYanNovelSource.extractAuthFromComment(dummyComment);
      expect(aesKeys, hasLength(2));
      expect(aesKeys[0], 'f041c49714d39908');
      expect(aesKeys[1], '4395daa50ad6baf7');
    });

    test('提取 Authorization Token', () {
      final (_, _, authTokens) =
          MaoYanNovelSource.extractAuthFromComment(dummyComment);
      expect(authTokens, hasLength(2));
      // 验证前加 Bearer 前缀
      expect(authTokens[0], startsWith('Bearer'));
      expect(authTokens[0], contains('XXXXXXXX'));
    });

    test('从内置 JSON 提取认证信息', () async {
      // 从 test asset 加载
      final jsonStr =
          await _loadTestSourceJson();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final comment = '${json['bookSourceComment'] ?? ''}';

      final (domains, aesKeys, authTokens) =
          MaoYanNovelSource.extractAuthFromComment(comment);

      // 13 个域名
      expect(domains, hasLength(13), reason: '应有 13 个域名（9 old + 4 new）');
      expect(aesKeys, hasLength(2), reason: '2 组 AES Key');
      expect(authTokens, hasLength(2), reason: '2 组 Authorization Token');

      // 第一个域名应该是 longchunbajiao (uType=0)
      expect(domains[0].$1, 'longchunbajiao');
      expect(domains[0].$2, 0);

      // 第一个 aesKey 是旧的
      expect(aesKeys[0], 'f041c49714d39908');

      // Token 以 Bearer 开头
      expect(authTokens[0], startsWith('Bearer '));
    });
  });

  group('MaoYanNovelSource — 工厂方法', () {
    test('fromBookSourceJson 正确解析内置 JSON', () async {
      final jsonStr = await _loadTestSourceJson();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final source = MaoYanNovelSource.fromBookSourceJson(json);

      expect(source.baseUrl, isNotEmpty);
      expect(source.headers.containsKey('client-device'), isTrue);
      expect(source.headers.containsKey('Authorization'), isTrue);
      expect(source.headers.containsKey('User-Agent'), isTrue);
      expect(source.headers['User-Agent'], 'okhttp/4.9.2');
      expect(source.domains, hasLength(13));
    });

    test('supportsBookSourceJson 识别猫眼书源', () {
      // 契约变更：光靠 bookSourceName 含「猫眼」不再命中本适配器。
      // 本适配器硬编码 /search 路径 + 只用 comment 里的域名表，任何第三方
      // 同名源被劫持进来都会因 domains 为空而请求发不出去（搜索/发现全空）。
      // 这类源应落到通用 RuleNovelSource。详见 source_routing_test.dart。
      expect(
        MaoYanNovelSource.supportsBookSourceJson({
          'bookSourceName': '猫眼看书（优++）',
        }),
        isFalse,
        reason: '无认证特征的同名第三方源必须交给通用规则引擎',
      );
      // 带真实认证特征（内置源形态）才命中：searchUrl 的 maoyankanshu 标记
      expect(
        MaoYanNovelSource.supportsBookSourceJson({
          'bookSourceName': '猫眼看书（优++）',
          'searchUrl':
              'data:;base64,{{java.base64Encode("/search")}},{"type":"maoyankanshu"}',
        }),
        isTrue,
      );
      // 光有 myweipin 字样但没有域名表/token → 不命中（适配器跑不起来）
      expect(
        MaoYanNovelSource.supportsBookSourceJson({
          'bookSourceName': '其他书源',
          'bookSourceComment': 'myweipin',
        }),
        isFalse,
      );
      expect(
        MaoYanNovelSource.supportsBookSourceJson({
          'bookSourceName': 'WTZW',
        }),
        isFalse,
      );
    });
  });

  group('MaoYanNovelSource — NovelSourceFactory 集成', () {
    test('工厂自动路由到 MaoYanNovelSource', () async {
      final jsonStr = await _loadTestSourceJson();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final source = NovelSourceFactory.fromBookSourceJson(json);
      expect(source, isA<MaoYanNovelSource>());
    });
  });
}

/// 加载内置书源 JSON
Future<String> _loadTestSourceJson() async {
  // flutter test 从项目根运行，用相对路径读取仓库内资源，跨平台可用
  return await File('assets/data/maoyan_book_source.json').readAsString();
}
