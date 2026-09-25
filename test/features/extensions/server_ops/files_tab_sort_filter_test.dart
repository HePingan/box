// 服务器运维插件：文件列表排序 / 过滤 / 多选批量删除的用例（A3）。
//
// 排序与过滤是纯函数（直接断言）；多选与批量删除走 widget 用例（假服务注入）。
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

class _FakeListService extends ServerOpsFilesService {
  _FakeListService({this.entries = const []}) : super(settings: _settings);

  List<RemoteStorageEntry> entries;
  final List<String> deleted = [];

  @override
  Future<List<RemoteStorageEntry>> list(String path) async => entries;

  @override
  Future<void> delete(String path) async => deleted.add(path);
}

Future<void> _pumpTab(WidgetTester tester, _FakeListService service) async {
  debugSetServerOpsRuntime(filesService: service);
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

  group('排序（纯函数，目录恒在前）', () {
    final entries = [
      RemoteStorageEntry(
        name: 'b.txt',
        path: 'b.txt',
        size: 200,
        isDirectory: false,
        modifiedAt: DateTime.utc(2026, 1, 2),
      ),
      RemoteStorageEntry(
        name: 'A.txt',
        path: 'A.txt',
        size: 300,
        isDirectory: false,
        modifiedAt: DateTime.utc(2026, 1, 3),
      ),
      RemoteStorageEntry(
        name: 'c.txt',
        path: 'c.txt',
        size: 100,
        isDirectory: false,
        modifiedAt: DateTime.utc(2026, 1, 1),
      ),
      const RemoteStorageEntry(name: 'zdir', path: 'zdir', isDirectory: true),
      const RemoteStorageEntry(name: 'adir', path: 'adir', isDirectory: true),
    ];

    test('名称档：目录恒在前，组内按名称升序', () {
      final sorted =
          ServerOpsFilesService.sortEntries(entries, OpsSortMode.name);
      expect(sorted.map((e) => e.name), ['adir', 'zdir', 'A.txt', 'b.txt', 'c.txt']);
    });

    test('名称档降序：目录仍在前，组内按名称降序', () {
      final sorted = ServerOpsFilesService.sortEntries(
        entries,
        OpsSortMode.name,
        descending: true,
      );
      expect(sorted.map((e) => e.name), ['zdir', 'adir', 'c.txt', 'b.txt', 'A.txt']);
    });

    test('大小档：小在前', () {
      final sorted =
          ServerOpsFilesService.sortEntries(entries, OpsSortMode.size);
      expect(sorted.map((e) => e.name), ['adir', 'zdir', 'c.txt', 'b.txt', 'A.txt']);
    });

    test('时间档：旧在前（缺失按 0 处理）', () {
      final sorted =
          ServerOpsFilesService.sortEntries(entries, OpsSortMode.time);
      // 目录没有时间 → 排在文件之前（目录恒在前），组内按时间。
      expect(sorted.map((e) => e.name), ['adir', 'zdir', 'c.txt', 'b.txt', 'A.txt']);
    });
  });

  group('过滤（纯函数）', () {
    const entries = [
      RemoteStorageEntry(name: 'Report.TXT', path: 'Report.TXT', isDirectory: false),
      RemoteStorageEntry(name: 'logs', path: 'logs', isDirectory: true),
      RemoteStorageEntry(name: 'conf.d', path: 'conf.d', isDirectory: true),
    ];

    test('大小写不敏感 + 子串匹配', () {
      expect(
        ServerOpsFilesService.filterEntries(entries, 'report').map((e) => e.name),
        ['Report.TXT'],
      );
      expect(
        ServerOpsFilesService.filterEntries(entries, 'LOGS').map((e) => e.name),
        ['logs'],
      );
      expect(
        ServerOpsFilesService.filterEntries(entries, '.d').map((e) => e.name),
        ['conf.d'],
      );
    });

    test('空/纯空格关键词返回原列表（不是空列表）', () {
      expect(ServerOpsFilesService.filterEntries(entries, ''), entries);
      expect(ServerOpsFilesService.filterEntries(entries, '   '), entries);
    });

    test('没有匹配时返回空列表', () {
      expect(ServerOpsFilesService.filterEntries(entries, 'zzz'), isEmpty);
    });
  });

  testWidgets('过滤框：只显示名称匹配的条目', (tester) async {
    final service = _FakeListService(
      entries: const [
        RemoteStorageEntry(name: 'notes.txt', path: 'notes.txt', size: 1, isDirectory: false),
        RemoteStorageEntry(name: 'app.log', path: 'app.log', size: 1, isDirectory: false),
        RemoteStorageEntry(name: 'etc', path: 'etc', isDirectory: true),
      ],
    );
    await _pumpTab(tester, service);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('app.log'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('ops-file-filter')), 'log');
    await tester.pump();

    expect(find.text('notes.txt'), findsNothing);
    expect(find.text('app.log'), findsOneWidget);
    expect(find.text('etc'), findsNothing);
  });

  testWidgets('排序菜单：切到"时间"档后列表重排', (tester) async {
    final service = _FakeListService(
      entries: [
        RemoteStorageEntry(
          name: 'old.txt',
          path: 'old.txt',
          size: 1,
          isDirectory: false,
          modifiedAt: DateTime.utc(2026, 1, 1),
        ),
        RemoteStorageEntry(
          name: 'new.txt',
          path: 'new.txt',
          size: 1,
          isDirectory: false,
          modifiedAt: DateTime.utc(2026, 6, 1),
        ),
      ],
    );
    await _pumpTab(tester, service);

    // 只读页面列表里的 ListTile（弹出菜单里也有 ListTile，要排除掉）。
    List<String> pageTitles() => tester
        .widgetList<ListTile>(
          find.descendant(
            of: find.byType(RefreshIndicator),
            matching: find.byType(ListTile),
          ),
        )
        .map((t) => (t.title as Text).data!)
        .toList();

    // 默认名称档：new 在 old 之前（n < o）。
    expect(pageTitles(), ['new.txt', 'old.txt']);

    await tester.tap(find.byTooltip('排序'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.ancestor(
        of: find.text('时间'),
        matching: find.byType(CheckedPopupMenuItem<OpsSortMode>),
      ),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(pageTitles(), ['old.txt', 'new.txt']);
  });

  testWidgets('长按进多选 → 全选 → 批量删除要二次确认（文案写不可恢复）', (tester) async {
    final service = _FakeListService(
      entries: const [
        RemoteStorageEntry(name: 'a.txt', path: 'a.txt', size: 1, isDirectory: false),
        RemoteStorageEntry(name: 'b.txt', path: 'b.txt', size: 1, isDirectory: false),
        RemoteStorageEntry(name: 'c.txt', path: 'c.txt', size: 1, isDirectory: false),
      ],
    );
    await _pumpTab(tester, service);

    await tester.longPress(find.widgetWithText(ListTile, 'a.txt'));
    await tester.pump();
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'b.txt'));
    await tester.pump();
    expect(find.text('已选 2 项'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.text('已选 3 项'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('将被删除，且无法恢复'), findsOneWidget);
    expect(service.deleted, isEmpty, reason: '还没确认，不能删');

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '删除'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.deleted, ['a.txt', 'b.txt', 'c.txt']);
    expect(find.textContaining('删除完成：共 3 项'), findsOneWidget);
    expect(find.text('已选 3 项'), findsNothing, reason: '删完退出多选');
  });

  testWidgets('多选删除的确认文案：含目录时写清"目录内所有内容将一并删除"', (tester) async {
    final service = _FakeListService(
      entries: const [
        RemoteStorageEntry(name: 'etc', path: 'etc', isDirectory: true),
        RemoteStorageEntry(name: 'a.txt', path: 'a.txt', size: 1, isDirectory: false),
      ],
    );
    await _pumpTab(tester, service);

    await tester.longPress(find.widgetWithText(ListTile, 'etc'));
    await tester.pump();
    await tester.tap(find.text('全选'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('目录内所有内容将一并删除'), findsOneWidget);
  });

  testWidgets('批量删除中间失败不打断整批（继续下一项）', (tester) async {
    final service = _FailingDeleteService(
      entries: const [
        RemoteStorageEntry(name: 'a.txt', path: 'a.txt', size: 1, isDirectory: false),
        RemoteStorageEntry(name: 'b.txt', path: 'b.txt', size: 1, isDirectory: false),
        RemoteStorageEntry(name: 'c.txt', path: 'c.txt', size: 1, isDirectory: false),
      ],
    );
    await _pumpTab(tester, service);

    await tester.longPress(find.widgetWithText(ListTile, 'a.txt'));
    await tester.pump();
    await tester.tap(find.text('全选'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '删除'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.attempted, ['a.txt', 'b.txt', 'c.txt']);
    expect(find.textContaining('失败 1 项'), findsOneWidget);
  });
}

class _FailingDeleteService extends _FakeListService {
  _FailingDeleteService({super.entries});

  final List<String> attempted = [];

  @override
  Future<void> delete(String path) async {
    attempted.add(path);
    if (path == 'b.txt') {
      throw const RemoteStorageException(
        RemoteStorageError.http,
        '服务器拒绝删除',
      );
    }
    deleted.add(path);
  }
}
