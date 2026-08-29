/// 镜像测速选线。
///
/// 纯逻辑 + 注入式探测函数，零 Flutter 依赖，方便单测。
///
/// 为什么用**中位数**而不是均值或单次采样：镜像速度抖动极大。实测同一镜像
/// 同一文件连打 5 次，耗时 1133 / 259 / 99000 / 347 / 1304 ms —— 中间那次
/// 直接超时。单次采样会误判，均值会被超时样本毁掉，中位数才稳定。
///
/// 为什么只下 64KB：实测 64KB 探测的中位排序与 512KB 大样本的排序一致
/// （gh-proxy 最快、hk 最慢），但耗时和流量都低一个量级。
library;

import 'github_accel_link.dart';

/// 单次探测结果。
class MirrorSample {
  const MirrorSample({
    required this.mirror,
    required this.ok,
    this.elapsed = Duration.zero,
    this.error = '',
  });

  final String mirror;
  final bool ok;
  final Duration elapsed;
  final String error;
}

/// 一个镜像的多轮汇总。
class MirrorRanking {
  const MirrorRanking({
    required this.mirror,
    required this.usable,
    required this.medianMs,
    required this.okCount,
    required this.total,
    this.error = '',
  });

  final String mirror;

  /// 至少有一轮成功。
  final bool usable;

  /// 成功样本的中位耗时（毫秒）。不可用时为 [maxMs]。
  final int medianMs;

  final int okCount;
  final int total;
  final String error;

  /// 不可用镜像的排序值，保证排在所有可用镜像之后。
  static const int maxMs = 1 << 30;

  String get label => mirror.replaceFirst(RegExp(r'^https?://'), '');

  /// 给 UI 用的简短描述。
  String get summary {
    if (!usable) return error.isEmpty ? '不可用' : '不可用（$error）';
    final speed = medianMs <= 0 ? '' : '${medianMs}ms';
    if (okCount < total) return '$speed（$okCount/$total 次成功）';
    return speed;
  }
}

/// 探测一个镜像一次。实现方负责真正发请求。
typedef MirrorProbeFn = Future<MirrorSample> Function(
  String mirror,
  String url,
);

class MirrorProbe {
  MirrorProbe({
    required MirrorProbeFn probe,
    this.rounds = 3,
    this.probeBytes = 65536,
  }) : _probe = probe;

  final MirrorProbeFn _probe;

  /// 每个镜像探测轮数。奇数便于取中位。
  /// 调大 → 结论更稳但更慢更耗流量；调小 → 反之。3 轮是实测够用的下限。
  final int rounds;

  /// 每轮下载的字节数。
  final int probeBytes;

  String get rangeHeader => 'bytes=0-${probeBytes - 1}';

  /// 对候选镜像并发测速，返回按快慢排序的结果（快的在前，不可用的在后）。
  ///
  /// 永不抛异常：任何镜像失败都记为不可用。
  Future<List<MirrorRanking>> rank(
    String stableUrl, {
    List<String>? mirrors,
  }) async {
    final candidates =
        mirrors ?? GithubAccelLink.mirrors.map((m) => m.url).toList();
    if (candidates.isEmpty) return const [];

    // 并发探测：串行会让 N 个镜像等 N 倍时间。
    final results = await Future.wait(
      candidates.map((m) => _probeOne(m, stableUrl)),
    );

    results.sort((a, b) {
      // 可用的一律排在不可用之前。
      if (a.usable != b.usable) return a.usable ? -1 : 1;
      return a.medianMs.compareTo(b.medianMs);
    });
    return results;
  }

  Future<MirrorRanking> _probeOne(String mirror, String url) async {
    final okMs = <int>[];
    var lastError = '';

    for (var i = 0; i < rounds; i++) {
      try {
        final s = await _probe(mirror, url);
        if (s.ok) {
          okMs.add(s.elapsed.inMilliseconds);
        } else {
          lastError = s.error;
        }
      } catch (e) {
        lastError = '$e';
      }
    }

    if (okMs.isEmpty) {
      return MirrorRanking(
        mirror: mirror,
        usable: false,
        medianMs: MirrorRanking.maxMs,
        okCount: 0,
        total: rounds,
        error: lastError,
      );
    }

    okMs.sort();
    return MirrorRanking(
      mirror: mirror,
      usable: true,
      medianMs: okMs[okMs.length ~/ 2],
      okCount: okMs.length,
      total: rounds,
    );
  }
}
