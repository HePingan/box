// 服务监控插件：快照解析与文案的用例（纯 Dart，不起 Flutter）。
import 'dart:convert';

import 'package:box/features/extensions/plugins/monitor/monitor_models.dart';
import 'package:flutter_test/flutter_test.dart';

final _goodBody = jsonEncode({
  'generatedAt': '2026-09-25T10:37:13+08:00',
  'panelUrl': 'https://ham.hpa888.top/',
  'summary': {'total': 2, 'up': 1, 'down': 1},
  'monitors': [
    {'name': 'Box 更新服务', 'up': false, 'id': 7, 'pingMs': 0, 'uptime24h': 98.5},
    {'name': 'myb2api 码友邦桥接', 'up': true, 'id': 1, 'pingMs': 118, 'uptime24h': 100.0},
  ],
});

void main() {
  group('快照解析', () {
    test('字段齐全：条目、计数、采样时间、面板地址都对', () {
      final snap = MonitorSnapshot.parse(_goodBody);
      expect(snap.total, 2);
      expect(snap.upCount, 1);
      expect(snap.downCount, 1);
      expect(snap.allUp, isFalse);
      expect(snap.panelUrl, 'https://ham.hpa888.top/');
      expect(snap.generatedAt, isNotNull);
      expect(
        snap.generatedAt!.toUtc().hour,
        2,
        reason: '10:37+08:00 换成 UTC 是 02:37',
      );
      expect(snap.monitors.first.name, 'Box 更新服务');
      expect(snap.monitors.first.up, isFalse);
      expect(snap.monitors.first.pingMs, 0);
      expect(snap.monitors.first.uptime24h, 98.5);
    });

    test('全在线时 allUp 为真', () {
      final snap = MonitorSnapshot.parse(
        jsonEncode({
          'monitors': [
            {'name': 'a', 'up': true},
            {'name': 'b', 'up': true},
          ],
        }),
      );
      expect(snap.allUp, isTrue);
      expect(snap.downCount, 0);
    });

    test('宽容：数字用字符串、1/0 当真假、缺字段用兜底', () {
      final snap = MonitorSnapshot.parse(
        jsonEncode({
          'monitors': [
            {'name': 'b', 'up': 1, 'id': '9', 'pingMs': '120', 'uptime24h': '99.9'},
          ],
        }),
      );
      final e = snap.monitors.single;
      expect(e.up, isTrue);
      expect(e.id, 9);
      expect(e.pingMs, 120);
      expect(e.uptime24h, closeTo(99.9, 1e-9));
    });

    test('没有名字的条目直接丢掉，不影响别的条目', () {
      final snap = MonitorSnapshot.parse(
        jsonEncode({
          'monitors': [
            {'up': true},
            {'name': '   ', 'up': true},
            {'name': '留下', 'up': true},
          ],
        }),
      );
      expect(snap.total, 1);
      expect(snap.monitors.single.name, '留下');
    });

    test('缺采样时间/面板地址时不抛，只是变 null', () {
      final snap = MonitorSnapshot.parse('{"monitors": []}');
      expect(snap.total, 0);
      expect(snap.generatedAt, isNull);
      expect(snap.panelUrl, isNull);
      expect(snap.allUp, isFalse, reason: '空列表不算「全部在线」');
    });

    test('结构不对就抛 MonitorFormatException', () {
      expect(
        () => MonitorSnapshot.parse('[1,2,3]'),
        throwsA(isA<MonitorFormatException>()),
      );
      expect(
        () => MonitorSnapshot.parse('{"monitors": "nope"}'),
        throwsA(isA<MonitorFormatException>()),
      );
      expect(
        () => MonitorSnapshot.parse('这不是 JSON'),
        throwsA(isA<MonitorFormatException>()),
      );
    });

    test('证书字段：剩余天数、是否有效、缺字段', () {
      final snap = MonitorSnapshot.parse(
        jsonEncode({
          'monitors': [
            {'name': 'a', 'up': true, 'certDays': 43, 'certValid': true},
            {'name': 'b', 'up': true, 'certDays': 7, 'certValid': true},
            {'name': 'c', 'up': true, 'certDays': 0, 'certValid': false},
            {'name': 'd', 'up': true},
          ],
        }),
      );
      expect(snap.monitors[0].certificateLabel, '证书 43 天');
      expect(snap.monitors[0].certificateWarning, isFalse);
      expect(snap.monitors[1].certificateLabel, '证书 7 天');
      expect(snap.monitors[1].certificateWarning, isTrue);
      expect(snap.monitors[2].certificateLabel, '证书已失效');
      expect(snap.monitors[2].certificateWarning, isTrue);
      expect(snap.monitors[3].certificateLabel, isNull, reason: '没有证书信息就不显示这一段');
      expect(snap.monitors[3].certificateWarning, isFalse, reason: '不知道 ≠ 有问题');
    });

    test('证书边界：正好 30 天不提醒，29 天提醒；没有天数但标了失效也提醒', () {
      // 注意：不能写成 `?'certDays': days` —— map 的**键**不可能为 null，
      // 那会触发 invalid_null_aware_operator（warning，会把 analyze 门禁打红）。
      MonitorEntry parse(int? days, bool? valid) {
        final raw = <String, Object?>{'name': 'x', 'up': true};
        if (days != null) raw['certDays'] = days;
        if (valid != null) raw['certValid'] = valid;
        return MonitorEntry.tryParse(raw)!;
      }
      expect(parse(30, true).certificateWarning, isFalse);
      expect(parse(29, true).certificateWarning, isTrue);
      expect(parse(-3, true).certificateLabel, '证书已到期');
      expect(parse(-3, true).certificateWarning, isTrue);
      expect(parse(null, false).certificateLabel, '证书已失效');
      expect(parse(null, false).certificateWarning, isTrue);
    });

    test('key：有 id 用 id，没有就用名字', () {
      final snap = MonitorSnapshot.parse(
        jsonEncode({
          'monitors': [
            {'name': 'a', 'id': 3, 'up': true},
            {'name': 'b', 'up': true},
          ],
        }),
      );
      expect(snap.monitors[0].key, 'id:3');
      expect(snap.monitors[1].key, 'name:b');
    });
  });

  group('文案', () {
    test('多久之前：刚刚 / 分钟 / 小时 / 天，负数与未知', () {
      final now = DateTime(2026, 9, 25, 12, 0);
      expect(monitorAgeText(null, now: now), isNull);
      expect(
        monitorAgeText(now.subtract(const Duration(seconds: 20)), now: now),
        '刚刚',
      );
      expect(
        monitorAgeText(now.subtract(const Duration(minutes: 3)), now: now),
        '3 分钟前',
      );
      expect(
        monitorAgeText(now.subtract(const Duration(hours: 5)), now: now),
        '5 小时前',
      );
      expect(
        monitorAgeText(now.subtract(const Duration(days: 2)), now: now),
        '2 天前',
      );
      expect(
        monitorAgeText(now.add(const Duration(minutes: 5)), now: now),
        '刚刚',
        reason: '服务端时间比手机快时不该显示负数',
      );
    });

    test('延迟与可用率文案', () {
      expect(monitorPingText(118), '118 ms');
      expect(monitorPingText(null), '—');
      expect(monitorUptimeText(100.0), '100%');
      expect(monitorUptimeText(99.98), '99.98%');
      expect(monitorUptimeText(99.5), '99.50%');
      expect(monitorUptimeText(null), '—');
      expect(monitorUptimeText(120), '100%', reason: '越界值夹到 0..100');
      expect(monitorUptimeText(-1), '0%');
    });
  });
}
