import 'dart:async';

/// 解析链结果的短 TTL 缓存 + 「同一地址的在途合并」（纯逻辑，可单测）。
///
/// 为什么需要它（2026-10-03 实测起播链）：
///   - 云播页归一化 + 直连 m3u8 解析实测 146ms ~ 1.9s，一条不可达线路要 **12s** 才封顶；
///   - 同一集在很短时间内会被解析好几次：切下一集又切回来、误触返回再进、
///     详情页预热与播放器起播各解析一次、自动续播回到同一集……
/// 这些重复请求完全是浪费 —— 而且每一次都要用户等。
///
/// 只缓存**成功解析出的地址**，不缓存失败：失败要立刻能重试。
/// TTL 默认 5 分钟：源站地址常带 `sign=` 之类短时令牌，缓存太久会拿到过期地址。
class StreamResolveCache {
  StreamResolveCache({
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 结果最长保留时间（超时即视为未命中）。
  final Duration ttl;

  final DateTime Function() _clock;

  final Map<String, _Entry> _done = <String, _Entry>{};
  final Map<String, Future<Uri>> _inflight = <String, Future<Uri>>{};
  int _hits = 0;

  /// 当前缓存条数。
  int get size => _done.length;

  /// 命中计数（只看 [take] / [peek] 命中，不含写入）。
  int get hits => _hits;

  /// 看一眼有没有（命中计数 +1）。命中且没过期才返回，过期顺手清掉。
  Uri? take(String key) {
    final uri = peek(key);
    if (uri != null) _hits++;
    return uri;
  }

  /// 只看一眼，不计命中数（预热判断用：已有结果就不必再发请求）。
  Uri? peek(String key) {
    final entry = _done[key];
    if (entry == null) return null;
    if (_clock().difference(entry.at) > ttl) {
      _done.remove(key);
      return null;
    }
    return entry.uri;
  }

  void put(String key, Uri resolved) {
    _done[key] = _Entry(resolved, _clock());
  }

  void invalidate(String key) {
    _done.remove(key);
    _inflight.remove(key);
  }

  void clear() {
    _done.clear();
    _inflight.clear();
  }

  /// 带缓存地解析：命中直接返回；未命中时**同一 key 的并发调用合并成一次**。
  /// [force] 忽略已有结果（刚失败过、要重新解析时用）。
  Future<Uri> resolve(
    String key,
    Future<Uri> Function() compute, {
    bool force = false,
  }) {
    if (!force) {
      final cached = take(key);
      if (cached != null) return Future<Uri>.value(cached);
      final running = _inflight[key];
      if (running != null) return running;
    }
    final future = compute();
    _inflight[key] = future;
    return future.then<Uri>((uri) {
      put(key, uri);
      return uri;
    }).whenComplete(() {
      _inflight.remove(key);
    });
  }
}

class _Entry {
  const _Entry(this.uri, this.at);

  final Uri uri;
  final DateTime at;
}
