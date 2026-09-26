import 'dart:convert';

import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:box/features/extensions/market/data/plugin_market_local_sync.dart';
import 'package:box/features/extensions/market/domain/plugin_market_manifest.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 插件包 sha256 的来源问题：`downloadPackage` 返回的 sha256 取自**同一个响应的
/// 响应头**，拿它当判据等于"自己验自己"—— 中间人改包再改头照样通过。
/// 清单里的 `packageSha256` 与包体不同源，才是有效的判据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final body = utf8.encode('PK\u0003\u0004fake zip bytes for hash test');
  final realHash = sha256.convert(body).toString();
  final otherHash =
      sha256.convert(utf8.encode('another payload entirely')).toString();

  MarketPluginTemplate tpl(String manifestSha, {String fmt = 'zip'}) =>
      MarketPluginTemplate.tryFromJson({
        'id': 'published_zip_plugin',
        'title': '有包的已发布插件',
        'subtitle': '清单给了 sha256',
        'areaCode': 'recommend',
        'actionCode': 'toast',
        'packageFormat': fmt,
        'packageUrl':
            'https://example.invalid/api/plugin-market/published_zip_plugin/package',
        'packageSha256': manifestSha,
      })!;

  PluginMarketApi api({required String headerSha}) => PluginMarketApi(
        httpClient: MockClient((req) async {
          if (req.url.path.contains('/package')) {
            return http.Response.bytes(
              body,
              200,
              headers: {
                'x-package-sha256': headerSha,
                'x-package-format': 'zip',
              },
            );
          }
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        loadSession: () async => null,
      );

  group('插件包校验以清单为准（不自己验自己）', () {
    test('清单 sha256 与包体不符 → 拒绝安装，哪怕响应头报的是「对」的', () async {
      final sync = PluginMarketLocalSync(api: api(headerSha: realHash));

      await expectLater(
        sync.installFromTemplate(tpl(otherHash)),
        throwsA(isA<PluginMarketApiException>()),
        reason: '响应头与包体同源，它说"对"没有证明力；清单才算数',
      );
    });

    test('清单 sha256 正确、响应头撒谎 → 仍能装上（以清单为准）', () async {
      final sync = PluginMarketLocalSync(api: api(headerSha: otherHash));

      final config = await sync.installFromTemplate(tpl(realHash));

      expect(config.enabled, isTrue);
      expect(config.packageSha256, realHash);
    });

    test('清单没给 sha256 时退回响应头（弱一档，但比不验强）', () async {
      final sync = PluginMarketLocalSync(api: api(headerSha: otherHash));

      await expectLater(
        sync.installFromTemplate(tpl('')),
        throwsA(isA<PluginMarketApiException>()),
      );
    });
  });

  group('FIX-10：只有清单声明 zip 才下载整包', () {
    test('非 zip 模板装的时候不该请求 /package（省一次整包传输）', () async {
      final hits = <String>[];
      final api2 = PluginMarketApi(
        httpClient: MockClient((req) async {
          hits.add(req.url.path);
          if (req.url.path.contains('/package')) {
            return http.Response.bytes(body, 200, headers: const {
              'x-package-sha256': '',
            });
          }
          return http.Response(
            '{}',
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        loadSession: () async => null,
      );

      // 清单带了 sha256、也带了 packageUrl，但 packageFormat 不是 zip：
      // 此前这种"弱启发式"命中就会拉一整个包（服务端自报上限 50MB）然后扔掉。
      final sync = PluginMarketLocalSync(api: api2);
      final config = await sync.installFromTemplate(tpl(realHash, fmt: 'json'));

      expect(
        hits.any((h) => h.contains('/package')),
        isFalse,
        reason: 'packageFormat != zip 时应走 /install 的 JSON 路径',
      );
      expect(config.enabled, isTrue);
    });
  });

  group('packageTrust：记下指纹锚在哪（审计用）', () {
    test('清单给了 sha256 → 锚在清单', () async {
      final sync = PluginMarketLocalSync(api: api(headerSha: otherHash));
      final config = await sync.installFromTemplate(tpl(realHash));

      expect(config.packageTrust, 'manifest');
    });

    test('只有响应头给了 sha256 → 锚在响应头（弱一档，如实记下）', () async {
      final sync = PluginMarketLocalSync(api: api(headerSha: realHash));
      final config = await sync.installFromTemplate(tpl(''));

      expect(config.packageTrust, 'response-header');
    });
  });
}

