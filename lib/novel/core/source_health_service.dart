import 'dart:async';

import 'novel_source.dart';
import 'novel_source_factory.dart';
import '../pages/source_manager/book_source_model.dart';

// ──────────────────────────────────────────
// 健康状态枚举
// ──────────────────────────────────────────

/// 书源健康状态
enum SourceHealthStatus {
  /// 尚未检测
  unknown,

  /// 正常（延迟 < 3000ms）
  healthy,

  /// 缓慢（延迟 >= 3000ms）
  degraded,

  /// 不可达（超时/网络错误/解析错误）
  down,
}

// ──────────────────────────────────────────
// 单个书源的健康快照
// ──────────────────────────────────────────

class SourceHealthSnapshot {
  const SourceHealthSnapshot({
    required this.sourceId,
    required this.status,
    required this.latencyMs,
    required this.lastChecked,
    this.errorMessage,
  });

  final String sourceId;
  final SourceHealthStatus status;
  final int latencyMs;
  final DateTime? lastChecked;
  final String? errorMessage;

  static SourceHealthSnapshot get unknown => const SourceHealthSnapshot(
        sourceId: '',
        status: SourceHealthStatus.unknown,
        latencyMs: -1,
        lastChecked: null,
      );

  bool get isUsable => status == SourceHealthStatus.healthy ||
      status == SourceHealthStatus.degraded;
}

// ──────────────────────────────────────────
// 健康检查服务
// ──────────────────────────────────────────

/// 书源健康检查服务
///
/// 职责：
/// - 对书源执行轻量级探测（搜索空字符串或最短关键词）
/// - 记录延迟和错误信息
/// - 缓存探测结果（默认 5 分钟 TTL）
/// - 提供批量检查
class SourceHealthService {
  SourceHealthService();

  /// 健康快照缓存，key = source id
  final Map<String, SourceHealthSnapshot> _cache = {};

  /// 正在检查中的 source id 集合，防止并发重复检测
  final Set<String> _inProgress = {};

  /// 探测超时（毫秒）
  int probeTimeoutMs = 8000;

  /// 快照 TTL（缓存有效时间）
  Duration cacheTtl = const Duration(minutes: 5);

  /// 获取缓存中的健康快照（不发起新探测）
  SourceHealthSnapshot getHealth(String sourceId) {
    return _cache[sourceId] ?? SourceHealthSnapshot.unknown;
  }

  /// 对单个书源执行探测
  ///
  /// 通过构造 [NovelSource] 并调用 `searchBooks` 来测试连通性。
  /// 如果正在探测同一个 source，返回已有 Future 避免并发。
  Future<SourceHealthSnapshot> ping(BookSourceModel source) async {
    final id = source.id;

    // 缓存有效期内直接返回
    final cached = _cache[id];
    if (cached != null && cached.lastChecked != null) {
      final age = DateTime.now().difference(cached.lastChecked!);
      if (age < cacheTtl) return cached;
    }

    // 防并发
    if (_inProgress.contains(id)) {
      // 等待正在进行的探测完成
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return _cache[id] ??
          const SourceHealthSnapshot(
            sourceId: '',
            status: SourceHealthStatus.unknown,
            latencyMs: -1,
            lastChecked: null,
          );
    }

    _inProgress.add(id);
    try {
      final snapshot = await _doPing(source);
      _cache[id] = snapshot;
      return snapshot;
    } finally {
      _inProgress.remove(id);
    }
  }

  Future<SourceHealthSnapshot> _doPing(BookSourceModel source) async {
    final stopwatch = Stopwatch()..start();

    try {
      final novelSource = NovelSourceFactory.fromBookSourceJson(
        source.toJson(),
      );

      // 使用最短关键词探测，减少数据传输量
      await novelSource
          .searchBooks('的', page: 1)
          .timeout(Duration(milliseconds: probeTimeoutMs));

      stopwatch.stop();
      final latency = stopwatch.elapsedMilliseconds;

      // 只要没抛异常就算连通成功
      final status = latency < 3000
          ? SourceHealthStatus.healthy
          : SourceHealthStatus.degraded;
      return SourceHealthSnapshot(
        sourceId: source.id,
        status: status,
        latencyMs: latency,
        lastChecked: DateTime.now(),
      );
    } on TimeoutException {
      stopwatch.stop();
      return SourceHealthSnapshot(
        sourceId: source.id,
        status: SourceHealthStatus.down,
        latencyMs: probeTimeoutMs,
        lastChecked: DateTime.now(),
        errorMessage: '连接超时（${probeTimeoutMs}ms）',
      );
    } catch (e) {
      stopwatch.stop();
      return SourceHealthSnapshot(
        sourceId: source.id,
        status: SourceHealthStatus.down,
        latencyMs: stopwatch.elapsedMilliseconds,
        lastChecked: DateTime.now(),
        errorMessage: e.toString().length > 120
            ? '${e.toString().substring(0, 120)}…'
            : e.toString(),
      );
    }
  }

  /// 同时最多探测几个书源。
  ///
  /// 原实现完全串行，10 个书源全超时要等 10×probeTimeoutMs（≈50s）才出结果，
  /// 书源管理页整段时间只能转圈。放开到无限并发会瞬间打爆连接池并让每个探测的
  /// 延迟数字互相污染（都在抢带宽，测出来的 latency 偏大导致误判 degraded），
  /// 所以取一个小的上限：3 路并发把最差耗时压到 ~1/3，瞬时连接数仍然可控。
  ///
  /// 调大：更快但延迟数字更不准、更容易被对端限流。调小：更准更慢，1 即回到串行。
  static const int maxConcurrentProbes = 3;

  /// 批量检测所有书源，返回 sourceId → 快照 映射。
  ///
  /// 以 [maxConcurrentProbes] 为上限分批并发。单个源的失败已在 [ping] 内部
  /// 收敛成 down 快照，不会抛出，因此这里不需要额外的错误兜底。
  Future<Map<String, SourceHealthSnapshot>> pingAll(
    List<BookSourceModel> sources,
  ) async {
    final results = <String, SourceHealthSnapshot>{};

    for (var i = 0; i < sources.length; i += maxConcurrentProbes) {
      final end = (i + maxConcurrentProbes).clamp(0, sources.length);
      final batch = sources.sublist(i, end);
      final snapshots = await Future.wait(batch.map(ping));
      for (var j = 0; j < batch.length; j++) {
        results[batch[j].id] = snapshots[j];
      }
    }

    return results;
  }

  /// 清空所有缓存
  void clearCache() {
    _cache.clear();
  }

  /// 移除指定 source 的缓存
  void invalidate(String sourceId) {
    _cache.remove(sourceId);
  }
}
