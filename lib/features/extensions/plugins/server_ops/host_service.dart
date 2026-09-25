// 服务器运维插件：抓主机快照 + 本地缓存上一次成功的结果 + 指标历史环形缓冲。
//
// 缓存不是为了省流量（快照不到几 KB），而是为了**冷启动不空白**：
// 打开页面先用上次的快照渲染，同时后台刷新；刷新失败保留旧内容并把原因
// 写进横幅（形态与「服务监控」插件一致）。
//
// 历史点与快照分开存：快照存原始文本（整份、可能带新字段），历史只存
// 每台机器的三条数字序列（见 HostHistory 的注释）。

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/features/extensions/plugins/server_ops/host_models.dart';

/// 网络取回原始 JSON 文本（可注入，测试里给假实现）。
typedef HostFetcher = Future<String> Function(Uri url, Duration timeout);

/// 取快照失败：`message` 是可以直接给用户看的中文原因。
class HostFetchException implements Exception {
  HostFetchException(this.message);

  final String message;

  @override
  String toString() => 'HostFetchException: $message';
}

/// 上次成功的快照 + 它是什么时候取回来的。
class HostCachedSnapshot {
  const HostCachedSnapshot({required this.snapshot, required this.fetchedAt});

  final HostSnapshot snapshot;
  final DateTime fetchedAt;
}

class HostService {
  HostService({
    Uri? endpoint,
    HostFetcher? fetcher,
    Duration? timeout,
    String? token,
  })  : endpoint = endpoint ?? defaultEndpoint,
        token = token ?? defaultToken,
        _providedFetcher = fetcher,
        _timeout = timeout ?? const Duration(seconds: 12);

  /// 线上快照（边缘机 nginx 静态文件，由 175 每 2 分钟推送）。
  ///
  /// 端点已收口：nginx 要求 `?token=`，不对直接 404。令牌**不进仓库**，
  /// 构建时经 `--dart-define=MONITOR_SNAPSHOT_TOKEN` 注入（与验签密钥同一套路，
  /// 也与「服务监控」共用同一个快照令牌）。本机开发/测试拿不到令牌也没关系：
  /// 单测都注入假 fetcher，不会真去请求。
  static final Uri defaultEndpoint =
      Uri.parse('https://box.hpa888.top/hosts.json');

  /// 构建时注入的默认令牌（测试/开发可经构造参数覆盖）。
  static const String defaultToken =
      String.fromEnvironment('MONITOR_SNAPSHOT_TOKEN');

  /// 本次实例使用的令牌。
  final String token;

  /// 实际请求地址：配了令牌就带上 `?token=`，没配就原样（构建脚本会拦住漏配）。
  Uri get requestUrl {
    if (token.isEmpty) return endpoint;
    return endpoint.replace(
      queryParameters: {...endpoint.queryParameters, 'token': token},
    );
  }

  static const String cacheKey = 'serverOps.hosts.lastSnapshot';
  static const String cacheAtKey = 'serverOps.hosts.lastSnapshotAt';

  /// 历史快照里出现过的机器 id（用来知道该读哪些 history key）。
  static const String historyIndexKey = 'serverOps.hosts.historyIds';

  /// 上一次**落点**的时刻（全局一个：所有机器是同一份快照采出来的）。
  static const String lastSampleAtKey = 'serverOps.hosts.lastSampleAt';

  /// 一台机器一段历史的键。
  static String historyKeyFor(String hostId) => 'serverOps.hosts.history.$hostId';

  /// 缓存上限：快照本来只有几 KB，超过这个数说明拿到的不是我们的快照，别往盘里写。
  static const int cacheMaxBytes = 256 * 1024;

  final Uri endpoint;
  final HostFetcher? _providedFetcher;

  /// 默认实现是实例方法（要看实例上的令牌），注入的则直接用注入的。
  late final HostFetcher _fetcher = _providedFetcher ?? _dioFetch;

  final Duration _timeout;

  /// 拉一份新快照；成功时顺手把原始文本落盘。失败抛 [HostFetchException]。
  Future<HostSnapshot> fetch() async {
    final String body;
    try {
      body = await _fetcher(requestUrl, _timeout);
    } on HostFetchException {
      rethrow;
    } catch (e) {
      throw HostFetchException('网络请求失败（$e）');
    }
    final HostSnapshot snapshot;
    try {
      snapshot = HostSnapshot.parse(body);
    } on HostFormatException catch (e) {
      throw HostFetchException('快照格式不对：${e.message}');
    }
    await _saveCache(body);
    return snapshot;
  }

  /// 上次成功的快照；没有/坏了都返回 null（不抛异常，调用方直接当"没缓存"）。
  Future<HostCachedSnapshot?> cached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final body = prefs.getString(cacheKey);
      if (body == null || body.isEmpty) return null;
      final at = prefs.getInt(cacheAtKey);
      return HostCachedSnapshot(
        snapshot: HostSnapshot.parse(body),
        fetchedAt: at == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(at),
      );
    } catch (_) {
      return null;
    }
  }

  /// 清快照缓存（"清除本地快照"入口）。
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cacheKey);
    await prefs.remove(cacheAtKey);
  }

  /// 读全部机器指标历史（键由 [historyIndexKey] 给出）。
  ///
  /// 返回值按机器 id 索引；没有历史的机器不出现（调用方记默认空历史）。
  Future<Map<String, HostHistory>> loadHistories() async {
    final out = <String, HostHistory>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final id in prefs.getStringList(historyIndexKey) ?? const <String>[]) {
        final raw = prefs.getString(historyKeyFor(id));
        if (raw == null || raw.isEmpty) continue;
        out[id] = HostHistory.decode(raw);
      }
    } catch (_) {
      // 缓存永远只是锦上添花：读不出来就当没有历史。
    }
    return out;
  }

  /// 把这一份快照落成一个历史点（**距上次落点不足 2 分钟时整批跳过**）。
  ///
  /// 为什么要卡 2 分钟：数据源本身就是 2 分钟一份的静态文件，手动连点刷新
  /// 会在同一份数据上重复落点，把折线画成"最近的变化被挤掉"的样子。
  /// 返回落点后的完整历史（无论是否真的落点），供界面直接重绘。
  Future<Map<String, HostHistory>> recordSample(
    HostSnapshot snapshot, {
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final histories = <String, HostHistory>{};
    for (final id in prefs.getStringList(historyIndexKey) ?? const <String>[]) {
      final raw = prefs.getString(historyKeyFor(id));
      if (raw == null || raw.isEmpty) continue;
      histories[id] = HostHistory.decode(raw);
    }

    final at = now ?? DateTime.now();
    final lastAt = prefs.getInt(lastSampleAtKey);
    final due = lastAt == null ||
        at.difference(DateTime.fromMillisecondsSinceEpoch(lastAt)) >=
            const Duration(seconds: kHostSampleStepSec);
    if (!due) return histories;

    final ids = <String>{...histories.keys};
    for (final host in snapshot.hosts) {
      // 离线机器没有指标，不落点（不落点 ≠ 落一个 0）。
      if (!host.online) continue;
      final previous = histories[host.id] ?? const HostHistory();
      final next = previous.appended(
        cpu: host.cpuPercent,
        mem: host.memPercent,
        disk: host.diskPercent,
      );
      histories[host.id] = next;
      ids.add(host.id);
      await prefs.setString(historyKeyFor(host.id), next.encode());
    }
    if (ids.isNotEmpty) {
      await prefs.setStringList(historyIndexKey, ids.toList(growable: false));
    }
    await prefs.setInt(lastSampleAtKey, at.millisecondsSinceEpoch);
    return histories;
  }

  /// 清全部指标历史（"清除本地快照"入口：快照和历史一起清，否则会留下
  /// 一段属于旧快照的折线，看起来像"刚刚还在跑"）。
  Future<void> clearHistories() async {
    final prefs = await SharedPreferences.getInstance();
    for (final id in prefs.getStringList(historyIndexKey) ?? const <String>[]) {
      await prefs.remove(historyKeyFor(id));
    }
    await prefs.remove(historyIndexKey);
    await prefs.remove(lastSampleAtKey);
  }

  Future<void> _saveCache(String body) async {
    if (body.length > cacheMaxBytes) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, body);
      await prefs.setInt(cacheAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // 落盘失败不影响这次显示。
    }
  }

  /// 默认实现：dio 取纯文本。HTTP 状态码也翻译成人话（页面直接显示）。
  Future<String> _dioFetch(Uri url, Duration timeout) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        // 快照是静态文件，别被中间层塞缓存（nginx 那头也标了 no-cache）。
        headers: const {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        },
      ),
    );
    try {
      final res = await dio.get<String>(
        url.toString(),
        options: Options(responseType: ResponseType.plain),
      );
      final data = res.data;
      if (data == null || data.isEmpty) {
        throw HostFetchException('服务端返回了空内容（HTTP ${res.statusCode}）');
      }
      return data;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404 && token.isEmpty) {
        // 端点收口后最常见的一种"看起来像服务端坏了"：本机构建没注入令牌。
        throw HostFetchException(
          '快照端点已收口，但这个构建没有带上访问令牌（MONITOR_SNAPSHOT_TOKEN）',
        );
      }
      if (code != null) {
        throw HostFetchException('服务端返回 HTTP $code');
      }
      throw HostFetchException(_dioReason(e));
    } finally {
      dio.close(force: true);
    }
  }

  static String _dioReason(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return '请求超时';
      case DioExceptionType.connectionError:
        return '连不上服务端（检查网络）';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badResponse:
        return '服务端响应异常';
      case DioExceptionType.unknown:
        return '网络不可用';
    }
  }
}
