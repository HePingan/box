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
import 'package:box/features/extensions/plugins/remote_storage/data/remote_thumbnail_cache.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/playback_progress_store.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/remote_storage_store.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/transfer_keepalive.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/transfer_queue_store.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/video_frame_channel.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exif_fixtures.dart';
import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTransport transport;
  late Directory docsDir;
  late Directory thumbRoot;
  late RemoteStorageService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    transport = FakeTransport();
    docsDir = await Directory.systemTemp.createTemp('rs_service_test_');
    thumbRoot = await Directory.systemTemp.createTemp('rs_thumb_test_');
    service = RemoteStorageService(
      transportFactory: (_) => transport,
      docsDirProvider: () async => docsDir,
      // 注入临时目录：缩略图缓存默认落 path_provider 的目录，单测里要避开平台通道。
      thumbnailCache: RemoteThumbnailCache(root: thumbRoot),
    );
  });

  tearDown(() async {
    for (final dir in [docsDir, thumbRoot]) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
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
      //
      // 285 P4：同步点改成**等信号**，不再用 `pumpEventQueue()` 数轮数。
      // 真实失败日志（全量并发时）证明"20 轮"根本同步不住：
      //   Expected: <1> Actual: <0>   （第一个还没发出 PUT）
      //   PathNotFoundException ... rs_service_test_XXX/one.txt（测试提前结束、
      //   目录被 tearDown 删掉后，在途的那个上传才去取文件长度）
      // 根因：`srcFile.length()` 是 IO 线程池的活，机器忙时 20 个事件循环轮次
      // 早就跑完了而它还没返回 —— 轮数同步点在负载下失效。
      final gate = Completer<void>();
      final putStarted = Completer<void>();
      var puts = 0;
      transport.handler = (request) async {
        if (request.method == 'HEAD') {
          // 故意慢一点：模拟机器忙时 IO 排队。用轮数同步的写法在这里必红，
          // 用信号同步的写法不受影响 —— 这条用例从此对负载不敏感。
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return const WebdavResponse(statusCode: 404, headers: {});
        }
        if (request.method == 'PUT') {
          puts += 1;
          if (!putStarted.isCompleted) putStarted.complete();
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
      // 等到第一个真的进了 PUT（在途名额已占住）；有界等待，真出问题会快速失败
      // 而不是把整个测试挂住。
      await putStarted.future.timeout(const Duration(seconds: 10));

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

  group('列表缩略图（281+）', () {
    RemoteStorageEntry image({String name = 'a.jpg', int size = 1000}) =>
        RemoteStorageEntry(
          name: name,
          path: name,
          isDirectory: false,
          size: size,
          modifiedAt: DateTime.utc(2023, 1, 30, 11, 22),
        );

    test('超过上限的**非 JPEG**：直接返回 null，一次请求都不发', () async {
      // 283 D1 起，超过上限的 JPEG 会走"EXIF 内嵌缩略图"探测（见下一组），
      // 但 PNG/WebP 里没有内嵌缩略图，探测没有意义。
      final result = await service.readThumbnail(
        testAccount(),
        image(name: 'a.png', size: kThumbnailMaxBytes + 1),
      );
      expect(result, isNull);
      expect(transport.requestCount, 0, reason: '不该为了超大图去发请求');
    });

    test('非图片：返回 null，不发请求', () async {
      final result = await service.readThumbnail(
        testAccount(),
        image(name: 'a.mp4'),
      );
      expect(result, isNull);
      expect(transport.requestCount, 0);
    });

    test('取回字节并缓存：第二次不再请求（滚动来回不重复下载）', () async {
      transport.handler = (_) async => streamResponse(kTinyPng, status: 206);
      final account = testAccount();
      final entry = image(size: kTinyPng.length);

      final first = await service.readThumbnail(account, entry);
      expect(first, isNotNull);
      expect(first!.length, kTinyPng.length);
      expect(transport.requestCount, 1);

      final second = await service.readThumbnail(account, entry);
      expect(second, isNotNull);
      expect(transport.requestCount, 1, reason: '命中缓存，不该再发请求');
    });

    test('服务器报错 → null（列表回退通用图标，不显示错误）', () async {
      transport.handler = (_) async => headResponse(status: 500);
      final result = await service.readThumbnail(testAccount(), image());
      expect(result, isNull);
    });

    test('返回内容比条目声明的大（列表过期）→ 不显示、不缓存', () async {
      // 条目说 1000 字节（够小），实际服务器给了超过上限的内容。
      final big = List<int>.filled(kThumbnailMaxBytes + 10, 1);
      transport.handler = (_) async => streamResponse(big, status: 206);

      final result = await service.readThumbnail(testAccount(), image());
      expect(result, isNull);

      // 再取一次仍然要发请求（没缓存失败结果）
      transport.handler = (_) async => streamResponse(kTinyPng, status: 206);
      final again = await service.readThumbnail(testAccount(), image());
      expect(again, isNotNull);
    });
  });

  group('EXIF 内嵌缩略图（283 D1）', () {
    RemoteStorageEntry jpeg({String name = 'big.jpg', int? size = 4 * 1024 * 1024}) =>
        RemoteStorageEntry(
          name: name,
          path: name,
          isDirectory: false,
          size: size,
          modifiedAt: DateTime.utc(2021, 8, 7, 13, 47),
        );

    test('大 JPEG 命中：一次有界前缀读就拿到内嵌缩略图（字节与真值一致）', () async {
      transport.handler = (_) async =>
          streamResponse(kExifJpeg, status: 206); // 服务器只回了文件开头一段

      final result = await service.readThumbnail(testAccount(), jpeg());

      expect(result, kExifEmbeddedThumb, reason: '取出的必须是 EXIF 里那张缩略图');
      expect(transport.requestCount, 1);
      expect(
        transport.requests.single.headers['range'],
        'bytes=0-',
        reason: '起点式 Range——带结束偏移的写法在坚果云上会被 416（281 的教训）',
      );
    });

    test('探测有上界：大图不会被整个读回来', () async {
      var chunksProduced = 0;
      Stream<List<int>> bigBody() async* {
        yield kExifJpeg; // 文件开头（EXIF 在这里）
        for (var i = 0; i < 64; i++) {
          chunksProduced++;
          yield Uint8List(64 * 1024); // 再补 4MB，模拟真实大图
        }
      }

      transport.handler = (_) async => WebdavResponse(
        statusCode: 206,
        headers: const {'content-length': '4194304'},
        bodyStream: bigBody(),
      );

      final result = await service.readThumbnail(testAccount(), jpeg());

      expect(result, kExifEmbeddedThumb);
      expect(
        chunksProduced,
        lessThan(64),
        reason: '读到 kExifProbeBytes 上限就该断开，不该把整张图读完',
      );
    });

    test('没有内嵌缩略图：返回 null，且**不重复探测**（负缓存）', () async {
      transport.handler = (_) async =>
          streamResponse(kJpegWithoutExif, status: 206);

      expect(await service.readThumbnail(testAccount(), jpeg()), isNull);
      expect(transport.requestCount, 1);

      expect(await service.readThumbnail(testAccount(), jpeg()), isNull);
      expect(
        transport.requestCount,
        1,
        reason: '探过没有就该记住，否则每次滚动都白花一次 256KB',
      );
    });

    test('大小未知的 JPEG 也走探测（未知大小原本一律不取）', () async {
      transport.handler = (_) async => streamResponse(kExifJpeg, status: 206);

      final result = await service.readThumbnail(testAccount(), jpeg(size: null));

      expect(result, kExifEmbeddedThumb);
    });

    test('命中后第二次走缓存，不再请求', () async {
      transport.handler = (_) async => streamResponse(kExifJpeg, status: 206);

      await service.readThumbnail(testAccount(), jpeg());
      await service.readThumbnail(testAccount(), jpeg());

      expect(transport.requestCount, 1, reason: '缩略图缓存命中');
    });

    test('探测失败（服务器 500）→ null，列表回退通用图标', () async {
      transport.handler = (_) async => headResponse(status: 500);

      expect(await service.readThumbnail(testAccount(), jpeg()), isNull);
    });
  });

  group('删账户清理本地残留（284 P1）', () {
    test('deleteAccount 清掉该账户的进度/滚动位置/缩略图，别的账户不受影响', () async {
      final cache = RemoteThumbnailCache(root: thumbRoot);
      final svc = RemoteStorageService(
        transportFactory: (_) => transport,
        docsDirProvider: () async => docsDir,
        thumbnailCache: cache,
      );
      const progress = RemotePlaybackProgressStore();
      final store = RemoteStorageStore();
      final a = testAccount(id: 'accA', createdAt: 1000);
      final b = testAccount(id: 'accB', createdAt: 2000);
      await svc.saveAccount(a);
      await svc.saveAccount(b);

      await progress.save(
        a,
        '/v.mp4',
        position: const Duration(minutes: 3),
        duration: const Duration(minutes: 10),
      );
      await progress.save(
        b,
        '/v.mp4',
        position: const Duration(minutes: 4),
        duration: const Duration(minutes: 10),
      );
      await store.saveBrowserScrollOffsets(<String, double>{
        'accA|/photos': 10,
        'accB|/photos': 20,
      });
      await cache.put('accA|/a.jpg|1', Uint8List.fromList(<int>[1, 2, 3]),
          scope: 'accA');
      await cache.put('accB|/b.jpg|1', Uint8List.fromList(<int>[1, 2, 3]),
          scope: 'accB');

      await svc.deleteAccount('accA');

      expect((await svc.loadAccounts()).map((x) => x.id).toList(), <String>['accB']);
      expect(
        await progress.positionFor(a, '/v.mp4'),
        isNull,
        reason: '进度残留是最像隐私的一条',
      );
      expect(await progress.positionFor(b, '/v.mp4'), isNotNull);
      expect(
        (await store.loadBrowserScrollOffsets()).keys.toSet(),
        <String>{'accB|/photos'},
      );
      expect(await cache.get('accA|/a.jpg|1', scope: 'accA'), isNull);
      expect(await cache.get('accB|/b.jpg|1', scope: 'accB'), isNotNull);
    });

    test('deleteAccount 后 EXIF 负缓存里该账户的条目也被清掉', () async {
      final cache = RemoteThumbnailCache(root: thumbRoot);
      final svc = RemoteStorageService(
        transportFactory: (_) => transport,
        docsDirProvider: () async => docsDir,
        thumbnailCache: cache,
      );
      final a = testAccount(id: 'accA', createdAt: 1000);
      await svc.saveAccount(a);

      // 一张大图（> 3MB）走 EXIF 探测：字节里没有 EXIF 内嵌缩略图 → 进负缓存。
      transport.handler = (request) async {
        if (request.method == 'GET') return streamResponse(kTinyPng);
        return const WebdavResponse(statusCode: 200, headers: <String, String>{});
      };
      const entry = RemoteStorageEntry(
        path: 'big.jpg',
        name: 'big.jpg',
        isDirectory: false,
        size: kThumbnailMaxBytes + 1,
      );
      int getCount() =>
          transport.requests.where((r) => r.method == 'GET').length;

      expect(await svc.readThumbnail(a, entry), isNull);
      expect(getCount(), 1, reason: '第一次探测发一次请求');
      expect(await svc.readThumbnail(a, entry), isNull);
      expect(getCount(), 1, reason: '第二次不再发请求（负缓存生效）');

      await svc.deleteAccount('accA');
      await svc.readThumbnail(a, entry);
      expect(
        getCount(),
        2,
        reason: '删账户清了负缓存，重新读时该探还得探',
      );
    });
  });

  group('EXIF 探测统计（284 P3）', () {
    /// 大图（> 3MB）的 JPEG 条目：走 EXIF 内嵌缩略图那条路。
    RemoteStorageEntry bigJpeg(String name) => RemoteStorageEntry(
      path: name,
      name: name,
      isDirectory: false,
      size: kThumbnailMaxBytes + 1,
    );

    test('命中与未命中分别计数；同一张重复读不重复计数', () async {
      final a = testAccount(id: 'accStats');
      final withThumb = bigJpeg('with.jpg');
      final withoutThumb = bigJpeg('without.jpg');
      transport.handler = (request) async {
        if (request.uri.path.contains('with.jpg')) {
          return streamResponse(kExifJpeg);
        }
        return streamResponse(kTinyPng);
      };

      expect(await service.readThumbnail(a, withThumb), isNotNull);
      expect(await service.readThumbnail(a, withoutThumb), isNull);

      var stats = service.exifThumbnailStats();
      expect(stats.hits, 1);
      expect(stats.misses, 1);
      expect(stats.probed, 2);
      expect(stats.hitRateLabel, '50%');

      // 再读一次：命中走缓存、未命中走负缓存，计数都不该再涨。
      expect(await service.readThumbnail(a, withThumb), isNotNull);
      expect(await service.readThumbnail(a, withoutThumb), isNull);
      stats = service.exifThumbnailStats();
      expect(stats.hits, 1);
      expect(stats.misses, 1);
    });

    test('没有探测过时统计为空', () {
      expect(service.exifThumbnailStats().isEmpty, isTrue);
    });
  });

  group('播放倍速偏好转发（284 P4）', () {
    test('默认 1×；保存后读回一致（走服务门面）', () async {
      expect(await service.loadPlaybackSpeed(), 1);
      await service.savePlaybackSpeed(1.5);
      expect(await service.loadPlaybackSpeed(), 1.5);
    });

    test('非法档位不落盘（服务层也拦住）', () async {
      await service.savePlaybackSpeed(1.25);
      await service.savePlaybackSpeed(0);
      expect(await service.loadPlaybackSpeed(), 1.25);
    });
  });

  group('递归收集文件夹（284 D6）', () {
    /// 按目录名分支应答的假服务器。
    ///
    /// 用 `uri.pathSegments`（**已解码**）而不是 `uri.path`：中文目录名在 URL 里是
    /// 百分号编码的，拿原始 path 去比对永远匹配不上（这个坑先在测试里踩了一次）。
    void serve(Map<String, List<DavItem>> tree) {
      transport.handler = (request) async {
        final segments = request.uri.pathSegments;
        if (segments.isNotEmpty) {
          final last = segments.last;
          final items = tree[last];
          if (items != null) return xmlResponse(propfindXml(items));
        }
        return xmlResponse(propfindXml(const <DavItem>[]));
      };
    }

    test('多层目录：收齐文件，跳过系统目录', () async {
      serve(<String, List<DavItem>>{
        '相册': const [
          DavItem('/dav/相册/', isCollection: true),
          DavItem('/dav/相册/a.jpg', displayName: 'a.jpg', size: 10),
          DavItem('/dav/相册/2021/', isCollection: true),
          DavItem('/dav/相册/@eaDir/', isCollection: true),
        ],
        '2021': const [
          DavItem('/dav/相册/2021/', isCollection: true),
          DavItem('/dav/相册/2021/b.jpg', displayName: 'b.jpg', size: 20),
          DavItem('/dav/相册/2021/01/', isCollection: true),
        ],
        '01': const [
          DavItem('/dav/相册/2021/01/', isCollection: true),
          DavItem('/dav/相册/2021/01/c.jpg', displayName: 'c.jpg', size: 30),
        ],
      });

      final listing = await service.listRecursive(testAccount(), '相册');

      expect(listing.files.map((e) => e.name).toList()..sort(),
          <String>['a.jpg', 'b.jpg', 'c.jpg']);
      expect(listing.dirsScanned, 3);
      expect(listing.truncated, isFalse);
      expect(listing.unreadableDirs, 0);
    });

    test('某个子目录读不出来（403）：跳过并计数，不整体失败', () async {
      transport.handler = (request) async {
        if (request.uri.pathSegments.last == '拒绝') {
          return const WebdavResponse(statusCode: 403, headers: <String, String>{});
        }
        return xmlResponse(propfindXml(const [
          DavItem('/dav/相册/', isCollection: true),
          DavItem('/dav/相册/ok.jpg', displayName: 'ok.jpg', size: 5),
          DavItem('/dav/相册/拒绝/', isCollection: true),
        ]));
      };

      final listing = await service.listRecursive(testAccount(), '相册');

      expect(listing.files.map((e) => e.name).toList(), <String>['ok.jpg']);
      expect(
        listing.unreadableDirs,
        1,
        reason: '选了 20 个相册，不该因为其中一个共享目录没权限就全下不了',
      );
    });

    test('文件数命中上限：停在上限并置 truncated（界面要告知）', () async {
      final many = <DavItem>[
        const DavItem('/dav/大批/', isCollection: true),
        for (var i = 0; i < kRecursiveDownloadMaxFiles + 5; i++)
          DavItem('/dav/大批/f$i.jpg', displayName: 'f$i.jpg', size: 1),
      ];
      serve(<String, List<DavItem>>{'大批': many});

      final listing = await service.listRecursive(testAccount(), '大批');

      expect(listing.files.length, kRecursiveDownloadMaxFiles);
      expect(listing.truncated, isTrue);
    });

    test('自引用列表不会让递归绕圈（同一目录只走一次）', () async {
      transport.handler = (request) async =>
          xmlResponse(propfindXml(const [
            DavItem('/dav/环/', isCollection: true),
            DavItem('/dav/环/a.jpg', displayName: 'a.jpg', size: 1),
            DavItem('/dav/环/子/', isCollection: true),
          ]));

      final listing = await service.listRecursive(testAccount(), '环');

      expect(listing.files.length, 1, reason: '同一个路径只下一次');
      expect(listing.dirsScanned, 2, reason: '环 + 环/子 各走一次就停');
      expect(listing.truncated, isFalse);
    });

    test('取消后立即停下', () async {
      serve(<String, List<DavItem>>{
        '相册': const [
          DavItem('/dav/相册/', isCollection: true),
          DavItem('/dav/相册/a.jpg', displayName: 'a.jpg', size: 10),
          DavItem('/dav/相册/2021/', isCollection: true),
        ],
      });
      final cancel = TransferCancelToken()..cancel();

      final listing = await service.listRecursive(
        testAccount(),
        '相册',
        cancel: cancel,
      );

      expect(listing.files, isEmpty);
      expect(listing.dirsScanned, 0);
    });

    test('download(subDir:) 落到子目录，保留结构', () async {
      transport.handler = (request) async {
        if (request.method == 'GET') {
          return streamResponse(const <int>[1, 2, 3, 4]);
        }
        return const WebdavResponse(statusCode: 404, headers: <String, String>{});
      };

      final path = await service.download(
        testAccount(),
        remotePath: '相册/2021/b.jpg',
        fileName: 'b.jpg',
        subDir: '相册/2021',
      );

      final expected = '${docsDir.path}/remote_storage/${testAccount().id}/相册/2021/b.jpg';
      expect(path, expected);
      expect(await File(expected).readAsBytes(), <int>[1, 2, 3, 4]);
    });

    test('isAlreadyDownloaded：同名同大小算已下载；大小不同/不存在算没下过', () async {
      transport.handler = (request) async =>
          streamResponse(const <int>[1, 2, 3]);
      const target = RecursiveDownloadTarget(subDir: '相册', fileName: 'a.jpg');
      final account = testAccount();

      expect(
        await service.isAlreadyDownloaded(account, target, size: 3),
        isFalse,
        reason: '还没下过',
      );

      await service.download(
        account,
        remotePath: '相册/a.jpg',
        fileName: 'a.jpg',
        subDir: '相册',
      );

      expect(await service.isAlreadyDownloaded(account, target, size: 3), isTrue);
      expect(
        await service.isAlreadyDownloaded(account, target, size: 999),
        isFalse,
        reason: '远端换过文件（大小不同）→ 不能当已下载，否则会跳过真该重下的',
      );
      expect(
        await service.isAlreadyDownloaded(account, target, size: null),
        isFalse,
        reason: '大小未知时不敢跳过',
      );
    });
  });

  group('目录快照接线（284 D7）', () {
    test('列出成功后能取到快照；强制刷新也写快照', () async {
      transport.handler = (request) async => xmlResponse(propfindXml(const [
            DavItem('/dav/a.txt', displayName: 'a.txt', size: 5),
          ]));

      expect(await service.cachedListing(testAccount(), '相册'), isNull);

      await service.list(testAccount(), '相册');

      final snapshot = await service.cachedListing(testAccount(), '相册');
      expect(snapshot, isNotNull);
      expect(snapshot!.entries.single.name, 'a.txt');
      expect(
        DateTime.now().difference(snapshot.at).inSeconds,
        lessThan(10),
        reason: '快照时间是写入时刻，不是啥远古时间',
      );
    });

    test('列出失败：不会留下半截快照', () async {
      transport.handler = (request) async =>
          const WebdavResponse(statusCode: 500, headers: <String, String>{});

      await expectLater(
        service.list(testAccount(), '相册'),
        throwsA(isA<RemoteStorageException>()),
      );

      expect(await service.cachedListing(testAccount(), '相册'), isNull);
    });

    test('删账户一并清掉该账户的目录快照', () async {
      transport.handler = (request) async => xmlResponse(propfindXml(const [
            DavItem('/dav/a.txt', displayName: 'a.txt', size: 5),
          ]));
      final account = testAccount();
      await service.saveAccount(account);
      await service.list(account, '相册');
      expect(await service.cachedListing(account, '相册'), isNotNull);

      await service.deleteAccount(account.id);

      expect(await service.cachedListing(account, '相册'), isNull);
    });
  });

  group('上传文件夹：本地扫描与建目录（284 D9）', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('d9_scan_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<File> write(String relative, [String content = 'x']) async {
      final file = File('${tmp.path}/$relative');
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      return file;
    }

    test('递归扫描：嵌套结构、相对路径含选中文件夹名、跳过隐藏条目', () async {
      await write('相册/a.jpg', '12345');
      await write('相册/2021/b.jpg', '1234567');
      await write('相册/2021/01/c.jpg', '1');
      await write('相册/.nomedia');
      await write('相册/.trashed-123.jpg');
      await Directory('${tmp.path}/相册/.thumbnails').create(recursive: true);

      final scan = await service.scanLocalDirectory('${tmp.path}/相册');

      final byName = {for (final f in scan.files) f.name: f};
      expect(byName.keys.toSet(), <String>{'a.jpg', 'b.jpg', 'c.jpg'});
      expect(byName['b.jpg']!.relativePath, '相册/2021/b.jpg');
      expect(byName['c.jpg']!.relativePath, '相册/2021/01/c.jpg');
      expect(byName['a.jpg']!.relativePath, '相册/a.jpg');
      expect(byName['a.jpg']!.size, 5);
      expect(
        scan.skippedHidden,
        3,
        reason: '.nomedia/.trashed-*/.thumbnails（隐藏目录）都不是用户内容',
      );
      expect(scan.dirs, 3);
      expect(scan.truncated, isFalse);
      expect(scan.unreadableDirs, 0);
      expect(scan.totalBytes, 5 + 7 + 1);
    });

    test('目录不存在/读不出来：不抛异常，返回空清单 + 计数', () async {
      final scan = await service.scanLocalDirectory('${tmp.path}/没有这个目录');

      expect(scan.files, isEmpty);
      expect(scan.unreadableDirs, 1);
      expect(scan.isEmpty, isTrue);
    });

    test('文件数命中上限：截断并置 truncated', () async {
      final dir = Directory('${tmp.path}/大批');
      await dir.create(recursive: true);
      for (var i = 0; i < kFolderUploadMaxFiles + 3; i++) {
        await File('${dir.path}/f$i.bin').writeAsString('x');
      }

      final scan = await service.scanLocalDirectory(dir.path);

      expect(scan.files.length, kFolderUploadMaxFiles);
      expect(scan.truncated, isTrue);
    });

    test('ensureRemoteDirs：父目录在前、已存在就跳过，返回新建数', () async {
      final created = <String>[];
      transport.handler = (request) async {
        // 注意 exists() 走的是 HEAD（405/501 才退回 PROPFIND）；
        // 中文名一律用已解码的 pathSegments 比对（uri.path 是百分号编码的）。
        if (request.method == 'HEAD') {
          return request.uri.pathSegments.last == '相册'
              ? const WebdavResponse(statusCode: 200, headers: <String, String>{})
              : const WebdavResponse(statusCode: 404, headers: <String, String>{});
        }
        if (request.method == 'MKCOL') {
          created.add(request.uri.path);
          return const WebdavResponse(statusCode: 201, headers: <String, String>{});
        }
        return const WebdavResponse(statusCode: 404, headers: <String, String>{});
      };

      final n = await service.ensureRemoteDirs(
        testAccount(),
        const ['相册/2021/01', '相册', '相册/2021'],
      );

      expect(created.map((p) => Uri.decodeComponent(p)).toList(), <String>[
        '/dav/相册/2021',
        '/dav/相册/2021/01',
      ]);
      expect(n, 2, reason: '已存在的 相册 不算新建');
    });

    test('ensureRemoteDirs：405（已存在）当成功，别的错误往上抛', () async {
      transport.handler = (request) async => request.method == 'MKCOL'
          ? const WebdavResponse(statusCode: 405, headers: <String, String>{})
          : const WebdavResponse(statusCode: 404, headers: <String, String>{});
      expect(await service.ensureRemoteDirs(testAccount(), const ['a/b']), 0);

      transport.handler = (request) async => request.method == 'MKCOL'
          ? const WebdavResponse(statusCode: 403, headers: <String, String>{})
          : const WebdavResponse(statusCode: 404, headers: <String, String>{});
      // exists 走 PROPFIND（404=不存在）→ 再 MKCOL 得 403 → 必须往上抛
      await expectLater(
        service.ensureRemoteDirs(testAccount(), const ['a']),
        throwsA(isA<RemoteStorageException>()),
        reason: '目录建不出来时继续传只会让每个文件都失败，该早点报错',
      );
    });
  });

  group('跨目录搜索（284 D10）', () {
    void serve(Map<String, List<DavItem>> tree) {
      transport.handler = (request) async {
        final segments = request.uri.pathSegments;
        if (segments.isNotEmpty) {
          final items = tree[segments.last];
          if (items != null) return xmlResponse(propfindXml(items));
        }
        return xmlResponse(propfindXml(const <DavItem>[]));
      };
    }

    test('跨目录命中：文件与目录都能搜到，系统目录不下探', () async {
      serve(<String, List<DavItem>>{
        '相册': const [
          DavItem('/dav/相册/', isCollection: true),
          DavItem('/dav/相册/2021-08-07.jpg', displayName: '2021-08-07.jpg', size: 5),
          DavItem('/dav/相册/2021/', isCollection: true),
          DavItem('/dav/相册/@eaDir/', isCollection: true),
        ],
        '2021': const [
          DavItem('/dav/相册/2021/', isCollection: true),
          DavItem('/dav/相册/2021/2021-09-01.jpg', displayName: '2021-09-01.jpg', size: 6),
          DavItem('/dav/相册/2021/别的.jpg', displayName: '别的.jpg', size: 7),
        ],
      });

      final result = await service.searchSubtree(
        testAccount(),
        rootPath: '相册',
        query: '2021',
      );

      expect(
        result.entries.map((e) => e.name).toList()..sort(),
        <String>['2021', '2021-08-07.jpg', '2021-09-01.jpg'],
        reason: '"2021" 目录本身也算命中，但 @eaDir 这类系统目录不下探',
      );
      expect(result.dirsScanned, 2);
      expect(result.truncated, isFalse);
      expect(result.canceled, isFalse);
    });

    test('某个子目录读不出来：跳过它继续搜，不整体失败', () async {
      transport.handler = (request) async {
        final last = request.uri.pathSegments.isEmpty
            ? ''
            : request.uri.pathSegments.last;
        if (last == '拒绝') {
          return const WebdavResponse(statusCode: 403, headers: <String, String>{});
        }
        return xmlResponse(propfindXml(const [
          DavItem('/dav/相册/', isCollection: true),
          DavItem('/dav/相册/命中1.jpg', displayName: '命中1.jpg', size: 1),
          DavItem('/dav/相册/拒绝/', isCollection: true),
        ]));
      };

      final result = await service.searchSubtree(
        testAccount(),
        rootPath: '相册',
        query: '命中',
      );

      expect(result.entries.map((e) => e.name).toList(), <String>['命中1.jpg']);
      expect(result.dirsScanned, 2);
    });

    test('自引用/环状列表：同一目录只走一次，结果不重复（防绕圈）', () async {
      // 服务端把集合自身也列出来（PROPFIND 的常见形态），且子目录指向回父目录：
      // 不去重就会反复列同一个目录——现象是"扫了 100 多个目录、结果里全是重复项"。
      transport.handler = (request) async =>
          xmlResponse(propfindXml(const [
            DavItem('/dav/环/', isCollection: true),
            DavItem('/dav/环/命中.jpg', displayName: '命中.jpg', size: 1),
            DavItem('/dav/环/子/', isCollection: true),
          ]));

      final result = await service.searchSubtree(
        testAccount(),
        rootPath: '环',
        query: '命中',
      );

      expect(result.entries.length, 1, reason: '重复命中只算一次（按路径去重）');
      expect(
        result.dirsScanned,
        2,
        reason: '环 + 环/子 各走一次就停：没有目录去重的话这里会是 100 多次',
      );
      expect(
        result.truncated,
        isFalse,
        reason: '不该因为绕圈把自己逼到上限',
      );
    });

    test('结果数命中上限：截断并置 truncated', () async {
      final many = <DavItem>[
        const DavItem('/dav/大批/', isCollection: true),
        for (var i = 0; i < kSubtreeSearchMaxResults + 5; i++)
          DavItem('/dav/大批/命中$i.jpg', displayName: '命中$i.jpg', size: 1),
      ];
      serve(<String, List<DavItem>>{'大批': many});

      final result = await service.searchSubtree(
        testAccount(),
        rootPath: '大批',
        query: '命中',
      );

      expect(result.entries.length, kSubtreeSearchMaxResults);
      expect(result.truncated, isTrue);
    });

    test('取消：返回取消前的部分结果，算 canceled 不算错误', () async {
      serve(<String, List<DavItem>>{
        '相册': const [
          DavItem('/dav/相册/', isCollection: true),
          DavItem('/dav/相册/命中1.jpg', displayName: '命中1.jpg', size: 1),
          DavItem('/dav/相册/子/', isCollection: true),
        ],
      });
      final cancel = TransferCancelToken();
      var calls = 0;

      final result = await service.searchSubtree(
        testAccount(),
        rootPath: '相册',
        query: '命中',
        cancel: cancel,
        onProgress: (dirs, hits) {
          calls += 1;
          if (calls == 1) cancel.cancel();
        },
      );

      expect(result.canceled, isTrue);
      expect(result.entries.map((e) => e.name).toList(), <String>['命中1.jpg']);
      expect(result.dirsScanned, 1, reason: '取消后不再往下走');
    });
  });

  group('视频首帧（284 D8）', () {
    const channel = MethodChannel(VideoFrameChannel.channelName);
    final calls = <MethodCall>[];

    void mockChannel(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    RemoteStorageService withVideoChannel() => RemoteStorageService(
          transportFactory: (_) => transport,
          docsDirProvider: () async => docsDir,
          // 同 setUp：缩略图缓存要注入临时目录，否则删账户清缓存会走平台通道。
          thumbnailCache: RemoteThumbnailCache(root: thumbRoot),
          videoFrames: VideoFrameChannel(channel: channel),
        );

    RemoteStorageEntry video(String path) => RemoteStorageEntry(
          name: path.split('/').last,
          path: path,
          isDirectory: false,
          size: 1024 * 1024,
        );

    setUp(() => calls.clear());
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('https + Basic：带上认证头走原生，拿到字节', () async {
      final bytes = Uint8List.fromList(<int>[9, 9, 9]);
      mockChannel((call) async {
        calls.add(call);
        return bytes;
      });
      final service = withVideoChannel();

      final got = await service.videoThumbnailBytes(
        testAccount(),
        video('视频/a.mp4'),
      );

      expect(got, bytes);
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['url'], contains('/%E8%A7%86%E9%A2%91/a.mp4'), reason: '远端路径要编码');
      expect(
        (args['headers'] as Map)['authorization'],
        startsWith('Basic '),
        reason: '直连必须带认证，否则原生那边只会拿到 401',
      );
    });

    test('需要中继的账户（http 明文）：直接跳过，不打原生', () async {
      mockChannel((call) async {
        calls.add(call);
        return null;
      });
      final service = withVideoChannel();
      // 需要中继的第二种情形：账户开了「允许不安全证书」（拍板7 里和 http 明文同路）。
      final insecure = testAccount(allowBadCert: true);

      expect(
        await service.videoThumbnailBytes(insecure, video('a.mp4')),
        isNull,
      );
      expect(calls, isEmpty, reason: '为一张缩略图开中继会话不划算');
    });

    test('成功会落缓存：第二次不再走原生/网络（滚回去不该再抽一次）', () async {
      mockChannel((call) async {
        calls.add(call);
        return Uint8List.fromList(<int>[7, 7]);
      });
      final service = withVideoChannel();
      final entry = video('a.mp4');

      expect(await service.videoThumbnailBytes(testAccount(), entry), isNotNull);
      expect(await service.videoThumbnailBytes(testAccount(), entry), isNotNull);

      expect(calls.length, 1, reason: '缩略图缓存命中：同键只抽一次');
    });

    test('失败记一次：负缓存生效后不再重复走网络', () async {
      mockChannel((call) async {
        calls.add(call);
        return null;
      });
      final service = withVideoChannel();
      final entry = video('a.mp4');

      expect(await service.videoThumbnailBytes(testAccount(), entry), isNull);
      expect(await service.videoThumbnailBytes(testAccount(), entry), isNull);
      expect(await service.videoThumbnailBytes(testAccount(), entry), isNull);

      expect(calls.length, 1, reason: '抽帧失败往往已经花掉一次往返，不能每次重建都再试');
    });

    test('删账户清掉负缓存：重新添加账户后会再试一次', () async {
      mockChannel((call) async {
        calls.add(call);
        return null;
      });
      final account = testAccount();
      final service = withVideoChannel();
      await service.saveAccount(account);
      await service.videoThumbnailBytes(account, video('a.mp4'));
      expect(calls.length, 1);

      await service.deleteAccount(account.id);
      await service.videoThumbnailBytes(account, video('a.mp4'));

      expect(calls.length, 2);
    });
  });

  group('传输恢复（284 P1）', () {
    late _MemQueueStore store;

    TransferQueue queueWith(TransferQueueStore s) => TransferQueue(
          retryDelay: Duration.zero,
          store: s,
          keepAlive: TransferKeepAlive(),
        );

    TransferRestoreSpec downloadSpec({String accountId = 'rs_test'}) =>
        TransferRestoreSpec(
          kind: TransferKind.download,
          accountId: accountId,
          remotePath: '/相册/a.jpg',
          fileName: 'a.jpg',
          title: 'a.jpg',
          subtitle: '测试账户',
          totalBytes: 4,
        );

    setUp(() => store = _MemQueueStore());

    /// 等任务跑完（传输里有真实 IO 的 await，靠固定次数 yield 不稳）。
    Future<void> waitDone(TransferTask task) async {
      for (var i = 0; i < 100 && task.isActive; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('恢复下载：factory 重建 runner 后真的能下下来', () async {
      final account = testAccount();
      await service.saveAccount(account);
      final queue = queueWith(store);
      final runner =
          service.runnerForRestore(account, downloadSpec());

      final task = queue.enqueue(
        kind: TransferKind.download,
        title: 'a.jpg',
        subtitle: '测试账户',
        spec: downloadSpec(),
        runner: runner,
      );
      await waitDone(task);

      expect(task.status, TransferStatus.done, reason: task.errorMessage);
      expect(task.result, isA<String>());
      expect(File(task.result! as String).existsSync(), isTrue);
    });

    test('恢复上传：沿用当时的覆盖选择与目标目录（不替用户改主意）', () async {
      final account = testAccount();
      final src = File('${docsDir.path}/src.bin');
      await src.writeAsString('hello');
      final spec = TransferRestoreSpec(
        kind: TransferKind.upload,
        accountId: account.id,
        remotePath: '/目标目录',
        localPath: src.path,
        fileName: 'src.bin',
        overwrite: true,
        title: 'src.bin',
        totalBytes: 5,
      );

      final task = TransferQueue(retryDelay: Duration.zero, store: store).enqueue(
        kind: TransferKind.upload,
        title: 'src.bin',
        subtitle: '测试账户',
        spec: spec,
        runner: service.runnerForRestore(account, spec),
      );
      await waitDone(task);

      expect(task.status, TransferStatus.done, reason: task.errorMessage);
      final puts = transport.requests
          .where((r) => r.method == 'PUT')
          .map((r) => Uri.decodeComponent(r.uri.path))
          .toList(growable: false);
      expect(puts.any((p) => p.endsWith('/目标目录/src.bin')), isTrue,
          reason: '目标目录要按恢复描述走，不能落到别处（实际: $puts）');
    });

    test('restoreTransfers：账户还在、源文件还在 → 恢复出来', () async {
      final account = testAccount();
      await service.saveAccount(account);
      final src = File('${docsDir.path}/keep.bin');
      await src.writeAsString('x');
      await store.save([
        downloadSpec().toJson(),
        TransferRestoreSpec(
          kind: TransferKind.upload,
          accountId: account.id,
          remotePath: '/d',
          localPath: src.path,
          fileName: 'keep.bin',
          title: 'keep.bin',
          totalBytes: 1,
        ).toJson(),
      ]);
      final queue = queueWith(store);

      final restored = await service.restoreTransfers(queue: queue);

      expect(restored, 2);
      expect(queue.tasks, hasLength(2));
      expect(queue.tasks.every((t) => t.restored), isTrue);
    });

    test('restoreTransfers：账户已删 / 上传源文件不在了 → 丢弃且不留在盘里', () async {
      final account = testAccount();
      await service.saveAccount(account);
      await store.save([
        downloadSpec(accountId: '已删除的账户').toJson(),
        TransferRestoreSpec(
          kind: TransferKind.upload,
          accountId: account.id,
          remotePath: '/d',
          localPath: '${docsDir.path}/不存在.bin',
          fileName: '不存在.bin',
          title: '不存在.bin',
          totalBytes: 1,
        ).toJson(),
      ]);
      final queue = queueWith(store);

      final restored = await service.restoreTransfers(queue: queue);

      expect(restored, 0);
      expect(queue.tasks, isEmpty);
      expect(await store.load(), isEmpty, reason: '丢掉的记录要一起从盘里清掉');
    });
  });
}

/// 内存里的落盘替身（service 测试不碰真实文件系统）。
class _MemQueueStore extends TransferQueueStore {
  _MemQueueStore() : super(dirProvider: () async => Directory.systemTemp);

  List<Map<String, Object?>> _records = const [];

  @override
  Future<List<Map<String, Object?>>> load() async => List.of(_records);

  @override
  Future<void> save(List<Map<String, Object?>> records) async {
    _records = List.of(records);
  }

  @override
  Future<void> clear() async => _records = const [];
}
