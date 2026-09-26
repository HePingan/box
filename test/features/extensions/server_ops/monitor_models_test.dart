// 站点快照（体检卡数据源）的纯逻辑用例。
//
// 最要紧的是 nearestCerts 的排序：卡片存在的意义就是"哪张证书最先到期" ——
// 按名字排的话它会答非所问。

import 'package:box/features/extensions/plugins/server_ops/monitor_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _m(String name,
        {bool up = true, int? certDays, int? pingMs}) =>
    {
      'name': name,
      'up': up,
      // null-aware 元素：值为 null 时这一项根本不进 map（模拟服务端不给该字段）
      'certDays': ?certDays,
      'pingMs': ?pingMs,
    };

void main() {
  test('解析：脏数据只跳过那一条，不让整张卡空掉', () {
    final s = MonitorSnapshot.tryParse({
      'monitors': [
        _m('好的站点', certDays: 80),
        'garbage',
        {'no_name': 1},
        _m('另一个', up: false, certDays: 40),
      ],
    })!;
    expect(s.total, 2);
    expect(s.monitors.map((m) => m.name).toList(), ['好的站点', '另一个']);
  });

  test('没有 certDays（HTTP 检查）→ null，不是 0', () {
    final e = MonitorEntry.tryParse(_m('175 自己的 Hermes'))!;
    expect(e.certDays, isNull);
    expect(e.certTight, isFalse, reason: '拿不到天数不该被当成"快到期"');
  });

  test('证书按天数升序取最近几张（不是按名字）', () {
    final s = MonitorSnapshot.tryParse({
      'monitors': [
        _m('zzz 最晚', certDays: 87),
        _m('aaa 最早', certDays: 42),
        _m('mmm 中间', certDays: 56),
      ],
    })!;
    expect(
      s.nearestCerts().map((m) => m.certDays).toList(),
      [42, 56, 87],
    );
    expect(s.nearestCerts(limit: 2).map((m) => m.name).toList(), ['aaa 最早', 'mmm 中间']);
  });

  test('阈值：14 天算急、30 天算该留意', () {
    expect(MonitorEntry.tryParse(_m('a', certDays: 14))!.certUrgent, isTrue);
    expect(MonitorEntry.tryParse(_m('a', certDays: 15))!.certUrgent, isFalse);
    expect(MonitorEntry.tryParse(_m('a', certDays: 30))!.certTight, isTrue);
    expect(MonitorEntry.tryParse(_m('a', certDays: 31))!.certTight, isFalse);
  });

  test('在线统计与挂了谁', () {
    final s = MonitorSnapshot.tryParse({
      'monitors': [_m('a'), _m('b', up: false), _m('c', up: false)],
    })!;
    expect(s.total, 3);
    expect(s.upCount, 1);
    expect(s.allUp, isFalse);
    expect(s.downNames, ['b', 'c']);
  });

  test('结构不对 → null（界面显示"没取到"，不是假装 0 个站点）', () {
    expect(MonitorSnapshot.tryParse(null), isNull);
    expect(MonitorSnapshot.tryParse({'monitors': 'x'}), isNull);
    expect(MonitorSnapshot.tryParse({'other': []}), isNull);
  });
}
