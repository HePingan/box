import 'package:box/plugin_manager.dart';
import 'package:box/plugin_market_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomePluginActionRegistry', () {
    test('runs registered custom action codes without enum changes', () async {
      const actionCode = 'test.customActionRegistry';
      HomePluginActionContext? captured;

      HomePluginActionRegistry.register(actionCode, (
        context,
        actionContext,
      ) async {
        captured = actionContext;
      });

      final ran = await HomePluginActionRegistry.run(
        actionCode,
        null,
        const HomePluginActionContext(
          pluginId: 'plugin_a',
          title: 'Plugin A',
          payload: 'payload-a',
        ),
      );

      expect(ran, isTrue);
      expect(captured, isNotNull);
      expect(captured!.pluginId, 'plugin_a');
      expect(captured!.payload, 'payload-a');
    });

    test('returns false for unknown action codes', () async {
      final ran = await HomePluginActionRegistry.run(
        'test.unknownActionRegistry',
        null,
        const HomePluginActionContext(pluginId: 'plugin_b', title: 'Plugin B'),
      );

      expect(ran, isFalse);
    });

    test('custom plugin config preserves actionCode for future actions', () {
      final config = HomeCustomPluginConfig.fromJson({
        'id': 'plugin_c',
        'title': 'Plugin C',
        'actionCode': 'plugin.customFutureAction',
      });

      expect(config.actionCode, 'plugin.customFutureAction');
      expect(config.effectiveActionCode, 'plugin.customFutureAction');
      expect(config.toJson()['actionCode'], 'plugin.customFutureAction');
    });

    test(
      'market install config preserves action code and structured payload',
      () {
        final template = MarketPluginTemplate.tryFromJson({
          'id': 'market_route_plugin',
          'title': '路由插件',
          'actionCode': 'custom.route',
          'payload': {'route': 'test_route'},
        })!;

        final config = HomeCustomPluginConfig.fromMarketTemplateForTest(
          template,
          createdAt: 42,
        );

        expect(config.actionCode, 'custom.route');
        expect(config.effectiveActionCode, 'custom.route');
        expect(config.payload, '{"route":"test_route"}');
        expect(config.toJson()['actionCode'], 'custom.route');
      },
    );

    testWidgets('navigate action resolves registered route builders', (
      tester,
    ) async {
      HomePluginRouteRegistry.register(
        'test_route_registry_page',
        (_) =>
            const Text('Route Registry Page', textDirection: TextDirection.ltr),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await HomePluginActionRegistry.run(
                  'navigate',
                  context,
                  const HomePluginActionContext(
                    pluginId: 'route_plugin',
                    title: 'Route Plugin',
                    payload: '{"route":"test_route_registry_page"}',
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Route Registry Page'), findsOneWidget);
    });
  });
}
