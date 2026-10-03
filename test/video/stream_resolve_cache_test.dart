import 'package:box/video/services/stream_resolve_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamResolveCache', () {
    test('未命中返回 null；写入后命中', () {
      final cache = StreamResolveCache();
      expect(cache.take('a'), isNull);
      cache.put('a', Uri.parse('https://x/a.m3u8'));
      expect(cache.take('a'), Uri.parse('https://x/a.m3u8'));
      expect(cache.hits, 1);
      expect(cache.size, 1);
    });

    test('过期即视为未命中（注入时钟，不靠等待）', () {
      var now = DateTime(2026, 10, 3, 8);
      final cache = StreamResolveCache(
        ttl: const Duration(minutes: 5),
        clock: () => now,
      );
      cache.put('a', Uri.parse('https://x/a.m3u8'));
      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(cache.take('a'), isNotNull);
      now = now.add(const Duration(seconds: 2)); // 超过 5 分钟
      expect(cache.take('a'), isNull);
      expect(cache.size, 0); // 过期项顺手清掉，不会一直涨
    });

    test('并发解析同一地址只算一次（在途合并）', () async {
      final cache = StreamResolveCache();
      var calls = 0;
      Future<Uri> compute() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return Uri.parse('https://x/a.m3u8');
      }

      final results = await Future.wait<Uri>(
        List<Future<Uri>>.generate(5, (_) => cache.resolve('a', compute)),
      );
      expect(calls, 1, reason: '5 个并发调用只应触发一次真实解析');
      expect(results.every((u) => u.path == '/a.m3u8'), isTrue);
      expect(cache.hits, 0, reason: '并发那几个走的是「在途合并」，不是缓存命中');
      // 等解析落地后再来一次，这回才是命中。
      await cache.resolve('a', compute);
      expect(calls, 1);
      expect(cache.hits, 1);
    });

    test('force 忽略已有结果（重试用）', () async {
      final cache = StreamResolveCache();
      var calls = 0;
      Future<Uri> compute() async {
        calls++;
        return Uri.parse('https://x/$calls.m3u8');
      }

      await cache.resolve('a', compute);
      await cache.resolve('a', compute);
      expect(calls, 1);
      await cache.resolve('a', compute, force: true);
      expect(calls, 2);
      expect(cache.take('a'), Uri.parse('https://x/2.m3u8'));
    });

    test('解析失败不写缓存，下次会重来', () async {
      final cache = StreamResolveCache();
      var calls = 0;
      Future<Uri> compute() async {
        calls++;
        throw StateError('boom');
      }

      await expectLater(cache.resolve('a', compute), throwsStateError);
      await expectLater(cache.resolve('a', compute), throwsStateError);
      expect(calls, 2);
      expect(cache.size, 0);
    });

    test('invalidate / clear', () async {
      final cache = StreamResolveCache();
      cache.put('a', Uri.parse('https://x/a.m3u8'));
      cache.put('b', Uri.parse('https://x/b.m3u8'));
      cache.invalidate('a');
      expect(cache.take('a'), isNull);
      expect(cache.take('b'), isNotNull);
      cache.clear();
      expect(cache.size, 0);
    });

    test('peek 不计命中数（预热判断不该算命中）', () {
      final cache = StreamResolveCache();
      cache.put('a', Uri.parse('https://x/a.m3u8'));
      expect(cache.peek('a'), isNotNull);
      expect(cache.hits, 0);
    });
  });
}
