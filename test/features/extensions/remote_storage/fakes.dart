// 远程存储插件测试共享设施：假传输层、响应构造器、PROPFIND XML 构造器。
//
// 全部测试离线运行：domain 层不依赖 dio，注入 FakeTransport 即可覆盖
// WebdavClient 的全部逻辑；service 层通过 transportFactory 注入。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';

/// 1×1 透明 PNG（C4 图片预览测试用）：真实的合法 PNG 字节，
/// 因为 `Image.memory` 会真的去解码——喂假字节会让测试报解码异常而不是断言失败。
final Uint8List kTinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
);

/// 记录请求、按 [handler] 应答的假传输层；未设置 handler 时返回 200 空响应。
class FakeTransport implements WebdavTransport {
  FakeTransport([this.handler]);

  Future<WebdavResponse> Function(WebdavRequest request)? handler;
  final List<WebdavRequest> requests = [];

  WebdavRequest get lastRequest => requests.last;

  int get requestCount => requests.length;

  /// 按顺序消耗应答函数（多请求场景）；超出预置数量时抛 StateError。
  static FakeTransport sequence(
    List<Future<WebdavResponse> Function(WebdavRequest)> handlers,
  ) {
    var index = 0;
    return FakeTransport((request) {
      if (index >= handlers.length) {
        throw StateError(
          '未预置更多应答：第 ${index + 1} 个请求 '
          '${request.method} ${request.uri}',
        );
      }
      return handlers[index++](request);
    });
  }

  @override
  Future<WebdavResponse> send(WebdavRequest request) {
    requests.add(request);
    final h = handler;
    if (h == null) {
      return Future.value(
        const WebdavResponse(statusCode: 200, headers: {}),
      );
    }
    return h(request);
  }
}

/// 读取请求体全文（PUT 上传断言用）。
Future<List<int>> bodyBytesOf(WebdavRequest request) async {
  final stream = request.bodyStream;
  if (stream == null) return const [];
  final chunks = await stream.toList();
  return chunks.expand((c) => c).toList();
}

/// 读请求体为 UTF-8 文本。
Future<String> bodyTextOf(WebdavRequest request) async {
  final bytes = await bodyBytesOf(request);
  return utf8.decode(bytes, allowMalformed: true);
}

/// XML 文本应答（PROPFIND/OPTIONS）。
WebdavResponse xmlResponse(
  String body, {
  int status = 207,
  Map<String, String> headers = const {},
}) {
  return WebdavResponse(
    statusCode: status,
    headers: {
      'content-type': 'application/xml; charset=utf-8',
      ...headers,
    },
    bodyText: body,
  );
}

/// 字节流应答（GET 等）。
WebdavResponse streamResponse(
  List<int> bytes, {
  int status = 200,
  Map<String, String> headers = const {},
}) {
  return WebdavResponse(
    statusCode: status,
    headers: {
      'content-length': '${bytes.length}',
      ...headers,
    },
    bodyStream: Stream<List<int>>.value(Uint8List.fromList(bytes)),
  );
}

/// HEAD 应答（无 body）。
WebdavResponse headResponse({
  int status = 200,
  Map<String, String> headers = const {},
}) {
  return WebdavResponse(statusCode: status, headers: headers);
}

/// PROPFIND 条目描述。
class DavItem {
  const DavItem(
    this.href, {
    this.displayName,
    this.isCollection = false,
    this.size,
    this.lastModified,
    this.etag,
  });

  final String href;
  final String? displayName;
  final bool isCollection;
  final int? size;
  final String? lastModified;
  final String? etag;
}

/// 生成标准 multistatus XML（含 propstat/status 结构）。
String propfindXml(List<DavItem> items) {
  final buffer = StringBuffer(
    '<?xml version="1.0" encoding="utf-8"?>'
    '<d:multistatus xmlns:d="DAV:">',
  );
  for (final item in items) {
    buffer.write('<d:response><d:href>${item.href}</d:href>'
        '<d:propstat><d:prop>');
    if (item.displayName != null) {
      buffer.write('<d:displayname>${item.displayName}</d:displayname>');
    }
    if (item.isCollection) {
      buffer.write('<d:resourcetype><d:collection/></d:resourcetype>');
    } else {
      buffer.write('<d:resourcetype/>');
      if (item.size != null) {
        buffer.write(
          '<d:getcontentlength>${item.size}</d:getcontentlength>',
        );
      }
    }
    if (item.lastModified != null) {
      buffer.write(
        '<d:getlastmodified>${item.lastModified}</d:getlastmodified>',
      );
    }
    if (item.etag != null) {
      buffer.write('<d:getetag>${item.etag}</d:getetag>');
    }
    buffer.write('</d:prop><d:status>HTTP/1.1 200 OK</d:status>'
        '</d:propstat></d:response>');
  }
  buffer.write('</d:multistatus>');
  return buffer.toString();
}

/// 生成配额 multistatus（RFC 4331）；传 null 表示该属性不返回。
String quotaXml({
  int? availableBytes,
  int? usedBytes,
  String href = '/dav/',
}) {
  final buffer = StringBuffer(
    '<?xml version="1.0" encoding="utf-8"?>'
    '<d:multistatus xmlns:d="DAV:">'
    '<d:response><d:href>$href</d:href>'
    '<d:propstat><d:prop>',
  );
  if (availableBytes != null) {
    buffer.write(
      '<d:quota-available-bytes>$availableBytes</d:quota-available-bytes>',
    );
  }
  if (usedBytes != null) {
    buffer.write('<d:quota-used-bytes>$usedBytes</d:quota-used-bytes>');
  }
  buffer.write('</d:prop><d:status>HTTP/1.1 200 OK</d:status>'
      '</d:propstat></d:response></d:multistatus>');
  return buffer.toString();
}

/// 构造测试账户。
RemoteStorageAccount testAccount({
  String id = 'rs_test',
  String label = '测试账户',
  String baseUrl = 'https://dav.example.com/dav/',
  String username = 'user@example.com',
  String password = 'app-pass',
  RemoteTlsMode tlsMode = RemoteTlsMode.auto,
  bool allowBadCert = false,
  bool showSystemFolders = false,
  int createdAt = 1000,
}) {
  return RemoteStorageAccount(
    id: id,
    label: label,
    baseUrl: baseUrl,
    username: username,
    password: password,
    tlsMode: tlsMode,
    allowBadCert: allowBadCert,
    showSystemFolders: showSystemFolders,
    createdAt: createdAt,
  );
}
