import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PluginSubmissionDto status labels', () {
    final pending = PluginSubmissionDto.fromJson({
      'id': 'ps_1',
      'pluginId': 'user.u_1.demo',
      'title': 'Demo',
      'subtitle': '',
      'version': '1.0.0',
      'status': 'pending_review',
      'actionCode': 'toast',
      'areaCode': 'recommend',
      'reviewNote': '',
      'authorName': 'alice',
    });
    expect(pending.statusLabel, '待审核');
    expect(pending.pluginId, 'user.u_1.demo');
  });

  test('AdminPluginQueue parses items and published', () {
    final queue = AdminPluginQueue.fromJson({
      'pendingCount': 1,
      'rejectsToday': 2,
      'items': [
        {
          'id': 'ps_1',
          'pluginId': 'user.u_1.demo',
          'title': 'Demo',
          'status': 'pending_review',
          'actionCode': 'toast',
          'areaCode': 'recommend',
          'authorName': 'alice',
        }
      ],
      'published': [
        {
          'id': 'user.u_1.demo',
          'title': 'Demo',
          'author': 'alice',
        }
      ],
      'audit': [
        {'action': 'approve', 'pluginId': 'user.u_1.demo'},
      ],
    });
    expect(queue.pendingCount, 1);
    expect(queue.rejectsToday, 2);
    expect(queue.items, hasLength(1));
    expect(queue.published, hasLength(1));
    expect(queue.audit, hasLength(1));
  });

  test('PluginMarketRemoteManifest fromJson', () {
    final m = PluginMarketRemoteManifest.fromJson({
      'version': 3,
      'channel': 'stable',
      'updatedAt': '2026-07-20T00:00:00.000Z',
      'plugins': [
        {
          'id': 'user.u_1.demo',
          'title': 'Demo',
          'actionCode': 'toast',
          'areaCode': 'recommend',
        }
      ],
    });
    expect(m.version, 3);
    expect(m.plugins, hasLength(1));
    expect(m.plugins.first['id'], 'user.u_1.demo');
  });
}
