import 'dart:async';

/// 进程级短时效内存缓存。
///
/// 视频分类 / 列表 / 详情这类接口在短时间内会被反复请求（切 tab、翻回上一页、
/// 重复点开同一部片），但内容变化很慢。给它们套一层 TTL 缓存，重复访问直接命中
/// 内存，省掉整轮网络往返，返回上一页 / 重复点开近乎秒开。
///
/// 只缓存“成功且非空”的结果——失败或空结果不写入，避免把一次偶发失败固化成
/// TTL 窗口内的持续空白。
class TtlCache {
  TtlCache._();

  /// 最大缓存条目数。超出后按 LRU（最近最少使用）淘汰最旧条目，
  /// 避免长时间浏览把分类/列表/详情结果无限堆积撑爆内存。
  static const int _maxEntries = 200;

  /// 用普通 LinkedHashMap 语义维持插入/访问顺序：
  /// 队首 = 最久未用，队尾 = 最近使用。命中时移到队尾，写入超限淘汰队首。
  static final Map<String, _CacheEntry> _store = <String, _CacheEntry>{};

  /// 正在进行中的请求去重：同一 key 并发请求只打一次网络，其余等待同一个 Future。
  static final Map<String, Future<dynamic>> _inflight =
      <String, Future<dynamic>>{};

  /// 读缓存；命中且未过期则返回，否则调用 [loader] 取值。
  ///
  /// [shouldCache] 决定取到的值是否值得写入缓存（默认非 null 即缓存）。
  static Future<T> getOrFetch<T>(
    String key, {
    required Duration ttl,
    required Future<T> Function() loader,
    bool Function(T value)? shouldCache,
  }) async {
    final now = DateTime.now();

    final cached = _store[key];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      // 命中：移到队尾标记为最近使用。
      _store.remove(key);
      _store[key] = cached;
      return cached.value as T;
    }
    // 过期条目顺手清掉。
    if (cached != null) {
      _store.remove(key);
    }

    // 请求去重：已有同 key 在途，直接复用。
    final existing = _inflight[key];
    if (existing != null) {
      return await existing as T;
    }

    final future = loader();
    _inflight[key] = future;

    try {
      final value = await future;
      final worthCaching = shouldCache?.call(value) ?? (value != null);
      if (worthCaching) {
        _store[key] = _CacheEntry(value, now.add(ttl));
        _evictIfNeeded();
      }
      return value;
    } finally {
      _inflight.remove(key);
    }
  }

  /// 超出容量时按 LRU 淘汰最旧条目（队首）。
  static void _evictIfNeeded() {
    while (_store.length > _maxEntries) {
      _store.remove(_store.keys.first);
    }
  }

  /// 清空全部缓存（如切换片源配置、手动刷新时）。
  static void clear() {
    _store.clear();
  }

  /// 按前缀失效（如某个 baseUrl 下的所有缓存）。
  static void invalidatePrefix(String prefix) {
    _store.removeWhere((key, _) => key.startsWith(prefix));
  }
}

class _CacheEntry {
  _CacheEntry(this.value, this.expiresAt);

  final dynamic value;
  final DateTime expiresAt;
}
