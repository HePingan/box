// 服务器运维插件：抓取、缓存与历史落点的用例（假 fetcher，不碰网络）。
import 'dart:convert';

import 'package:box/features/extensions/plugins/server_ops/host_models.dart';
import 'package:box/features/extensions/plugins/server_ops/host_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String bodyWith({
  double cpu = 3.1,
  double mem = 54.9,
  double disk = 66.6,
  bool online = true,
}) =>
    jsonEncode({
      'generatedAt': '2026-09-25T16:00:00+08:00',
      'hosts': [
        {
          'id': 'hpa888',
          'name': '阿里云 · 主服务端',
          'ip': '47.109.97.1',
          'online': online,
          'cpuPercent': cpu,
          'memTotalBytes': 7843819520,
          'memUsedBytes': 4307644416,
          'memPercent': mem,
          'diskTotalBytes': 63224078336,
          'diskUsedBytes': 42084376576,
          'diskPercent': disk,
        },
      ],
    });

HostSnapshot snapshotWith({
  double cpu = 3.1,
  bool online = true,
  String id = 'hpa888',
}) =>
    HostSnapshot.parse(
      jsonEncode({
        'hosts': [
          {
            'id': id,
            'name': '主机 $id',
            'online': online,
            if (online) 'cpuPercent': cpu,
          },
        ],
      }),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('fetch', () {
    test('成功：解析出来，同时把原始文本和取回时间落盘', () async {
      final service = HostService(fetcher: (url, timeout) async => bodyWith());
      final snap = await service.fetch();
      expect(snap.total, 1);
      expect(snap.hosts.single.name, '阿里云 · 主服务端');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(HostService.cacheKey), isNotNull);
      expect(prefs.getInt(HostService.cacheAtKey), isNotNull);
    });

    test('请求打在配置的端点上（默认是边缘机那个静态文件）', () async {
      Uri? seen;
      final service = HostService(
        fetcher: (url, timeout) async {
          seen = url;
          return bodyWith();
        },
      );
      await service.fetch();
      expect(seen, HostService.defaultEndpoint);
      expect(seen.toString(), 'https://box.hpa888.top/hosts.json');
    });

    test('端点已收口：配了令牌就带 ?token=，没配就不带', () async {
      final withToken = HostService(
        fetcher: (u, t) async => bodyWith(),
        token: 'abc123',
      );
      expect(
        withToken.requestUrl.toString(),
        'https://box.hpa888.top/hosts.json?token=abc123',
      );

      final noToken = HostService(fetcher: (u, t) async => bodyWith());
      expect(noToken.requestUrl, HostService.defaultEndpoint);
      expect(
        noToken.requestUrl.queryParameters.containsKey('token'),
        isFalse,
      );
    });

    test('已有查询参数时令牌是追加而不是覆盖', () {
      final service = HostService(
        endpoint: Uri.parse('https://box.hpa888.top/hosts.json?x=1'),
        fetcher: (u, t) async => bodyWith(),
        token: 'abc123',
      );
      expect(service.requestUrl.queryParameters, {'x': '1', 'token': 'abc123'});
    });

    test('网络异常 → HostFetchException，message 带原因', () async {
      final service = HostService(
        fetcher: (url, timeout) async => throw Exception('连接被拒绝'),
      );
      await expectLater(
        service.fetch(),
        throwsA(
          isA<HostFetchException>().having(
            (e) => e.message,
            'message',
            contains('网络请求失败'),
          ),
        ),
      );
    });

    test('拿到的不是快照（结构不对）→ 异常里说明是格式问题', () async {
      final service = HostService(
        fetcher: (url, timeout) async => '<html>502 Bad Gateway</html>',
      );
      await expectLater(
        service.fetch(),
        throwsA(
          isA<HostFetchException>().having(
            (e) => e.message,
            'message',
            contains('快照格式不对'),
          ),
        ),
      );
    });
  });

  group('缓存', () {
    test('异常内容不落盘：失败之后缓存仍是上一次成功的那份', () async {
      var fail = false;
      final service = HostService(
        fetcher: (url, timeout) async {
          if (fail) throw Exception('断网');
          return bodyWith(cpu: 11.1);
        },
      );
      await service.fetch();
      fail = true;
      await expectLater(service.fetch(), throwsA(isA<HostFetchException>()));

      final cached = await service.cached();
      expect(cached, isNotNull);
      expect(cached!.snapshot.hosts.single.cpuPercent, closeTo(11.1, 1e-9));
    });

    test('cached 把取回时间一起带回来（横幅要显示"几分钟前"）', () async {
      final service = HostService(fetcher: (u, t) async => bodyWith());
      await service.fetch();
      final cached = await service.cached();
      expect(cached, isNotNull);
      expect(
        DateTime.now().difference(cached!.fetchedAt).inSeconds,
        lessThan(5),
      );
    });

    test('没有缓存时 cached 返回 null（不抛异常）', () async {
      final service = HostService(fetcher: (u, t) async => bodyWith());
      expect(await service.cached(), isNull);
    });

    test('缓存内容坏了 → 返回 null（当作没有缓存）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        HostService.cacheKey: '这不是 JSON',
      });
      final service = HostService(fetcher: (u, t) async => bodyWith());
      expect(await service.cached(), isNull);
    });

    test('clearCache 清掉快照与取回时间', () async {
      final service = HostService(fetcher: (u, t) async => bodyWith());
      await service.fetch();
      await service.clearCache();
      expect(await service.cached(), isNull);
    });
  });

  group('历史落点', () {
    test('第一次采样落一个点，并按机器 id 建索引', () async {
      final service = HostService();
      final histories = await service.recordSample(snapshotWith(cpu: 12.5));

      expect(histories['hpa888'], isNotNull);
      expect(histories['hpa888']!.cpu, [12.5]);

      // 读回来一致（索引 key 正确）
      final reloaded = await service.loadHistories();
      expect(reloaded['hpa888']!.cpu, [12.5]);
    });

    test('离线的机器不落点（不落点 ≠ 落一个 0）', () async {
      final service = HostService();
      final base = DateTime(2026, 9, 25, 16, 0);
      // 先在线采一个点，再等一个采样周期改为离线：序列长度不该变。
      await service.recordSample(snapshotWith(cpu: 10), now: base);
      final histories = await service.recordSample(
        snapshotWith(online: false),
        now: base.add(const Duration(seconds: kHostSampleStepSec)),
      );
      expect(histories['hpa888']!.cpu, [10.0]);
      expect(histories['hpa888']!.hasAny, isFalse, reason: '只有一个点');
    });

    test('不到 2 分钟不重复落点（避免连点刷新把折线挤掉）', () async {
      final service = HostService();
      final base = DateTime(2026, 9, 25, 16, 0);
      await service.recordSample(snapshotWith(cpu: 10), now: base);
      final second = await service.recordSample(
        snapshotWith(cpu: 20),
        now: base.add(const Duration(seconds: 30)),
      );
      expect(second['hpa888']!.cpu, [10.0], reason: '30 秒后再来一次不该落点');

      final third = await service.recordSample(
        snapshotWith(cpu: 20),
        now: base.add(const Duration(seconds: kHostSampleStepSec)),
      );
      expect(third['hpa888']!.cpu, [10.0, 20.0]);
    });

    test('环形缓冲：连续 65 次采样只留最近 60 个点', () async {
      final service = HostService();
      final base = DateTime(2026, 9, 25, 16, 0);
      Map<String, HostHistory> latest = const {};
      for (var i = 0; i < 65; i++) {
        latest = await service.recordSample(
          snapshotWith(cpu: i.toDouble()),
          now: base.add(Duration(seconds: kHostSampleStepSec * i)),
        );
      }
      final cpu = latest['hpa888']!.cpu;
      expect(cpu.length, kHostHistoryMaxPoints);
      expect(cpu.first, 5.0, reason: '前 5 个点应被挤掉');
      expect(cpu.last, 64.0);
    });

    test('clearHistories 把序列与索引都清掉', () async {
      final service = HostService();
      await service.recordSample(snapshotWith(cpu: 1));
      await service.clearHistories();
      expect(await service.loadHistories(), isEmpty);
    });

    test('缓存里是别人的数据（历史键坏）不影响采样', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        HostService.historyIndexKey: <String>['hpa888'],
        HostService.historyKeyFor('hpa888'): '坏数据',
      });
      final service = HostService();
      final histories = await service.recordSample(snapshotWith(cpu: 7.5));
      expect(histories['hpa888']!.cpu, [7.5]);
    });
  });
}
