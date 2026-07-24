import 'package:box/features/extensions/market/domain/plugin_market_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('A3 商店模型新字段', () {
    test('MarketPluginTemplate 解析 downloadCount / publishedAt', () {
      final tpl = MarketPluginTemplate.tryFromJson({
        'id': 'user.u1.demo',
        'title': 'Demo',
        'subtitle': 'sub',
        'areaCode': 'recommend',
        'actionCode': 'toast',
        'payload': '',
        'downloadCount': 42,
        'publishedAt': '2026-01-02T03:04:05.000',
        'tags': ['工具', '推荐'],
      });
      expect(tpl, isNotNull);
      expect(tpl!.downloadCount, 42);
      expect(tpl.publishedAt, '2026-01-02T03:04:05.000');
      expect(tpl.tags, containsAll(<String>['工具', '推荐']));
    });

    test('缺省字段安全回退', () {
      final tpl = MarketPluginTemplate.tryFromJson({
        'id': 'user.u1.demo',
        'title': 'Demo',
        'payload': '',
      });
      expect(tpl, isNotNull);
      expect(tpl!.downloadCount, 0);
      expect(tpl.publishedAt, '');
    });

    test('toJson 往返保留新字段', () {
      final tpl = MarketPluginTemplate.tryFromJson({
        'id': 'user.u1.demo',
        'title': 'Demo',
        'payload': '',
        'downloadCount': 7,
        'publishedAt': '2026-05-06T00:00:00.000',
      });
      final round = MarketPluginTemplate.tryFromJson(tpl!.toJson());
      expect(round!.downloadCount, 7);
      expect(round.publishedAt, '2026-05-06T00:00:00.000');
    });
  });

  group('A3 排序纯逻辑', () {
    List<MarketPluginTemplate> mk(List<Map<String, dynamic>> raw) => raw
        .map((e) => MarketPluginTemplate.tryFromJson({
              'title': 'T',
              'payload': '',
              ...e,
            })!)
        .toList();

    test('按下载量降序', () {
      final list = mk([
        {'id': 'a', 'downloadCount': 3},
        {'id': 'b', 'downloadCount': 10},
        {'id': 'c', 'downloadCount': 5},
      ]);
      list.sort((a, b) => b.downloadCount.compareTo(a.downloadCount));
      expect(list.map((e) => e.id).toList(), ['b', 'c', 'a']);
    });

    test('按更新时间降序（字符串 ISO 可比）', () {
      final list = mk([
        {'id': 'a', 'publishedAt': '2026-01-01T00:00:00.000'},
        {'id': 'b', 'publishedAt': '2026-03-01T00:00:00.000'},
        {'id': 'c', 'publishedAt': '2026-02-01T00:00:00.000'},
      ]);
      list.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      expect(list.map((e) => e.id).toList(), ['b', 'c', 'a']);
    });
  });
}
