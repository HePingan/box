// 服务器运维插件：下载残留清理的用例（A8）。
//
// 两部分：
//   1. ServerOpsDownloadCache 的纯单测（注入临时目录，不碰 path_provider）；
//   2. widget 用例：文件页有「清空下载缓存」入口，二次确认后才真清。
import 'dart:io';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/server_ops/files_tab.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_download_cache.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _settings = ServerOpsSettings(
  baseUrl: 'https://box.hpa888.top/dav',
  user: 'boxops',
  password: 'pw',
);

class _FakeListService extends ServerOpsFilesService {
  _FakeListService({this.entries = const []}) : super(settings: _settings);

  List<RemoteStorageEntry> entries;
  final List<String> downloaded = [];

  @override
  Future<List<RemoteStorageEntry>> list(String path) async => entries;

  @override
  Future<void> download(
    String remotePath,
    File dest, {
    void Function(int received, int total)? onProgress,
    TransferCancelToken? cancel,
  }) async {
    downloaded.add(remotePath);
    onProgress?.call(10, 10);
  }
}

class _FakeDownloadCache extends ServerOpsDownloadCache {
  _FakeDownloadCache() : super(tempDirProvider: () async => Directory.systemTemp);

  int cleared = 0;
  final List<String> prepared = [];

  @override
  Future<File> prepare(String name) async {
    prepared.add(name);
    return File('${Directory.systemTemp.path}/$name');
  }

  @override
  Future<int> clear() async {
    cleared += 1;
    return 2048;
  }
}

void main() {
  tearDown(() => debugSetServerOpsRuntime());

  group('ServerOpsDownloadCache（纯单测）', () {
    test('prepare 先删掉同名旧文件（这就是"下载残留清理"）', () async {
      final base = await Directory.systemTemp.createTemp('ops-dl-');
      addTearDown(() => base.deleteSync(recursive: true));
      final cache = ServerOpsDownloadCache(tempDirProvider: () async => base);

      final dir = await cache.directory();
      final old = File('${dir.path}/report.txt')..writeAsStringSync('上一次的半截内容');

      final dest = await cache.prepare('report.txt');

      expect(await old.exists(), isFalse, reason: '同名旧文件必须先删掉');
      expect(dest.path, '${dir.path}/report.txt');
      // 下载写进去的是全新内容，不再和旧内容混在一起。
      dest.writeAsStringSync('新内容');
      expect(dest.readAsStringSync(), '新内容');
    });

    test('目录落在临时目录的 server_ops_downloads 子目录里', () async {
      final base = await Directory.systemTemp.createTemp('ops-dl-');
      addTearDown(() => base.deleteSync(recursive: true));
      final cache = ServerOpsDownloadCache(tempDirProvider: () async => base);

      final dir = await cache.directory();

      expect(dir.path, '${base.path}/${ServerOpsDownloadCache.subdirName}');
      expect(await dir.exists(), isTrue);
    });

    test('clear 删掉整个下载子目录并返回释放字节数', () async {
      final base = await Directory.systemTemp.createTemp('ops-dl-');
      addTearDown(() => base.deleteSync(recursive: true));
      final cache = ServerOpsDownloadCache(tempDirProvider: () async => base);

      final dir = await cache.directory();
      File('${dir.path}/a.bin').writeAsBytesSync(List<int>.filled(3, 0));
      File('${dir.path}/b.bin').writeAsBytesSync(List<int>.filled(4, 0));

      final bytes = await cache.clear();

      expect(bytes, 7);
      expect(await dir.exists(), isTrue, reason: '清完要重建，下次下载还能用');
      expect(dir.listSync(), isEmpty);
    });

    test('clear 对空缓存是安全的', () async {
      final base = await Directory.systemTemp.createTemp('ops-dl-');
      addTearDown(() => base.deleteSync(recursive: true));
      final cache = ServerOpsDownloadCache(tempDirProvider: () async => base);

      expect(await cache.clear(), 0);
    });
  });

  testWidgets('「清空下载缓存」入口：二次确认后才清，清完给释放多少的提示', (tester) async {
    final service = _FakeListService();
    final cache = _FakeDownloadCache();
    debugSetServerOpsRuntime(filesService: service, downloadCache: cache);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ServerOpsFilesTab(settings: _settings)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('清空下载缓存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 文案要说清清的是什么（与 host 页清快照/历史区分开）。
    expect(find.textContaining('不影响远端文件，也不影响快照与历史'), findsOneWidget);
    expect(cache.cleared, 0, reason: '还没确认，不能清');

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '清空'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(cache.cleared, 1);
    expect(find.textContaining('释放 2.0 KB'), findsOneWidget);
  });

  testWidgets('下载前先清同名旧文件（页面走的是下载缓存的 prepare）', (tester) async {
    final service = _FakeListService(
      entries: const [
        RemoteStorageEntry(
          name: 'a.txt',
          path: 'a.txt',
          size: 1,
          isDirectory: false,
        ),
      ],
    );
    final cache = _FakeDownloadCache();
    debugSetServerOpsRuntime(filesService: service, downloadCache: cache);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ServerOpsFilesTab(settings: _settings)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'a.txt'),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('下载到本机'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.downloaded, ['a.txt']);
    expect(
      cache.prepared,
      ['a.txt'],
      reason: '下载前必须让缓存 prepare（清掉同名旧文件）再写',
    );
  });
}
