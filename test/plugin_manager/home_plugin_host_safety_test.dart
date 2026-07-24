import 'package:box/plugin_manager.dart';
import 'package:box/core/storage/cache_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomePluginHost safety', () {
    test('batch-safe lookup returns null for missing plugin ids', () async {
      final host = HomePluginHost(
        persistence: HomePluginPersistence(
          cache: CacheStore.inMemory('home_plugin_host_safety_missing'),
        ),
      );
      await host.bootstrap();

      expect(host.findById('missing_plugin_id'), isNull);
    });

    test('batch-safe lookup returns the exact matching plugin', () async {
      final host = HomePluginHost(
        persistence: HomePluginPersistence(
          cache: CacheStore.inMemory('home_plugin_host_safety_match'),
        ),
      );
      await host.bootstrap();

      await host.register(
        HomePlugin(
          id: 'custom_safe_lookup',
          title: 'Safe Lookup',
          subtitle: 'Test plugin',
          icon: Icons.extension_outlined,
          color: Colors.blue,
          area: HomePluginArea.center,
          onTap: (_) async {},
        ),
      );

      final plugin = host.findById('custom_safe_lookup');

      expect(plugin, isNotNull);
      expect(plugin!.id, 'custom_safe_lookup');
    });
  });
}
