import 'package:flutter_test/flutter_test.dart';

import 'package:box/core/storage/cache_store.dart';

void main() {
  test('clear() 清空全部条目并返回删除数量', () async {
    final store = CacheStore.inMemory('clear-test');
    await store.write('a', {'v': 1});
    await store.write('b', {'v': 2});
    await store.write('c', {'v': 3});

    expect(await store.read('a'), isNotNull);

    final removed = await store.clear();

    expect(removed, 3);
    expect(await store.read('a'), isNull);
    expect(await store.read('b'), isNull);
    expect(await store.read('c'), isNull);
  });

  test('clear() 在空缓存上返回 0 且不抛异常', () async {
    final store = CacheStore.inMemory('clear-empty');
    expect(await store.clear(), 0);
  });

  test('sizeInBytes() 随写入增长、clear 后归零', () async {
    final store = CacheStore.inMemory('size-test');
    expect(await store.sizeInBytes(), 0);

    await store.write('chapter-1', {'content': '正文' * 200});
    final afterFirst = await store.sizeInBytes();
    expect(afterFirst, greaterThan(0));

    await store.write('chapter-2', {'content': '正文' * 200});
    expect(await store.sizeInBytes(), greaterThan(afterFirst));

    await store.clear();
    expect(await store.sizeInBytes(), 0);
  });

  test('clear() 后仍可继续正常写读', () async {
    final store = CacheStore.inMemory('reuse-test');
    await store.write('k', {'v': 'old'});
    await store.clear();
    await store.write('k', {'v': 'new'});

    final data = await store.read('k') as Map;
    expect(data['v'], 'new');
  });
}
