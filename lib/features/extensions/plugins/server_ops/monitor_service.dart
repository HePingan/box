// 取 `monitors.json`（被监控站点快照）。
//
// 与 hosts.json 同一条链路、同一个令牌：边缘机 nginx 要求 `?token=`，不对直接 404。
// 令牌不进仓库，构建时经 `--dart-define=MONITOR_SNAPSHOT_TOKEN` 注入。

import 'dart:convert';

import 'package:dio/dio.dart';

import 'monitor_models.dart';

/// 拉一份原始文本（可注入，测试不联网）。
typedef MonitorFetcher = Future<String> Function(Uri url, Duration timeout);

class MonitorFetchException implements Exception {
  const MonitorFetchException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MonitorService {
  MonitorService({
    Uri? endpoint,
    String? token,
    MonitorFetcher? fetcher,
    Duration? timeout,
  })  : endpoint = endpoint ?? defaultEndpoint,
        token = token ?? defaultToken,
        _providedFetcher = fetcher,
        _timeout = timeout ?? const Duration(seconds: 12);

  /// 站点快照（与主机快照同一个目录，同一个令牌）。
  static final Uri defaultEndpoint =
      Uri.parse('https://box.hpa888.top/monitors.json');

  static const String defaultToken =
      String.fromEnvironment('MONITOR_SNAPSHOT_TOKEN');

  final Uri endpoint;
  final String token;
  final MonitorFetcher? _providedFetcher;
  final Duration _timeout;

  late final MonitorFetcher _fetcher = _providedFetcher ?? _dioFetch;

  Uri get requestUrl {
    if (token.isEmpty) return endpoint;
    return endpoint.replace(
      queryParameters: {...endpoint.queryParameters, 'token': token},
    );
  }

  /// 拉一份；解析不出来（结构变了）抛 [MonitorFetchException]。
  Future<MonitorSnapshot> fetch() async {
    final String body;
    try {
      body = await _fetcher(requestUrl, _timeout);
    } catch (e) {
      throw MonitorFetchException('取站点快照失败（$e）');
    }
    final snapshot = MonitorSnapshot.tryParse(_decode(body));
    if (snapshot == null) {
      throw const MonitorFetchException('站点快照格式不对');
    }
    return snapshot;
  }

  Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      // 不是合法 JSON（拿到的可能是错误页）→ 交给上层报"格式不对"。
      return null;
    }
  }

  Future<String> _dioFetch(Uri url, Duration timeout) async {
    final dio = Dio(BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      responseType: ResponseType.plain,
    ));
    final resp = await dio.getUri<dynamic>(url);
    final data = resp.data;
    if (data is String) return data;
    return '$data';
  }
}
