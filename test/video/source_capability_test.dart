import 'package:flutter_test/flutter_test.dart';

import 'package:box/video/services/source_capability.dart';
import 'package:box/video/services/video_api_service.dart';

/// ① 源能力判定的护栏。
///
/// 用例里的响应样本全部来自 2026-10-03 对 28 个源的真实复测
/// （走 App 同一条代理、关键词「战狼」），不是编的：
/// 当时 8 个源在「关键词搜索」这一档就坏。
void main() {
  group('classifySearchResponse —— 按真实样本判档', () {
    test('标准成功响应 → searchable（list 为空也算成功）', () {
      expect(
        classifySearchResponse(
          statusCode: 200,
          body: '{"code":1,"msg":"数据列表","page":1,"list":[]}',
        ),
        SourceSearchCapability.searchable,
      );
      expect(
        classifySearchResponse(
          statusCode: 200,
          body: '{"code":1,"list":[{"vod_id":1,"vod_name":"战狼"}]}',
        ),
        SourceSearchCapability.searchable,
      );
      // 有些实现用 0 表示成功。
      expect(
        classifySearchResponse(statusCode: 200, body: '{"code":0,"list":[]}'),
        SourceSearchCapability.searchable,
      );
    });

    test('豆瓣/茅台实测样本 code:1002 → keywordForbidden', () {
      const body =
          '{"code":1002,"msg":"Current API forbids keyword search","list":[]}';
      expect(
        classifySearchResponse(statusCode: 200, body: body),
        SourceSearchCapability.keywordForbidden,
      );
      expect(
        isStructurallyBroken(SourceSearchCapability.keywordForbidden),
        isTrue,
      );
    });

    test('卧龙/旺旺实测样本：api 地址回的是 HTML → notAnApi', () {
      const body =
          '<!DOCTYPE html><html><head><title>天涯影视资源</title></head></html>';
      expect(
        classifySearchResponse(
          statusCode: 200,
          body: body,
          contentType: 'text/html',
        ),
        SourceSearchCapability.notAnApi,
      );
      // 哪怕 content-type 缺失（有些站点不写），靠正文形态也要判对。
      expect(
        classifySearchResponse(statusCode: 200, body: '  <html></html>'),
        SourceSearchCapability.notAnApi,
      );
      expect(
        classifySearchResponse(statusCode: 200, body: 'Not Found: api path'),
        SourceSearchCapability.notAnApi,
      );
    });

    test('百度云 zy / 艾旦影视实测样本 404 → notAnApi（接口路径没了）', () {
      expect(
        classifySearchResponse(statusCode: 404, body: '404 page not found'),
        SourceSearchCapability.notAnApi,
      );
      expect(
        classifySearchResponse(statusCode: 410, body: ''),
        SourceSearchCapability.notAnApi,
      );
    });

    test('无尽实测样本 403 → blocked，但不算“接口层坏”', () {
      final cap = classifySearchResponse(
        statusCode: 403,
        body: '<html><body>403 Forbidden</body></html>',
      );
      expect(cap, SourceSearchCapability.blocked);
      // WAF 拦的是出口 IP，不是接口本身坏 —— 别一次就判死。
      expect(isStructurallyBroken(cap), isFalse);
      expect(
        classifySearchResponse(statusCode: 429, body: ''),
        SourceSearchCapability.blocked,
      );
    });

    test('速播实测样本 522/502、以及连不上 → unreachable，也不判死', () {
      expect(
        classifySearchResponse(statusCode: 522, body: 'connection timed out'),
        SourceSearchCapability.unreachable,
      );
      expect(
        classifySearchResponse(statusCode: 502, body: ''),
        SourceSearchCapability.unreachable,
      );
      expect(
        classifySearchResponse(statusCode: null, body: ''),
        SourceSearchCapability.unreachable,
      );
      expect(isStructurallyBroken(SourceSearchCapability.unreachable), isFalse);
    });

    test('判不出来的一律 unknown，不据此隐藏任何源', () {
      // 空响应体。
      expect(
        classifySearchResponse(statusCode: 200, body: '   '),
        SourceSearchCapability.unknown,
      );
      // 是 JSON，但没有 code 字段（不是标准苹果 CMS 响应）。
      expect(
        classifySearchResponse(statusCode: 200, body: '{"list":[]}'),
        SourceSearchCapability.unknown,
      );
      expect(isStructurallyBroken(SourceSearchCapability.unknown), isFalse);
      expect(isStructurallyBroken(SourceSearchCapability.searchable), isFalse);
      expect(isStructurallyBroken(SourceSearchCapability.blocked), isFalse);
    });

    test('describeCapability 给用户看的说法不为空', () {
      for (final capability in SourceSearchCapability.values) {
        expect(describeCapability(capability).trim(), isNotEmpty);
      }
    });
  });

  group('SourceSearchCapabilityProbe —— 探测本身永不炸', () {
    test('按源回报能力，且只探传入的源', () async {
      final probed = <String>[];
      final probe = SourceSearchCapabilityProbe(
        probeOverride: (baseUrl, keyword) async {
          probed.add(baseUrl);
          if (baseUrl.contains('bad')) {
            return const SourceProbeResponse(
              statusCode: 200,
              body: '{"code":1002,"msg":"forbids keyword search"}',
            );
          }
          if (baseUrl.contains('html')) {
            return const SourceProbeResponse(
              statusCode: 200,
              body: '<html>oops</html>',
            );
          }
          return const SourceProbeResponse(statusCode: 200, body: '{"code":1}');
        },
      );

      final results = await probe.probeAll([
        'https://ok.tv/api',
        'https://bad.tv/api',
        'https://html.tv/api',
      ]);

      expect(probed.length, 3);
      expect(results.length, 3);
      final byUrl = {for (final r in results) r.baseUrl: r.capability};
      expect(byUrl['https://ok.tv/api'], SourceSearchCapability.searchable);
      expect(
        byUrl['https://bad.tv/api'],
        SourceSearchCapability.keywordForbidden,
      );
      expect(byUrl['https://html.tv/api'], SourceSearchCapability.notAnApi);
    });

    test('探测抛异常 → 记 unknown，不向上抛（探测不该影响搜索）', () async {
      final probe = SourceSearchCapabilityProbe(
        probeOverride: (baseUrl, keyword) async => throw StateError('boom'),
      );
      final results = await probe.probeAll(['https://a.tv/api']);
      expect(results.single.capability, SourceSearchCapability.unknown);
    });

    test('空列表不发请求', () async {
      var calls = 0;
      final probe = SourceSearchCapabilityProbe(
        probeOverride: (baseUrl, keyword) async {
          calls++;
          return const SourceProbeResponse(statusCode: 200, body: '{"code":1}');
        },
      );
      expect(await probe.probeAll([]), isEmpty);
      expect(calls, 0);
    });
  });

  group('VideoApiService.buildSearchProbeUrl —— 与搜索同一条地址构造路径', () {
    test('探测地址把搜索参数落在和 searchVideo 同一处（内层目标）', () {
      final url = VideoApiService.buildSearchProbeUrl(
        'https://caiji.example.com/api.php/provide/vod/',
        '战狼',
      );
      // 地址会被代理包一层，参数必须落在**内层目标**上，
      // 而不是被塞进代理自己的 query 里（那样站点收到的就是空搜索）。
      final inner = Uri.parse(url).queryParameters['url'];
      expect(inner, isNotNull, reason: '应走代理包装');
      final innerUri = Uri.parse(inner!);
      expect(innerUri.queryParameters['ac'], 'videolist');
      expect(innerUri.queryParameters['wd'], '战狼');
    });
  });
}
