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
    test('blocks install when action is not registered', () {
      final template = MarketPluginTemplate.tryFromJson({
        'id': 'custom_action_plugin',
        'title': '自定义动作',
        'actionCode': 'custom.missing',
      })!;

      final result = PluginCompatibilityChecker.check(
        template,
        currentAppVersion: '1.0.0',
        actionExists: (_) => false,
        permissionSupported: (_) => true,
      );

      expect(result.canInstall, isFalse);
      expect(result.blockingIssues.single.code, 'action_unavailable');
    });

    test('checks app version permissions and deprecated warnings', () {
      final template = MarketPluginTemplate.tryFromJson({
        'id': 'compat_plugin',
        'title': '兼容性插件',
        'actionCode': 'custom.route',
        'minAppVersion': '2.0.0',
        'permissions': ['network', 'camera'],
        'deprecated': true,
      })!;

      final result = PluginCompatibilityChecker.check(
        template,
        currentAppVersion: '1.5.0',
        actionExists: (_) => true,
        permissionSupported: (permission) =>
            permission == PluginPermission.network,
      );

      expect(result.canInstall, isFalse);
      expect(
        result.blockingIssues.map((e) => e.code),
        containsAll(['app_version_unsupported', 'permission_unsupported']),
      );
      expect(result.warningIssues.single.code, 'plugin_deprecated');
    });

    test('allows compatible plugins', () {
      final template = MarketPluginTemplate.tryFromJson({
        'id': 'compatible_plugin',
        'title': '兼容插件',
        'actionCode': 'custom.route',
        'minAppVersion': '1.0.0',
        'permissions': ['network'],
      })!;

      final result = PluginCompatibilityChecker.check(
        template,
        currentAppVersion: '1.5.0',
        actionExists: (_) => true,
        permissionSupported: (_) => true,
      );

      expect(result.canInstall, isTrue);
      expect(result.issues, isEmpty);
    });
  });
}
