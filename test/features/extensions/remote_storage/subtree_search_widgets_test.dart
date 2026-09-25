// 搜索结果面板的缓存标注与"重新搜索"（286 P4）：
// 界面必须让用户知道结果里有一部分是缓存，并给他一次"不看缓存"的机会。
import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/remote_storage_browser_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

class _FakeService extends RemoteStorageService {
  _FakeService();

  /// 每次 searchSubtree 的 useSnapshot 取值（按调用顺序）。
  final List<bool> useSnapshotCalls = <bool>[];

  // 要超过 kSearchEntryThreshold(30)：否则 AppBar 上根本不出现搜索图标
  // （"超 30 条才给搜索入口"是 C3 的既定设计）。
  @override
  Future<List<RemoteStorageEntry>> list(
    RemoteStorageAccount account,
    String path, {
    bool forceRefresh = false,
  }) async =>
      <RemoteStorageEntry>[
        for (var i = 0; i < 31; i++)
          RemoteStorageEntry(
            name: '别的$i.jpg',
            path: '别的$i.jpg',
            isDirectory: false,
            size: 3,
          ),
      ];

  @override
  Future<SubtreeSearchResult> searchSubtree(
    RemoteStorageAccount account, {
    required String rootPath,
    required String query,
    void Function(int scannedDirs, int found)? onProgress,
    TransferCancelToken? cancel,
    bool useSnapshot = true,
  }) async {
    useSnapshotCalls.add(useSnapshot);
    return SubtreeSearchResult(
      entries: const <RemoteStorageEntry>[
        RemoteStorageEntry(
          name: '找到的.jpg',
          path: '相册/找到的.jpg',
          isDirectory: false,
          size: 4,
        ),
      ],
      dirsScanned: 4,
      truncated: false,
      canceled: false,
      snapshotDirs: useSnapshot ? 3 : 0,
      oldestSnapshotAt:
          useSnapshot ? DateTime.now().subtract(const Duration(minutes: 8)) : null,
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('结果来自缓存：写清条数/时间，并给「重新搜索」；点了就不看缓存', (tester) async {
    final service = _FakeService();
    debugSetRemoteStorageRuntime(service: service, queue: TransferQueue());
    await tester.pumpWidget(
      MaterialApp(home: RemoteStorageBrowserPage(account: testAccount())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 先点搜索图标打开筛选栏（默认不显示输入框）
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    // 输入一个本目录筛不到的词 → 出现「搜子目录」入口
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump();
    expect(find.text('搜子目录'), findsOneWidget);

    await tester.tap(find.text('搜子目录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(service.useSnapshotCalls, <bool>[true]);
    expect(find.textContaining('3 个目录用了本地缓存'), findsOneWidget);
    expect(find.textContaining('8 分钟前'), findsOneWidget);
    expect(find.text('找到的.jpg'), findsOneWidget);

    // 点「重新搜索」→ 第二次调用必须显式关掉快照
    await tester.tap(find.text('重新搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(service.useSnapshotCalls, <bool>[true, false]);
    expect(find.textContaining('用了本地缓存'), findsNothing,
        reason: '现场列出来的结果不该再标缓存');
    expect(find.text('重新搜索'), findsNothing);

    await tester.tap(find.text('关闭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
