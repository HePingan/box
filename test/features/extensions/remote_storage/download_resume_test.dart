// 279 C2：下载断点续传的测试（纯逻辑 + 客户端 Range 行为）。
//
// 服务层的断点归属/落点决策放在 remote_storage_service_test.dart 的「下载」组里
// （那里已有临时目录与账户 fixture）。

import 'dart:io';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  WebdavClient clientWith(FakeTransport transport) => WebdavClient(
    baseUrl: 'https://dav.example.com/dav/',
    username: 'user@example.com',
    password: 'app-pass',
    transport: transport,
  );

  group('Content-Range 解析（C2）', () {
    test('标准形态：bytes 100-199/200', () {
      final r = parseContentRange('bytes 100-199/200');
      expect(r, isNotNull);
      expect(r!.start, 100);
      expect(r.end, 199);
      expect(r.total, 200);
      expect(r.length, 100);
    });

    test('全长未知：bytes 0-99/*', () {
      final r = parseContentRange('bytes 0-99/*');
      expect(r?.start, 0);
      expect(r?.total, isNull);
    });

    test('不可满足/垃圾输入一律 null（调用方就此退化为从头下载）', () {
      expect(parseContentRange('bytes */200'), isNull);
      expect(parseContentRange('bytes 5-'), isNull);
      expect(parseContentRange('items 0-9/10'), isNull);
      expect(parseContentRange(''), isNull);
      expect(parseContentRange(null), isNull);
    });
  });

  group('断点归属元数据（C2）', () {
    test('往返与匹配', () {
      const meta = PartialDownload(accountId: 'acc1', remotePath: 'a/b.zip');
      final parsed = PartialDownload.tryParse(meta.toJsonString());
      expect(parsed, isNotNull);
      expect(parsed!.matches(accountId: 'acc1', remotePath: 'a/b.zip'), isTrue);
      // 同名文件来自别的账户 → 不匹配（否则会把两份文件拼坏）
      expect(parsed.matches(accountId: 'acc2', remotePath: 'a/b.zip'), isFalse);
      expect(parsed.matches(accountId: 'acc1', remotePath: 'a/c.zip'), isFalse);
    });

    test('坏元数据解析为 null，不抛异常', () {
      expect(PartialDownload.tryParse(''), isNull);
      expect(PartialDownload.tryParse('{'), isNull);
      expect(PartialDownload.tryParse('{"remotePath":"a"}'), isNull);
      expect(PartialDownload.tryParse('[]'), isNull);
    });
  });

  group('客户端 Range 行为（C2）', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rs_resume_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('206 + Content-Range 起点一致 → 追加写入并报累计进度', () async {
      final file = File('${tmp.path}/f.bin');
      await file.writeAsBytes(List<int>.filled(100, 7));

      final transport = FakeTransport(
        (_) async => WebdavResponse(
          statusCode: 206,
          headers: {
            'content-range': 'bytes 100-199/200',
            'content-length': '100',
          },
          bodyStream: Stream<List<int>>.value(Uint8List(100)..fillRange(0, 100, 9)),
        ),
      );
      final progress = <int>[];
      await clientWith(transport).downloadTo(
        'f.bin',
        file,
        resumeFrom: 100,
        onProgress: (received, _) => progress.add(received),
      );

      expect(transport.lastRequest.headers['range'], 'bytes=100-');
      final bytes = await file.readAsBytes();
      expect(bytes.length, 200);
      expect(bytes.sublist(0, 100).every((b) => b == 7), isTrue);
      expect(bytes.sublist(100).every((b) => b == 9), isTrue);
      // 进度是"含已下载部分"的累计值，不是本轮增量
      expect(progress.last, 200);
    });

    test('服务端忽略 Range（200）→ 截断重写，不叠一份重复内容', () async {
      final file = File('${tmp.path}/f.bin');
      await file.writeAsBytes(List<int>.filled(100, 7));

      final transport = FakeTransport(
        (_) async => WebdavResponse(
          statusCode: 200,
          headers: {'content-length': '50'},
          bodyStream: Stream<List<int>>.value(
            Uint8List(50)..fillRange(0, 50, 3),
          ),
        ),
      );
      await clientWith(transport).downloadTo('f.bin', file, resumeFrom: 100);
      final bytes = await file.readAsBytes();
      expect(bytes.length, 50);
      expect(bytes.every((b) => b == 3), isTrue);
    });

    test('最终字节数对不上全长 → 抛错（保留断点，不交出半截文件）', () async {
      final file = File('${tmp.path}/f.bin');
      await file.writeAsBytes(List<int>.filled(100, 7));
      final transport = FakeTransport(
        (_) async => WebdavResponse(
          statusCode: 206,
          headers: {
            'content-range': 'bytes 100-299/300',
            'content-length': '50',
          },
          bodyStream: Stream<List<int>>.value(
            Uint8List(50)..fillRange(0, 50, 9),
          ),
        ),
      );
      await expectLater(
        clientWith(transport).downloadTo('f.bin', file, resumeFrom: 100),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.message,
            'message',
            contains('下载不完整'),
          ),
        ),
      );
      // 断点文件还在（下一轮还能续）
      expect(await file.exists(), isTrue);
      expect(await file.length(), 150);
    });

    test('resumeFrom 与实际文件长度不符 → 不带 Range（避免要求错误的偏移）', () async {
      final file = File('${tmp.path}/f.bin');
      await file.writeAsBytes(List<int>.filled(30, 7));
      final transport = FakeTransport(
        (_) async => WebdavResponse(
          statusCode: 200,
          headers: {'content-length': '30'},
          bodyStream: Stream<List<int>>.value(
            Uint8List(30)..fillRange(0, 30, 1),
          ),
        ),
      );
      await clientWith(transport).downloadTo('f.bin', file, resumeFrom: 999);
      expect(transport.lastRequest.headers.containsKey('range'), isFalse);
    });
  });
}
