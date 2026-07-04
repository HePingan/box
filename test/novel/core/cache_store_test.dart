import 'package:box/novel/core/cache_store.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CacheStore', () {
    test('write then read same key', () async {
      final store = CacheStore.inMemory('test');
      await store.write('k1', {'a': 1});
      final value = await store.read('k1');
      expect(value, {'a': 1});
    });

    test('read missing key returns null', () async {
      final store = CacheStore.inMemory('test');
      expect(await store.read('missing'), isNull);
    });

    test('remove deletes key', () async {
      final store = CacheStore.inMemory('test');
      await store.write('k2', 123);
      await store.remove('k2');
      expect(await store.read('k2'), isNull);
    });
  });
}
