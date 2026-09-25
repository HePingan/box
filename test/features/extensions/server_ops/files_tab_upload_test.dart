// 服务器运维插件：上传多选 + 串行队列 + 可取消的用例（A2，假服务注入，不联网）。
//
// 上传入口改成 `FilePicker.pickFiles()`（多选）后，页面用 OpsFilePicker 接缝注入，
// 用例不碰真实文件选择器；串行/取消/失败继续都在假服务里断言。
import 'dart:async';
import 'dart:io';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
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

class _FakeUploadService extends ServerOpsFilesService {
  _FakeUploadService() : super(settings: _settings);

  final List<String> started = [];
  final Set<String> failFor = {};

  /// 挂在第一项上传上的闸门（取消用例用）。
  Completer<void>? gate;

  int active = 0;
  int maxActive = 0;

  @override
  Future<List<RemoteStorageEntry>> list(String path) async => const [];

  @override
  Future<void> upload(
    File file,
    String remotePath, {
    void Function(int sent, int total)? onProgress,
    TransferCancelToken? cancel,
  }) async {
    started.add(remotePath);
    active += 1;
    if (active > maxActive) maxActive = active;
    try {
      final g = gate;
      if (g != null) {
        await g.future;
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      cancel?.throwIfCanceled();
      if (failFor.contains(remotePath)) {
        throw const RemoteStorageException(
          RemoteStorageError.http,
          '服务器拒绝了这个文件',
        );
      }
      onProgress?.call(10, 10);
    } finally {
      active -= 1;
    }
  }
}

Future<void> _pumpTab(
  WidgetTester tester,
  _FakeUploadService service, {
  List<OpsPickedFile> picked = const [],
}) async {
  debugSetServerOpsRuntime(
    filesService: service,
    filePicker: () async => picked,
  );
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: ServerOpsFilesTab(settings: _settings)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpABit(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  tearDown(() => debugSetServerOpsRuntime());

  testWidgets('多选上传：三个文件都上传，且并发恒为 1（串行队列）', (tester) async {
    final service = _FakeUploadService();
    await _pumpTab(
      tester,
      service,
      picked: const [
        OpsPickedFile(name: 'a.txt', path: '/tmp/a.txt'),
        OpsPickedFile(name: 'b.txt', path: '/tmp/b.txt'),
        OpsPickedFile(name: 'c.txt', path: '/tmp/c.txt'),
      ],
    );

    await tester.tap(find.text('上传'));
    await _pumpABit(tester);

    expect(service.started, ['a.txt', 'b.txt', 'c.txt']);
    expect(service.maxActive, 1, reason: '并发必须恒为 1');
    expect(find.textContaining('上传完成：共 3 项'), findsOneWidget);
  });

  testWidgets('取消：在途项被取消后不再发起后续 PUT', (tester) async {
    final service = _FakeUploadService()..gate = Completer<void>();
    await _pumpTab(
      tester,
      service,
      picked: const [
        OpsPickedFile(name: 'a.txt', path: '/tmp/a.txt'),
        OpsPickedFile(name: 'b.txt', path: '/tmp/b.txt'),
        OpsPickedFile(name: 'c.txt', path: '/tmp/c.txt'),
      ],
    );

    await tester.tap(find.text('上传'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(service.started, ['a.txt'], reason: '第一项卡在闸门上');
    expect(find.textContaining('第 1/3 项'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    service.gate!.complete();
    await _pumpABit(tester);

    expect(service.started, ['a.txt'], reason: '取消后不能再发起第 2、3 项');
    expect(find.textContaining('已取消上传'), findsOneWidget);
  });

  testWidgets('中间失败不打断整批：第 2 个失败，第 3 个照传', (tester) async {
    final service = _FakeUploadService()..failFor.add('b.txt');
    await _pumpTab(
      tester,
      service,
      picked: const [
        OpsPickedFile(name: 'a.txt', path: '/tmp/a.txt'),
        OpsPickedFile(name: 'b.txt', path: '/tmp/b.txt'),
        OpsPickedFile(name: 'c.txt', path: '/tmp/c.txt'),
      ],
    );

    await tester.tap(find.text('上传'));
    await _pumpABit(tester);

    expect(service.started, ['a.txt', 'b.txt', 'c.txt']);
    expect(find.textContaining('失败 1 项'), findsOneWidget);
  });

  testWidgets('本机无可读路径的文件被跳过并给出提示', (tester) async {
    final service = _FakeUploadService();
    await _pumpTab(
      tester,
      service,
      picked: const [
        OpsPickedFile(name: 'cloud-only.txt', path: ''),
        OpsPickedFile(name: 'a.txt', path: '/tmp/a.txt'),
      ],
    );

    await tester.tap(find.text('上传'));
    await _pumpABit(tester);

    expect(service.started, ['a.txt']);
    expect(find.textContaining('已跳过'), findsOneWidget);
  });

  testWidgets('取消选择（空列表）时不发起任何上传', (tester) async {
    final service = _FakeUploadService();
    await _pumpTab(tester, service, picked: const []);

    await tester.tap(find.text('上传'));
    await _pumpABit(tester);

    expect(service.started, isEmpty);
  });
}
