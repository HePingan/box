import 'package:box/plugin_manager.dart';
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
  });
}
