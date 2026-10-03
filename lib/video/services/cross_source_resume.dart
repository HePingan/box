import 'dart:async';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../video_module.dart';
import 'source_match.dart';
import 'video_api_service.dart';

/// 一次「换源找片」的结果。
class CrossSourceHit {
  const CrossSourceHit({
    required this.source,
    required this.vodId,
    required this.vodName,
  });

  final VideoSource source;
  final int vodId;
  final String vodName;
}

/// 一次「换源找片」的过程汇报（给界面说清发生了什么）。
class CrossSourceReport {
  const CrossSourceReport({
    required this.searched,
    required this.hit,
    required this.failedSources,
  });

  /// 真正发过搜索请求的源数。
  final int searched;
  final CrossSourceHit? hit;

  /// 请求抛错/超时（只计数，不拉黑）的源名，用于如实告知。
  final List<String> failedSources;
}

/// 按片名在**可用片源**里找同一部片，找到就返回那家源。
///
/// 设计取舍：
/// - **只搜可见源**（① 的可见性层）：已自动隐藏的坏源不该再花用户的流量；
/// - 并发窗口 4、先命中先返回，总预算默认 8s —— 与探测口径一致（实测 22/28 源
///   有同一部片，最快的源 ~0.8s，典型 1~1.7s 命中）；
/// - 命中判据 = **归一化片名精确相等**（`normalizeSourceName`），不做模糊匹配：
///   换源放错片比找不到更糟；
/// - **搜到 0 结果不算源坏**（老片在某些源本来就没有），只有请求失败才记账，
///   且 `autoHide: false` —— 换源失败是网络层面的事，不该把源拉黑。
class CrossSourceMovieFinder {
  const CrossSourceMovieFinder({
    this.concurrency = 4,
    this.budget = const Duration(seconds: 8),
    this.perSourceTimeout = const Duration(seconds: 8),
    this.searchOverride,
  });

  final int concurrency;
  final Duration budget;
  final Duration perSourceTimeout;

  /// 测试用：替掉真实的搜索（界面接线用例要的是「找片器是真的、网络是假的」）。
  final Future<List<VodItem>> Function(VideoSource source, String keyword)?
  searchOverride;

  Future<CrossSourceReport> find({
    required List<VideoSource> sources,
    required String vodName,
    Future<List<VodItem>> Function(VideoSource source, String keyword)? search,
  }) async {
    final wanted = normalizeSourceName(vodName);
    await VideoModule.ensureVisibilityLoaded();
    final candidates = VideoModule.visibleSourcesOf(sources);
    if (wanted.isEmpty || candidates.isEmpty) {
      return const CrossSourceReport(
        searched: 0,
        hit: null,
        failedSources: <String>[],
      );
    }

    final searchFn = search ?? searchOverride ?? _defaultSearch;
    final watch = Stopwatch()..start();
    final failed = <String>[];
    var searched = 0;
    var next = 0;
    CrossSourceHit? hit;

    Future<void> worker() async {
      while (true) {
        if (hit != null || watch.elapsed >= budget) return;
        final index = next++;
        if (index >= candidates.length) return;
        final source = candidates[index];
        searched++;
        try {
          final items = await searchFn(
            source,
            vodName,
          ).timeout(perSourceTimeout);
          if (hit != null) return;
          for (final item in items) {
            if (normalizeSourceName(item.vodName) == wanted) {
              hit = CrossSourceHit(
                source: source,
                vodId: item.vodId,
                vodName: item.vodName,
              );
              return;
            }
          }
        } catch (_) {
          // 这个源这次没答上来：记账（不隐藏），如实告诉用户。
          failed.add(source.name);
          // 记账是本地写，等它落地 —— 不然调用方/用例可能读到还没写进去的计数。
          await VideoModule.markSourceFailure(
            source,
            reason: '换源找片时请求失败',
            autoHide: false,
          );
        }
      }
    }

    final workers = concurrency.clamp(1, 8);
    await Future.wait(List<Future<void>>.generate(workers, (_) => worker()));

    return CrossSourceReport(
      searched: searched,
      hit: hit,
      failedSources: List<String>.unmodifiable(failed),
    );
  }

  Future<List<VodItem>> _defaultSearch(VideoSource source, String keyword) {
    return VideoApiService.searchVideo(source.url, keyword);
  }
}
