// 服务监控插件：抓取与缓存的用例（假 fetcher，不碰网络）。
import 'dart:convert';

import 'package:box/features/extensions/plugins/monitor/monitor_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String bodyWith({bool up = true, String name = 'Box 更新服务'}) => jsonEncode({
  'generatedAt': '2026-09-25T10:37:13+08:00',
  'panelUrl': 'https://ham.hpa888.top/',
  'monitors': [
    {'name': name, 'up': up, 'id': 7, 'pingMs': 110, 'uptime24h': 100.0},
  ],
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('fetch', () {
    test('成功：解析出来，同时把原始文本和取回时间落盘', () async {
      final service = ServiceMonitorService(
        fetcher: (url, timeout) async => bodyWith(),
      );
      final snap = await service.fetch();
      expect(snap.total, 1);
      expect(snap.monitors.single.name, 'Box 更新服务');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ServiceMonitorService.cacheKey), isNotNull);
      expect(prefs.getInt(ServiceMonitorService.cacheAtKey), isNotNull);
    });

    test('请求打在配置的端点上（默认是边缘机那个静态文件）', () async {
      Uri? seen;
      final service = ServiceMonitorService(
        fetcher: (url, timeout) async {
          seen = url;
          return bodyWith();
        },
      );
      await service.fetch();
      expect(seen, ServiceMonitorService.defaultEndpoint);
      expect(seen.toString(), 'https://box.hpa888.top/monitors.json');
    });

    test('端点已收口：配置了令牌就带 ?token=，没配就不带', () async {
      final withToken = ServiceMonitorService(
        fetcher: (u, t) async => bodyWith(),
        token: 'abc123',
      );
      expect(
        withToken.requestUrl.toString(),
        'https://box.hpa888.top/monitors.json?token=abc123',
      );

      Uri? seen;
      final capture = ServiceMonitorService(
        fetcher: (u, t) async {
          seen = u;
          return bodyWith();
        },
        token: 'abc123',
      );
      await capture.fetch();
      expect(seen!.queryParameters['token'], 'abc123');

      final noToken = ServiceMonitorService(fetcher: (u, t) async => bodyWith());
      expect(noToken.requestUrl, ServiceMonitorService.defaultEndpoint);
      expect(noToken.requestUrl.queryParameters.containsKey('token'), isFalse);
    });

    test('已有查询参数时令牌是追加而不是覆盖', () {
      final service = ServiceMonitorService(
        endpoint: Uri.parse('https://box.hpa888.top/monitors.json?x=1'),
        fetcher: (u, t) async => bodyWith(),
        token: 'abc123',
      );
      expect(service.requestUrl.queryParameters, {'x': '1', 'token': 'abc123'});
    });

    test('网络异常 → MonitorFetchException，message 带原因', () async {
      final service = ServiceMonitorService(
        fetcher: (url, timeout) async => throw Exception('连接被拒绝'),
      );
      await expectLater(
        service.fetch(),
        throwsA(
          isA<MonitorFetchException>().having(
            (e) => e.message,
            'message',
            contains('网络请求失败'),
          ),
        ),
      );
    });

    test('拿到的不是快照（结构不对）→ 异常里说明是格式问题', () async {
      final service = ServiceMonitorService(
        fetcher: (url, timeout) async => '<html>502 Bad Gateway</html>',
      );
      await expectLater(
        service.fetch(),
        throwsA(
          isA<MonitorFetchException>().having(
            (e) => e.message,
            'message',
            contains('快照格式不对'),
          ),
        ),
      );
    });

    test('异常内容不落盘：失败之后缓存仍然是上一次成功的那份', () async {
      var fail = false;
      final service = ServiceMonitorService(
        fetcher: (url, timeout) async {
          if (fail) throw Exception('断网');
          return bodyWith(name: '第一次');
        },
      );
      await service.fetch();
      fail = true;
      await expectLater(service.fetch(), throwsA(isA<MonitorFetchException>()));
      final cached = await service.cached();
      expect(cached?.snapshot.monitors.single.name, '第一次');
    });

    test('超大响应不写盘（防止把别的东西当快照存下来）', () async {
      final huge = jsonEncode({
        'monitors': [
          {'name': 'x' * (ServiceMonitorService.cacheMaxBytes + 10), 'up': true},
        ],
      });
      final service = ServiceMonitorService(fetcher: (url, timeout) async => huge);
      await service.fetch();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ServiceMonitorService.cacheKey), isNull);
    });
  });

  group('cached', () {
    test('没有缓存 → null', () async {
      final service = ServiceMonitorService(fetcher: (u, t) async => bodyWith());
      expect(await service.cached(), isNull);
    });

    test('有缓存 → 快照 + 取回时间', () async {
      final service = ServiceMonitorService(fetcher: (u, t) async => bodyWith());
      await service.fetch();
      final cached = await service.cached();
      expect(cached, isNotNull);
      expect(cached!.snapshot.total, 1);
      expect(
        DateTime.now().difference(cached.fetchedAt).inSeconds.abs(),
        lessThan(30),
      );
    });

    test('盘里是坏数据 → 当没有缓存（不抛异常）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ServiceMonitorService.cacheKey: '{不是 JSON',
      });
      final service = ServiceMonitorService(fetcher: (u, t) async => bodyWith());
      expect(await service.cached(), isNull);
    });

    test('clearCache 之后就没有了', () async {
      final service = ServiceMonitorService(fetcher: (u, t) async => bodyWith());
      await service.fetch();
      await service.clearCache();
      expect(await service.cached(), isNull);
    });
  });
}
