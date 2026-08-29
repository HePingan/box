import 'dart:async';

import 'package:box/novel/core/source_health_service.dart';
import 'package:box/novel/pages/source_manager/book_source_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// A2：pingAll 有界并发契约。
///
/// 原实现完全串行：10 个源全超时 = 10×5s ≈ 50s 卡在书源管理页。
/// 改成分批并发后，这里锁死两件事：
///   1. 真的并发了（最差耗时随并发度下降）
///   2. 并发有上限（不打爆连接池，也不让延迟数字互相污染）
void main() {
  test('pingAll 并发度不超过 maxConcurrentProbes', () async {
    final service = _RecordingService(const Duration(milliseconds: 40));
    final sources = _sources(10);

    await service.pingAll(sources);

    expect(
      service.peakConcurrency,
      lessThanOrEqualTo(SourceHealthService.maxConcurrentProbes),
      reason: '并发无上限会瞬间打爆连接池，且各探测互相抢带宽让 latency 偏大误判 degraded',
    );
  });

  test('pingAll 确实并发（不是退化成串行）', () async {
    final service = _RecordingService(const Duration(milliseconds: 40));

    await service.pingAll(_sources(6));

    expect(
      service.peakConcurrency,
      greaterThan(1),
      reason: '退化成串行就白改了，最差耗时又回到 N×timeout',
    );
  });

  test('每个源都有结果，且 key 是 sourceId', () async {
    final service = _RecordingService(Duration.zero);
    final sources = _sources(7);

    final results = await service.pingAll(sources);

    expect(results, hasLength(7));
    for (final s in sources) {
      expect(results.containsKey(s.id), isTrue, reason: '漏掉 ${s.id}');
      expect(results[s.id]!.sourceId, s.id);
    }
  });

  test('源数量不是并发度整数倍时不丢也不越界', () async {
    // 10 % 3 == 1，最后一批只有 1 个 —— sublist 的 end 必须 clamp
    final service = _RecordingService(Duration.zero);

    final results = await service.pingAll(_sources(10));

    expect(results, hasLength(10));
    expect(service.probeCount, 10);
  });

  test('空列表返回空 map，不抛', () async {
    final service = _RecordingService(Duration.zero);
    expect(await service.pingAll(const []), isEmpty);
  });

  test('单个源探测失败不影响同批其他源', () async {
    final service = _RecordingService(
      const Duration(milliseconds: 10),
      failIndexes: {1},
    );
    final sources = _sources(5);

    final results = await service.pingAll(sources);

    expect(results, hasLength(5), reason: '一个源抛异常不能带走整批');
    expect(results[sources[1].id]!.status, SourceHealthStatus.down);
    expect(results[sources[2].id]!.status, SourceHealthStatus.healthy);
  });
}

List<BookSourceModel> _sources(int n) {
  return List.generate(n, (i) => _source(i));
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

/// 记录并发峰值的替身：覆写 ping 绕开真实网络。
class _RecordingService extends SourceHealthService {
  _RecordingService(this.delay, {this.failIndexes = const {}});

  final Duration delay;

  /// 用「第几个源」标记失败，因为 BookSourceModel.id 是从 url+name 派生的 getter
  final Set<int> failIndexes;

  int _active = 0;
  int peakConcurrency = 0;
  int probeCount = 0;

  @override
  Future<SourceHealthSnapshot> ping(BookSourceModel source) async {
    _active++;
    probeCount++;
    if (_active > peakConcurrency) peakConcurrency = _active;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (failIndexes.any((i) => source.bookSourceUrl.endsWith('/${i}'))) {
        // 真实 ping 内部已把失败收敛成 down 快照，这里模拟同样契约
        return SourceHealthSnapshot(
          sourceId: source.id,
          status: SourceHealthStatus.down,
          latencyMs: -1,
          lastChecked: DateTime.now(),
          errorMessage: 'boom',
        );
      }
      return SourceHealthSnapshot(
        sourceId: source.id,
        status: SourceHealthStatus.healthy,
        latencyMs: 10,
        lastChecked: DateTime.now(),
      );
    } finally {
      _active--;
    }
  }
}
