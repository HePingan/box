// 播放中继单测：真实回环 HTTP 服务（127.0.0.1 随机端口）+ 假上游，不触外网。
// 覆盖：200 转发与字节一致、Range 透传与 206、HEAD 无 body、令牌不符 404、
// 非 GET/HEAD 405、上游异常 502、close 幂等且端口关闭、客户端断开后上游订阅取消。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/application/playback_relay.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _Res {
  _Res(this.statusCode, this.headers, this.bytes);

  final int statusCode;
  final Map<String, String?> headers;
  final List<int> bytes;

  String? header(String name) => headers[name];
}

// 断言时用到的头快照名单（x-internal 用于验证非白名单头不转发）。
const _snapshotNames = [
  'content-type',
  'content-length',
  'content-range',
  'accept-ranges',
  'etag',
  'last-modified',
  'x-internal',
];

Future<_Res> _request(String url, {String method = 'GET', String? range}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse(url));
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    final headers = <String, String?>{};
    for (final name in _snapshotNames) {
      headers[name] = response.headers.value(name);
    }
    return _Res(response.statusCode, headers, builder.takeBytes());
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('GET：状态、白名单头与字节完整转发', () async {
    final payload = List<int>.generate(256, (i) => i % 251);
    bool? seenHead;
    String? seenRange;
    final relay = await PlaybackRelay.start(
      upstream: ({required bool head, String? rangeHeader}) async {
        seenHead = head;
        seenRange = rangeHeader;
        return WebdavResponse(
          statusCode: 200,
          headers: const {
            'content-type': 'video/mp4',
            'accept-ranges': 'bytes',
            'x-internal': 'should-not-forward',
          },
          bodyStream: Stream<List<int>>.fromIterable([
            payload.sublist(0, 100),
            payload.sublist(100),
          ]),
        );
      },
    );
    addTearDown(relay.close);

    final res = await _request(relay.url);
    expect(res.statusCode, 200);
    expect(res.header('content-type'), 'video/mp4');
    expect(res.header('accept-ranges'), 'bytes');
    expect(res.header('x-internal'), isNull, reason: '非白名单头不得转发');
    expect(res.bytes, payload);
    expect(seenHead, isFalse);
    expect(seenRange, isNull);
  });

  test('Range：透传 range 头，206 与 content-range 原样返回', () async {
    String? seenRange;
    final relay = await PlaybackRelay.start(
      upstream: ({required bool head, String? rangeHeader}) async {
        seenRange = rangeHeader;
        return WebdavResponse(
          statusCode: 206,
          headers: const {
            'content-type': 'video/mp4',
            'content-range': 'bytes 4-7/16',
            'content-length': '4',
          },
          bodyStream: Stream<List<int>>.value(const [4, 5, 6, 7]),
        );
      },
    );
    addTearDown(relay.close);

    final res = await _request(relay.url, range: 'bytes=4-7');
    expect(seenRange, 'bytes=4-7');
    expect(res.statusCode, 206);
    expect(res.header('content-range'), 'bytes 4-7/16');
    expect(res.bytes, const [4, 5, 6, 7]);
  });

  test('HEAD：上游收到 head=true，响应无 body', () async {
    bool? seenHead;
    final relay = await PlaybackRelay.start(
      upstream: ({required bool head, String? rangeHeader}) async {
        seenHead = head;
        return WebdavResponse(
          statusCode: 200,
          headers: const {'content-type': 'video/mp4', 'content-length': '100'},
          bodyStream: Stream<List<int>>.value(const [1, 2, 3]),
        );
      },
    );
    addTearDown(relay.close);

    final res = await _request(relay.url, method: 'HEAD');
    expect(res.statusCode, 200);
    expect(seenHead, isTrue);
    expect(res.header('content-length'), '100');
    expect(res.bytes, isEmpty);
  });

  test('令牌不符：404 且不调用上游', () async {
    var calls = 0;
    final relay = await PlaybackRelay.start(
      upstream: ({required bool head, String? rangeHeader}) async {
        calls++;
        return WebdavResponse(
          statusCode: 200,
          headers: const {},
          bodyStream: Stream<List<int>>.value(const [1]),
        );
      },
    );
    addTearDown(relay.close);

    final bad = relay.url.replaceFirst('/rs/', '/rs/deadbeef');
    final res = await _request(bad);
    expect(res.statusCode, 404);
    expect(calls, 0);
  });

  test('非 GET/HEAD 方法：405 且不调用上游', () async {
    var calls = 0;
    final relay = await PlaybackRelay.start(
      upstream: ({required bool head, String? rangeHeader}) async {
        calls++;
        return WebdavResponse(
          statusCode: 200,
          headers: const {},
          bodyStream: Stream<List<int>>.value(const [1]),
        );
      },
    );
    addTearDown(relay.close);

    final res = await _request(relay.url, method: 'POST');
    expect(res.statusCode, 405);
    expect(calls, 0);
  });

  test('上游异常：502 而非挂死', () async {
    final relay = await PlaybackRelay.start(
      upstream: ({required bool head, String? rangeHeader}) async {
        throw const SocketException('upstream down');
      },
    );
    addTearDown(relay.close);

    final res = await _request(relay.url);
    expect(res.statusCode, 502);
  });

  test('close：幂等且端口关闭后拒绝连接', () async {
    final relay = await PlaybackRelay.start(
      upstream: ({required bool head, String? rangeHeader}) async =>
          WebdavResponse(
        statusCode: 200,
        headers: const {},
        bodyStream: Stream<List<int>>.value(const [1]),
      ),
    );
    final url = relay.url;
    await relay.close();
    await relay.close(); // 二次调用不抛错

    await expectLater(_request(url), throwsA(isA<SocketException>()));
  });

  test('close：在途上游取流被取消（不泄漏订阅）', () async {
    final cancelSeen = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelSeen.isCompleted) cancelSeen.complete();
      },
    );
    final relay = await PlaybackRelay.start(
      upstream: ({required bool head, String? rangeHeader}) async =>
          WebdavResponse(
        statusCode: 200,
        headers: const {'content-type': 'video/mp4'},
        bodyStream: controller.stream,
      ),
    );
    addTearDown(() async {
      if (!controller.isClosed) await controller.close();
      await relay.close();
    });

    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(relay.url));
    // 注意：必须先发首块再等响应头——中继收到首块才 flush 响应头，反序会互等。
    final responseFuture = request.close();
    controller.add(List<int>.filled(16, 7));
    final response = await responseFuture;

    final first = Completer<void>();
    response.listen(
      (_) {
        if (!first.isCompleted) first.complete();
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
    await first.future.timeout(const Duration(seconds: 5));

    // 播放页退出：close() 必须取消在途取流，而不是把上游整段读进空处。
    await relay.close();
    await cancelSeen.future.timeout(const Duration(seconds: 3));
    client.close(force: true);
  });

  test('平台行为钉住：播放器单方断开不上报写失败，回收依赖 close()', () async {
    final cancelSeen = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelSeen.isCompleted) cancelSeen.complete();
      },
    );
    final relay = await PlaybackRelay.start(
      upstream: ({required bool head, String? rangeHeader}) async =>
          WebdavResponse(
        statusCode: 200,
        headers: const {'content-type': 'video/mp4'},
        bodyStream: controller.stream,
      ),
    );
    addTearDown(() async {
      if (!controller.isClosed) await controller.close();
      await relay.close();
    });

    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(relay.url));
    final responseFuture = request.close();
    controller.add(List<int>.filled(16, 7));
    final response = await responseFuture;

    final first = Completer<void>();
    response.listen(
      (_) {
        if (!first.isCompleted) first.complete();
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
    await first.future.timeout(const Duration(seconds: 5));

    // 播放器断开连接后继续泵入数据：dart:io 静默吞掉写失败，订阅不会因此被取消。
    client.close(force: true);
    for (var i = 0; i < 3; i++) {
      if (!controller.isClosed) controller.add(List<int>.filled(64 * 1024, 9));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(
      cancelSeen.isCompleted,
      isFalse,
      reason: 'dart:io 不会向服务端上报客户端断开；此处失败说明平台行为变化，'
          '需重评断线回收策略（当前依赖 close() 显式取消）',
    );

    // 可靠回收点：close()。
    await relay.close();
    await cancelSeen.future.timeout(const Duration(seconds: 3));
  });

  // ------------------------------------------------------ C6 预读缓冲

  test('预读缓冲（C6）：超过上限的数据完整、按序转发（缓冲不丢不重）', () async {
    // 总量 6MB（1MB × 6）> 4MB 上限，必然走过"暂停上游 → 排空 → 放开"
    final chunk = Uint8List.fromList(List<int>.generate(1024 * 1024, (i) => i % 251));
    final payload = <List<int>>[for (var i = 0; i < 6; i++) chunk];
    const total = 6 * 1024 * 1024;
    final relay = await PlaybackRelay.start(
      upstream: ({required bool head, String? rangeHeader}) async =>
          WebdavResponse(
        statusCode: 200,
        headers: {'content-type': 'video/mp4', 'content-length': '$total'},
        bodyStream: Stream<List<int>>.fromIterable(payload),
      ),
    );
    addTearDown(relay.close);

    final res = await _request(relay.url);
    expect(res.statusCode, 200);
    expect(res.bytes.length, total);
    // 逐段校验：预读缓冲不能错位或丢块
    for (var i = 0; i < 6; i++) {
      expect(
        res.bytes.sublist(i * 1024 * 1024, (i + 1) * 1024 * 1024),
        equals(chunk),
        reason: '第 $i 段不一致',
      );
    }
  });

  test('预读缓冲（C6）：客户端不读时上游被暂停（不会把整段读进内存）', () async {
    var pauses = 0;
    var resumes = 0;
    final controller = StreamController<List<int>>(
      onPause: () => pauses += 1,
      onResume: () => resumes += 1,
    );
    final relay = await PlaybackRelay.start(
      upstream: ({required bool head, String? rangeHeader}) async =>
          WebdavResponse(
        statusCode: 200,
        headers: const {'content-type': 'video/mp4'},
        bodyStream: controller.stream,
      ),
    );
    addTearDown(() async {
      if (!controller.isClosed) await controller.close();
      await relay.close();
    });

    // 用裸 Socket 发请求并**故意不读**：dart:io 的 HttpClient 会把响应体读进自己
    // 的缓冲里（等于一直消费），只有裸 socket 才能让下游真的堵住——这正是
    // "播放器卡住/还没开始取流"的场景。
    final uri = Uri.parse(relay.url);
    final socket = await Socket.connect(uri.host, uri.port);
    addTearDown(() => socket.destroy());
    socket.write('GET ${uri.path} HTTP/1.1\r\nHost: ${uri.host}\r\n\r\n');
    await socket.flush();

    // 上游拼命推：累计远超 4MB 上限
    for (var i = 0; i < 12; i++) {
      if (controller.isClosed) break;
      controller.add(Uint8List(1024 * 1024));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(
      pauses,
      greaterThan(0),
      reason: '下游不消费时必须暂停上游，否则内存会随文件大小线性增长',
    );

    // 开始读 → 排空到低水位后放开上游，数据继续流动
    var received = 0;
    socket.listen((data) => received += data.length);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(received, greaterThan(0), reason: '恢复后应能继续收到数据');
    expect(resumes, greaterThan(0));
  });
}
