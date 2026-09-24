// Widget 测试（离线，注入假 service）：
// - 账户编辑面板：空地址 / 地址无法解析 / 缺用户名 / 合法保存 四条校验路径。
// - 浏览页：空目录空态、加载失败错误态（含重试）、条目列表渲染。

import 'dart:async';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/remote_thumbnail_cache.dart';
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

  /// 取过哪些图（D5 断言"只预取相邻一张"）。
  final List<String> previewPaths = [];

  /// 这些路径取图时抛错（D5 断言"一张坏图不阻塞整个相册"）。
  final Set<String> previewFailPaths = {};

  @override
  Future<PreviewPayload> readImagePreview(
    RemoteStorageAccount account,
    String path, {
    TransferCancelToken? cancel,
  }) async {
    previewPaths.add(path);
    if (previewFailPaths.contains(path)) {
      throw const RemoteStorageException(
        RemoteStorageError.http,
        '服务器返回 HTTP 500',
        statusCode: 500,
      );
    }
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

  /// 缩略图缓存占用（283 D3）：面板与清空按钮的假数据/调用记录。
  ThumbnailCacheUsage cacheUsage = const ThumbnailCacheUsage(
    files: 0,
    bytes: 0,
    memoryCount: 0,
  );
  int clearCacheCalls = 0;

  @override
  Future<ThumbnailCacheUsage> thumbnailCacheUsage() async => cacheUsage;

  @override
  Future<void> clearThumbnailCache() async {
    clearCacheCalls += 1;
    cacheUsage = const ThumbnailCacheUsage(
      files: 0,
      bytes: 0,
      memoryCount: 0,
    );
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

    testWidgets(
      '超过上限的大图：不给整取，但会去试 EXIF 内嵌缩略图（283 D1 改的规则）',
      (tester) async {
        // 281 时的规则是"大图一律不取"；283 D1 起大 JPEG 走 EXIF 内嵌缩略图
        // （读文件开头 256KB），所以页面必须去问 service——但它仍然**不会**整取。
        final service = _FakeService(
          entries: [imageEntry(size: kThumbnailMaxBytes + 1)],
        );
        service.thumbnailBytes = kTinyPng;
        debugSetRemoteStorageRuntime(service: service);

        await tester.pumpWidget(
          MaterialApp(home: RemoteStorageBrowserPage(account: testAccount())),
        );
        await tester.pumpAndSettle();

        expect(
          service.thumbnailPaths,
          contains('a.jpg'),
          reason: '整取上限只挡"整取"，不挡 EXIF 探测',
        );
      },
    );

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

    testWidgets('超过整取上限的大图（JPEG）也会去要缩略图（283 D1 的 EXIF 路径）', (tester) async {
      // 这条用例存在的理由：service 层单测全绿不代表功能接上了——页面若只按
      // isThumbnailableEntry 判定，大图根本不会去问 service。
      final service = await pumpBrowser(
        tester,
        entries: const [
          RemoteStorageEntry(
            name: 'big.jpg',
            path: 'big.jpg',
            isDirectory: false,
            size: kThumbnailMaxBytes + 1,
          ),
        ],
      );
      service.thumbnailBytes = kTinyPng;
      await tester.pumpAndSettle();

      expect(
        service.thumbnailPaths,
        contains('big.jpg'),
        reason: '大 JPEG 必须走到 service（由 it 去试 EXIF 内嵌缩略图）',
      );
    });

    testWidgets('超过整取上限的 PNG 不去要缩略图（没有内嵌缩略图可试）', (tester) async {
      final service = await pumpBrowser(
        tester,
        entries: const [
          RemoteStorageEntry(
            name: 'big.png',
            path: 'big.png',
            isDirectory: false,
            size: kThumbnailMaxBytes + 1,
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(service.thumbnailPaths, isEmpty);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('大小未知的 JPEG 也会去要缩略图（探测代价有界）', (tester) async {
      final service = await pumpBrowser(
        tester,
        entries: const [
          RemoteStorageEntry(
            name: 'unknown.jpg',
            path: 'unknown.jpg',
            isDirectory: false,
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(service.thumbnailPaths, contains('unknown.jpg'));
    });
  });

  group('缩略图缓存面板（283 D3）', () {
    Future<_FakeService> pumpWithCache(
      WidgetTester tester, {
      required int files,
      required int bytes,
    }) async {
      final service = _FakeService();
      service.cacheUsage = ThumbnailCacheUsage(
        files: files,
        bytes: bytes,
        memoryCount: files,
      );
      debugSetRemoteStorageRuntime(service: service);
      await tester.pumpWidget(
        MaterialApp(home: RemoteStorageBrowserPage(account: testAccount())),
      );
      await tester.pumpAndSettle();
      return service;
    }

    Future<void> openCachePanel(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip('更多'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('缩略图缓存'));
      await tester.pumpAndSettle();
    }

    testWidgets('「更多」里能看到缓存占用（张数 + 大小）', (tester) async {
      await pumpWithCache(tester, files: 37, bytes: 5 * 1024 * 1024);

      await openCachePanel(tester);

      expect(find.text('缩略图缓存'), findsWidgets, reason: '面板标题');
      expect(
        find.textContaining('已缓存 37 张'),
        findsOneWidget,
        reason: '占用要能看到，缓存不该是黑盒',
      );
      expect(find.textContaining('5.00 MB'), findsOneWidget);
    });

    testWidgets('有缓存时点「清空」→ 调用清空并刷新为 0', (tester) async {
      final service = await pumpWithCache(
        tester,
        files: 12,
        bytes: 2 * 1024 * 1024,
      );

      await openCachePanel(tester);
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();

      expect(service.clearCacheCalls, 1);
      expect(
        find.textContaining('已缓存 0 张'),
        findsOneWidget,
        reason: '清空后占用立刻归零',
      );
      expect(find.text('缩略图缓存已清空'), findsOneWidget);
    });

    testWidgets('空缓存时「清空」按钮禁用（没什么可清的）', (tester) async {
      await pumpWithCache(tester, files: 0, bytes: 0);

      await openCachePanel(tester);

      final button = tester.widget<TextButton>(
        find.ancestor(of: find.text('清空'), matching: find.byType(TextButton)),
      );
      expect(button.onPressed, isNull);
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
  group('传输队列失败重试按钮（283 D4）', () {
    // 注意：本组**不能**用 pumpEventQueue()/pumpAndSettle()。
    //   - pumpEventQueue() 内部是 Future.delayed → 在 testWidgets 的 fake-async 里
    //     不推进时间就永远不会完成（测试直接挂死）；
    //   - 队列的退避、AppLogger 的 250ms 落盘防抖都是定时器，要显式推进假时间。
    Future<void> settleTimers(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('失败任务显示「重试」；点它真的重跑并变成已完成', (tester) async {
      final queue = TransferQueue(retryDelay: Duration.zero);
      debugSetRemoteStorageRuntime(queue: queue);
      final task = queue.enqueue(
        kind: TransferKind.download,
        title: 'photo.jpg',
        subtitle: '测试账户 / dcim',
        totalBytes: 1000,
        runner: (cancel, onProgress) async {
          throw const RemoteStorageException(
            RemoteStorageError.network,
            '连接超时',
          );
        },
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TransferQueueSheet())),
      );
      await settleTimers(tester);

      expect(task.status, TransferStatus.failed);
      expect(find.text('失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget, reason: '失败任务要给一键重跑');

      // 换掉 runner（模拟网络恢复）后点重试
      task.runner = (cancel, onProgress) async {
        onProgress(1000, 1000);
        return '/tmp/photo.jpg';
      };
      await tester.tap(find.text('重试'));
      await settleTimers(tester);

      expect(task.status, TransferStatus.done);
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('重试'), findsNothing, reason: '成功后不再显示重试');
    });

    testWidgets('进行中的任务显示「取消」而不是「重试」', (tester) async {
      final queue = TransferQueue(retryDelay: Duration.zero);
      debugSetRemoteStorageRuntime(queue: queue);
      final gate = Completer<void>();
      queue.enqueue(
        kind: TransferKind.download,
        title: 'big.bin',
        subtitle: '测试账户 / dcim',
        totalBytes: 1000,
        runner: (cancel, onProgress) async {
          await gate.future;
          return '/tmp/big.bin';
        },
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TransferQueueSheet())),
      );
      await settleTimers(tester);

      expect(find.text('取消'), findsOneWidget);
      expect(find.text('重试'), findsNothing);

      gate.complete();
      await settleTimers(tester);
    });
  });
  group('图片预览相册滑动（283 D5）', () {
    RemoteStorageEntry pic(String n) => RemoteStorageEntry(
      name: n,
      path: n,
      isDirectory: false,
      size: 1024,
      modifiedAt: DateTime(2024, 1, 1),
    );

    Future<_FakeService> pumpGallery(WidgetTester tester, List<String> names) async {
      final service = await pumpBrowser(
        tester,
        entries: names.map(pic).toList(),
      );
      await tester.tap(find.text(names.first));
      await tester.pumpAndSettle();
      return service;
    }

    Future<void> swipe(WidgetTester tester) async {
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
      await tester.pumpAndSettle();
    }

    /// 对话框里的文本（列表还压在下面，同名文件在两层都有，必须限定范围）。
    Finder inDialog(String text) => find.descendant(
      of: find.byType(Dialog),
      matching: find.text(text),
    );

    testWidgets('滑动浏览：标题显示"第几张 / 共几张"，且只预取相邻一张', (tester) async {
      final service = await pumpGallery(tester, ['p1.png', 'p2.png', 'p3.png']);

      expect(find.text('1 / 3'), findsOneWidget);
      expect(
        service.previewPaths.toSet(),
        {'p1.png', 'p2.png'},
        reason: '当前张 + 相邻一张；不该把整个目录的图都拉下来',
      );

      await swipe(tester);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(
        service.previewPaths.toSet(),
        {'p1.png', 'p2.png', 'p3.png'},
        reason: '滑到第二张后预取第三张',
      );
    });

    testWidgets('滑到相邻张再滑回来：不重复下载', (tester) async {
      final service = await pumpGallery(tester, ['p1.png', 'p2.png', 'p3.png']);

      await swipe(tester);
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
      await tester.pumpAndSettle();

      expect(find.text('1 / 3'), findsOneWidget);
      expect(
        service.previewPaths.where((p) => p == 'p1.png').length,
        1,
        reason: '同一个 future 复用，来回滑不该重复取',
      );
    });

    testWidgets('滑到最后一张继续左滑 → 停在最后一张，不崩', (tester) async {
      await pumpGallery(tester, ['p1.png', 'p2.png']);

      await swipe(tester);
      expect(find.text('2 / 2'), findsOneWidget);

      await swipe(tester); // 已到边界
      expect(find.text('2 / 2'), findsOneWidget);
      expect(inDialog('p2.png'), findsOneWidget, reason: '标题仍是当前这张');
    });

    testWidgets('单张图：不显示计数（没什么可数的）', (tester) async {
      await pumpGallery(tester, ['only.png']);

      expect(inDialog('only.png'), findsOneWidget);
      expect(find.textContaining('1 / 1'), findsNothing);
    });

    testWidgets('某一张取不到：那一页说明原因，仍可滑到下一张', (tester) async {
      final service = await pumpBrowser(
        tester,
        entries: ['p1.png', 'p2.png', 'p3.png'].map(pic).toList(),
      );
      service.previewFailPaths.add('p1.png');

      await tester.tap(find.text('p1.png'));
      await tester.pumpAndSettle();

      expect(find.textContaining('预览失败'), findsOneWidget);
      expect(find.textContaining('可左右滑动看下一张'), findsOneWidget);

      await swipe(tester);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget, reason: '下一张正常显示');
    });

    testWidgets('预览对话框可关闭', (tester) async {
      await pumpGallery(tester, ['p1.png', 'p2.png']);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      expect(find.byType(PageView), findsNothing);
      expect(find.text('p1.png'), findsOneWidget, reason: '回到列表');
    });
  });
}
