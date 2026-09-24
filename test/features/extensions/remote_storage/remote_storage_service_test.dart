// 服务门面单测：账户 CRUD/排序、客户端缓存与失效、http 明文策略、
// 测试连接（成功/失败归一）、系统目录过滤透传、冲突扫描、
// 下载（落盘/同名序号/失败清理）、上传（跳过/覆盖/PUT 体/非法名）、
// 预览截断与超限、播放通道判定、openRelay 端到端（回环）。
//
// 全程离线：FakeTransport 注入 + 临时目录承载下载落盘。

import 'dart:async';
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

    test('服务器以 NFD 存名时按冲突处理，不造出第二份同名文件（O6）', () async {
      // 服务器上是 NFD 的 café.txt，用户选的是 NFC 的 café.txt：
      // `exists()` 会返回 404（名字不相等），只看它就会重复上传。
      transport.handler = (request) async {
        if (request.method == 'PROPFIND') {
          return xmlResponse(propfindXml(const [
            DavItem('/dav/café.txt'),
          ]));
        }
        return const WebdavResponse(statusCode: 404, headers: {});
      };

      final conflicts = await service.scanConflicts(
        testAccount(),
        files: const [
          LocalUploadFile(path: '/tmp/x', name: 'caf\u00e9.txt', size: 1),
          LocalUploadFile(path: '/tmp/y', name: 'other.txt', size: 1),
        ],
        targetDir: '',
      );

      expect(conflicts, ['caf\u00e9.txt'], reason: '归一化差异要按同名算');
      expect(transport.requestCount, 1, reason: '仍然只发一次 PROPFIND');
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

    // ---------------------------------------------------------- C2 断点续传

    /// 造一个"上次中断留下的断点"：`.part` 字节 + 同名 `.part.meta` 归属信息。
    Future<File> seedPartial(
      String name,
      List<int> bytes, {
      String? accountId,
      String remotePath = 'a.bin',
    }) async {
      final dir = Directory('${docsDir.path}/remote_storage/${testAccount().id}');
      await dir.create(recursive: true);
      final part = File('${dir.path}/$name.part');
      await part.writeAsBytes(bytes);
      await File('${part.path}.meta').writeAsString(
        PartialDownload(
          accountId: accountId ?? testAccount().id,
          remotePath: remotePath,
        ).toJsonString(),
      );
      return part;
    }

    test('同账户同路径的断点 → 带 Range 续传，落盘是两段拼接的结果', () async {
      final part = await seedPartial('a.bin', const [1, 2, 3]);
      transport.handler = (_) async => WebdavResponse(
        statusCode: 206,
        headers: {
          'content-range': 'bytes 3-5/6',
          'content-length': '3',
        },
        bodyStream: Stream<List<int>>.value(Uint8List.fromList([4, 5, 6])),
      );

      final path = await service.download(
        testAccount(),
        remotePath: 'a.bin',
        fileName: 'a.bin',
      );

      expect(transport.lastRequest.headers['range'], 'bytes=3-');
      expect(await File(path).readAsBytes(), [1, 2, 3, 4, 5, 6]);
      // 完成品落位、断点与元数据都清掉
      expect(await File('${part.path}.meta').exists(), isFalse);
      expect(await part.exists(), isFalse);
    });

    test('断点属于别的账户 → 不续传：先丢弃断点，再整份重下', () async {
      final part = await seedPartial('a.bin', const [9, 9, 9], accountId: 'other');
      transport.handler = (_) async => streamResponse(const [1, 2]);

      final path = await service.download(
        testAccount(),
        remotePath: 'a.bin',
        fileName: 'a.bin',
      );

      // 没有 Range：偏移错了会把坏字节拼进去
      expect(transport.lastRequest.headers.containsKey('range'), isFalse);
      expect(await File(path).readAsBytes(), [1, 2]);
      expect(await part.exists(), isFalse);
    });

    test('断点属于别的远端路径（同名文件）→ 同样不续传', () async {
      await seedPartial('a.bin', const [9, 9, 9], remotePath: 'other/a.bin');
      transport.handler = (_) async => streamResponse(const [1, 2]);

      final path = await service.download(
        testAccount(),
        remotePath: 'a.bin',
        fileName: 'a.bin',
      );

      expect(transport.lastRequest.headers.containsKey('range'), isFalse);
      expect(await File(path).readAsBytes(), [1, 2]);
    });

    test('0 字节断点不复用（没有可续的字节）', () async {
      final part = await seedPartial('a.bin', const []);
      transport.handler = (_) async => streamResponse(const [1, 2]);

      final path = await service.download(
        testAccount(),
        remotePath: 'a.bin',
        fileName: 'a.bin',
      );

      expect(transport.lastRequest.headers.containsKey('range'), isFalse);
      expect(await File(path).readAsBytes(), [1, 2]);
      expect(path, isNot(endsWith('a (1).bin')));
      expect(await part.exists(), isFalse);
    });

    test('成品已存在时不覆盖它：落到「a (1).bin」，也不拿它的断点去续传', () async {
      // 已有成品 a.bin（上一次下载的结果）
      final dir = Directory('${docsDir.path}/remote_storage/${testAccount().id}');
      await dir.create(recursive: true);
      await File('${dir.path}/a.bin').writeAsBytes(const [1, 1, 1]);
      // 同时存在一份"别的文件"留下的同名断点
      await seedPartial('a.bin', const [7, 7]);

      transport.handler = (_) async => streamResponse(const [2, 2]);

      final path = await service.download(
        testAccount(),
        remotePath: 'b.bin',
        fileName: 'a.bin',
      );

      expect(path, endsWith('a (1).bin'));
      expect(await File('${dir.path}/a.bin').readAsBytes(), [1, 1, 1]);
      expect(await File(path).readAsBytes(), [2, 2]);
    });

    test('可重试失败且已收到字节 → 保留 .part 供下一轮续传', () async {
      transport.handler = (_) async => WebdavResponse(
        statusCode: 200,
        headers: {'content-length': '10'},
        bodyStream: Stream<List<int>>.fromIterable([
          Uint8List.fromList([1, 2, 3]),
        ]).asyncExpand((chunk) async* {
          yield chunk;
          throw const SocketException('broken mid-stream');
        }),
      );
      // 中途断流抛的是原始 SocketException（不是 RemoteStorageException）——
      // 队列按 isRetryableTransferError 分类，这里只断言"断点留下了"。
      try {
        await service.download(
          testAccount(),
          remotePath: 'a.bin',
          fileName: 'a.bin',
        );
        fail('中途断流应当抛出');
      } catch (_) {
        // 类型不重要：重要的是别把半截文件当成果交出去
      }
      final dir = Directory('${docsDir.path}/remote_storage/${testAccount().id}');
      final part = File('${dir.path}/a.bin.part');
      expect(await part.exists(), isTrue);
      expect(await part.length(), 3);
      expect(await File('${part.path}.meta').exists(), isTrue);
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

    test('并发同名上传：第二个视为已存在，不静默覆盖（C7）', () async {
      // 队列现在会同时跑多个任务。`exists()` 在另一个同名上传写完之前返回 404，
      // 两个文件都会通过检查 → 后写的静默覆盖先写的。在途占位必须堵住这条路。
      final gate = Completer<void>();
      var puts = 0;
      transport.handler = (request) async {
        if (request.method == 'HEAD') {
          return const WebdavResponse(statusCode: 404, headers: {});
        }
        if (request.method == 'PUT') {
          puts += 1;
          await gate.future;
          return const WebdavResponse(statusCode: 201, headers: {});
        }
        return const WebdavResponse(statusCode: 500, headers: {});
      };
      final one = await writeLocal('one.txt', 'one');
      final two = await writeLocal('two.txt', 'two');

      final first = service.uploadFile(
        testAccount(),
        file: LocalUploadFile(path: one.path, name: 'u.txt', size: 3),
        targetDir: '',
        overwrite: false,
      );
      await pumpEventQueue(); // 让第一个走到 PUT 并占住在途名额

      final second = await service.uploadFile(
        testAccount(),
        file: LocalUploadFile(path: two.path, name: 'u.txt', size: 3),
        targetDir: '',
        overwrite: false,
      );

      expect(second, isFalse, reason: '同名在途 → 视为已存在，直接跳过');
      expect(puts, 1, reason: '只允许一个 PUT 落在同一个远端路径上');

      gate.complete();
      expect(await first, isTrue);
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

  group('写操作（B1）', () {
    FakeTransport writeTransport({
      int moveStatus = 201,
      int deleteStatus = 204,
      int mkcolStatus = 201,
      bool destinationExists = false,
    }) {
      return FakeTransport((request) async {
        switch (request.method) {
          case 'HEAD':
            // 只用于"目标是否存在"的预检。
            final exists = destinationExists &&
                (request.uri.path.endsWith('b.txt') ||
                    request.uri.path.endsWith('dup') ||
                    request.uri.path.endsWith('%E6%96%B0%E5%BB%BA'));
            return headResponse(status: exists ? 200 : 404);
          case 'MOVE':
          case 'COPY':
            return WebdavResponse(statusCode: moveStatus, headers: const {});
          case 'DELETE':
            return WebdavResponse(statusCode: deleteStatus, headers: const {});
          case 'MKCOL':
            return WebdavResponse(statusCode: mkcolStatus, headers: const {});
          case 'PROPFIND':
            return xmlResponse(propfindXml(const [DavItem('/dav/a.txt')]));
          default:
            return const WebdavResponse(statusCode: 200, headers: {});
        }
      });
    }

    test('createFolder：MKCOL 201 成功并作废父目录缓存', () async {
      transport = writeTransport();
      final svc = RemoteStorageService(
        transportFactory: (_) => transport,
        docsDirProvider: () async => docsDir,
        dirCacheTtl: const Duration(seconds: 30),
      );
      final account = testAccount();

      await svc.list(account, ''); // 先灌一次缓存
      await svc.createFolder(account, parentPath: '', name: '新建');
      await svc.list(account, ''); // 缓存应已失效 → 再发一次 PROPFIND

      expect(
        transport.requests.where((r) => r.method == 'MKCOL'),
        hasLength(1),
      );
      expect(
        transport.requests.where((r) => r.method == 'PROPFIND'),
        hasLength(2),
      );
    });

    test('createFolder：名称不可用 → 明确原因，不发请求', () async {
      transport = writeTransport();
      await expectLater(
        service.createFolder(testAccount(), parentPath: '', name: 'NUL'),
        throwsA(
          isA<RemoteStorageException>()
              .having((e) => e.message, 'message', contains('保留名')),
        ),
      );
      expect(transport.requests, isEmpty);
    });

    test('renameEntry：先查重再 MOVE，Destination 指向同目录新名', () async {
      transport = writeTransport();
      const entry = RemoteStorageEntry(
        name: 'a.txt',
        path: 'a.txt',
        isDirectory: false,
      );

      await service.renameEntry(testAccount(), entry: entry, newName: 'b.txt');

      expect(transport.lastRequest.method, 'MOVE');
      expect(
        transport.lastRequest.headers['destination'],
        'https://dav.example.com/dav/b.txt',
      );
      expect(transport.lastRequest.headers['overwrite'], 'F');
    });

    test('renameEntry：目标已存在 → 冲突且不发 MOVE', () async {
      transport = writeTransport(destinationExists: true);
      const entry = RemoteStorageEntry(
        name: 'a.txt',
        path: 'a.txt',
        isDirectory: false,
      );

      await expectLater(
        service.renameEntry(testAccount(), entry: entry, newName: 'b.txt'),
        throwsA(
          isA<RemoteStorageException>()
              .having((e) => e.kind, 'kind', RemoteStorageError.conflict),
        ),
      );
      expect(
        transport.requests.where((r) => r.method == 'MOVE'),
        isEmpty,
        reason: '预检发现同名就不该再发 MOVE（避免服务器忽略 Overwrite 时静默覆盖）',
      );
    });

    test('renameEntry：名字没变 → 直接返回，不发任何请求', () async {
      transport = writeTransport();
      const entry = RemoteStorageEntry(
        name: 'a.txt',
        path: 'a.txt',
        isDirectory: false,
      );

      await service.renameEntry(testAccount(), entry: entry, newName: 'a.txt');
      expect(transport.requests, isEmpty);
    });

    test('moveEntry / copyEntry：目标目录与源目录缓存都作废', () async {
      transport = writeTransport();
      final svc = RemoteStorageService(
        transportFactory: (_) => transport,
        docsDirProvider: () async => docsDir,
        dirCacheTtl: const Duration(seconds: 30),
      );
      final account = testAccount();
      const entry = RemoteStorageEntry(
        name: 'a.txt',
        path: 'src/a.txt',
        isDirectory: false,
      );

      await svc.list(account, 'src');
      await svc.list(account, 'dst');

      await svc.moveEntry(account, entry: entry, targetDir: 'dst');
      expect(transport.lastRequest.method, 'MOVE');
      expect(
        transport.lastRequest.headers['destination'],
        'https://dav.example.com/dav/dst/a.txt',
      );

      await svc.list(account, 'src');
      await svc.list(account, 'dst');
      expect(
        transport.requests.where((r) => r.method == 'PROPFIND'),
        hasLength(4),
        reason: '源目录与目标目录的缓存都要失效',
      );

      await svc.copyEntry(account, entry: entry, targetDir: 'dst');
      expect(transport.lastRequest.method, 'COPY');
    });

    test('deleteEntries：逐项执行，单项失败不中断整批', () async {
      transport = FakeTransport((request) async {
        if (request.uri.path.endsWith('bad.txt')) {
          return const WebdavResponse(statusCode: 403, headers: {});
        }
        return const WebdavResponse(statusCode: 204, headers: {});
      });

      final result = await service.deleteEntries(testAccount(), const [
        RemoteStorageEntry(name: 'ok1.txt', path: 'ok1.txt', isDirectory: false),
        RemoteStorageEntry(name: 'bad.txt', path: 'bad.txt', isDirectory: false),
        RemoteStorageEntry(name: 'ok2.txt', path: 'ok2.txt', isDirectory: false),
      ]);

      expect(result.succeeded, 2);
      expect(result.hasFailures, isTrue);
      expect(result.failures.single, contains('bad.txt'));
      expect(result.summary, contains('成功 2 项'));
      expect(
        transport.requests.where((r) => r.method == 'DELETE'),
        hasLength(3),
        reason: '一个失败不能挡住后面两个',
      );
    });

    test('deleteEntry：403 时抛出可读原因（UI 直接展示）', () async {
      transport = FakeTransport(
        (_) async => const WebdavResponse(statusCode: 403, headers: {}),
      );
      await expectLater(
        service.deleteEntry(
          testAccount(),
          entry: const RemoteStorageEntry(
            name: 'ro.txt',
            path: 'ro.txt',
            isDirectory: false,
          ),
        ),
        throwsA(
          isA<RemoteStorageException>()
              .having((e) => e.message, 'message', contains('只读')),
        ),
      );
    });
  });

  group('目录缓存（O3：返回上一级不再重列）', () {
    RemoteStorageService cachingService(Duration ttl) => RemoteStorageService(
          transportFactory: (_) => transport,
          docsDirProvider: () async => docsDir,
          dirCacheTtl: ttl,
        );

    FakeTransport listingTransport() => FakeTransport(
          (request) async => switch (request.method) {
            'PROPFIND' => xmlResponse(
                propfindXml(const [DavItem('/dav/a.txt', etag: '"e1"')]),
              ),
            'PUT' => const WebdavResponse(statusCode: 201, headers: {}),
            _ => headResponse(status: 404),
          },
        );

    test('TTL 内重复 list 命中缓存：只发 1 次 PROPFIND', () async {
      transport = listingTransport();
      final svc = cachingService(const Duration(seconds: 30));

      final first = await svc.list(testAccount(), '');
      final second = await svc.list(testAccount(), '');

      expect(transport.requestCount, 1);
      expect(first.single.name, 'a.txt');
      expect(second.single.etag, '"e1"', reason: 'etag 要跟着缓存一起复用');
    });

    test('forceRefresh 绕过缓存（下拉刷新/刷新按钮的语义）', () async {
      transport = listingTransport();
      final svc = cachingService(const Duration(seconds: 30));

      await svc.list(testAccount(), '');
      await svc.list(testAccount(), '', forceRefresh: true);

      expect(transport.requestCount, 2);
    });

    test('TTL 为 0 等于不缓存', () async {
      transport = listingTransport();
      final svc = cachingService(Duration.zero);

      await svc.list(testAccount(), '');
      await svc.list(testAccount(), '');

      expect(transport.requestCount, 2);
    });

    test('不同账户、不同路径互不串缓存', () async {
      transport = listingTransport();
      final svc = cachingService(const Duration(seconds: 30));

      await svc.list(testAccount(id: 'a'), '');
      await svc.list(testAccount(id: 'b'), '');
      await svc.list(testAccount(id: 'a'), 'sub');

      expect(transport.requestCount, 3);
    });

    test('上传成功后该目录缓存失效（传完立刻能看到）', () async {
      transport = listingTransport();
      final svc = cachingService(const Duration(seconds: 30));
      final account = testAccount();

      await svc.list(account, '');
      final src = File('${docsDir.path}/up.txt')..writeAsStringSync('x');
      await svc.uploadFile(
        account,
        file: LocalUploadFile(path: src.path, name: 'up.txt', size: 1),
        targetDir: '',
        overwrite: true,
      );
      await svc.list(account, '');

      expect(
        transport.requests.where((r) => r.method == 'PROPFIND'),
        hasLength(2),
        reason: '上传后必须重新列目录，否则用户看不到刚传的文件',
      );
    });

    test('配额透传（服务器未实现时为空对象，不报错）', () async {
      transport.handler = (_) async =>
          xmlResponse(quotaXml(availableBytes: 42, usedBytes: 8));

      final q = await service.quota(testAccount());
      expect(q.availableBytes, 42);
      expect(q.usedBytes, 8);

      transport.handler = (_) async => xmlResponse(quotaXml());
      final empty = await service.quota(testAccount());
      expect(empty.hasAny, isFalse);
    });
  });
}
