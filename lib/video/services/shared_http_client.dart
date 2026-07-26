import 'package:http/http.dart' as http;

/// 全局共享的持久 HTTP 客户端。
///
/// 顶层 `http.get()` 每次调用都会新建一个 `Client` 用完即弃，没有
/// keep-alive、没有连接池。聚合搜索一次打 N 个源就是 N 次全新的
/// TCP+TLS 握手。改为复用同一个 `http.Client`（dart:io 的底层
/// HttpClient 默认带连接池 + keep-alive），同域名多次请求可复用
/// 已建立的连接，显著降低搜索 / 详情 / 探流的握手开销。
class SharedHttpClient {
  SharedHttpClient._();

  static http.Client? _instance;

  /// 进程级共享单例。首次访问时惰性创建。
  static http.Client get instance => _instance ??= http.Client();

  /// 仅在极少数需要强制重建连接池的场景使用（如整体网络栈重置）。
  static void reset() {
    _instance?.close();
    _instance = null;
  }
}
