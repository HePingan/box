import 'package:box/novel/core/cache_store.dart';
import 'package:box/plugin_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomePlugin lifecycle and event bus', () {
    test(
      'host notifies lifecycle hooks on register toggle and unregister',
      () async {
        final events = <String>[];
        final lifecycle = _RecordingLifecycle(events);
        final host = HomePluginHost(
          persistence: HomePluginPersistence(
            cache: CacheStore.inMemory('home_plugin_lifecycle'),
          ),
          lifecycle: lifecycle,
        );
        await host.bootstrap();

        await host.register(
          HomePlugin(
            id: 'lifecycle_plugin',
            title: 'Lifecycle Plugin',
            subtitle: 'Lifecycle test',
            icon: Icons.extension_outlined,
            color: Colors.blue,
            area: HomePluginArea.center,
            onTap: (_) async {},
          ),
        );
        await host.toggleEnabled('lifecycle_plugin', false);
        await host.unregister('lifecycle_plugin');

        expect(events, [
          'initialize:lifecycle_plugin',
          'disabled:lifecycle_plugin',
          'uninstall:lifecycle_plugin',
        ]);
      },
    );

    test('event bus emits to subscribers and supports unsubscribe', () {
      final bus = PluginEventBus();
      final received = <dynamic>[];
      void handler(dynamic data) => received.add(data);

      bus.subscribe('plugin.test', handler);
      bus.emit('plugin.test', {'ok': true});
      bus.unsubscribe('plugin.test', handler);
      bus.emit('plugin.test', {'ok': false});

      expect(received, [
        {'ok': true},
      ]);
    });
  });
}

class _RecordingLifecycle implements HomePluginLifecycle {
  _RecordingLifecycle(this.events);

  final List<String> events;

  @override
  Future<void> onInitialize(HomePlugin plugin) async {
    events.add('initialize:${plugin.id}');
  }

  @override
  Future<void> onEnabled(HomePlugin plugin) async {
    events.add('enabled:${plugin.id}');
  }

  @override
  Future<void> onDisabled(HomePlugin plugin) async {
    events.add('disabled:${plugin.id}');
  }

  @override
  Future<void> onUninstall(HomePlugin plugin) async {
    events.add('uninstall:${plugin.id}');
  }

  @override
  Future<bool> validate(HomePlugin plugin) async => true;
}
