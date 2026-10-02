import 'dart:convert';
import 'dart:io';

import 'package:box/core/storage/cache_store.dart';

/// 图床"边缘 IP"记忆：哪些 IP 通、哪些不通。
///
/// 为什么需要它（2026-10-02 实测，175 上三个来回完全一致）：
///
/// ```
/// tuer.justpic01pt.com 解析出 10 个 IP：
///   全通 5 个：154.19.241.171 / 154.23.172.162 / 154.23.172.198 / 154.23.172.235 / 38.49.45.53
///   全不通 5 个：185.13.110.21 ~ 185.13.110.25（整段）
/// 走域名每次新建连接：10/15 成功（随机挑 IP，挑到不通的那 5 个就失败）
/// 直连一个通着的 IP：  15/15 成功（两个端口都是）
/// ```
///
/// 结论：用户看到的"图床连不上 / 一直转圈"，一多半不是端口被封、也不是我们的并发，
/// 而是**域名里混着一半死 IP**，每条新连接都在掷硬币。所以这里记住哪个 IP 通：
/// 取图先直连它，失败就把它改成"坏"，下次换一个。
///
/// 直连 IP 不会削弱安全：连接层换了地址，TLS 的 SNI 与证书校验**仍按域名**
/// （实测图床证书是 `*.justpic01pt.com` 的合法 Let's Encrypt 证书，校验照过）。
class ComicImageEdges {
  ComicImageEdges({
    CacheStore? cacheStore,
    Future<List<String>> Function(String host)? resolver,
    this.badTtl = const Duration(minutes: 30),
  }) : _cache = cacheStore ?? CacheStore(namespace: 'comic_img_edges'),
       _resolve = resolver ?? _systemResolve;

  final CacheStore _cache;

  /// 解析域名 → IP 列表（测试注入假的，别在单测里联网）。
  final Future<List<String>> Function(String host) _resolve;

  /// "坏 IP"记多久。太短会把真坏的一直重试，太长则 IP 恢复了也不再用。
  final Duration badTtl;

  static const String _key = 'hosts';

  /// 同一次取图里别反复解析域名（一次取图可能试好几个地址）。
  final Map<String, List<String>> _resolved = {};

  static Future<List<String>> _systemResolve(String host) async {
    final list = await InternetAddress.lookup(host);
    return [for (final a in list) a.address];
  }

  Future<Map<String, Map<String, dynamic>>> _all() async {
    Object? raw;
    try {
      raw = await _cache.read(_key);
    } catch (_) {
      // 读不出来（没平台实现 / 文件坏了）就当没记忆：绝不因为"记不住"影响取图。
      return <String, Map<String, dynamic>>{};
    }
    if (raw is! Map) return <String, Map<String, dynamic>>{};
    final out = <String, Map<String, dynamic>>{};
    raw.forEach((k, v) {
      if (v is Map) out['$k'] = Map<String, dynamic>.from(v);
    });
    return out;
  }

  Future<void> _save(Map<String, Map<String, dynamic>> all) async {
    try {
      await _cache.write(_key, all);
    } catch (_) {
      // 存不下也无所谓（下次重新学一遍）。
    }
  }

  /// 这个域名的已知"通"的 IP（同时不在坏名单里/坏名单已过期）。
  Future<String?> preferred(String host) async {
    final entry = (await _all())[host];
    final good = entry?['good'] as String?;
    if (good == null || good.isEmpty) return null;
    return _isBad(entry, good) ? null : good;
  }

  /// 可以在失败后换着试的 IP：解析出来的、不在坏名单里的、没试过的。
  ///
  /// [limit] 限制最多给几个（一条连接 8 秒，试太多等于让用户等）。
  Future<List<String>> fallbackIps(
    String host, {
    Set<String> tried = const {},
    int limit = 2,
  }) async {
    List<String> ips;
    try {
      ips = _resolved[host] ??= await _resolve(host);
    } catch (_) {
      return const <String>[];
    }
    final entry = (await _all())[host];
    final out = <String>[];
    for (final ip in ips) {
      if (tried.contains(ip)) continue;
      if (_isBad(entry, ip)) continue;
      out.add(ip);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 这个 IP 通了（记下来，下次先用它）。
  Future<void> markGood(String host, String ip) async {
    final all = await _all();
    final entry = all.putIfAbsent(host, () => <String, dynamic>{});
    entry['good'] = ip;
    entry['goodAt'] = DateTime.now().millisecondsSinceEpoch;
    // 通了就把它从坏名单里摘掉（同一个 IP 的坏记忆不该压住事实）。
    (entry['bad'] as Map?)?.remove(ip);
    await _save(all);
  }

  /// 这个 IP 不通（记下来，[badTtl] 内不再用它）。
  Future<void> markBad(String host, String ip) async {
    final all = await _all();
    final entry = all.putIfAbsent(host, () => <String, dynamic>{});
    if (entry['good'] == ip) entry.remove('good');
    final bad = Map<String, dynamic>.from(
      (entry['bad'] as Map?) ?? const <String, dynamic>{},
    );
    bad[ip] = DateTime.now().millisecondsSinceEpoch;
    entry['bad'] = bad;
    await _save(all);
  }

  /// 坏记忆过期了就当没记过（IP 会恢复，别永久拉黑）。
  bool _isBad(Map<String, dynamic>? entry, String ip) {
    final at = (entry?['bad'] as Map?)?[ip];
    if (at is! int) return false;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    return age < badTtl.inMilliseconds;
  }

  /// 给界面/日志看的一行（"这个域名记住了哪个 IP"）。
  Future<String> describe(String host) async {
    final entry = (await _all())[host];
    final good = entry?['good'] as String? ?? '（还没学到）';
    final bad = ((entry?['bad'] as Map?) ?? const <String, dynamic>{})
        .keys
        .join(',');
    return 'good=$good bad=[$bad]';
  }

  /// JSON 原文（测试与排查用）。
  Future<String> dump() async => jsonEncode(await _all());
}
