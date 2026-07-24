import 'package:flutter_test/flutter_test.dart';
import 'package:box/core/storage/cache_store.dart';

void main() {
  group('CacheStore TTL', () {
    late CacheStore store;

    setUp(() {
      store = CacheStore.inMemory('test_ttl');
    });

    test('write then read returns data when ttl is null', () async {
      await store.write('key1', {'hello': 'world'});
      final result = await store.read('key1');
      expect(result, {'hello': 'world'});
    });

    test('read returns null for missing key', () async {
      final result = await store.read('nonexistent');
      expect(result, isNull);
    });

    test('read returns data before TTL expires', () async {
      await store.write('key2', 'still valid', ttl: const Duration(hours: 1));
      final result = await store.read('key2');
      expect(result, 'still valid');
    });

    test('read returns null after TTL expires', () async {
      // 用负 Duration 模拟已过期
      await store.write('key3', 'expired', ttl: const Duration(seconds: -1));
      final result = await store.read('key3');
      expect(result, isNull);
    });

    test('read returns null for negative TTL (already past)', () async {
      await store.write('key4', 'already gone', ttl: const Duration(seconds: -1));
      final result = await store.read('key4');
      expect(result, isNull);
    });

    test('remove deletes the cached entry', () async {
      await store.write('key5', 'to be removed');
      await store.remove('key5');
      final result = await store.read('key5');
      expect(result, isNull);
    });

    test('multiple keys are isolated', () async {
      await store.write('a', 'value_a', ttl: const Duration(seconds: -1));
      await store.write('b', 'value_b', ttl: const Duration(hours: 1));

      // a 已过期
      final resultA = await store.read('a');
      expect(resultA, isNull);

      // b 仍然有效
      final resultB = await store.read('b');
      expect(resultB, 'value_b');
    });

    test('overwrite with new TTL', () async {
      await store.write('key6', 'first', ttl: const Duration(seconds: -1));
      await store.write('key6', 'second', ttl: const Duration(hours: 1));

      final result = await store.read('key6');
      expect(result, 'second');
    });

    test('complex data types round-trip correctly', () async {
      final complex = {
        'list': [1, 2, 3],
        'nested': {'a': 1, 'b': 'hello'},
        'bool': true,
        'number': 3.14,
      };
      await store.write('complex', complex, ttl: const Duration(minutes: 5));
      final result = await store.read('complex');
      expect(result, complex);
    });
  });
}
