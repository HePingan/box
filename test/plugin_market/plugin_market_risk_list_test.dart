import 'package:box/features/extensions/market/data/plugin_market_local_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PluginMarketSyncResult risks', () {
    test('default risks is empty', () {
      const result = PluginMarketSyncResult();
      expect(result.risks, isEmpty);
      expect(result.checked, 0);
      expect(result.yankedDisabled, 0);
      expect(result.riskCleared, 0);
      expect(result.skipped, false);
      expect(result.failed, false);
    });

    test('risks can carry yanked/outdated/checksum entries', () {
      const result = PluginMarketSyncResult(
        checked: 2,
        yankedDisabled: 1,
        riskCleared: 0,
        risks: [
          PluginRiskEntry(
            pluginId: 'p-yanked',
            title: '已下架插件',
            kind: PluginRiskKind.yanked,
            note: '管理员已下架',
            localVersion: '1.0',
          ),
          PluginRiskEntry(
            pluginId: 'p-outdated',
            title: '待更新插件',
            kind: PluginRiskKind.outdated,
            note: '有新版本可更新',
            localVersion: '1.0',
            latestVersion: '1.1',
          ),
          PluginRiskEntry(
            pluginId: 'p-bad',
            title: '校验失败插件',
            kind: PluginRiskKind.checksumMismatch,
            note: '本地包校验与商店不一致',
            localVersion: '2.0',
            latestVersion: '2.0',
          ),
        ],
      );
      expect(result.risks, hasLength(3));
      expect(result.risks[0].kind, PluginRiskKind.yanked);
      expect(result.risks[0].pluginId, 'p-yanked');
      expect(result.risks[1].kind, PluginRiskKind.outdated);
      expect(result.risks[1].localVersion, '1.0');
      expect(result.risks[1].latestVersion, '1.1');
      expect(result.risks[2].kind, PluginRiskKind.checksumMismatch);
      expect(result.risks[2].note, contains('不一致'));
    });

    test('PluginRiskKind has all three variants', () {
      expect(PluginRiskKind.values, hasLength(3));
      expect(PluginRiskKind.values.contains(PluginRiskKind.yanked), true);
      expect(PluginRiskKind.values.contains(PluginRiskKind.outdated), true);
      expect(PluginRiskKind.values.contains(PluginRiskKind.checksumMismatch), true);
    });

    test('PluginRiskEntry required fields are stored', () {
      const entry = PluginRiskEntry(
        pluginId: 'id',
        title: 'title',
        kind: PluginRiskKind.yanked,
        note: 'note',
        localVersion: 'v1',
        latestVersion: '',
      );
      expect(entry.pluginId, 'id');
      expect(entry.title, 'title');
      expect(entry.kind, PluginRiskKind.yanked);
      expect(entry.note, 'note');
      expect(entry.localVersion, 'v1');
      expect(entry.latestVersion, '');
    });

    test('PluginRiskEntry defaults empty versions', () {
      const entry = PluginRiskEntry(
        pluginId: 'x',
        title: 'y',
        kind: PluginRiskKind.outdated,
        note: 'z',
      );
      expect(entry.localVersion, '');
      expect(entry.latestVersion, '');
    });
  });
}
