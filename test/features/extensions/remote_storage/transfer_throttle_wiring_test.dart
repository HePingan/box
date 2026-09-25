// 限速是否真的接进了传输（285 P2）。
//
// 单测只证明"数学对"，这里证明**接线对**：downloadTo / uploadFrom 在每一块之后
// 都问过限速器。用一个记录型限速器替身（不起真等待），避免用例靠 sleep 计时。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/domain/transfer_throttle.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

class _RecordingThrottle extends TransferThrottle {
  _RecordingThrottle() : super(1000000);

  /// 每次被问到时"已传字节数"（累积值）。
  final List<int> calls = <int>[];

  @override
  Future<void> limit(int receivedBytes, Duration elapsed) async {
    calls.add(receivedBytes);
  }
}

void main() {
  WebdavClient clientWith(FakeTransport transport) => WebdavClient(
        baseUrl: 'https://dav.example.com/dav/',
        username: 'user@example.com',
        password: 'app-pass',
        transport: transport,
      );

  test('downloadTo：每块之后都过限速器，累积字节数与进度一致', () async {
    final dir = await Directory.systemTemp.createTemp('rs_thr_dl_');
    addTearDown(() => dir.delete(recursive: true));
    final dest = File('${dir.path}/out.bin');

    final chunks = [
      Uint8List.fromList(List<int>.filled(10, 1)),
      Uint8List.fromList(List<int>.filled(20, 2)),
      Uint8List.fromList(List<int>.filled(5, 3)),
    ];
    final transport = FakeTransport(
      (request) async => WebdavResponse(
        statusCode: 200,
        headers: const {'content-length': '35'},
        bodyStream: Stream<List<int>>.fromIterable(chunks),
      ),
    );

    final throttle = _RecordingThrottle();
    await clientWith(transport).downloadTo('a.bin', dest, throttle: throttle);

    expect(await dest.readAsBytes(), hasLength(35));
    expect(throttle.calls, [10, 30, 35], reason: '每块之后都要按累积字节过限速器');
  });

  test('downloadTo：不给限速器时正常（不限速路径不受影响）', () async {
    final dir = await Directory.systemTemp.createTemp('rs_thr_none_');
    addTearDown(() => dir.delete(recursive: true));
    final dest = File('${dir.path}/out.bin');
    final transport = FakeTransport(
      (request) async => streamResponse(List<int>.filled(8, 7)),
    );
    await clientWith(transport).downloadTo('a.bin', dest);
    expect(await dest.length(), 8);
  });

  test('uploadFrom：每块之后都过限速器，最后一块是文件全长', () async {
    final dir = await Directory.systemTemp.createTemp('rs_thr_up_');
    addTearDown(() => dir.delete(recursive: true));
    final src = File('${dir.path}/a.bin');
    await src.writeAsBytes(List<int>.generate(300 * 1024, (i) => i % 251));

    // 必须把请求体读完：PUT 体是流式的，没人读就等于没传（asyncMap 不推进）。
    final transport = FakeTransport((request) async {
      await bodyBytesOf(request);
      return const WebdavResponse(statusCode: 201, headers: <String, String>{});
    });

    final throttle = _RecordingThrottle();
    await clientWith(transport).uploadFrom(src, 'a.bin', throttle: throttle);

    expect(throttle.calls, isNotEmpty, reason: '读文件会分成多块');
    expect(throttle.calls.last, 300 * 1024,
        reason: '最后一次报的是文件全长');
    // 单调递增：累积字节数不能被重置（否则限速会一段段重新开始算账）
    for (var i = 1; i < throttle.calls.length; i++) {
      expect(throttle.calls[i], greaterThan(throttle.calls[i - 1]));
    }
  });
}
