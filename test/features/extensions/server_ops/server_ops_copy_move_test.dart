// 服务器运维插件：复制 / 移动到的用例（A4，假传输 + 内存假文件系统，不联网）。
//
// 关键断言：**目录复制必须客户端递归逐文件 COPY** —— 实测对目录直接发 COPY
// 只会得到一个空副本目录（子文件不在里面）。所以这里用一个内存文件系统承接
// 请求序列，复制完再列一次目录，断言子文件**真的存在**。
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:box/features/extensions/plugins/server_ops/files_tab.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../remote_storage/fakes.dart';

const _base = 'https://box.hpa888.top/dav';
const _basePath = '/dav/';

const _settings = ServerOpsSettings(
  baseUrl: _base,
  user: 'boxops',
  password: 'pw',
);

/// 内存假 WebDAV 文件系统：MKCOL / PROPFIND / COPY / MOVE / HEAD / DELETE 都能跑。
/// 用它才能断言"复制后子文件真的存在"，而不是只看发过什么请求。
class _FakeDavFs implements WebdavTransport {
  _FakeDavFs({
    Iterable<String> dirs = const [],
    Iterable<String> files = const [],
  }) {
    for (final dir in dirs) {
      if (dir.isNotEmpty) this.dirs.add(dir);
    }
    for (final file in files) {
      this.files.add(file);
    }
  }

  final Set<String> dirs = {''};
  final Set<String> files = {};
  final List<WebdavRequest> requests = [];

  String _rel(Uri uri) {
    final path = uri.path;
    if (!path.startsWith(_basePath)) return path;
    return path.substring(_basePath.length).replaceAll(RegExp(r'/+$'), '');
  }

  String _parent(String path) {
    final idx = path.lastIndexOf('/');
    return idx < 0 ? '' : path.substring(0, idx);
  }

  /// 把 src 子树搬到/复制到 dst（MOVE 时 [remove] 为 true）。
  void _transfer(String src, String dst, {required bool remove}) {
    for (final dir
        in dirs.where((d) => d == src || d.startsWith('$src/')).toList()) {
      dirs.add('$dst${dir.substring(src.length)}');
    }
    for (final file
        in files.where((f) => f == src || f.startsWith('$src/')).toList()) {
      files.add('$dst${file.substring(src.length)}');
    }
    if (remove) {
      dirs.removeWhere((d) => d == src || d.startsWith('$src/'));
      files.removeWhere((f) => f == src || f.startsWith('$src/'));
    }
  }

  @override
  Future<WebdavResponse> send(WebdavRequest request) async {
    requests.add(request);
    final path = _rel(request.uri);
    switch (request.method) {
      case 'HEAD':
        return WebdavResponse(
          statusCode: dirs.contains(path) || files.contains(path) ? 200 : 404,
          headers: const {},
        );
      case 'PROPFIND':
        if (!dirs.contains(path)) {
          return const WebdavResponse(statusCode: 404, headers: {});
        }
        final items = <DavItem>[
          DavItem('$_basePath$path', isCollection: true),
        ];
        for (final dir in dirs) {
          if (dir != path && _parent(dir) == path) {
            items.add(DavItem('$_basePath$dir', isCollection: true));
          }
        }
        for (final file in files) {
          if (_parent(file) == path) {
            items.add(DavItem('$_basePath$file', size: 1));
          }
        }
        return xmlResponse(propfindXml(items));
      case 'MKCOL':
        if (dirs.contains(path)) {
          return const WebdavResponse(statusCode: 405, headers: {});
        }
        if (!dirs.contains(_parent(path))) {
          return const WebdavResponse(statusCode: 409, headers: {});
        }
        dirs.add(path);
        return const WebdavResponse(statusCode: 201, headers: {});
      case 'COPY':
      case 'MOVE':
        final destination =
            _rel(Uri.parse(request.headers['destination'] ?? ''));
        final exists =
            dirs.contains(destination) || files.contains(destination);
        if (exists && request.headers['overwrite'] == 'F') {
          return const WebdavResponse(statusCode: 412, headers: {});
        }
        _transfer(path, destination, remove: request.method == 'MOVE');
        return const WebdavResponse(statusCode: 201, headers: {});
      case 'DELETE':
        files.remove(path);
        dirs.removeWhere((d) => d == path || d.startsWith('$path/'));
        return const WebdavResponse(statusCode: 204, headers: {});
      case 'PUT':
        files.add(path);
        return const WebdavResponse(statusCode: 201, headers: {});
      default:
        return const WebdavResponse(statusCode: 200, headers: {});
    }
  }
}

ServerOpsFilesService _serviceWith(_FakeDavFs fs) => ServerOpsFilesService(
      settings: _settings,
      client: WebdavClient(
        baseUrl: _base,
        username: 'boxops',
        password: 'pw',
        transport: fs,
      ),
    );

List<String> _copySources(_FakeDavFs fs) => [
      for (final request in fs.requests)
        if (request.method == 'COPY')
          request.uri.path
              .substring(_basePath.length)
              .replaceAll(RegExp(r'/+$'), ''),
    ];

void main() {
  group('服务层：复制文件', () {
    test('文件复制走服务端 COPY 一次完成（不耗手机流量）', () async {
      final fs = _FakeDavFs(dirs: ['dest'], files: ['a.txt']);
      final service = _serviceWith(fs);

      await service.copyEntry('a.txt', 'dest/a.txt', isDirectory: false);

      expect(_copySources(fs), ['a.txt']);
      final dest = fs.requests.firstWhere((r) => r.method == 'COPY');
      expect(dest.uri.path, '/dav/a.txt');
      expect(
        dest.headers['destination'],
        Uri.parse('$_base/dest/a.txt').toString(),
      );
      expect(dest.headers['overwrite'], 'F');
      expect((await service.list('dest')).map((e) => e.name), ['a.txt']);
    });

    test('目标已存在 → 抛 conflict，且不发 COPY', () async {
      final fs = _FakeDavFs(dirs: ['dest'], files: ['a.txt', 'dest/a.txt']);
      final service = _serviceWith(fs);

      await expectLater(
        service.copyEntry('a.txt', 'dest/a.txt', isDirectory: false),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.kind,
            'kind',
            RemoteStorageError.conflict,
          ),
        ),
      );
      expect(_copySources(fs), isEmpty);
    });
  });

  group('服务层：复制目录（防"空目录陷阱"）', () {
    test('目录复制：递归逐文件 COPY，复制后子文件真的存在', () async {
      final fs = _FakeDavFs(
        dirs: ['backup', 'dir', 'dir/sub'],
        files: ['dir/a.txt', 'dir/sub/b.txt'],
      );
      final service = _serviceWith(fs);
      final progress = <String>[];

      await service.copyEntry(
        'dir',
        'backup/dir',
        isDirectory: true,
        onProgress: (done, total) => progress.add('$done/$total'),
      );

      // 强断言：副本目录里子目录与子文件都在（服务端整目录 COPY 会得到空目录）。
      expect(
        (await service.list('backup/dir')).map((e) => e.name),
        ['sub', 'a.txt'],
      );
      expect(
        (await service.list('backup/dir/sub')).map((e) => e.name),
        ['b.txt'],
      );

      // 请求序列：没有对目录本身的一次 COPY，只有逐文件 COPY。
      // 顺序按 list 的返回（目录恒在前，所以先钻 sub）。
      expect(_copySources(fs)..sort(), ['dir/a.txt', 'dir/sub/b.txt']);
      expect(
        _copySources(fs).contains('dir'),
        isFalse,
        reason: '对目录直接 COPY 只会得到空目录，必须逐文件',
      );
      expect(progress, ['1/2', '2/2']);
    });

    test('目录复制：源目录里的空子目录也会被建出来', () async {
      final fs = _FakeDavFs(
        dirs: ['target', 'dir', 'dir/empty'],
        files: ['dir/f.txt'],
      );
      final service = _serviceWith(fs);

      await service.copyEntry('dir', 'target/dir', isDirectory: true);

      expect(fs.dirs.contains('target/dir/empty'), isTrue);
      expect(
        (await service.list('target/dir')).map((e) => e.name),
        ['empty', 'f.txt'],
      );
    });

    test('取消后不再发起后续 COPY', () async {
      final fs = _FakeDavFs(
        dirs: ['target', 'dir'],
        files: ['dir/a.txt', 'dir/b.txt', 'dir/c.txt'],
      );
      final service = _serviceWith(fs);
      final cancel = TransferCancelToken();

      await expectLater(
        service.copyEntry(
          'dir',
          'target/dir',
          isDirectory: true,
          cancel: cancel,
          onProgress: (done, total) => cancel.cancel(),
        ),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.kind,
            'kind',
            RemoteStorageError.canceled,
          ),
        ),
      );
      expect(_copySources(fs), ['dir/a.txt'], reason: '取消后不能再发第 2、3 个 COPY');
    });
  });

  group('服务层：移动到…', () {
    test('移动：一次 MOVE，整树跟着走', () async {
      final fs = _FakeDavFs(
        dirs: ['dest', 'dir', 'dir/sub'],
        files: ['dir/a.txt', 'dir/sub/b.txt'],
      );
      final service = _serviceWith(fs);

      await service.moveEntry('dir', 'dest/dir');

      final moves = fs.requests.where((r) => r.method == 'MOVE').toList();
      expect(moves.length, 1, reason: '目录移动由服务端一次完成，不该逐文件');
      expect(moves.single.uri.path, '/dav/dir');
      expect(
        moves.single.headers['destination'],
        Uri.parse('$_base/dest/dir').toString(),
      );
      expect(fs.dirs.contains('dir'), isFalse, reason: '源目录应已不在');
      expect(
        (await service.list('dest/dir')).map((e) => e.name),
        ['sub', 'a.txt'],
      );
    });

    test('目标已存在 → conflict，且不发 MOVE', () async {
      final fs = _FakeDavFs(dirs: ['dest', 'dest/dir', 'dir']);
      final service = _serviceWith(fs);

      await expectLater(
        service.moveEntry('dir', 'dest/dir'),
        throwsA(isA<RemoteStorageException>()),
      );
      expect(fs.requests.any((r) => r.method == 'MOVE'), isFalse);
    });
  });

  group('页面：复制到…（目录选择器）', () {
    testWidgets('行菜单"复制到…"→ 进目标目录 → 确认 → 调 copyEntry', (tester) async {
      final service = _FakeCopyService(
        tree: const {
          '': [
            RemoteStorageEntry(name: 'dest', path: 'dest', isDirectory: true),
            RemoteStorageEntry(
              name: 'a.txt',
              path: 'a.txt',
              size: 1,
              isDirectory: false,
            ),
          ],
          'dest': [],
        },
      );
      await _pumpPage(tester, service);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'a.txt'),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('复制到…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 选择器列出 dest；进去后确认。
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ListTile, 'dest'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('选择此目录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.copied, ['a.txt->dest/a.txt']);
    });

    testWidgets('不能把目录复制进它自己的子目录里', (tester) async {
      final service = _FakeCopyService(
        tree: const {
          '': [RemoteStorageEntry(name: 'dir', path: 'dir', isDirectory: true)],
          'dir': [
            RemoteStorageEntry(
              name: 'inner',
              path: 'dir/inner',
              isDirectory: true,
            ),
          ],
          'dir/inner': [],
        },
      );
      await _pumpPage(tester, service);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'dir'),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('复制到…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 在 dir 里再进 inner，然后选它 → 目标 dir/inner/dir 落在源目录内部，必须拒绝。
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ListTile, 'dir'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ListTile, 'inner'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('选择此目录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.copied, isEmpty);
      expect(find.textContaining('不能把目录放进它自己的子目录里'), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(WidgetTester tester, _FakeCopyService service) async {
  debugSetServerOpsRuntime(filesService: service);
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: ServerOpsFilesTab(settings: _settings)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _FakeCopyService extends ServerOpsFilesService {
  _FakeCopyService({this.tree = const {}}) : super(settings: _settings);

  final Map<String, List<RemoteStorageEntry>> tree;
  final List<String> copied = [];
  final List<String> moved = [];

  @override
  Future<List<RemoteStorageEntry>> list(String path) async =>
      tree[path] ?? const [];

  @override
  Future<void> copyEntry(
    String from,
    String to, {
    required bool isDirectory,
    void Function(int done, int total)? onProgress,
    TransferCancelToken? cancel,
  }) async {
    copied.add('$from->$to');
    onProgress?.call(1, 1);
  }

  @override
  Future<void> moveEntry(String from, String to) async {
    moved.add('$from->$to');
  }
}
