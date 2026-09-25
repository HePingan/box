// 服务监控插件：抓快照 + 本地缓存上一次成功的结果。
//
// 缓存不是为了省流量（快照不到 1KB），而是为了**冷启动不空白**：
// 打开页面先用上次的快照渲染，同时后台刷新；刷新失败保留旧内容并把原因
// 写进横幅（远端存储插件 D7 用的同一形状）。

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/features/extensions/plugins/monitor/monitor_models.dart';

/// 网络取回原始 JSON 文本（可注入，测试里给假实现）。
typedef MonitorFetcher = Future<String> Function(Uri url, Duration timeout);

/// 取快照失败：`message` 是可以直接给用户看的中文原因。
class MonitorFetchException implements Exception {
  MonitorFetchException(this.message);

  final String message;

  @override
  String toString() => 'MonitorFetchException: $message';
}

/// 上次成功的快照 + 它是什么时候取回来的。
class MonitorCachedSnapshot {
  const MonitorCachedSnapshot({required this.snapshot, required this.fetchedAt});

  final MonitorSnapshot snapshot;
  final DateTime fetchedAt;
}

class ServiceMonitorService {
  ServiceMonitorService({
    Uri? endpoint,
    MonitorFetcher? fetcher,
    Duration? timeout,
  })  : endpoint = endpoint ?? defaultEndpoint,
        _fetcher = fetcher ?? _dioFetch,
        _timeout = timeout ?? const Duration(seconds: 12);

  /// 线上快照（边缘机 nginx 静态文件，由 175 每 2 分钟推送）。
  static final Uri defaultEndpoint =
      Uri.parse('https://box.hpa888.top/monitors.json');

  static const String cacheKey = 'serviceMonitor.lastSnapshot';
  static const String cacheAtKey = 'serviceMonitor.lastSnapshotAt';

  /// 缓存上限：快照本来 <1KB，超过这个数说明拿到的不是我们的快照，别往盘里写。
  static const int cacheMaxBytes = 64 * 1024;

  final Uri endpoint;
  final MonitorFetcher _fetcher;
  final Duration _timeout;

  /// 拉一份新快照；成功时顺手把原始文本落盘。失败抛 [MonitorFetchException]。
  Future<MonitorSnapshot> fetch() async {
    final String body;
    try {
      body = await _fetcher(endpoint, _timeout);
    } on MonitorFetchException {
      rethrow;
    } catch (e) {
      throw MonitorFetchException('网络请求失败（$e）');
    }
    final MonitorSnapshot snapshot;
    try {
      snapshot = MonitorSnapshot.parse(body);
    } on MonitorFormatException catch (e) {
      throw MonitorFetchException('快照格式不对：${e.message}');
    }
    await _saveCache(body);
    return snapshot;
  }

  /// 上次成功的快照；没有/坏了都返回 null（不抛异常，调用方直接当"没缓存"）。
  Future<MonitorCachedSnapshot?> cached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final body = prefs.getString(cacheKey);
      if (body == null || body.isEmpty) return null;
      final at = prefs.getInt(cacheAtKey);
      return MonitorCachedSnapshot(
        snapshot: MonitorSnapshot.parse(body),
        fetchedAt: at == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(at),
      );
    } catch (_) {
      return null;
    }
  }

  /// 清缓存（目前只给测试和"删数据"类入口用）。
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cacheKey);
    await prefs.remove(cacheAtKey);
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
  static Future<String> _dioFetch(Uri url, Duration timeout) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        // 快照是静态文件，别被中间层塞缓存（nginx 那头也标了 no-cache）。
        headers: const {'Accept': 'application/json', 'Cache-Control': 'no-cache'},
      ),
    );
    try {
      final res = await dio.get<String>(
        url.toString(),
        options: Options(responseType: ResponseType.plain),
      );
      final data = res.data;
      if (data == null || data.isEmpty) {
        throw MonitorFetchException('服务端返回了空内容（HTTP ${res.statusCode}）');
      }
      return data;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != null) {
        throw MonitorFetchException('服务端返回 HTTP $code');
      }
      throw MonitorFetchException(_dioReason(e));
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

/// 缓存里存的是原始文本，这里给测试一个便捷构造。
String encodeMonitorSnapshotForTest(Map<String, Object?> json) =>
    jsonEncode(json);
