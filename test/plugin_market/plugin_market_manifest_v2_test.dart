import 'package:box/plugin_market_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Plugin market manifest v2 metadata', () {
    test('parses extended metadata with structured payload', () {
      final template = MarketPluginTemplate.tryFromJson({
        'id': 'market_v2_plugin',
        'version': '2.1.0',
        'minAppVersion': '1.1.8',
        'title': 'V2 插件',
        'subtitle': '扩展元数据',
        'areaCode': 'novel',
        'actionCode': 'custom.route',
        'payload': {'route': '/novel/list', 'filter': 'recommend'},
        'author': 'box',
        'tags': ['novel', 'recommend'],
        'permissions': ['openPage', 'network'],
        'deprecated': true,
        'changelog': '支持 Manifest v2',
      });

      expect(template, isNotNull);
      expect(template!.version, '2.1.0');
      expect(template.minAppVersion, '1.1.8');
      expect(template.author, 'box');
      expect(template.tags, ['novel', 'recommend']);
      expect(template.permissions, ['openPage', 'network']);
      expect(template.deprecated, isTrue);
      expect(template.changelog, '支持 Manifest v2');
      expect(template.actionCode, 'custom.route');
      expect(template.payload, isEmpty);
      expect(template.payloadData, {
        'route': '/novel/list',
        'filter': 'recommend',
      });
      expect(template.toJson()['payload'], {
        'route': '/novel/list',
        'filter': 'recommend',
      });
    });

    test('keeps legacy string payload and defaults metadata safely', () {
      final template = MarketPluginTemplate.tryFromJson({
        'id': 'legacy_plugin',
        'title': '旧插件',
        'payload': 'legacy-payload',
      });

      expect(template, isNotNull);
      expect(template!.version, '1.0.0');
      expect(template.minAppVersion, isEmpty);
      expect(template.author, isEmpty);
      expect(template.tags, isEmpty);
      expect(template.permissions, isEmpty);
      expect(template.deprecated, isFalse);
      expect(template.changelog, isEmpty);
      expect(template.payload, 'legacy-payload');
      expect(template.payloadData, isEmpty);
      expect(template.toJson()['payload'], 'legacy-payload');
    });

    test('collects parse errors without dropping valid templates', () {
      final result = parseMarketPluginTemplatesWithReport([
        {'id': 'valid_plugin', 'title': '有效插件'},
        {'title': '缺少 ID'},
        'not-a-map',
      ]);

      expect(result.templates.map((e) => e.id), ['valid_plugin']);
      expect(result.errors, hasLength(2));
      expect(result.errors.map((e) => e.field), containsAll(['id', 'item']));
    });

    test('normalizes typed permissions from manifest strings', () {
      final template = MarketPluginTemplate.tryFromJson({
        'id': 'permission_plugin',
        'title': '权限插件',
        'permissions': ['network', 'clipboard', 'unknown'],
      });

      expect(template, isNotNull);
      expect(template!.typedPermissions, [
        PluginPermission.network,
        PluginPermission.clipboard,
      ]);
      expect(template.requiresPermission(PluginPermission.storage), isFalse);
    });
    test('checks declared permissions before plugin execution', () async {
      final template = MarketPluginTemplate.tryFromJson({
        'id': 'permission_runtime_plugin',
        'title': '运行时权限插件',
        'permissions': ['network', 'clipboard'],
      });

      expect(template, isNotNull);
      expect(
        await PluginPermissionChecker.check(
          template!,
          PluginPermission.network,
        ),
        isTrue,
      );
      expect(
        await PluginPermissionChecker.check(template, PluginPermission.storage),
        isFalse,
      );
    });
  });
}
