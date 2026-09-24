// Widget 测试（离线，注入假 service）：
// - 浏览页排序：默认「修改时间 新在前」、切换名称/大小、目录恒在前、
//   时间/大小缺失兜底、当前排序打勾、会话内保持。
// - 浏览页滚动位置恢复：离开子目录再进入恢复偏移。
// - 排序纯函数：目录优先、稳定性（同键保持相对顺序）。

import 'dart:convert';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/remote_storage_store.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/remote_storage_browser_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// 假服务：按目录返回条目（覆盖「进出目录」场景）。
class _FakeService extends RemoteStorageService {
  _FakeService(this.entriesByPath);

  final Map<String, List<RemoteStorageEntry>> entriesByPath;

  @override
  Future<List<RemoteStorageEntry>> list(
    RemoteStorageAccount account,
    String path, {
    bool forceRefresh = false,
  }) async {
    return entriesByPath[path] ?? const <RemoteStorageEntry>[];
  }

  /// 覆写配额：本文件不测上传，只为避免误走真实传输层。
  @override
  Future<RemoteStorageQuota> quota(
    RemoteStorageAccount account, {
    String path = '',
  }) async {
    return const RemoteStorageQuota();
  }
}

RemoteStorageEntry _file(String name, {int? size, DateTime? modifiedAt}) {
  return RemoteStorageEntry(
    name: name,
    path: name,
    isDirectory: false,
    size: size,
    modifiedAt: modifiedAt,
  );
}

RemoteStorageEntry _dir(String name, {int? size, DateTime? modifiedAt}) {
  return RemoteStorageEntry(
    name: name,
    path: name,
    isDirectory: true,
    size: size,
    modifiedAt: modifiedAt,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugResetRemoteStorageBrowserSessionState();
  });

  Future<void> pumpBrowser(
    WidgetTester tester,
    _FakeService service, {
    String initialPath = '',
  }) async {
    debugSetRemoteStorageRuntime(service: service);
    await tester.pumpWidget(
      MaterialApp(
        home: RemoteStorageBrowserPage(
          account: testAccount(),
          initialPath: initialPath,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 当前列表里的条目名（顺序 = 渲染顺序；仅取可见项）。
  List<String> listItems(WidgetTester tester) {
    return tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data!)
        .toList(growable: false);
  }

  Future<void> openSortMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pumpAndSettle();
  }

  Future<void> closeSortMenu(WidgetTester tester) async {
    await tester.tapAt(const Offset(4, 200)); // 点菜单外 → 关闭
    await tester.pumpAndSettle();
  }

  Future<void> chooseSort(WidgetTester tester, String label) async {
    await openSortMenu(tester);
    await tester.tap(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(CheckedPopupMenuItem<RemoteStorageSortField>),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 排序菜单三项的勾选状态（顺序 = 枚举声明序：名称 / 修改时间 / 大小）。
  List<bool> checkedFlags(WidgetTester tester) {
    return tester
        .widgetList<CheckedPopupMenuItem<RemoteStorageSortField>>(
          find.byType(CheckedPopupMenuItem<RemoteStorageSortField>),
        )
        .map((item) => item.checked)
        .toList(growable: false);
  }

  /// 最上层（当前可见）浏览页的目录列表。
  ///
  /// 子目录 route 压在父 route 之上时，父级列表可能仍在树上，
  /// 故按「不含父级独有条目 root.txt」筛选。
  Finder visibleList(WidgetTester tester) {
    final elements = find.byType(ListView).evaluate().toList();
    expect(elements, isNotEmpty, reason: '未找到目录列表');
    for (final element in elements) {
      final candidate = find.byElementPredicate((e) => identical(e, element));
      final isParent = find
          .descendant(of: candidate, matching: find.text('root.txt'))
          .evaluate()
          .isNotEmpty;
      if (!isParent) return candidate;
    }
    fail('未找到最上层浏览页的列表');
  }

  group('排序纯函数', () {
    test('字段缺失 → 名称升序兜底，且与输入顺序无关', () {
      final input = <RemoteStorageEntry>[
        _file('b.txt', size: 10),
        _file('a.txt', size: 10),
      ];
      final output = sortedRemoteStorageEntries(
        input,
        RemoteStorageSortField.modifiedTime,
      );
      expect(
        output.map((e) => e.name).toList(),
        <String>['a.txt', 'b.txt'],
        reason: '时间全缺失 → 名称升序',
      );
    });

    test('目录恒在前，目录之间同样按所选字段', () {
      final input = <RemoteStorageEntry>[
        _file('a.txt', size: 1, modifiedAt: DateTime(2024, 6, 1)),
        _dir('zz-dir', modifiedAt: DateTime(2024, 1, 1)),
        _dir('aa-dir', modifiedAt: DateTime(2024, 5, 1)),
      ];
      final byTime = sortedRemoteStorageEntries(
        input,
        RemoteStorageSortField.modifiedTime,
      );
      expect(
        byTime.map((e) => e.name).toList(),
        <String>['aa-dir', 'zz-dir', 'a.txt'],
        reason: '目录在前，且目录之间按修改时间新在前',
      );
    });

    test('排序幂等：重复排序结果不变（稳定）', () {
      final input = <RemoteStorageEntry>[
        _dir('docs', modifiedAt: DateTime(2024, 5, 1)),
        _dir('pics'),
        _file('a.txt', size: 5, modifiedAt: DateTime(2024, 1, 1)),
        _file('b.txt'),
        _file('c.txt', size: 5, modifiedAt: DateTime(2024, 1, 1)),
      ];
      for (final field in RemoteStorageSortField.values) {
        final once = sortedRemoteStorageEntries(input, field);
        final twice = sortedRemoteStorageEntries(once, field);
        expect(
          twice.map((e) => e.name).toList(),
          once.map((e) => e.name).toList(),
          reason: '再次排序不应改变顺序（$field）',
        );
      }
    });
  });

  group('浏览页排序', () {
    // 输入为 client 基准序：目录在前（名称升序）→ 文件（名称升序）。
    List<RemoteStorageEntry> mixedEntries() {
      return <RemoteStorageEntry>[
        _dir('aa-dir', modifiedAt: DateTime(2024, 1, 1)),
        _dir('zz-dir', modifiedAt: DateTime(2024, 5, 1)),
        _file('mid.txt', size: 300, modifiedAt: DateTime(2024, 3, 1)),
        _file('newest.txt', size: 100, modifiedAt: DateTime(2024, 6, 1)),
        _file('nodate.txt', size: 200),
        _file('nosize.txt', modifiedAt: DateTime(2024, 4, 1)),
      ];
    }

    testWidgets('默认：目录在前 + 修改时间新在前（缺失排最后）', (tester) async {
      await pumpBrowser(
        tester,
        _FakeService(<String, List<RemoteStorageEntry>>{'': mixedEntries()}),
      );

      expect(listItems(tester), <String>[
        'zz-dir',
        'aa-dir',
        'newest.txt',
        'nosize.txt',
        'mid.txt',
        'nodate.txt',
      ]);

      await openSortMenu(tester);
      expect(checkedFlags(tester), <bool>[false, true, false], reason: '默认项打勾');
      await closeSortMenu(tester);
      expect(
        tester.widget<PopupMenuButton<RemoteStorageSortField>>(
          find.byType(PopupMenuButton<RemoteStorageSortField>),
        ).tooltip,
        '排序',
      );
    });

    testWidgets('切换名称 → 名称升序（目录仍在前）', (tester) async {
      await pumpBrowser(
        tester,
        _FakeService(<String, List<RemoteStorageEntry>>{'': mixedEntries()}),
      );

      await chooseSort(tester, '名称');
      expect(listItems(tester), <String>[
        'aa-dir',
        'zz-dir',
        'mid.txt',
        'newest.txt',
        'nodate.txt',
        'nosize.txt',
      ]);

      await openSortMenu(tester);
      expect(checkedFlags(tester), <bool>[true, false, false]);
      await closeSortMenu(tester);
    });

    testWidgets('切换大小 → 大在前（缺失排最后，目录仍在前）', (tester) async {
      await pumpBrowser(
        tester,
        _FakeService(<String, List<RemoteStorageEntry>>{'': mixedEntries()}),
      );

      await chooseSort(tester, '大小（大在前）');
      expect(listItems(tester), <String>[
        'aa-dir',
        'zz-dir',
        'mid.txt',
        'nodate.txt',
        'newest.txt',
        'nosize.txt',
      ]);

      await openSortMenu(tester);
      expect(checkedFlags(tester), <bool>[false, false, true]);
      await closeSortMenu(tester);
    });

    testWidgets('切换回修改时间 → 恢复默认顺序', (tester) async {
      await pumpBrowser(
        tester,
        _FakeService(<String, List<RemoteStorageEntry>>{'': mixedEntries()}),
      );

      await chooseSort(tester, '名称');
      await chooseSort(tester, '修改时间（新在前）');
      expect(listItems(tester), <String>[
        'zz-dir',
        'aa-dir',
        'newest.txt',
        'nosize.txt',
        'mid.txt',
        'nodate.txt',
      ]);
    });

    testWidgets('会话内保持：进入子目录仍用已选排序', (tester) async {
      final service = _FakeService(<String, List<RemoteStorageEntry>>{
        '': <RemoteStorageEntry>[_dir('sub', modifiedAt: DateTime(2024, 1, 1))],
        'sub': <RemoteStorageEntry>[
          // 基准序（名称升序）：a.txt, b.txt；按时间/大小则相反。
          _file('a.txt', size: 50, modifiedAt: DateTime(2024, 1, 1)),
          _file('b.txt', size: 100, modifiedAt: DateTime(2024, 6, 1)),
        ],
      });
      await pumpBrowser(tester, service);

      await chooseSort(tester, '名称');
      await tester.tap(find.text('sub'));
      await tester.pumpAndSettle();

      expect(find.text('b.txt'), findsOneWidget);
      expect(listItems(tester), <String>['a.txt', 'b.txt'], reason: '沿用会话排序');
      // 新 route 里菜单仍显示「名称」为当前项。
      await openSortMenu(tester);
      expect(checkedFlags(tester), <bool>[true, false, false]);
      await closeSortMenu(tester);
    });
  });

  group('浏览页滚动位置恢复', () {
    testWidgets('离开子目录再进入 → 恢复滚动位置', (tester) async {
      final longList = <RemoteStorageEntry>[
        for (var i = 1; i <= 40; i++)
          _file(
            'sub-${i.toString().padLeft(2, '0')}.txt',
            size: i * 10,
            modifiedAt: DateTime(2024, 1, 1),
          ),
      ];
      final service = _FakeService(<String, List<RemoteStorageEntry>>{
        '': <RemoteStorageEntry>[
          _dir('sub', modifiedAt: DateTime(2024, 1, 1)),
          _file('root.txt', size: 1, modifiedAt: DateTime(2024, 1, 1)),
        ],
        'sub': longList,
      });
      await pumpBrowser(tester, service);

      // 进入子目录
      await tester.tap(find.text('sub'));
      await tester.pumpAndSettle();
      final controller =
          tester.widget<ListView>(visibleList(tester)).controller!;
      expect(controller.offset, 0);

      // 滚动一段
      await tester.drag(visibleList(tester), const Offset(0, -400));
      await tester.pumpAndSettle();
      final scrolled = controller.offset;
      expect(scrolled, greaterThan(100));

      // 返回上级：父级列表位置仍在（状态未销毁）
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('root.txt'), findsOneWidget);

      // 再次进入（新 route）→ 恢复上次位置
      await tester.tap(find.text('sub'));
      await tester.pumpAndSettle();
      final restored =
          tester.widget<ListView>(visibleList(tester)).controller!.offset;
      expect(restored, closeTo(scrolled, 1));
      expect(
        find.text('sub-01.txt').hitTestable(),
        findsNothing,
        reason: '已滚动离开顶部',
      );
    });

    testWidgets('首次进入目录 → 从顶部开始', (tester) async {
      final service = _FakeService(<String, List<RemoteStorageEntry>>{
        '': <RemoteStorageEntry>[_dir('fresh')],
        'fresh': <RemoteStorageEntry>[
          for (var i = 1; i <= 40; i++)
            _file('f-${i.toString().padLeft(2, '0')}.txt', size: i),
        ],
      });
      await pumpBrowser(tester, service);

      await tester.tap(find.text('fresh'));
      await tester.pumpAndSettle();

      final controller =
          tester.widget<ListView>(visibleList(tester)).controller!;
      expect(controller.offset, 0);
      expect(find.text('f-01.txt'), findsOneWidget);
    });
  });

  group('本地搜索（C3）', () {
    _FakeService bigDir() => _FakeService({
      '': [
        for (var i = 0; i < 40; i++)
          _file('file${i.toString().padLeft(2, '0')}.TXT'),
        _file('报告 2024 年度.pdf'),
      ],
    });

    testWidgets('小目录不显示搜索入口（不打扰）', (tester) async {
      await pumpBrowser(
        tester,
        _FakeService({
          '': [_file('a.txt'), _file('b.txt')],
        }),
      );
      expect(find.byIcon(Icons.search_rounded), findsNothing);
    });

    testWidgets('条目多时给出搜索入口', (tester) async {
      await pumpBrowser(tester, bigDir());
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('输入即本地过滤：大小写不敏感、多词是"与"关系', (tester) async {
      await pumpBrowser(tester, bigDir());

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'FILE39');
      await tester.pumpAndSettle();
      expect(listItems(tester), ['file39.TXT']);

      // 多词：两个词都要命中（'报告' + '2024'）
      await tester.enterText(find.byType(TextField), '报告 2024');
      await tester.pumpAndSettle();
      expect(listItems(tester), ['报告 2024 年度.pdf']);

      // 任一词不命中 → 空
      await tester.enterText(find.byType(TextField), '报告 1999');
      await tester.pumpAndSettle();
      expect(listItems(tester), isEmpty);
    });

    testWidgets('筛选时给出计数，筛空时给「清空筛选」而不是「空目录」', (tester) async {
      await pumpBrowser(tester, bigDir());
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'file3');
      await tester.pumpAndSettle();
      expect(find.textContaining('筛选出'), findsOneWidget);
      expect(find.textContaining('41'), findsOneWidget); // 总数仍是整目录

      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pumpAndSettle();
      expect(find.text('空目录'), findsNothing);
      expect(find.textContaining('没有匹配'), findsOneWidget);

      await tester.tap(find.text('清空筛选'));
      await tester.pumpAndSettle();
      expect(listItems(tester).length, greaterThan(0));
    });

    testWidgets('筛选后进入多选：全选只作用于筛选出来的条目', (tester) async {
      await pumpBrowser(tester, bigDir());
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'file3');
      await tester.pumpAndSettle(); // file30…file39 = 10 项

      await tester.longPress(find.text('file30.TXT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();

      expect(find.text('已选 10 项'), findsOneWidget);
    });

    test('纯函数：空白查询原样返回（连列表都不重建）', () {
      final entries = [_file('a.txt')];
      expect(identical(filterRemoteEntries(entries, '   '), entries), isTrue);
      expect(identical(filterRemoteEntries(entries, ''), entries), isTrue);
      expect(filterRemoteEntries(entries, 'A.TXT').single.name, 'a.txt');
      expect(filterRemoteEntries(entries, 'b'), isEmpty);
    });
  });

  group('偏好持久化（283 D2）', () {
    List<RemoteStorageEntry> sizedFiles() => <RemoteStorageEntry>[
      _file('a.txt', size: 100, modifiedAt: DateTime(2024, 1, 1)),
      _file('b.txt', size: 300, modifiedAt: DateTime(2024, 2, 1)),
      _file('c.txt', size: 200, modifiedAt: DateTime(2024, 3, 1)),
    ];

    List<RemoteStorageEntry> longList() => <RemoteStorageEntry>[
      for (var i = 1; i <= 40; i++) _file('f-${i.toString().padLeft(2, '0')}.txt', size: i),
    ];

    testWidgets('切换排序 → 落盘（以前只活在进程里）', (tester) async {
      await pumpBrowser(tester, _FakeService({'': sizedFiles()}));

      await chooseSort(tester, '大小（大在前）');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(RemoteStorageStore.browserSortFieldKey),
        'size',
        reason: '排序选择要写进磁盘',
      );
      expect(
        listItems(tester).take(3).toList(),
        <String>['b.txt', 'c.txt', 'a.txt'],
        reason: '当场也要按新排序显示',
      );
    });

    testWidgets('冷启动按磁盘上的排序渲染（不用再手动切一次）', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RemoteStorageStore.browserSortFieldKey: 'size',
      });

      await pumpBrowser(tester, _FakeService({'': sizedFiles()}));

      expect(
        listItems(tester).take(3).toList(),
        <String>['b.txt', 'c.txt', 'a.txt'],
        reason: '读盘后要按大小排（默认是按修改时间）',
      );
      await openSortMenu(tester);
      expect(checkedFlags(tester), <bool>[false, false, true]);
    });

    testWidgets('磁盘上的排序名不认识（旧数据/手改）→ 退回默认，不崩', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RemoteStorageStore.browserSortFieldKey: 'nonsense',
      });

      await pumpBrowser(tester, _FakeService({'': sizedFiles()}));

      expect(
        listItems(tester).take(3).toList(),
        <String>['c.txt', 'b.txt', 'a.txt'],
        reason: '退回默认「修改时间 新在前」',
      );
      await openSortMenu(tester);
      expect(checkedFlags(tester), <bool>[false, true, false]);
    });

    testWidgets('滚动位置落盘（防抖后写盘，键含账户+目录）', (tester) async {
      await pumpBrowser(tester, _FakeService({'': longList()}));

      await tester.drag(visibleList(tester), const Offset(0, -400));
      await tester.pumpAndSettle();
      final scrolled =
          tester.widget<ListView>(visibleList(tester)).controller!.offset;
      expect(scrolled, greaterThan(100));

      await tester.pump(const Duration(seconds: 1)); // 越过 800ms 防抖

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(RemoteStorageStore.browserScrollOffsetsKey);
      expect(raw, isNotNull, reason: '滚动位置应当落盘');
      final saved = (jsonDecode(raw!) as Map)['rs_test\u0000'];
      expect((saved! as num).toDouble(), closeTo(scrolled, 1));
    });

    testWidgets('冷启动恢复：磁盘上有位置 → 进目录直接回到那里', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RemoteStorageStore.browserScrollOffsetsKey: jsonEncode(
          <String, double>{'rs_test\u0000': 300},
        ),
      });

      await pumpBrowser(tester, _FakeService({'': longList()}));

      final controller =
          tester.widget<ListView>(visibleList(tester)).controller!;
      expect(controller.offset, closeTo(300, 1), reason: '从磁盘恢复偏移');
      expect(find.text('f-01.txt').hitTestable(), findsNothing);
    });

    testWidgets('磁盘上的滚动位置是坏数据 → 从顶部开始，不崩', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RemoteStorageStore.browserScrollOffsetsKey: '{坏 JSON',
      });

      await pumpBrowser(tester, _FakeService({'': longList()}));

      final controller =
          tester.widget<ListView>(visibleList(tester)).controller!;
      expect(controller.offset, 0);

      // 走到"坏数据"分支会写一条 debug 日志，AppLogger 有 250ms 防抖落盘定时器；
      // 不把它跑完，测试框架会判定"widget 树销毁后仍有未完成定时器"而失败。
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
