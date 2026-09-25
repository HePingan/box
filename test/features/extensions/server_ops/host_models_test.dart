// 服务器运维插件：hosts.json 解析与文案的用例（纯 Dart，不起 Flutter）。
import 'dart:convert';

import 'package:box/features/extensions/plugins/server_ops/host_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 线上真实形状：一台在线（字段齐全）+ 一台离线（只有 id/name/ip/online）。
final _goodBody = jsonEncode({
  'generatedAt': '2026-09-25T16:00:00+08:00',
  'hosts': [
    {
      'id': 'hpa888',
      'name': '阿里云 · 主服务端',
      'ip': '47.109.97.1',
      'online': true,
      'cpuPercent': 3.1,
      'cpuCount': 4,
      'memTotalBytes': 7843819520,
      'memUsedBytes': 4307644416,
      'memPercent': 54.9,
      'swapTotalBytes': 2147479552,
      'swapUsedBytes': 244748288,
      'diskTotalBytes': 63224078336,
      'diskUsedBytes': 42084376576,
      'diskPercent': 66.6,
      'load1': 1.53,
      'load5': 0.83,
      'load15': 0.46,
      'uptimeSeconds': 445041,
      'netRxBytesPerSec': 15205,
      'netTxBytesPerSec': 47497,
    },
    {
      'id': 'other',
      'name': '测试机',
      'ip': '10.0.0.2',
      'online': false,
    },
  ],
});

void main() {
  group('快照解析', () {
    test('字段齐全：主机、计数、采样时刻都对', () {
      final snap = HostSnapshot.parse(_goodBody);
      expect(snap.total, 2);
      expect(snap.onlineCount, 1);
      expect(snap.offlineCount, 1);
      expect(snap.allOnline, isFalse);
      expect(snap.generatedAt, isNotNull);
      expect(
        snap.generatedAt!.toUtc().hour,
        8,
        reason: '16:00+08:00 换成 UTC 是 08:00',
      );

      final host = snap.hosts.first;
      expect(host.id, 'hpa888');
      expect(host.name, '阿里云 · 主服务端');
      expect(host.ip, '47.109.97.1');
      expect(host.online, isTrue);
      expect(host.cpuPercent, closeTo(3.1, 1e-9));
      expect(host.cpuCount, 4);
      expect(host.memUsedBytes, 4307644416);
      expect(host.memPercent, closeTo(54.9, 1e-9));
      expect(host.diskPercent, closeTo(66.6, 1e-9));
      expect(host.load1, closeTo(1.53, 1e-9));
      expect(host.uptimeSeconds, 445041);
      expect(host.netRxBytesPerSec, 15205);
    });

    test('全在线时 allOnline 为真', () {
      final snap = HostSnapshot.parse(
        jsonEncode({
          'hosts': [
            {'id': 'a', 'name': 'A', 'online': true, 'cpuPercent': 1},
            {'id': 'b', 'name': 'B', 'online': true, 'cpuPercent': 2},
          ],
        }),
      );
      expect(snap.allOnline, isTrue);
      expect(snap.offlineCount, 0);
      expect(snap.generatedAt, isNull, reason: '没有 generatedAt 就是 null');
    });

    test('离线机器：只缺指标不崩，全部是 null 而不是 0', () {
      final snap = HostSnapshot.parse(_goodBody);
      final offline = snap.hosts.singleWhere((h) => h.id == 'other');
      expect(offline.online, isFalse);
      expect(offline.cpuPercent, isNull);
      expect(offline.memTotalBytes, isNull);
      expect(offline.memPercent, isNull);
      expect(offline.diskPercent, isNull);
      expect(offline.uptimeSeconds, isNull);
      expect(hostPercentText(offline.cpuPercent), '—');
      expect(hostUptimeText(offline.uptimeSeconds), '—');
    });

    test('宽容：字符串数字照收，memPercent 缺了就按 used/total 反算', () {
      final snap = HostSnapshot.parse(
        jsonEncode({
          'hosts': [
            {
              'id': 'b',
              'name': 'B',
              'online': 'true',
              'cpuPercent': '12.5',
              'memTotalBytes': '1000',
              'memUsedBytes': '250',
              'load1': '0.5',
              'uptimeSeconds': '3600',
            },
          ],
        }),
      );
      final host = snap.hosts.single;
      expect(host.online, isTrue);
      expect(host.cpuPercent, closeTo(12.5, 1e-9));
      expect(host.memPercent, closeTo(25.0, 1e-9), reason: '250/1000 反算出 25%');
      expect(host.load1, closeTo(0.5, 1e-9));
      expect(host.uptimeSeconds, 3600);
    });

    test('百分比越界被夹回 0–100（负值/超过 100 的脏数据不许画到线外）', () {
      final snap = HostSnapshot.parse(
        jsonEncode({
          'hosts': [
            {'id': 'a', 'name': 'A', 'online': true, 'cpuPercent': 140},
            {'id': 'b', 'name': 'B', 'online': true, 'cpuPercent': -5},
          ],
        }),
      );
      expect(snap.hosts.first.cpuPercent, 100);
      expect(snap.hosts.last.cpuPercent, 0);
    });

    test('没有名字的条目直接丢掉，不影响别的条目', () {
      final snap = HostSnapshot.parse(
        jsonEncode({
          'hosts': [
            {'id': 'x', 'online': true},
            {'id': 'y', 'name': '   ', 'online': true},
            {'id': 'z', 'name': '留下', 'online': true},
          ],
        }),
      );
      expect(snap.total, 1);
      expect(snap.hosts.single.name, '留下');
    });

    test('id 缺失时用名字当标识（历史缓存的键不能为空）', () {
      final snap = HostSnapshot.parse(
        jsonEncode({
          'hosts': [
            {'name': '只有名字', 'online': true},
          ],
        }),
      );
      expect(snap.hosts.single.id, '只有名字');
    });
  });

  group('坏快照', () {
    test('顶层不是对象 → HostFormatException', () {
      expect(
        () => HostSnapshot.parse('[1, 2, 3]'),
        throwsA(isA<HostFormatException>()),
      );
    });

    test('hosts 不是列表 → HostFormatException', () {
      expect(
        () => HostSnapshot.parse('{"hosts": {"a": 1}}'),
        throwsA(
          isA<HostFormatException>()
              .having((e) => e.message, 'message', contains('hosts')),
        ),
      );
    });

    test('不是合法 JSON → HostFormatException', () {
      expect(
        () => HostSnapshot.parse('<html>502 Bad Gateway</html>'),
        throwsA(
          isA<HostFormatException>()
              .having((e) => e.message, 'message', contains('JSON')),
        ),
      );
    });

    test('hosts 里夹着非对象条目：跳过它，其余照收', () {
      final snap = HostSnapshot.parse(
        jsonEncode({
          'hosts': [
            42,
            null,
            {'id': 'ok', 'name': '正常', 'online': true},
          ],
        }),
      );
      expect(snap.total, 1);
      expect(snap.hosts.single.id, 'ok');
    });
  });

  group('历史环形缓冲', () {
    test('追加一个点，序列增长', () {
      const history = HostHistory();
      final next = history.appended(cpu: 10, mem: 20, disk: 30);
      expect(next.cpu, [10.0]);
      expect(next.mem, [20.0]);
      expect(next.disk, [30.0]);
      expect(next.hasAny, isFalse, reason: '一个点画不出线');
    });

    test('值为 null 的项不落点（缺字段不是 0）', () {
      final next = const HostHistory(cpu: [1, 2])
          .appended(mem: 50); // cpu/disk 都没给
      expect(next.cpu, [1.0, 2.0]);
      expect(next.disk, isEmpty);
      expect(next.mem, [50.0]);
    });

    test('超过上限丢最旧的（保留最近 60 个点）', () {
      var history = const HostHistory();
      for (var i = 1; i <= 65; i++) {
        history = history.appended(cpu: i.toDouble());
      }
      expect(history.cpu.length, kHostHistoryMaxPoints);
      expect(history.cpu.first, 6.0, reason: '第 1–5 个点应被挤掉');
      expect(history.cpu.last, 65.0);
    });

    test('pushHostRing 是纯函数：原序列不被改动', () {
      final source = <double>[1, 2, 3];
      final out = pushHostRing(source, 4, 3);
      expect(out, [2.0, 3.0, 4.0]);
      expect(source, [1.0, 2.0, 3.0]);
    });

    test('encode/decode 来回一致', () {
      const history = HostHistory(cpu: [1.5], mem: [2.5], disk: [3.5]);
      final back = HostHistory.decode(history.encode());
      expect(back.cpu, [1.5]);
      expect(back.mem, [2.5]);
      expect(back.disk, [3.5]);
    });

    test('缓存坏了当"没有历史"，不抛异常', () {
      expect(HostHistory.decode('不是 JSON').cpu, isEmpty);
      expect(HostHistory.decode('{"cpu": "x"}').cpu, isEmpty);
      expect(HostHistory.decode('[1,2]').cpu, isEmpty);
    });
  });

  group('文案', () {
    test('百分比：整数不写小数点，其余一位小数', () {
      expect(hostPercentText(55.0), '55%');
      expect(hostPercentText(54.9), '54.9%');
      expect(hostPercentText(null), '—');
    });

    test('字节数：1024 进制，一位小数', () {
      expect(hostBytesText(7843819520), '7.3 GB');
      expect(hostBytesText(1024), '1.0 KB');
      expect(hostBytesText(512), '512 B');
      expect(hostBytesText(null), '—');
      expect(hostBytesText(-1), '—');
    });

    test('速率带 /s 后缀；负数按 0', () {
      expect(hostRateText(47497), '46.4 KB/s');
      expect(hostRateText(-5), '0 B/s');
      expect(hostRateText(null), '—');
    });

    test('负载三个值拼一行，缺的顶位', () {
      expect(hostLoadText(1.53, 0.83, 0.46), '1.53 / 0.83 / 0.46');
      expect(hostLoadText(1.5, null, null), '1.50 / — / —');
    });

    test('运行时长：天/小时/分钟', () {
      expect(hostUptimeText(445041), '5 天 3 小时');
      expect(hostUptimeText(7200), '2 小时 0 分钟');
      expect(hostUptimeText(300), '5 分钟');
      expect(hostUptimeText(null), '—');
    });

    test('内存一行：已用 / 总量（百分比）', () {
      expect(
        hostUsageText(4307644416, 7843819520, 54.9),
        '4.0 GB / 7.3 GB（54.9%）',
      );
      expect(hostUsageText(null, null, 54.9), '54.9%');
      expect(hostUsageText(null, null, null), '—');
    });

    test('采样时间的人话', () {
      final now = DateTime(2026, 9, 25, 16, 30);
      expect(
        hostAgeText(DateTime(2026, 9, 25, 16, 29, 40), now: now),
        '刚刚',
      );
      expect(
        hostAgeText(DateTime(2026, 9, 25, 16, 10), now: now),
        '20 分钟前',
      );
      expect(
        hostAgeText(DateTime(2026, 9, 25, 12, 30), now: now),
        '4 小时前',
      );
      expect(
        hostAgeText(DateTime(2026, 9, 23, 16, 30), now: now),
        '2 天前',
      );
      expect(hostAgeText(null, now: now), isNull);
    });
  });
}
