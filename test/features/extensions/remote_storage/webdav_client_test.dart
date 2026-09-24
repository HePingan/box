// WebdavClient 单测（注入 FakeTransport，离线）。
//
// 覆盖：uriFor 编码、list 解析/排序/过滤、自条目跳过（含无尾斜杠变体）、
// 错误状态映射、exists 的 HEAD→PROPFIND 回退、head 头解析、readUpTo 截断、
// downloadTo 流式与取消、uploadFrom PUT 体与 507、openStream 透传、probe。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  WebdavClient clientWith(FakeTransport transport, {String? baseUrl}) {
    return WebdavClient(
      baseUrl: baseUrl ?? 'https://dav.example.com/dav/',
      username: 'user@example.com',
      password: 'app-pass',
      transport: transport,
    );
  }

  group('uriFor', () {
    test('逐段百分号编码', () {
      final client = clientWith(FakeTransport());
      expect(
        client.uriFor('a b/中文.txt').toString(),
        'https://dav.example.com/dav/a%20b/%E4%B8%AD%E6%96%87.txt',
      );
      expect(
        client.uriFor('').toString(),
        'https://dav.example.com/dav/',
      );
    });

    test('baseUrl 缺尾斜杠时仍正确拼接（归一化）', () {
      final client = clientWith(
        FakeTransport(),
        baseUrl: 'https://dav.example.com/dav',
      );
      expect(
        client.uriFor('Box/a.txt').toString(),
        'https://dav.example.com/dav/Box/a.txt',
      );
    });
  });

  group('list', () {
    test('解析/排序/过滤系统目录/跳过自身，并带 Basic 认证与 Depth:1', () async {
      final transport = FakeTransport((request) async {
        return xmlResponse(propfindXml(const [
          DavItem('/dav/', isCollection: true),
          DavItem('/dav/Box/', isCollection: true),
          DavItem(
            '/dav/z.txt',
            size: 10,
            lastModified: 'Wed, 21 Oct 2015 07:28:00 GMT',
          ),
          DavItem(
            '/dav/%E4%B8%AD%E6%96%87.txt',
            displayName: '中文.txt',
            size: 3,
          ),
          DavItem('/dav/@eaDir/', isCollection: true),
        ]));
      });
      final client = clientWith(transport);

      final entries = await client.list('');

      expect(entries.map((e) => e.name).toList(),
          ['Box', 'z.txt', '中文.txt']);
      expect(entries[0].isDirectory, isTrue);
      expect(entries[0].path, 'Box');
      expect(entries[1].size, 10);
      expect(entries[1].modifiedAt, isNotNull);
      expect(entries[1].modifiedAt!.year, 2015);
      expect(entries[2].path, '中文.txt');

      final request = transport.lastRequest;
      expect(request.method, 'PROPFIND');
      expect(request.headers['depth'], '1');
      expect(request.headers['content-type'],
          contains('application/xml'));
      expect(
        request.headers['authorization'],
        'Basic ${base64.encode(utf8.encode('user@example.com:app-pass'))}',
      );
      final body = await bodyTextOf(request);
      expect(body, contains('propfind'));
      expect(body, contains('displayname'));
      expect(request.contentLength, utf8.encode(body).length);
    });

    test('filterSystemNames=false 时包含 @eaDir', () async {
      final transport = FakeTransport((request) async {
        return xmlResponse(propfindXml(const [
          DavItem('/dav/', isCollection: true),
          DavItem('/dav/@eaDir/', isCollection: true),
          DavItem('/dav/Box/', isCollection: true),
          DavItem('/dav/a.txt', size: 1),
        ]));
      });
      final entries = await clientWith(transport).list(
        '',
        filterSystemNames: false,
      );
      expect(
        entries.map((e) => e.name).toList(),
        ['@eaDir', 'Box', 'a.txt'],
      );
    });

    test('子目录列表：请求路径正确、自身条目被跳过', () async {
      final transport = FakeTransport((request) async {
        return xmlResponse(propfindXml(const [
          DavItem('/dav/Box/', isCollection: true),
          DavItem('/dav/Box/sub/', isCollection: true),
          DavItem('/dav/Box/a.txt', size: 5),
        ]));
      });
      final entries = await clientWith(transport).list('Box');

      expect(entries.map((e) => e.name).toList(), ['sub', 'a.txt']);
      expect(entries[1].path, 'Box/a.txt');
      expect(transport.lastRequest.uri.path, '/dav/Box');
    });

    test('自身条目缺尾斜杠（如 /dav）不得产生幻影条目', () async {
      final transport = FakeTransport((request) async {
        return xmlResponse(propfindXml(const [
          DavItem('/dav', isCollection: true),
          DavItem('/dav/Box/', isCollection: true),
        ]));
      });
      final entries = await clientWith(transport).list('');
      expect(entries.map((e) => e.name).toList(), ['Box']);
    });

    test('401 → unauthorized 且提示应用密码', () async {
      final transport = FakeTransport(
        (request) async => const WebdavResponse(statusCode: 401, headers: {}),
      );
      await expectLater(
        clientWith(transport).list(''),
        throwsA(
          isA<RemoteStorageException>()
              .having((e) => e.kind, 'kind', RemoteStorageError.unauthorized)
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('应用密码')),
        ),
      );
    });

    test('空响应体与非法 XML → 明确报「非 WebDAV 服务」', () async {
      final empty = FakeTransport((request) async => xmlResponse(''));
      await expectLater(
        clientWith(empty).list(''),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.message,
            'message',
            '服务器返回内容无法解析（非 WebDAV 服务？）',
          ),
        ),
      );

      final malformed = FakeTransport(
        (request) async => xmlResponse('<html><body>hi'),
      );
      await expectLater(
        clientWith(malformed).list(''),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.message,
            'message',
            '服务器返回内容无法解析（非 WebDAV 服务？）',
          ),
        ),
      );
    });
  });

  group('exists', () {
    test('404 → false；200 → true', () async {
      final missing = FakeTransport(
        (request) async => headResponse(status: 404),
      );
      expect(await clientWith(missing).exists('a.txt'), isFalse);

      final present = FakeTransport(
        (request) async => headResponse(status: 200),
      );
      expect(await clientWith(present).exists('a.txt'), isTrue);
    });

    test('405/501 → PROPFIND Depth:0 回退', () async {
      final transport = FakeTransport.sequence([
        (request) async => headResponse(status: 405),
        (request) async => xmlResponse(
              '<d:multistatus xmlns:d="DAV:"><d:response>'
              '<d:href>/dav/a.txt</d:href></d:response></d:multistatus>',
            ),
      ]);
      expect(await clientWith(transport).exists('a.txt'), isTrue);
      expect(transport.requestCount, 2);
      expect(transport.lastRequest.method, 'PROPFIND');
      expect(transport.lastRequest.headers['depth'], '0');
    });

    test('500 → http 异常', () async {
      final transport = FakeTransport(
        (request) async => headResponse(status: 500),
      );
      await expectLater(
        clientWith(transport).exists('a.txt'),
        throwsA(
          isA<RemoteStorageException>()
              .having((e) => e.kind, 'kind', RemoteStorageError.http),
        ),
      );
    });
  });

  group('head', () {
    test('解析 content-length / content-type / accept-ranges', () async {
      final transport = FakeTransport((request) async => headResponse(
            status: 200,
            headers: {
              'content-length': '1234',
              'content-type': 'video/mp4',
              'accept-ranges': 'bytes',
            },
          ));
      final info = await clientWith(transport).head('v.mp4');
      expect(info.contentLength, 1234);
      expect(info.contentType, 'video/mp4');
      expect(info.acceptRanges, isTrue);
    });

    test('404 → notFound', () async {
      final transport = FakeTransport(
        (request) async => headResponse(status: 404),
      );
      await expectLater(
        clientWith(transport).head('gone.txt'),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.kind,
            'kind',
            RemoteStorageError.notFound,
          ),
        ),
      );
    });
  });

  group('readUpTo', () {
    test('超限截断并带 totalLength（Range 生效 206）', () async {
      final payload = List<int>.generate(100, (i) => i);
      final transport = FakeTransport((request) async {
        // 起点式 Range：结束偏移不写进请求，避免"结束偏移超过文件大小"被回 416
        expect(request.headers['range'], 'bytes=0-');
        return streamResponse(payload, status: 206);
      });
      final result = await clientWith(transport).readUpTo('f.bin', 40);
      expect(result.bytes.length, 40);
      expect(result.truncated, isTrue);
      expect(result.totalLength, 100);
    });

    test('服务器对起点式 Range 回 416 → 退回普通 GET，仍然只读 maxBytes（坚果云）', () async {
      // 实测坚果云：带 Range 的预览请求被回 416（"请求范围不满足"），
      // 用户看到的就是「预览失败：服务器返回 HTTP 416」。
      final payload = List<int>.generate(100, (i) => i);
      final transport = FakeTransport((request) async {
        if (request.headers.containsKey('range')) {
          return const WebdavResponse(statusCode: 416, headers: {});
        }
        return streamResponse(payload, status: 200);
      });

      final result = await clientWith(transport).readUpTo('pic.jpg', 40);

      expect(result.bytes.length, 40, reason: '退回普通 GET 后仍只读上限内的字节');
      expect(result.bytes, payload.sublist(0, 40));
      expect(result.truncated, isTrue);
      expect(transport.requestCount, 2, reason: '先带 Range 被拒，再不带 Range 重来');
      expect(transport.requests.last.headers.containsKey('range'), isFalse);
    });

    test('0 字节文件（0- 不可满足）→ 退回普通 GET，不报错', () async {
      final transport = FakeTransport((request) async {
        if (request.headers.containsKey('range')) {
          return const WebdavResponse(statusCode: 416, headers: {});
        }
        return streamResponse(const <int>[], status: 200);
      });

      final result = await clientWith(transport).readUpTo('empty.txt', 40);
      expect(result.bytes, isEmpty);
      expect(result.truncated, isFalse);
    });

    test('恰好等于上限 → 不截断', () async {
      final payload = List<int>.generate(40, (i) => i);
      final transport = FakeTransport(
        (request) async => streamResponse(payload, status: 206),
      );
      final result = await clientWith(transport).readUpTo('f.bin', 40);
      expect(result.bytes.length, 40);
      expect(result.truncated, isFalse);
    });

    test('服务器忽略 Range（200 全量）时由调用方看到截断', () async {
      final payload = List<int>.generate(100, (i) => i);
      final transport = FakeTransport(
        (request) async => streamResponse(payload, status: 200),
      );
      final result = await clientWith(transport).readUpTo('f.bin', 40);
      expect(result.bytes.length, 40);
      expect(result.truncated, isTrue);
    });

    test('bodyText 应答（无流）同样受限', () async {
      final transport = FakeTransport(
        (request) async => const WebdavResponse(
          statusCode: 200,
          headers: {},
          bodyText: 'hello world',
        ),
      );
      final result = await clientWith(transport).readUpTo('f.txt', 5);
      expect(utf8.decode(result.bytes), 'hello');
      expect(result.truncated, isTrue);
    });
  });

  group('downloadTo', () {
    test('写文件并上报进度', () async {
      final dir = await Directory.systemTemp.createTemp('rs_dl_');
      addTearDown(() => dir.delete(recursive: true));
      final dest = File('${dir.path}/out.bin');

      final payload = List<int>.generate(64, (i) => i);
      final transport = FakeTransport(
        (request) async => streamResponse(payload),
      );
      final progress = <List<int>>[];
      await clientWith(transport).downloadTo(
        'a.bin',
        dest,
        onProgress: (received, total) => progress.add([received, total]),
      );

      expect(await dest.readAsBytes(), payload);
      expect(progress.last, [64, 64]);
    });

    test('中途取消抛 TransferCanceledException', () async {
      final dir = await Directory.systemTemp.createTemp('rs_dl_');
      addTearDown(() => dir.delete(recursive: true));
      final dest = File('${dir.path}/out.bin');

      final controller = StreamController<List<int>>();
      final transport = FakeTransport((request) async => WebdavResponse(
            statusCode: 200,
            headers: const {'content-length': '8'},
            bodyStream: controller.stream,
          ));
      final token = TransferCancelToken();
      final future = clientWith(transport).downloadTo(
        'a.bin',
        dest,
        onProgress: (received, total) => token.cancel(),
        cancel: token,
      );
      controller.add(Uint8List.fromList([1, 2, 3, 4]));
      controller.add(Uint8List.fromList([5, 6, 7, 8]));
      await controller.close();

      await expectLater(future, throwsA(isA<TransferCanceledException>()));
    });
  });

  group('uploadFrom', () {
    test('PUT 请求体/长度/认证正确，进度上报', () async {
      final dir = await Directory.systemTemp.createTemp('rs_up_');
      addTearDown(() => dir.delete(recursive: true));
      final src = File('${dir.path}/a.bin');
      await src.writeAsBytes([1, 2, 3, 4, 5]);

      final transport = FakeTransport(
        (request) async => headResponse(status: 201),
      );
      final progress = <List<int>>[];
      await clientWith(transport).uploadFrom(
        src,
        'up/a.bin',
        onProgress: (sent, total) => progress.add([sent, total]),
      );

      final request = transport.lastRequest;
      expect(request.method, 'PUT');
      expect(request.uri.path, '/dav/up/a.bin');
      expect(request.headers['content-length'], '5');
      expect(request.headers['authorization'], startsWith('Basic '));
      expect(await bodyBytesOf(request), [1, 2, 3, 4, 5]);
      expect(progress.last, [5, 5]);
    });

    test('507 → insufficientStorage', () async {
      final dir = await Directory.systemTemp.createTemp('rs_up_');
      addTearDown(() => dir.delete(recursive: true));
      final src = File('${dir.path}/a.bin');
      await src.writeAsBytes([1]);

      final transport = FakeTransport(
        (request) async => headResponse(status: 507),
      );
      await expectLater(
        clientWith(transport).uploadFrom(src, 'a.bin'),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.kind,
            'kind',
            RemoteStorageError.insufficientStorage,
          ),
        ),
      );
    });
  });

  group('openStream', () {
    test('Range 透传、404 不抛错原样返回', () async {
      final transport = FakeTransport(
        (request) async => headResponse(status: 404),
      );
      final resp = await clientWith(transport).openStream(
        'v.mp4',
        rangeHeader: 'bytes=0-1',
      );
      expect(resp.statusCode, 404);
      expect(transport.lastRequest.method, 'GET');
      expect(transport.lastRequest.headers['range'], 'bytes=0-1');

      await clientWith(transport).openStream('v.mp4', head: true);
      expect(transport.lastRequest.method, 'HEAD');
      expect(transport.lastRequest.headers.containsKey('range'), isFalse);
    });
  });

  group('probe', () {
    test('OPTIONS + PROPFIND 成功', () async {
      final transport = FakeTransport.sequence([
        (request) async => headResponse(
              status: 200,
              headers: {'dav': '1,2', 'allow': 'OPTIONS, PROPFIND'},
            ),
        (request) async => xmlResponse(propfindXml(const [
              DavItem('/dav/', isCollection: true),
              DavItem('/dav/a.txt', size: 1),
            ])),
      ]);
      final result = await clientWith(transport).probe();
      expect(result.ok, isTrue);
      expect(result.optionsStatus, 200);
      expect(result.davHeader, '1,2');
      expect(result.allowHeader, 'OPTIONS, PROPFIND');
      expect(result.rootEntryCount, 1);
    });

    test('OPTIONS 失败不致命；PROPFIND 失败时给出错误信息', () async {
      final transport = FakeTransport.sequence([
        (request) async => throw const RemoteStorageException(
              RemoteStorageError.methodNotAllowed,
              '服务器返回 HTTP 405',
            ),
        (request) async => const WebdavResponse(statusCode: 401, headers: {}),
      ]);
      final result = await clientWith(transport).probe();
      expect(result.ok, isFalse);
      expect(result.optionsStatus, isNull);
      expect(result.errorMessage, contains('应用密码'));
    });
  });

  group('etag 与配额（O3/O5）', () {
    test('list 解析 getetag；服务器不返回该属性时为 null', () async {
      final transport = FakeTransport(
        (_) async => xmlResponse(
          propfindXml(const [
            DavItem('/dav/a.txt', etag: '"abc123"'),
            DavItem('/dav/b.txt'),
          ]),
        ),
      );

      final entries = await clientWith(transport).list('');

      expect(
        entries.firstWhere((e) => e.name == 'a.txt').etag,
        '"abc123"',
      );
      expect(entries.firstWhere((e) => e.name == 'b.txt').etag, isNull);
    });

    test('PROPFIND 请求体必须带 getetag，否则服务器不会返回', () async {
      final transport = FakeTransport(
        (_) async => xmlResponse(propfindXml(const [])),
      );

      await clientWith(transport).list('');

      expect(await bodyTextOf(transport.lastRequest), contains('getetag'));
    });

    test('配额解析：正常值 / 只返回一项 / 负数 / 非法 XML', () {
      final ok = WebdavClient.parseQuotaMultistatus(
        quotaXml(availableBytes: 12345, usedBytes: 500),
      );
      expect(ok.availableBytes, 12345);
      expect(ok.usedBytes, 500);
      expect(ok.hasAny, isTrue);

      final partial =
          WebdavClient.parseQuotaMultistatus(quotaXml(usedBytes: 7));
      expect(partial.availableBytes, isNull);
      expect(partial.usedBytes, 7);

      final negative =
          WebdavClient.parseQuotaMultistatus(quotaXml(availableBytes: -3));
      expect(negative.availableBytes, isNull, reason: 'RFC 4331 用负数表示未知');
      expect(negative.hasAny, isFalse);

      expect(WebdavClient.parseQuotaMultistatus('').hasAny, isFalse);
      expect(WebdavClient.parseQuotaMultistatus('<not-xml').hasAny, isFalse);
      expect(WebdavClient.parseQuotaMultistatus(quotaXml()).hasAny, isFalse);
    });

    test('quota() 用 Depth:0 单查目录自己', () async {
      final transport = FakeTransport(
        (_) async => xmlResponse(quotaXml(availableBytes: 999)),
      );

      final q = await clientWith(transport).quota('');

      expect(q.availableBytes, 999);
      expect(transport.lastRequest.method, 'PROPFIND');
      expect(transport.lastRequest.headers['depth'], '0');
      expect(
        await bodyTextOf(transport.lastRequest),
        contains('quota-available-bytes'),
      );
    });
  });

  group('大目录解析（O4：后台 isolate）', () {
    final baseUri = Uri.parse('https://dav.example.com/dav/');

    String bigMultistatus(int count) => propfindXml(
          List<DavItem>.generate(
            count,
            (i) => DavItem(
              '/dav/目录$i/文件$i.txt',
              size: i,
              etag: '"e$i"',
            ),
          ),
        );

    test('超过阈值：隔离解析结果与主 isolate 解析逐项一致', () async {
      final xml = bigMultistatus(1200);
      expect(
        xml.length >= kParseIsolateThresholdChars,
        isTrue,
        reason: 'fixture 必须超过阈值，否则测不到 isolate 分支（实际 ${xml.length}）',
      );

      final main = WebdavClient.parseListing(xml, '', baseUri);
      final isolated = await WebdavClient.parseListingMaybeIsolated(
        xml,
        basePath: '',
        baseUri: baseUri,
        filterSystemNames: true,
      );

      expect(isolated.length, main.length);
      for (var i = 0; i < main.length; i++) {
        expect(isolated[i].name, main[i].name);
        expect(isolated[i].path, main[i].path);
        expect(isolated[i].size, main[i].size);
        expect(isolated[i].etag, main[i].etag);
        expect(isolated[i].isDirectory, main[i].isDirectory);
      }
    });

    test('低于阈值：直接在本 isolate 解析（普通目录不为几毫秒起 isolate）', () async {
      final xml = propfindXml(const [DavItem('/dav/a.txt')]);
      final entries = await WebdavClient.parseListingMaybeIsolated(
        xml,
        basePath: '',
        baseUri: baseUri,
        filterSystemNames: true,
      );
      expect(entries.single.name, 'a.txt');
    });

    test('isolate 里的解析错误能带回调用方（而不是静默空列表）', () async {
      final broken = '<broken>${'z' * kParseIsolateThresholdChars}';
      await expectLater(
        WebdavClient.parseListingMaybeIsolated(
          broken,
          basePath: '',
          baseUri: baseUri,
          filterSystemNames: true,
        ),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.message,
            'message',
            contains('无法解析'),
          ),
        ),
      );
    });
  });

  group('写操作（B1：DELETE / MKCOL / MOVE / COPY）', () {
    test('delete：204 成功；404 与 403 各自有可读文案', () async {
      final transport = FakeTransport(
        (_) async => const WebdavResponse(statusCode: 204, headers: {}),
      );
      await clientWith(transport).delete('a/b.txt');
      expect(transport.lastRequest.method, 'DELETE');
      expect(transport.lastRequest.uri.path, '/dav/a/b.txt');

      transport.handler =
          (_) async => const WebdavResponse(statusCode: 404, headers: {});
      await expectLater(
        clientWith(transport).delete('b.txt'),
        throwsA(
          isA<RemoteStorageException>()
              .having((e) => e.kind, 'kind', RemoteStorageError.notFound)
              .having((e) => e.message, 'message', contains('已不存在')),
        ),
      );

      transport.handler =
          (_) async => const WebdavResponse(statusCode: 403, headers: {});
      await expectLater(
        clientWith(transport).delete('b.txt'),
        throwsA(
          isA<RemoteStorageException>()
              .having((e) => e.kind, 'kind', RemoteStorageError.forbidden)
              .having((e) => e.message, 'message', contains('只读')),
        ),
      );
    });

    test('createDirectory：MKCOL 201 成功；405/409 说「目录已存在」而不是「不支持」', () async {
      final transport = FakeTransport(
        (_) async => const WebdavResponse(statusCode: 201, headers: {}),
      );
      await clientWith(transport).createDirectory('新建 目录');
      expect(transport.lastRequest.method, 'MKCOL');
      expect(transport.lastRequest.uri.path, '/dav/%E6%96%B0%E5%BB%BA%20%E7%9B%AE%E5%BD%95');

      for (final status in <int>[405, 409]) {
        transport.handler =
            (_) async => WebdavResponse(statusCode: status, headers: const {});
        await expectLater(
          clientWith(transport).createDirectory('dup'),
          throwsA(
            isA<RemoteStorageException>()
                .having((e) => e.kind, 'kind', RemoteStorageError.conflict)
                .having((e) => e.message, 'message', contains('目录已存在')),
          ),
          reason: 'MKCOL 的 405 是"已存在"，不能映射成"服务器不支持"',
        );
      }
    });

    test('move：Destination 为绝对 URL 且已百分号编码，Overwrite 显式为 F', () async {
      final transport = FakeTransport(
        (_) async => const WebdavResponse(statusCode: 201, headers: {}),
      );

      await clientWith(transport).move('a/中文.txt', 'b/新 名字.txt');

      expect(transport.lastRequest.method, 'MOVE');
      expect(transport.lastRequest.uri.path, '/dav/a/%E4%B8%AD%E6%96%87.txt');
      expect(transport.lastRequest.headers['overwrite'], 'F');
      expect(
        transport.lastRequest.headers['destination'],
        'https://dav.example.com/dav/b/%E6%96%B0%20%E5%90%8D%E5%AD%97.txt',
        reason: 'Destination 必须是绝对 URL，相对路径会被服务器拒绝',
      );
    });

    test('copy：Overwrite 可按参数置 T；与 MOVE 共用同一套头', () async {
      final transport = FakeTransport(
        (_) async => const WebdavResponse(statusCode: 204, headers: {}),
      );

      await clientWith(transport).copy('a.txt', 'sub/a.txt', overwrite: true);

      expect(transport.lastRequest.method, 'COPY');
      expect(transport.lastRequest.headers['overwrite'], 'T');
      expect(
        transport.lastRequest.headers['destination'],
        'https://dav.example.com/dav/sub/a.txt',
      );
    });

    test('MOVE/COPY：412 → 冲突「目标已存在」，409 → 冲突「上级目录不存在」', () async {
      final transport = FakeTransport();

      transport.handler =
          (_) async => const WebdavResponse(statusCode: 412, headers: {});
      await expectLater(
        clientWith(transport).move('a.txt', 'b.txt'),
        throwsA(
          isA<RemoteStorageException>()
              .having((e) => e.kind, 'kind', RemoteStorageError.conflict)
              .having((e) => e.message, 'message', contains('目标已存在')),
        ),
      );

      transport.handler =
          (_) async => const WebdavResponse(statusCode: 409, headers: {});
      await expectLater(
        clientWith(transport).copy('a.txt', 'missing/a.txt'),
        throwsA(
          isA<RemoteStorageException>()
              .having((e) => e.kind, 'kind', RemoteStorageError.conflict)
              .having((e) => e.message, 'message', contains('上级目录')),
        ),
      );
    });
  });

  group('Retry-After 与请求留痕（O2/O9）', () {
    test('秒数与 HTTP-date 两种形式都能解析；非法值返回 null', () {
      expect(parseRetryAfterHeader('120'), const Duration(seconds: 120));
      expect(parseRetryAfterHeader(' 30 '), const Duration(seconds: 30));
      expect(parseRetryAfterHeader('0'), isNull);
      expect(parseRetryAfterHeader('-5'), isNull);
      expect(parseRetryAfterHeader('soon'), isNull);
      expect(parseRetryAfterHeader(''), isNull);
      expect(parseRetryAfterHeader(null), isNull);

      final futureDate = HttpDate.format(
        DateTime.now().toUtc().add(const Duration(seconds: 90)),
      );
      final parsed = parseRetryAfterHeader(futureDate);
      expect(parsed, isNotNull);
      expect(parsed!.inSeconds, inInclusiveRange(60, 90));

      final pastDate = HttpDate.format(
        DateTime.now().toUtc().subtract(const Duration(seconds: 60)),
      );
      expect(parseRetryAfterHeader(pastDate), isNull);
    });

    test('429 响应的 Retry-After 带进异常，供队列退避', () async {
      final transport = FakeTransport(
        (_) async => const WebdavResponse(
          statusCode: 429,
          headers: {'retry-after': '45'},
        ),
      );
      await expectLater(
        () => clientWith(transport).list(''),
        throwsA(
          isA<RemoteStorageException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 45),
              ),
        ),
      );
    });

    test('没有 Retry-After 时异常上为 null（退回本地退避）', () async {
      final transport = FakeTransport(
        (_) async => const WebdavResponse(statusCode: 503, headers: {}),
      );
      await expectLater(
        () => clientWith(transport).list(''),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            isNull,
          ),
        ),
      );
    });
  });
}
