// 服务器运维插件：「文件」页签的用例（注入假服务，不碰网络）。
//
// 与服务器页签一样用有界 pump：底部操作栏在 busy 时会换成进度条，
// `pumpAndSettle` 会被不确定进度圈拖到超时。
import 'dart:convert';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:box/features/extensions/plugins/server_ops/files_tab.dart';
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

class _FakeFilesService extends ServerOpsFilesService {
  _FakeFilesService({this.entries = const []}) : super(settings: _settings);

  List<RemoteStorageEntry> entries;
  final List<String> listed = [];
  String? createdPath;
  String? deletedPath;
  String? renamedTo;

  /// 被当文本读过的路径。点图片/压缩包时这里必须是空的 —— 二进制走文本预览
  /// 正是真机上报的 bug（截图打开是一屏乱码方块）。
  final List<String> textReads = [];

  @override
  Future<ReadUpTo> readUpTo(String path, int maxBytes) async {
    textReads.add(path);
    return ReadUpTo(
      bytes: Uint8List.fromList(utf8.encode('hello text')),
      truncated: false,
      totalLength: 10,
    );
  }

  @override
  Future<List<RemoteStorageEntry>> list(String path) async {
    listed.add(path);
    return entries;
  }

  @override
  Future<void> createDirectory(String path) async {
    createdPath = path;
  }

  @override
  Future<void> delete(String path) async {
    deletedPath = path;
  }

  @override
  Future<void> rename(String from, String to) async {
    renamedTo = to;
  }
}

Future<void> _pumpTab(
  WidgetTester tester,
  _FakeFilesService service, {
  OpsImagePreviewOpener? imageOpener,
}) async {
  debugSetServerOpsRuntime(
    filesService: service,
    imagePreviewOpener: imageOpener,
  );
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: ServerOpsFilesTab(settings: _settings)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  tearDown(() => debugSetServerOpsRuntime());

  testWidgets('首屏列出根目录条目，面包屑显示"根目录"', (tester) async {
    final service = _FakeFilesService(
      entries: const [
        RemoteStorageEntry(
          name: 'etc',
          path: 'etc',
          isDirectory: true,
        ),
        RemoteStorageEntry(
          name: 'report.txt',
          path: 'report.txt',
          isDirectory: false,
          size: 2048,
        ),
      ],
    );
    await _pumpTab(tester, service);

    expect(service.listed, ['']);
    expect(find.text('etc'), findsOneWidget);
    expect(find.text('report.txt'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('根目录'), findsOneWidget);
    expect(find.text('/'), findsOneWidget, reason: '底部显示当前路径');
  });

  testWidgets('点目录进下一级：面包屑追加，列出的是新路径', (tester) async {
    final service = _FakeFilesService(
      entries: const [
        RemoteStorageEntry(name: 'etc', path: 'etc', isDirectory: true),
      ],
    );
    await _pumpTab(tester, service);

    await tester.tap(find.widgetWithText(ListTile, 'etc'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.listed, ['', 'etc']);
    expect(find.text('根目录'), findsOneWidget);
    // 面包屑里多了 etc（列表里那条也是 etc，所以按 TextButton 限定）。
    expect(find.widgetWithText(TextButton, 'etc'), findsOneWidget);
    expect(find.text('/etc'), findsOneWidget);
  });

  testWidgets('返回上一级按钮回到根', (tester) async {
    final service = _FakeFilesService(
      entries: const [
        RemoteStorageEntry(name: 'etc', path: 'etc', isDirectory: true),
      ],
    );
    await _pumpTab(tester, service);
    await tester.tap(find.widgetWithText(ListTile, 'etc'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('上一级'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.listed.last, '');
    expect(find.text('/'), findsOneWidget);
  });

  testWidgets('新建文件夹：确认后调 createDirectory，路径是当前目录 + 名字',
      (tester) async {
    final service = _FakeFilesService();
    await _pumpTab(tester, service);

    await tester.tap(find.text('新建文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'newdir');
    await tester.tap(find.text('创建'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.createdPath, 'newdir');
  });

  testWidgets('删除要二次确认，文案写清无法恢复；确认后才真删', (tester) async {
    final service = _FakeFilesService(
      entries: const [
        RemoteStorageEntry(
          name: 'report.txt',
          path: 'report.txt',
          isDirectory: false,
          size: 10,
        ),
      ],
    );
    await _pumpTab(tester, service);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'report.txt'),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('无法恢复'), findsOneWidget);
    expect(service.deletedPath, isNull, reason: '还没确认，不能删');

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.deletedPath, 'report.txt');
  });

  testWidgets('目录删除的确认文案说明"目录内所有内容一并删除"', (tester) async {
    final service = _FakeFilesService(
      entries: const [
        RemoteStorageEntry(name: 'etc', path: 'etc', isDirectory: true),
      ],
    );
    await _pumpTab(tester, service);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'etc'),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('目录内所有内容将一并删除'), findsOneWidget);
  });

  testWidgets('重命名：预检冲突等由服务层负责，页面只把新目标传下去',
      (tester) async {
    final service = _FakeFilesService(
      entries: const [
        RemoteStorageEntry(
          name: 'etc',
          path: 'a/etc',
          isDirectory: true,
        ),
      ],
    );
    // 先进入 a 目录，验证重命名用的是"父目录 + 新名字"。
    service.entries = const [
      RemoteStorageEntry(name: 'a', path: 'a', isDirectory: true),
    ];
    await _pumpTab(tester, service);
    await tester.tap(find.text('a'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    service.entries = const [
      RemoteStorageEntry(name: 'etc', path: 'a/etc', isDirectory: true),
    ];
    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'etc'),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('重命名'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'etc2');
    await tester.tap(find.text('重命名').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.renamedTo, 'a/etc2');
  });

  testWidgets('没配口令时给出提示（不硬编码任何口令）', (tester) async {
    final service = _FakeFilesService();
    debugSetServerOpsRuntime(filesService: service);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ServerOpsFilesTab(settings: ServerOpsSettings()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('还没配置运维通道口令'), findsOneWidget);
  });
  testWidgets('点图片走相册预览：只把同目录图片传进去，且不当文本读', (tester) async {
    final service = _FakeFilesService(
      entries: const [
        RemoteStorageEntry(
          name: 'notes.txt',
          path: 'notes.txt',
          size: 10,
          isDirectory: false,
        ),
        RemoteStorageEntry(
          name: 'Screenshot_20260.png',
          path: 'Screenshot_20260.png',
          size: 2048,
          isDirectory: false,
        ),
        RemoteStorageEntry(
          name: 'photo.jpg',
          path: 'photo.jpg',
          size: 2048,
          isDirectory: false,
        ),
        RemoteStorageEntry(
          name: 'pkg.zip',
          path: 'pkg.zip',
          size: 2048,
          isDirectory: false,
        ),
      ],
    );
    int opened = 0;
    List<RemoteStorageEntry>? shown;
    int? at;
    await _pumpTab(
      tester,
      service,
      imageOpener: (context, account, images, initialIndex) async {
        opened++;
        shown = images;
        at = initialIndex;
      },
    );

    await tester.tap(find.widgetWithText(ListTile, 'Screenshot_20260.png'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(opened, 1, reason: '点图片要开图片预览');
    expect(
      shown!.map((e) => e.name),
      ['Screenshot_20260.png', 'photo.jpg'],
      reason: '只传图片：混进 txt/zip 会让"下一张"翻到文档或压缩包上',
    );
    expect(at, 0);
    expect(service.textReads, isEmpty, reason: '图片不能走文本读取');
  });

  testWidgets('点压缩包不当文本看：给"用其他应用打开"，取消则不下载', (tester) async {
    final service = _FakeFilesService(
      entries: const [
        RemoteStorageEntry(
          name: 'pkg.zip',
          path: 'pkg.zip',
          size: 2048,
          isDirectory: false,
        ),
      ],
    );
    await _pumpTab(tester, service);

    await tester.tap(find.widgetWithText(ListTile, 'pkg.zip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('用其他应用打开'), findsOneWidget);
    expect(find.textContaining('二进制文件'), findsOneWidget);
    expect(service.textReads, isEmpty, reason: '二进制不能走文本读取');

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('用其他应用打开'), findsNothing);
  });

  testWidgets('点文本文件仍然走文本预览（不回退）', (tester) async {
    final service = _FakeFilesService(
      entries: const [
        RemoteStorageEntry(
          name: 'notes.txt',
          path: 'notes.txt',
          size: 10,
          isDirectory: false,
        ),
      ],
    );
    await _pumpTab(tester, service);

    await tester.tap(find.widgetWithText(ListTile, 'notes.txt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.textReads, ['notes.txt']);
    expect(find.text('hello text'), findsOneWidget);
  });
}
