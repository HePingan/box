// 服务门面单测：账户 CRUD/排序、客户端缓存与失效、http 明文策略、
// 测试连接（成功/失败归一）、系统目录过滤透传、冲突扫描、
// 下载（落盘/同名序号/失败清理）、上传（跳过/覆盖/PUT 体/非法名）、
// 预览截断与超限、播放通道判定、openRelay 端到端（回环）。
//
// 全程离线：FakeTransport 注入 + 临时目录承载下载落盘。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTransport transport;
  late Directory docsDir;
  late RemoteStorageService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    transport = FakeTransport();
    docsDir = await Directory.systemTemp.createTemp('rs_service_test_');
    service = RemoteStorageService(
      transportFactory: (_) => transport,
      docsDirProvider: () async => docsDir,
    );
  });

  tearDown(() async {
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
  });

  group('账户', () {
    test('保存/更新/删除：按创建时间升序，同 id 覆盖', () async {
      await service.saveAccount(testAccount(id: 'a', createdAt: 2000));
      await service.saveAccount(testAccount(id: 'b', createdAt: 1000));
      var all = await service.loadAccounts();
      expect(all.map((a) => a.id).toList(), ['b', 'a']);

      await service.saveAccount(
        testAccount(id: 'a', label: '改名', createdAt: 2000),
      );
      all = await service.loadAccounts();
      expect(all, hasLength(2));
      expect(all.singleWhere((a) => a.id == 'a').label, '改名');

      await service.deleteAccount('a');
      all = await service.loadAccounts();
      expect(all.map((a) => a.id).toList(), ['b']);
    });
  });

  group('客户端缓存与 http 策略', () {
    test('同配置复用实例；保存后重建', () async {
      final account = testAccount();
      final first = service.clientFor(account);
      expect(identical(service.clientFor(account), first), isTrue);

      await service.saveAccount(account);
      expect(identical(service.clientFor(account), first), isFalse);
    });

    test('http 明文：deny 拒绝 / 私网 auto 放行 / 公网 auto 拒绝 / allow 放行',
        () {
      expect(
        () => service.clientFor(
          testAccount(
            id: 'h1',
            baseUrl: 'http://192.168.1.10:5005/',
            tlsMode: RemoteTlsMode.deny,
          ),
        ),
        throwsA(isA<RemoteStorageException>()),
      );
      service.clientFor(
        testAccount(id: 'h2', baseUrl: 'http://192.168.1.10:5005/'),
      );
      expect(
        () => service.clientFor(
          testAccount(id: 'h3', baseUrl: 'http://dav.example.com/dav/'),
        ),
        throwsA(isA<RemoteStorageException>()),
      );
      service.clientFor(
        testAccount(
          id: 'h4',
          baseUrl: 'http://dav.example.com/dav/',
          tlsMode: RemoteTlsMode.allow,
        ),
      );
    });

    test('地址非法：clientFor 抛归一异常', () {
      expect(
        () => service.clientFor(
          testAccount(id: 'h5', baseUrl: 'dav.example.com/dav'),
        ),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.message,
            'message',
            contains('前缀'),
          ),
        ),
      );
    });
  });

  group('测试连接', () {
    test('成功：OPTIONS 头 + PROPFIND 目录数（系统目录被过滤）', () async {
      transport.handler = (request) async {
        switch (request.method) {
          case 'OPTIONS':
            return const WebdavResponse(
              statusCode: 200,
              headers: {'dav': '1,2', 'allow': 'OPTIONS, PROPFIND'},
            );
          case 'PROPFIND':
            return xmlResponse(propfindXml(const [
              DavItem('/dav/', isCollection: true),
              DavItem('/dav/a.txt', displayName: 'a.txt', size: 3),
              DavItem('/dav/@eaDir/', isCollection: true),
            ]));
          default:
            return const WebdavResponse(statusCode: 404, headers: {});
        }
      };

      final result = await service.testConnection(testAccount());
      expect(result.optionsStatus, 200);
      expect(result.davHeader, '1,2');
      expect(result.rootListable, isTrue);
      expect(result.rootEntryCount, 1, reason: '自身条目与 @eaDir 均不计');

      final propfind =
          transport.requests.firstWhere((r) => r.method == 'PROPFIND');
      expect(
        propfind.headers['authorization'],
        'Basic ${base64.encode(utf8.encode('user@example.com:app-pass'))}',
      );
    });

    test('失败：网络异常归一为中文提示', () async {
      transport.handler = (_) => Future.error(const SocketException('down'));
      final result = await service.testConnection(testAccount());
      expect(result.rootListable, isFalse);
      expect(result.errorMessage, contains('无法连接'));
    });

    test('失败：401 归一为认证提示', () async {
      transport.handler =
          (_) async => const WebdavResponse(statusCode: 401, headers: {});
      final result = await service.testConnection(testAccount());
      expect(result.rootListable, isFalse);
      expect(result.errorMessage, contains('应用密码'));
    });
  });

  group('列目录', () {
    test('showSystemFolders 决定系统目录过滤', () async {
      transport.handler = (_) async => xmlResponse(propfindXml(const [
            DavItem('/dav/', isCollection: true),
            DavItem('/dav/@eaDir/', isCollection: true),
            DavItem('/dav/photo.jpg', displayName: 'photo.jpg', size: 10),
          ]));

      final hidden = await service.list(testAccount(), '');
      expect(hidden.map((e) => e.name).toList(), ['photo.jpg']);

      final shown = await service.list(
        testAccount(id: 'rs_all', showSystemFolders: true),
        '',
      );
      expect(shown.map((e) => e.name).toSet(), {'@eaDir', 'photo.jpg'});
    });
  });

  group('冲突扫描', () {
    test('快路径：一次 PROPFIND 判定全部同名文件（不再是每文件一次 HEAD）', () async {
      transport.handler = (request) async => xmlResponse(
            propfindXml(const [
              DavItem('/dav/a.txt'),
              DavItem('/dav/sub', isCollection: true),
              DavItem('/dav/b.txt'),
            ]),
          );

      final conflicts = await service.scanConflicts(
        testAccount(),
        files: const [
          LocalUploadFile(path: '/tmp/a.txt', name: 'a.txt', size: 1),
          LocalUploadFile(path: '/tmp/c.txt', name: 'c.txt', size: 1),
          LocalUploadFile(path: '/tmp/b.txt', name: 'b.txt', size: 1),
        ],
        targetDir: '',
      );

      expect(conflicts, ['a.txt', 'b.txt'], reason: '顺序与入参一致；目录不算冲突');
      expect(transport.requestCount, 1, reason: '3 个文件也只发 1 次请求');
      expect(transport.lastRequest.method, 'PROPFIND');
    });

    test('displayname 与真实文件名不同时按 href 判定，不漏判', () async {
      transport.handler = (_) async => xmlResponse(
            propfindXml(const [
              DavItem('/dav/real.txt', displayName: '显示名不一样.txt'),
            ]),
          );

      final conflicts = await service.scanConflicts(
        testAccount(),
        files: const [
          LocalUploadFile(path: '/tmp/real.txt', name: 'real.txt', size: 1),
        ],
        targetDir: '',
      );

      expect(conflicts, ['real.txt'], reason: '漏判会导致静默覆盖');
    });

    test('目录列表失败（403）时退回逐文件 HEAD，保持判定权威', () async {
      transport.handler = (request) async {
        if (request.method == 'PROPFIND') {
          return const WebdavResponse(statusCode: 403, headers: {});
        }
        return request.uri.path.endsWith('a.txt')
            ? headResponse()
            : headResponse(status: 404);
      };

      final conflicts = await service.scanConflicts(
        testAccount(),
        files: const [
          LocalUploadFile(path: '/tmp/a.txt', name: 'a.txt', size: 1),
          LocalUploadFile(path: '/tmp/b.txt', name: 'b.txt', size: 1),
        ],
        targetDir: '',
      );

      expect(conflicts, ['a.txt']);
      expect(
        transport.requests.where((r) => r.method == 'HEAD'),
        hasLength(2),
        reason: '退化路径必须仍有权威判定，不能因为优化漏判',
      );
    });

    test('空文件列表直接返回空，不发请求', () async {
      final conflicts = await service.scanConflicts(
        testAccount(),
        files: const [],
        targetDir: '',
      );
      expect(conflicts, isEmpty);
      expect(transport.requestCount, 0);
    });
  });

  group('下载', () {
    test('落盘：字节一致且位于账户子目录', () async {
      final bytes = List<int>.generate(64, (i) => i);
      transport.handler = (_) async => streamResponse(bytes);

      final path = await service.download(
        testAccount(),
        remotePath: 'a.bin',
        fileName: 'a.bin',
      );
      expect(path, contains('remote_storage/rs_test'));
      expect(await File(path).readAsBytes(), bytes);
    });

    test('同名自动加序号：第二次为「a (1).bin」', () async {
      transport.handler = (_) async => streamResponse(const [1, 2, 3]);
      final first = await service.download(
        testAccount(),
        remotePath: 'a.bin',
        fileName: 'a.bin',
      );
      final second = await service.download(
        testAccount(),
        remotePath: 'a.bin',
        fileName: 'a.bin',
      );
      expect(second, isNot(first));
      expect(second, endsWith('a (1).bin'));
      expect(await File(first).exists(), isTrue);
      expect(await File(second).exists(), isTrue);
    });

    test('失败：不留 .part 残留', () async {
      transport.handler = (_) => Future.error(const SocketException('down'));
      await expectLater(
        service.download(
          testAccount(),
          remotePath: 'x.bin',
          fileName: 'x.bin',
        ),
        throwsA(isA<RemoteStorageException>()),
      );
      final leftovers =
          docsDir.listSync(recursive: true).whereType<File>().toList();
      expect(leftovers, isEmpty);
    });
  });

  group('上传', () {
    Future<File> writeLocal(String name, String text) async {
      final file = File('${docsDir.path}/$name');
      await file.writeAsString(text);
      return file;
    }

    test('默认跳过：远端同名时返回 false 且不发 PUT', () async {
      transport.handler = (request) async => request.method == 'HEAD'
          ? headResponse()
          : const WebdavResponse(statusCode: 500, headers: {});
      final local = await writeLocal('u.txt', 'hello');

      final ok = await service.uploadFile(
        testAccount(),
        file: LocalUploadFile(path: local.path, name: 'u.txt', size: 5),
        targetDir: '',
        overwrite: false,
      );
      expect(ok, isFalse);
      expect(transport.requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    test('覆盖：PUT 到目标目录，请求体与本地一致', () async {
      transport.handler = (request) async => request.method == 'PUT'
          ? const WebdavResponse(statusCode: 201, headers: {})
          : const WebdavResponse(statusCode: 404, headers: {});
      final local = await writeLocal('u.txt', 'hello');

      final ok = await service.uploadFile(
        testAccount(),
        file: LocalUploadFile(path: local.path, name: 'u.txt', size: 5),
        targetDir: 'docs',
        overwrite: true,
      );
      expect(ok, isTrue);
      final put = transport.requests.singleWhere((r) => r.method == 'PUT');
      expect(put.uri.toString(), 'https://dav.example.com/dav/docs/u.txt');
      expect(await bodyTextOf(put), 'hello');
    });

    test('非法文件名：拒绝并抛归一异常', () async {
      final local = await writeLocal('u.txt', 'x');
      await expectLater(
        service.uploadFile(
          testAccount(),
          file: LocalUploadFile(path: local.path, name: '../evil.txt', size: 1),
          targetDir: '',
          overwrite: true,
        ),
        throwsA(isA<RemoteStorageException>()),
      );
    });
  });

  group('预览', () {
    test('文本：超过上限截断到 512KB 并标记', () async {
      final big = Uint8List(kPreviewTextMaxBytes + 100);
      transport.handler = (_) async => streamResponse(big);

      final preview = await service.readTextPreview(testAccount(), 'big.txt');
      expect(preview.truncated, isTrue);
      expect(preview.bytes.length, kPreviewTextMaxBytes);
      expect(preview.oversize, isFalse);
    });

    test('图片：HEAD 超 20MB 直接拒绝（不发 GET）', () async {
      transport.handler = (request) async => request.method == 'HEAD'
          ? headResponse(headers: {
              'content-length': '${kPreviewImageMaxBytes + 1}',
            })
          : const WebdavResponse(statusCode: 500, headers: {});

      final preview = await service.readImagePreview(testAccount(), 'big.jpg');
      expect(preview.oversize, isTrue);
      expect(preview.bytes, isEmpty);
      expect(preview.totalLength, kPreviewImageMaxBytes + 1);
      expect(transport.requests.where((r) => r.method == 'GET'), isEmpty);
    });
  });

  group('播放通道', () {
    RemoteStorageEntry entry() =>
        const RemoteStorageEntry(name: 'v.mp4', path: 'v.mp4', isDirectory: false);

    test('https 直连带 Basic；http 与自签走中继', () {
      final direct = service.resolvePlayback(testAccount(), entry());
      expect(direct.needsRelay, isFalse);
      expect(
        direct.directUri.toString(),
        'https://dav.example.com/dav/v.mp4',
      );
      expect(direct.headers['authorization'], startsWith('Basic '));

      final lan = service.resolvePlayback(
        testAccount(id: 'lan', baseUrl: 'http://192.168.1.10:5005/'),
        entry(),
      );
      expect(lan.needsRelay, isTrue);
      expect(lan.headers, isEmpty);

      final selfSigned = service.resolvePlayback(
        testAccount(id: 'ss', allowBadCert: true),
        entry(),
      );
      expect(selfSigned.needsRelay, isTrue);
    });

    test('openRelay：回环请求经假传输转发字节', () async {
      // TestWidgetsFlutterBinding 默认把 HttpClient 拦截为 400（且 HttpOverrides.global
      // 只有 setter，无法读回保存）；置空后本测试内创建的客户端走真实实现。
      // 本文件其余测试均用假传输，不发真实网络请求，故置空不会影响它们；
      // 请求只发往本机回环中继（127.0.0.1），不触外网。
      HttpOverrides.global = null;

      final bytes = List<int>.generate(32, (i) => i * 2);
      transport.handler = (_) async => streamResponse(bytes);

      final relay = await service.openRelay(testAccount(), entry());
      addTearDown(relay.close);

      final client = HttpClient();
      final resp = await (await client.getUrl(Uri.parse(relay.url))).close();
      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      client.close(force: true);

      expect(resp.statusCode, 200);
      expect(builder.takeBytes(), bytes);
      expect(transport.lastRequest.method, 'GET');
      expect(
        transport.lastRequest.uri.toString(),
        'https://dav.example.com/dav/v.mp4',
      );
    });
  });
}
