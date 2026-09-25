// 服务器运维插件：文件页服务层的用例（假传输，不碰网络）。
import 'dart:convert';
import 'dart:io';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../remote_storage/fakes.dart';

const _base = 'https://box.hpa888.top/dav';

ServerOpsFilesService serviceWith(FakeTransport transport) {
  return ServerOpsFilesService(
    settings: const ServerOpsSettings(
      baseUrl: _base,
      user: 'boxops',
      password: 'pw',
    ),
    client: WebdavClient(
      baseUrl: _base,
      username: 'boxops',
      password: 'pw',
      transport: transport,
    ),
  );
}

void main() {
  group('路径工具', () {
    test('joinPath 拼相对路径并归一斜杠', () {
      expect(ServerOpsFilesService.joinPath('', 'a.txt'), 'a.txt');
      expect(ServerOpsFilesService.joinPath('etc', 'hosts'), 'etc/hosts');
      expect(ServerOpsFilesService.joinPath('/etc/', '/hosts'), 'etc/hosts');
      expect(ServerOpsFilesService.joinPath('etc', ''), 'etc');
    });

    test('parentOf 到根为止', () {
      expect(ServerOpsFilesService.parentOf('a/b/c'), 'a/b');
      expect(ServerOpsFilesService.parentOf('a'), '');
      expect(ServerOpsFilesService.parentOf(''), '');
      expect(ServerOpsFilesService.parentOf('/a/b/'), 'a');
      expect(ServerOpsFilesService.parentOf('a/b'), 'a');
    });

    test('breadcrumbs 含根，且逐级累积', () {
      expect(ServerOpsFilesService.breadcrumbs(''), [('', '根目录')]);
      expect(ServerOpsFilesService.breadcrumbs('etc/nginx'), [
        ('', '根目录'),
        ('etc', 'etc'),
        ('etc/nginx', 'nginx'),
      ]);
    });

    test('basename 取最后一段', () {
      expect(ServerOpsFilesService.basename('/tmp/box-ops-verify'), 'box-ops-verify');
      expect(ServerOpsFilesService.basename('a.txt'), 'a.txt');
      expect(ServerOpsFilesService.basename(''), '');
    });
  });

  group('连接参数', () {
    test('按设置建 client，Basic 头用的是设置里的用户名/口令', () async {
      final transport = FakeTransport(
        (request) async => xmlResponse(
          propfindXml(const [DavItem('/dav/', isCollection: true)]),
        ),
      );
      final service = ServerOpsFilesService(
        settings: const ServerOpsSettings(
          baseUrl: _base,
          user: 'someone',
          password: 'secret',
        ),
        transportFactory: () => transport,
      );
      await service.list('');
      final auth = transport.lastRequest.headers['authorization'];
      expect(auth, 'Basic ${base64.encode(utf8.encode('someone:secret'))}');
    });

    test('没喊口令时仍然按设置建 client（由页面负责给引导）', () {
      final service = ServerOpsFilesService(
        settings: const ServerOpsSettings(baseUrl: _base, user: 'boxops'),
        transportFactory: () => FakeTransport(),
      );
      expect(service.client.baseUrl, _base);
      expect(service.client.username, 'boxops');
    });
  });

  group('目录与传输', () {
    test('list 透传目录条目', () async {
      final transport = FakeTransport(
        (request) async => xmlResponse(
          propfindXml(const [
            DavItem('/dav/', isCollection: true),
            DavItem('/dav/etc', isCollection: true),
            DavItem('/dav/a.txt', size: 12),
          ]),
        ),
      );
      final entries = await serviceWith(transport).list('');
      expect(entries.map((e) => e.name), ['etc', 'a.txt']);
      expect(entries.first.isDirectory, isTrue);
      expect(entries.last.size, 12);
    });

    test('createDirectory 发的是 MKCOL', () async {
      final transport = FakeTransport(
        (request) async => const WebdavResponse(statusCode: 201, headers: {}),
      );
      await serviceWith(transport).createDirectory('tmp/new');
      expect(transport.lastRequest.method, 'MKCOL');
      expect(transport.lastRequest.uri.path, '/dav/tmp/new');
    });

    test('upload 发 PUT，请求体就是本地文件字节', () async {
      final dir = await Directory.systemTemp.createTemp('server-ops-up-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final payload = List<int>.generate(16, (i) => i);
      final file = File('${dir.path}/payload.bin')
        ..writeAsBytesSync(payload);

      final transport = FakeTransport(
        (request) async => const WebdavResponse(statusCode: 201, headers: {}),
      );
      await serviceWith(transport).upload(file, 'dir/payload.bin');

      final put = transport.lastRequest;
      expect(put.method, 'PUT');
      expect(put.uri.path, '/dav/dir/payload.bin');
      expect(await bodyBytesOf(put), payload);
    });

    test('download 把响应字节写进本地文件', () async {
      final dir = await Directory.systemTemp.createTemp('server-ops-dl-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dest = File('${dir.path}/out.txt');

      final transport = FakeTransport(
        (request) async => streamResponse(utf8.encode('hello')),
      );
      await serviceWith(transport).download('a.txt', dest);

      expect(transport.lastRequest.method, 'GET');
      expect(dest.readAsStringSync(), 'hello');
    });

    test('错误按远端存储的口径翻译成中文', () async {
      final transport = FakeTransport(
        (request) async => const WebdavResponse(statusCode: 403, headers: {}),
      );
      final service = serviceWith(transport);
      await expectLater(
        service.createDirectory('locked'),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.message,
            'message',
            contains('权限'),
          ),
        ),
      );
    });
  });

  group('重命名：覆盖保护靠 exists() 预检', () {
    test('目标已存在 → 抛 conflict，且**不发 MOVE**', () async {
      final transport = FakeTransport(
        // HEAD 目标存在（200）；本用例不该出现 MOVE。
        (request) async => const WebdavResponse(statusCode: 200, headers: {}),
      );
      final service = serviceWith(transport);
      await expectLater(
        service.rename('a.txt', 'b.txt'),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.kind,
            'kind',
            RemoteStorageError.conflict,
          ),
        ),
      );
      expect(
        transport.requests.any((r) => r.method == 'MOVE'),
        isFalse,
        reason: '预检发现冲突后不该再发 MOVE（服务端 Overwrite:F 不一定生效）',
      );
    });

    test('目标不存在 → 发 MOVE，Destination 是绝对 URL', () async {
      final transport = FakeTransport((request) async {
        if (request.method == 'HEAD') {
          return const WebdavResponse(statusCode: 404, headers: {});
        }
        return const WebdavResponse(statusCode: 201, headers: {});
      });
      await serviceWith(transport).rename('a.txt', 'dir/b.txt');

      final move = transport.requests.firstWhere((r) => r.method == 'MOVE');
      expect(move.uri.path, '/dav/a.txt');
      expect(
        move.headers['destination'],
        Uri.parse('$_base/dir/b.txt').toString(),
      );
      expect(move.headers['overwrite'], 'F');
    });
  });

  group('文本预览', () {
    test('readUpTo 把开头字节读回来（截断标记透传）', () async {
      final transport = FakeTransport(
        (request) async => streamResponse(utf8.encode('line1\nline2')),
      );
      final result = await serviceWith(transport).readUpTo('notes.txt', 1024);
      expect(utf8.decode(result.bytes), 'line1\nline2');
      expect(result.truncated, isFalse);
    });
  });

  group('错误文案', () {
    test('远端存储异常直接用它的中文 message', () {
      expect(
        serverOpsErrorMessage(
          const RemoteStorageException(RemoteStorageError.notFound, '路径不存在'),
        ),
        '路径不存在',
      );
    });

    test('其它异常兜底成一句中文', () {
      expect(serverOpsErrorMessage(StateError('boom')), contains('操作失败'));
    });
  });
}
