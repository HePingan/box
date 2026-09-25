// 本目录筛选的界面行为（287 D1）：筛选条、条件生效、横幅、一键清除。
//
// 断言口径：列表是虚拟化的（只有可见项被构建），所以"某条在不在"要用
// **横幅上的精确计数**来断言，而不是靠 find.text 找某一个文件名。
//
// 两条要守的行为：① 结构化筛选关掉搜索框后**继续生效**（关个搜索框回来发现
// 筛选没了会让人迷惑）；② 清除要能把名称与结构化条件一起清掉。
import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/remote_storage_browser_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// 4 个各具特征的文件 + 30 条填充 + 1 个目录 = 35 条。
List<RemoteStorageEntry> _entries({bool withDirectory = true}) {
  final now = DateTime.now();
  return <RemoteStorageEntry>[
    RemoteStorageEntry(
      name: '大图.png',
      path: '大图.png',
      isDirectory: false,
      size: 200 * 1024 * 1024,
      modifiedAt: now.subtract(const Duration(hours: 1)),
    ),
    RemoteStorageEntry(
      name: '小图.png',
      path: '小图.png',
      isDirectory: false,
      size: 1000,
      modifiedAt: now.subtract(const Duration(days: 40)),
    ),
    RemoteStorageEntry(
      name: '电影.mp4',
      path: '电影.mp4',
      isDirectory: false,
      size: 300 * 1024 * 1024,
      modifiedAt: now.subtract(const Duration(hours: 2)),
    ),
    RemoteStorageEntry(
      name: '笔记.txt',
      path: '笔记.txt',
      isDirectory: false,
      size: 500,
      modifiedAt: now.subtract(const Duration(minutes: 5)),
    ),
    for (var i = 0; i < 30; i++)
      RemoteStorageEntry(
        name: '填充$i.dat',
        path: '填充$i.dat',
        isDirectory: false,
        size: 10,
        modifiedAt: now,
      ),
    if (withDirectory)
      const RemoteStorageEntry(name: '相册', path: '相册', isDirectory: true),
  ];
}

class _FakeService extends RemoteStorageService {
  _FakeService({this.withDirectory = true});

  final bool withDirectory;

  @override
  Future<List<RemoteStorageEntry>> list(
    RemoteStorageAccount account,
    String path, {
    bool forceRefresh = false,
  }) async =>
      _entries(withDirectory: withDirectory);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> open(WidgetTester tester, {bool withDirectory = true}) async {
    debugSetRemoteStorageRuntime(
      service: _FakeService(withDirectory: withDirectory),
      queue: TransferQueue(),
    );
    await tester.pumpWidget(
      MaterialApp(home: RemoteStorageBrowserPage(account: testAccount())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
  }

  testWidgets('筛选条：三个条件都可选，选中后计数与条目都对（目录仍在）', (tester) async {
    await open(tester);

    // 默认三行都是"全部"，且没有横幅（没筛就不该有横幅）
    expect(find.text('类型：全部类型'), findsOneWidget);
    expect(find.text('大小：全部大小'), findsOneWidget);
    expect(find.text('时间：全部时间'), findsOneWidget);
    expect(find.textContaining('筛选出'), findsNothing);

    // 类型 = 图片 → 大图 + 小图 + 目录 = 3 / 35
    await tester.tap(find.text('类型：全部类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片'));
    await tester.pumpAndSettle();

    expect(find.text('类型：图片'), findsOneWidget);
    expect(find.textContaining('筛选出 3 / 35 项（图片）'), findsOneWidget,
        reason: '目录必须留下，否则没法往下走');
    expect(find.text('大图.png'), findsOneWidget);
    expect(find.text('电影.mp4'), findsNothing, reason: '视频不该留下');

    // 叠加大小 = 大于 100 MB → 只剩大图 + 目录 = 2 / 35
    await tester.tap(find.text('大小：全部大小'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('大于 100 MB'));
    await tester.pumpAndSettle();

    expect(find.textContaining('筛选出 2 / 35 项（图片 · 大于 100 MB）'), findsOneWidget);
    expect(find.text('小图.png'), findsNothing, reason: '小图不满足大小条件');

    // 一键清除：条件与结果都回到全量
    await tester.tap(find.text('清除'));
    await tester.pump();
    expect(find.text('类型：全部类型'), findsOneWidget);
    expect(find.textContaining('筛选出'), findsNothing);
  });

  testWidgets('时间条件：只留今天的；关掉搜索框后结构化条件仍然生效', (tester) async {
    await open(tester);

    await tester.tap(find.text('时间：全部时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();

    // 今天的：大图 + 电影 + 笔记 + 30 条填充 = 33，加目录 = 34 / 35
    expect(find.textContaining('筛选出 34 / 35 项（今天）'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search_off_rounded));
    await tester.pump();

    expect(find.textContaining('筛选出 34 / 35 项（今天）'), findsOneWidget,
        reason: '关搜索框只该收起名称条件，结构化筛选要继续生效');
  });

  testWidgets('筛空时的话术说清"是条件筛掉的"，并给清空入口', (tester) async {
    // 这个用例刻意用"没有目录"的目录：目录一律保留，有目录时筛选结果不会空。
    await open(tester, withDirectory: false);

    await tester.tap(find.text('类型：全部类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('音频'));
    await tester.pumpAndSettle();

    expect(find.textContaining('本目录没有符合「音频」的条目'), findsOneWidget);

    await tester.tap(find.text('清空筛选'));
    await tester.pump();

    expect(find.textContaining('本目录没有符合'), findsNothing);
    expect(find.text('类型：全部类型'), findsOneWidget);
  });
}
