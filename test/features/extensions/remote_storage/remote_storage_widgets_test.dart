// Widget 测试（离线，注入假 service）：
// - 账户编辑面板：空地址 / 地址无法解析 / 缺用户名 / 合法保存 四条校验路径。
// - 浏览页：空目录空态、加载失败错误态（含重试）、条目列表渲染。

import 'dart:typed_data';

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

  /// 页面读到的配额；本文件不测上传路径，只为避免误走真实传输层。
  RemoteStorageQuota quotaResult = const RemoteStorageQuota();

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

  /// 覆写配额：不让 widget 测试走到真实传输层（配额只用于提示，默认给空）。
  @override
  Future<RemoteStorageQuota> quota(
    RemoteStorageAccount account, {
    String path = '',
  }) async {
    return quotaResult;
  }

  /// 图片预览返回的字节（C4 测试用）：一张 1×1 PNG 就够，测的是解码参数不是图。
  Uint8List imageBytes = kTinyPng;

  @override
  Future<PreviewPayload> readImagePreview(
    RemoteStorageAccount account,
    String path, {
    TransferCancelToken? cancel,
  }) async {
    return PreviewPayload(bytes: imageBytes, truncated: false, oversize: false);
  }

  /// 列表缩略图（281+）：默认不给图（回退图标），用例按需塞字节。
  Uint8List? thumbnailBytes;
  final List<String> thumbnailPaths = [];
  bool thumbnailsEnabled = true;
  final List<bool> savedThumbnailFlags = [];

  @override
  Future<Uint8List?> readThumbnail(
    RemoteStorageAccount account,
    RemoteStorageEntry entry, {
    TransferCancelToken? cancel,
  }) async {
    thumbnailPaths.add(entry.path);
    return thumbnailBytes;
  }

  @override
  Future<bool> loadThumbnailsEnabled() async => thumbnailsEnabled;

  @override
  Future<void> saveThumbnailsEnabled(bool enabled) async {
    thumbnailsEnabled = enabled;
    savedThumbnailFlags.add(enabled);
  }

  /// 记录批量删除调用（B1 的删除确认测试用），不触网。
  final List<List<RemoteStorageEntry>> deletedBatches = [];

  RemoteBatchResult batchResult = const RemoteBatchResult.empty();

  @override
  Future<RemoteBatchResult> deleteEntries(
    RemoteStorageAccount account,
    List<RemoteStorageEntry> entries,
  ) async {
    deletedBatches.add(entries);
    return batchResult;
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

  group('列表缩略图（281+）', () {
    RemoteStorageEntry imageEntry({
      String name = 'a.jpg',
      int size = 1024,
    }) => RemoteStorageEntry(
      name: name,
      path: name,
      isDirectory: false,
      size: size,
      modifiedAt: DateTime.utc(2023, 1, 30, 11, 22),
    );

    testWidgets('小图显示缩略图（不是通用图标）', (tester) async {
      final service = _FakeService(entries: [imageEntry()]);
      service.thumbnailBytes = kTinyPng;
      debugSetRemoteStorageRuntime(service: service);

      await tester.pumpWidget(
        MaterialApp(home: RemoteStorageBrowserPage(account: testAccount())),
      );
      await tester.pumpAndSettle();

      expect(service.thumbnailPaths, ['a.jpg'], reason: '应该去取这张图');
      expect(
        find.byType(Image),
        findsOneWidget,
        reason: '取到字节后行首应是图片缩略图',
      );
      expect(find.byIcon(Icons.image_outlined), findsNothing);
    });

    testWidgets('超过上限的大图不取：保持通用图标，也不发请求', (tester) async {
      final service = _FakeService(
        entries: [imageEntry(size: kThumbnailMaxBytes + 1)],
      );
      service.thumbnailBytes = kTinyPng;
      debugSetRemoteStorageRuntime(service: service);

      await tester.pumpWidget(
        MaterialApp(home: RemoteStorageBrowserPage(account: testAccount())),
      );
      await tester.pumpAndSettle();

      expect(service.thumbnailPaths, isEmpty, reason: '大图不该去取');
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('取不到（返回 null）→ 回退通用图标，列表不显示错误', (tester) async {
      final service = _FakeService(entries: [imageEntry()]);
      service.thumbnailBytes = null;
      debugSetRemoteStorageRuntime(service: service);

      await tester.pumpWidget(
        MaterialApp(home: RemoteStorageBrowserPage(account: testAccount())),
      );
      await tester.pumpAndSettle();

      expect(service.thumbnailPaths, ['a.jpg'], reason: '尝试过');
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('失败'), findsNothing);
    });

    testWidgets('开关关闭时完全不取图（偏好从存储读）', (tester) async {
      final service = _FakeService(entries: [imageEntry()]);
      service.thumbnailsEnabled = false;
      service.thumbnailBytes = kTinyPng;
      debugSetRemoteStorageRuntime(service: service);

      await tester.pumpWidget(
        MaterialApp(home: RemoteStorageBrowserPage(account: testAccount())),
      );
      await tester.pumpAndSettle();

      expect(service.thumbnailPaths, isEmpty);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('顶栏「更多」里可以关掉缩略图，并写回偏好', (tester) async {
      final service = _FakeService(entries: [imageEntry()]);
      service.thumbnailBytes = kTinyPng;
      debugSetRemoteStorageRuntime(service: service);

      await tester.pumpWidget(
        MaterialApp(home: RemoteStorageBrowserPage(account: testAccount())),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);

      // 行内也有 tooltip '更多'（每行的操作菜单），这里只点顶栏那个。
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip('更多'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示图片缩略图'));
      await tester.pumpAndSettle();

      expect(service.savedThumbnailFlags, [false], reason: '关掉要持久化');
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
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

  group('写操作 UI（B1：多选与删除确认）', () {
    const fileA = RemoteStorageEntry(
      name: 'a.txt',
      path: 'a.txt',
      isDirectory: false,
      size: 5,
    );
    const fileB = RemoteStorageEntry(
      name: 'b.txt',
      path: 'b.txt',
      isDirectory: false,
      size: 7,
    );
    const folder = RemoteStorageEntry(
      name: 'docs',
      path: 'docs',
      isDirectory: true,
    );

    testWidgets('长按进多选：顶栏切成批量动作；再点一下取消选择即退出', (tester) async {
      await pumpBrowser(tester, entries: const [fileA, fileB]);

      expect(find.text('已选 1 项'), findsNothing);

      await tester.longPress(find.text('a.txt'));
      await tester.pumpAndSettle();

      expect(find.text('已选 1 项'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '删除'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '复制到'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);

      // 多选态下点同一项 = 取消选择；选空后自动退出多选。
      await tester.tap(find.text('a.txt'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsNothing);
      expect(find.widgetWithText(TextButton, '删除'), findsNothing);
    });

    testWidgets('全选把当前目录所有条目选中（含文件夹）', (tester) async {
      await pumpBrowser(tester, entries: const [fileA, folder]);

      await tester.longPress(find.text('a.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();

      expect(find.text('已选 2 项'), findsOneWidget);
      expect(find.text('取消全选'), findsOneWidget);
    });

    testWidgets('删除确认：含文件夹时标题与文案都点明"内容一并删除、不可恢复"', (tester) async {
      final service = await pumpBrowser(tester, entries: const [fileA, folder]);

      await tester.longPress(find.text('docs'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();

      expect(find.text('删除文件夹及其内容？'), findsOneWidget);
      expect(find.textContaining('一并删除'), findsOneWidget);
      expect(find.textContaining('无法恢复'), findsOneWidget);

      // 取消：不发任何删除请求（这是"二次确认"的意义）。
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.deletedBatches, isEmpty);
    });

    testWidgets('确认删除后走批量删除接口，并把结果汇报出来', (tester) async {
      final service = await pumpBrowser(tester, entries: const [fileA, fileB]);

      await tester.longPress(find.text('a.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();
      // 全是文件：标题不该提文件夹。
      expect(find.text('删除这些文件？'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(service.deletedBatches, hasLength(1));
      expect(
        service.deletedBatches.single.map((e) => e.name).toList(),
        ['a.txt', 'b.txt'],
      );
      expect(find.textContaining('删除完成'), findsOneWidget);
    });

    testWidgets('部分失败时列出明细（不假装成功）', (tester) async {
      final service = await pumpBrowser(tester, entries: const [fileA, fileB]);
      service.batchResult = const RemoteBatchResult(
        succeeded: 1,
        failures: ['b.txt：服务器拒绝删除（只读挂载或权限不足）'],
      );

      await tester.longPress(find.text('a.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(find.text('删除：部分未完成'), findsOneWidget);
      expect(find.textContaining('b.txt：'), findsOneWidget);
    });

    testWidgets('常态顶栏有「新建文件夹」入口', (tester) async {
      await pumpBrowser(tester, entries: const [fileA]);
      expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);
    });
  });

  group('图片预览（C4：降采样解码）', () {
    testWidgets('预览图按屏幕宽度 ×2 解码，不是全尺寸', (tester) async {
      await pumpBrowser(
        tester,
        entries: const [
          RemoteStorageEntry(
            name: 'pic.png',
            path: 'pic.png',
            isDirectory: false,
            size: 1024,
          ),
        ],
      );

      await tester.tap(find.text('pic.png'));
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image));
      final media = tester.view;
      final expected = previewImageDecodeWidth(
        logicalWidth: media.physicalSize.width / media.devicePixelRatio,
        devicePixelRatio: media.devicePixelRatio,
      );
      expect(
        image.image,
        isA<ResizeImage>(),
        reason: '不给 cacheWidth 就会按原图尺寸解码：20MB 的图能解成近 200MB 位图',
      );
      expect((image.image as ResizeImage).width, expected);
    });
  });
}
