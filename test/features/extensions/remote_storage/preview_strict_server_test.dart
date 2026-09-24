// 真实 socket + 严格服务器：验证预览路径在"结束偏移超界即回 416"的服务器上可用。
//
// 假传输层（FakeTransport）只验证了客户端的意图，不经过 dio 的真实请求构造与
// HTTP 栈。这个用例起一个真回环 HTTP 服务，按坚果云的严格行为实现：
//   - 带结束偏移的 Range（bytes=0-39）→ 416（RFC 7233 本该夹到文件末尾回 206）
//   - 起点式 Range（bytes=0-）      → 206 + Content-Range
//   - 不带 Range                    → 200 全量
// 然后驱动**真实的 dio 传输**（DioWebdavTransport）走一遍 readUpTo。

import 'dart:io';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// 严格服务器：只接受起点式 Range。
class _StrictDavServer {
  _StrictDavServer(this._server);

  final HttpServer _server;
  final List<String?> seenRanges = <String?>[];
  Uint8List payload = Uint8List.fromList(List<int>.generate(100, (i) => i));

  String get baseUrl => 'http://127.0.0.1:${_server.port}/dav/';

  static Future<_StrictDavServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final self = _StrictDavServer(server);
    self._listen();
    return self;
  }

  void _listen() {
    _server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      seenRanges.add(range);
      final response = request.response;

      // 严格实现：只要写了结束偏移且超界就 416（这里一律拒绝带结束偏移的区间）
      final hasEndOffset =
          range != null && RegExp(r'^bytes=\d+-\d+$').hasMatch(range);
      if (hasEndOffset) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set('content-range', 'bytes */${payload.length}');
        await response.close();
        return;
      }
      if (range != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          'content-range',
          'bytes 0-${payload.length - 1}/${payload.length}',
        );
        response.headers.contentLength = payload.length;
        response.add(payload);
        await response.close();
        return;
      }
      response.statusCode = HttpStatus.ok;
      response.headers.contentLength = payload.length;
      response.add(payload);
      await response.close();
    });
  }

  Future<void> close() => _server.close(force: true);
}

WebdavClient _client(_StrictDavServer server) => WebdavClient(
  baseUrl: server.baseUrl,
  username: 'u',
  password: 'p',
  transport: DioWebdavTransport(allowBadCert: false, badCertHost: ''),
);

void main() {
  test('预览：严格服务器（区间超界回 416）下仍能取到字节', () async {
    final server = await _StrictDavServer.start();
    addTearDown(server.close);

    final result = await _client(server).readUpTo('pic.jpg', 40);

    expect(result.bytes, server.payload.sublist(0, 40));
    expect(result.truncated, isTrue);
    expect(result.totalLength, 100);
    expect(
      server.seenRanges,
      ['bytes=0-'],
      reason: '真实请求里只发起点式 Range——发 bytes=0-39 会被这台服务器回 416',
    );
  });

  test('预览：服务器连起点式 Range 都拒（一律 416）→ 退回普通 GET 仍可用', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final payload = Uint8List.fromList(List<int>.generate(100, (i) => i + 1));
    final seen = <String?>[];
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      seen.add(range);
      final response = request.response;
      if (range != null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set('content-range', 'bytes */${payload.length}');
        await response.close();
        return;
      }
      response.statusCode = HttpStatus.ok;
      response.headers.contentLength = payload.length;
      response.add(payload);
      await response.close();
    });

    final client = WebdavClient(
      baseUrl: 'http://127.0.0.1:${server.port}/dav/',
      username: 'u',
      password: 'p',
      transport: DioWebdavTransport(allowBadCert: false, badCertHost: ''),
    );

    final result = await client.readUpTo('pic.jpg', 40);

    expect(result.bytes, payload.sublist(0, 40));
    expect(seen, ['bytes=0-', null], reason: '第一次被 416，第二次不带 Range');
  });
}
