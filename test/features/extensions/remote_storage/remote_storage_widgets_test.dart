// Widget 测试（离线，注入假 service）：
// - 账户编辑面板：空地址 / 地址无法解析 / 缺用户名 / 合法保存 四条校验路径。
// - 浏览页：空目录空态、加载失败错误态（含重试）、条目列表渲染。

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/remote_storage_browser_page.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/remote_storage_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// 假服务：只覆写页面用到的读/写账户与列目录，其余走默认实现（不会被调用）。
class _FakeService extends RemoteStorageService {
  _FakeService({this.entries = const [], this.listError}) : super();

  List<RemoteStorageEntry> entries;
  RemoteStorageException? listError;
  RemoteStorageAccount? saved;

  @override
  Future<List<RemoteStorageEntry>> list(
    RemoteStorageAccount account,
    String path, {
    bool forceRefresh = false,
  }) async {
    final err = listError;
    if (err != null) throw err;
    return entries;
  }

  @override
  Future<void> saveAccount(RemoteStorageAccount account) async {
    saved = account;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<_FakeService> pumpBrowser(
    WidgetTester tester, {
    List<RemoteStorageEntry> entries = const [],
    RemoteStorageException? listError,
  }) async {
    final service = _FakeService(entries: entries, listError: listError);
    debugSetRemoteStorageRuntime(service: service);
    await tester.pumpWidget(
      MaterialApp(home: RemoteStorageBrowserPage(account: testAccount())),
    );
    await tester.pumpAndSettle();
    return service;
  }

  Future<_FakeService> pumpSheet(WidgetTester tester) async {
    final service = _FakeService();
    debugSetRemoteStorageRuntime(service: service);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const RemoteStorageAccountEditorSheet(),
                ),
                child: const Text('open-sheet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();
    return service;
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
  }

  group('账户编辑面板', () {
    testWidgets('空地址 → 提示请输入服务器地址', (tester) async {
      await pumpSheet(tester);
      await tapSave(tester);
      expect(find.text('请输入服务器地址'), findsOneWidget);
    });

    testWidgets('地址缺前缀 → 提示无法解析', (tester) async {
      await pumpSheet(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'dav.example.com/dav',
      );
      await tapSave(tester);
      expect(find.text('地址无法解析，请包含 http:// 或 https:// 前缀'), findsOneWidget);
    });

    testWidgets('缺用户名 → 提示请输入用户名', (tester) async {
      await pumpSheet(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'https://dav.example.com/dav/',
      );
      await tapSave(tester);
      expect(find.text('请输入用户名'), findsOneWidget);
    });

    testWidgets('合法输入 → 保存并回传字段', (tester) async {
      final service = await pumpSheet(tester);
      await tester.enterText(
        find.byType(TextField).at(0),
        'https://dav.example.com/dav/',
      );
      await tester.enterText(find.byType(TextField).at(1), '我的坚果云');
      await tester.enterText(
        find.byType(TextField).at(2),
        'user@example.com',
      );
      await tester.enterText(find.byType(TextField).at(3), 'app-pass');
      await tapSave(tester);

      expect(service.saved, isNotNull);
      expect(service.saved!.baseUrl, 'https://dav.example.com/dav/');
      expect(service.saved!.label, '我的坚果云');
      expect(service.saved!.username, 'user@example.com');
      expect(service.saved!.password, 'app-pass');
    });
  });

  group('浏览页', () {
    testWidgets('空目录 → 空态', (tester) async {
      await pumpBrowser(tester);
      expect(find.text('空目录'), findsOneWidget);
    });

    testWidgets('加载失败 → 错误文案 + 重试按钮', (tester) async {
      await pumpBrowser(
        tester,
        listError: const RemoteStorageException(
          RemoteStorageError.unauthorized,
          '用户名或密码不正确；坚果云请使用网页端生成的「应用密码」',
        ),
      );
      expect(find.textContaining('应用密码'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('条目列表 → 渲染名称', (tester) async {
      await pumpBrowser(
        tester,
        entries: const [
          RemoteStorageEntry(
            name: 'a.txt',
            path: 'a.txt',
            isDirectory: false,
            size: 5,
          ),
          RemoteStorageEntry(name: 'docs', path: 'docs', isDirectory: true),
        ],
      );
      expect(find.textContaining('a.txt'), findsAtLeastNWidgets(1));
      expect(find.textContaining('docs'), findsAtLeastNWidgets(1));
    });
  });
}
