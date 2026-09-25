// 分享落点面板（286 P3）：
//   * 列表、账户/目录默认值、入队（含 spec，被杀后可恢复）；
//   * 传成功后删掉缓存中转副本，且**只删自己的中转文件**；
//   * 没有账户时给出去处，而不是让用户点一个必然失败的按钮。
import 'dart:io';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/share_inbox_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/share_inbox_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeService extends RemoteStorageService {
  _FakeService({this.accounts = const <RemoteStorageAccount>[]});

  List<RemoteStorageAccount> accounts;
  final List<({String accountId, String path, String name, String targetDir})>
      uploads = <({String accountId, String path, String name, String targetDir})>[];

  @override
  Future<List<RemoteStorageAccount>> loadAccounts() async => accounts;

  @override
  Future<bool> uploadFile(
    RemoteStorageAccount account, {
    required LocalUploadFile file,
    required String targetDir,
    bool overwrite = false,
    void Function(int sent, int total)? onProgress,
    TransferCancelToken? cancel,
  }) async {
    uploads.add((
      accountId: account.id,
      path: file.path,
      name: file.name,
      targetDir: targetDir,
    ));
    onProgress?.call(file.size, file.size);
    return true;
  }
}

/// 面板加载账户时有不确定进度圈（CircularProgressIndicator 永远在动），
/// `pumpAndSettle` 会一直等下去 —— 一律用有界 pump（本仓库已知坑）。
Future<void> boundedPump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350)); // 面板弹出动画
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100)); // 异步结果回填
}

RemoteStorageAccount _account(String id) => RemoteStorageAccount(
      id: id,
      label: '账户$id',
      baseUrl: 'https://dav.example.com/dav/',
      username: 'u',
      password: 'p',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> pumpSheet(
    WidgetTester tester, {
    required RemoteStorageService service,
    required TransferQueue queue,
    required List<SharedInboxFile> files,
  }) async {
    debugSetRemoteStorageRuntime(service: service, queue: queue);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ShareInboxSheet(files: files),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await boundedPump(tester);
  }

  testWidgets('列出分享文件，默认第一个账户 + 根目录，点上传按约定入队', (tester) async {
    final service = _FakeService(accounts: [_account('a1'), _account('a2')]);
    final queue = TransferQueue();
    await pumpSheet(
      tester,
      service: service,
      queue: queue,
      files: const [
        SharedInboxFile(
          path: '/tmp/1_a.jpg',
          name: 'a.jpg',
          sizeBytes: 2048,
          mimeType: 'image/jpeg',
        ),
        SharedInboxFile(
          path: '/tmp/2_v.mp4',
          name: 'v.mp4',
          sizeBytes: 5 * 1024 * 1024,
          mimeType: 'video/mp4',
        ),
      ],
    );

    expect(find.text('收到 2 个分享文件'), findsOneWidget);
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.text('v.mp4'), findsOneWidget);

    await tester.tap(find.text('上传到远程存储'));
    await boundedPump(tester);

    expect(queue.tasks, hasLength(2));
    expect(queue.tasks.every((t) => t.kind == TransferKind.upload), isTrue);
    // 不依赖队列内部顺序：按标题取。
    final spec = queue.tasks.firstWhere((t) => t.title == 'a.jpg').spec!;
    expect(spec.accountId, 'a1', reason: '默认用第一个账户');
    expect(spec.remotePath, '', reason: '默认根目录（空串）');
    expect(spec.localPath, '/tmp/1_a.jpg');
    expect(spec.fileName, 'a.jpg');
    // 真正上传也会被执行（队列已在跑）
    await boundedPump(tester);
    expect(service.uploads.map((u) => u.name), containsAll(<String>['a.jpg', 'v.mp4']));
  });

  testWidgets('目标目录：填了相对路径自动补前导斜杠', (tester) async {
    final service = _FakeService(accounts: [_account('a1')]);
    final queue = TransferQueue();
    await pumpSheet(
      tester,
      service: service,
      queue: queue,
      files: const [
        SharedInboxFile(
          path: '/tmp/1_a.jpg',
          name: 'a.jpg',
          sizeBytes: 1,
          mimeType: 'image/jpeg',
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), '相册/2026');
    await tester.tap(find.text('上传到远程存储'));
    await boundedPump(tester);

    expect(queue.tasks.single.spec!.remotePath, '/相册/2026');
  });

  testWidgets('上传成功后删掉中转副本；非中转路径一律不删', (tester) async {
    // 注意：testWidgets 的测试体跑在 FakeAsync 里，dart:io 的**异步**接口
    // 在这里不会完成（会挂死）→ 造/清临时文件一律用同步 API。
    final tmp = Directory.systemTemp.createTempSync('share_inbox_test_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final inbox = Directory('${tmp.path}/shared_inbox')..createSync(recursive: true);
    final inboxFile = File('${inbox.path}/1_a.jpg')
      ..writeAsBytesSync(List<int>.filled(4, 1));
    // 一个"用户自己的文件"（路径里没有 shared_inbox）：绝不能被删
    final userFile = File('${tmp.path}/user_photo.jpg')
      ..writeAsBytesSync(List<int>.filled(4, 2));

    final service = _FakeService(accounts: [_account('a1')]);
    final queue = TransferQueue();
    await pumpSheet(
      tester,
      service: service,
      queue: queue,
      files: [
        SharedInboxFile(
          path: inboxFile.path,
          name: 'a.jpg',
          sizeBytes: 4,
          mimeType: 'image/jpeg',
        ),
        SharedInboxFile(
          path: userFile.path,
          name: 'user_photo.jpg',
          sizeBytes: 4,
          mimeType: 'image/jpeg',
        ),
      ],
    );

    await tester.tap(find.text('上传到远程存储'));
    await boundedPump(tester);

    expect(inboxFile.existsSync(), isFalse, reason: '中转副本传完就删');
    expect(userFile.existsSync(), isTrue, reason: '不是我们的中转文件，绝不能删');
  });

  testWidgets('没有账户：提示去处，不出现上传按钮', (tester) async {
    final service = _FakeService(accounts: const <RemoteStorageAccount>[]);
    final queue = TransferQueue();
    await pumpSheet(
      tester,
      service: service,
      queue: queue,
      files: const [
        SharedInboxFile(
          path: '/tmp/1_a.jpg',
          name: 'a.jpg',
          sizeBytes: 1,
          mimeType: 'image/jpeg',
        ),
      ],
    );

    expect(find.textContaining('还没有远程存储账户'), findsOneWidget);
    expect(find.text('上传到远程存储'), findsNothing);
    expect(queue.tasks, isEmpty);
  });

  testWidgets('点取消：不入队', (tester) async {
    final service = _FakeService(accounts: [_account('a1')]);
    final queue = TransferQueue();
    await pumpSheet(
      tester,
      service: service,
      queue: queue,
      files: const [
        SharedInboxFile(
          path: '/tmp/1_a.jpg',
          name: 'a.jpg',
          sizeBytes: 1,
          mimeType: 'image/jpeg',
        ),
      ],
    );

    await tester.tap(find.text('取消'));
    await boundedPump(tester);
    expect(queue.tasks, isEmpty);
    expect(service.uploads, isEmpty);
  });
}
