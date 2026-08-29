import 'package:box/novel/core/source_health_service.dart';
import 'package:box/novel/pages/source_manager/book_source_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// ping 的「同源防并发」契约。
///
/// 旧实现用 `Set<String> _inProgress` + 固定 sleep 100ms：撞上正在跑的探测时
/// 睡 100ms 然后读缓存。两个问题：
///   1. 100ms 是凭空猜的。真实探测最长 8s，睡醒缓存大概率还是空的，
///      于是返回 sourceId 为空串的 unknown 快照 —— 调用方拿到的是
///      「张冠李戴」的结果，而不是自己请求那个源的结果。
///   2. 即便缓存恰好有值，那也可能是上一轮的旧快照。
///
/// 正确做法是共享同一个 Future：后到的调用方直接 await 前一个，
/// 拿到的必然是本源、本轮的真实结果。
void main() {
  group('同源并发去重', () {
    test('并发请求同一个源只探测一次', () async {
      final service = _CountingService(const Duration(milliseconds: 50));
      final source = _source(0);

      final results = await Future.wait([
        service.ping(source),
        service.ping(source),
        service.ping(source),
      ]);

      expect(service.probeCount, 1, reason: '同源并发应合并成一次真实探测');
      // 三个调用方都必须拿到本源的真实结果
      for (final r in results) {
        expect(r.sourceId, source.id);
        expect(r.status, SourceHealthStatus.healthy);
      }
    });

    test('后到的调用方拿到真实结果，而非空 sourceId 的 unknown', () async {
      // 探测耗时 300ms，远超旧实现那个 100ms 的猜测值 ——
      // 旧实现在这里必然返回 unknown（sourceId 为空串）
      final service = _CountingService(const Duration(milliseconds: 300));
      final source = _source(0);

      final first = service.ping(source);
      final second = service.ping(source);

      final r2 = await second;
      await first;

      expect(r2.sourceId, source.id, reason: 'sourceId 为空串说明拿错了源的结果');
      expect(r2.status, isNot(SourceHealthStatus.unknown));
    });

    test('探测完成后 in-flight 释放，下次可重新探测', () async {
      final service = _CountingService(Duration.zero);
      final source = _source(0);

      await service.ping(source);
      service.invalidate(source.id); // 清掉缓存，绕开 TTL 短路
      await service.ping(source);

      expect(service.probeCount, 2, reason: 'in-flight 未释放会让后续探测永久复用旧 Future');
    });

    test('探测抛异常也释放 in-flight，不卡死后续请求', () async {
      final service = _CountingService(Duration.zero, throwRaw: true);
      final source = _source(0);

      await expectLater(service.ping(source), throwsA(isA<StateError>()));

      // 第二次必须能重新发起，而不是复用那个已失败的 Future
      await expectLater(service.ping(source), throwsA(isA<StateError>()));
      expect(service.probeCount, 2);
    });

    test('不同源互不阻塞，各自拿到自己的结果', () async {
      final service = _CountingService(const Duration(milliseconds: 30));

      final results = await Future.wait([
        service.ping(_source(0)),
        service.ping(_source(1)),
      ]);

      expect(service.probeCount, 2);
      expect(results[0].sourceId, _source(0).id);
      expect(results[1].sourceId, _source(1).id);
      expect(results[0].sourceId, isNot(results[1].sourceId));
    });

    test('缓存命中时不重复探测（TTL 内）', () async {
      final service = _CountingService(Duration.zero);
      final source = _source(0);

      await service.ping(source);
      await service.ping(source);

      expect(service.probeCount, 1, reason: 'TTL 内应直接返回缓存');
    });
  });

  group('pingAll 遇到重复源', () {
    test('同批内重复源不产生空 sourceId 的结果', () async {
      final service = _CountingService(const Duration(milliseconds: 120));
      final dup = _source(0);
      // 同一个源在同一批（并发度 3）里出现两次
      final sources = [dup, dup, _source(1)];

      final results = await service.pingAll(sources);

      // 结果按 id 归并，重复源只占一个 key
      expect(results.keys, containsAll([dup.id, _source(1).id]));
      for (final entry in results.entries) {
        expect(
          entry.value.sourceId,
          entry.key,
          reason: 'key 与快照里的 sourceId 不一致说明结果错配',
        );
      }
      expect(service.probeCount, 2, reason: '重复源应合并，只探测 2 次');
    });
  });
}

BookSourceModel _source(int i) {
  return BookSourceModel(
    rawJson: {
      'bookSourceName': '源$i',
      'bookSourceUrl': 'http://example.com/$i',
    },
    bookSourceName: '源$i',
    bookSourceUrl: 'http://example.com/$i',
    bookSourceGroup: '',
    searchUrl: '',
    exploreUrl: '',
    enabled: true,
    weight: 0,
    customOrder: i,
  );
}

/// 替身：覆写真实网络探测，只数次数。
///
/// 覆写的是 [SourceHealthService.doProbe]（受保护的探测钩子），
/// 这样 ping 里的缓存 / 去重逻辑仍然是被测的真实实现。
class _CountingService extends SourceHealthService {
  _CountingService(this.delay, {this.throwRaw = false});

  final Duration delay;

  /// 直接抛原始异常（模拟 _doPing 之外的意外失败），验证 in-flight 释放
  final bool throwRaw;

  int probeCount = 0;

  @override
  Future<SourceHealthSnapshot> doProbe(BookSourceModel source) async {
    probeCount++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (throwRaw) throw StateError('boom');
    return SourceHealthSnapshot(
      sourceId: source.id,
      status: SourceHealthStatus.healthy,
      latencyMs: 10,
      lastChecked: DateTime.now(),
    );
  }
}
