// 跨目录搜索复用目录快照（286 P4）。
//
// 关心三件事：
//   1. 有新鲜快照时**一个现场请求都不发**（这才是复用快照的意义）；
//   2. 超龄快照不采信（宁可慢，也不给用户看过时目录）；
//   3. 结果里带上"哪部分来自缓存、最旧多久"，界面才能诚实标注。
import 'dart:io';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/remote_storage_store.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

class _FakeStore extends RemoteStorageStore {
  final Map<String, DirSnapshot> snapshots = <String, DirSnapshot>{};
  final List<String> savedPaths = <String>[];

  String _key(String accountId, String path) => '$accountId|$path';

  void seed(String accountId, String path, List<RemoteStorageEntry> entries,
      {required DateTime at}) {
    snapshots[_key(accountId, path)] = DirSnapshot(entries: entries, at: at);
  }

  @override
  Future<DirSnapshot?> loadDirSnapshot(String accountId, String path) async =>
      snapshots[_key(accountId, path)];

  @override
  Future<void> saveDirSnapshot(
    String accountId,
    String path,
    List<RemoteStorageEntry> entries,
  ) async {
    savedPaths.add(path);
    seed(accountId, path, entries, at: DateTime.now());
  }

  @override
  Future<int> clearAccountSnapshots(String accountId) async => 0;
}

RemoteStorageEntry _file(String path) => RemoteStorageEntry(
      name: path.split('/').last,
      path: path,
      isDirectory: false,
      size: 10,
    );

RemoteStorageEntry _dir(String path) => RemoteStorageEntry(
      name: path.split('/').last,
      path: path,
      isDirectory: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;
  late FakeTransport transport;
  late _FakeStore store;
  late RemoteStorageService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    docsDir = Directory.systemTemp.createTempSync('rs_p4_');
    transport = FakeTransport();
    store = _FakeStore();
    service = RemoteStorageService(
      store: store,
      transportFactory: (_) => transport,
      docsDirProvider: () async => docsDir,
    );
  });

  tearDown(() {
    try {
      docsDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  void serve(Map<String, List<DavItem>> tree) {
    transport.handler = (request) async {
      final segments = request.uri.pathSegments;
      if (segments.isNotEmpty) {
        final items = tree[segments.last];
        if (items != null) return xmlResponse(propfindXml(items));
      }
      return xmlResponse(propfindXml(const <DavItem>[]));
    };
  }

  test('新鲜快照：一个现场请求都不发，并写明缓存条数', () async {
    final account = testAccount();
    store.seed(account.id, '相册', [
      _dir('相册/2021'),
      _file('相册/2021-08-07.jpg'),
    ], at: DateTime.now().subtract(const Duration(minutes: 12)));
    store.seed(account.id, '相册/2021', [
      _file('相册/2021/2021-09-01.jpg'),
    ], at: DateTime.now().subtract(const Duration(minutes: 12)));
    // 任何现场请求都会返回空树：只要结果有命中，就说明确实用了快照。
    serve(<String, List<DavItem>>{});

    final result = await service.searchSubtree(
      account,
      rootPath: '相册',
      query: '2021',
    );

    expect(transport.requests, isEmpty, reason: '有快照就不该再打网络');
    expect(
      result.entries.map((e) => e.name).toList()..sort(),
      <String>['2021', '2021-08-07.jpg', '2021-09-01.jpg'],
      reason: '快照里的子目录也要继续下探',
    );
    expect(result.snapshotDirs, 2);
    expect(result.fromSnapshot, isTrue);
    expect(result.oldestSnapshotAt, isNotNull);
    final note = result.snapshotNote(DateTime.now())!;
    expect(note, contains('2 个目录用了本地缓存'));
    expect(note, contains('12 分钟前'));
  });

  test('超龄快照（>1 小时）：不采信，重新现场列', () async {
    final account = testAccount();
    store.seed(account.id, '相册', [
      _file('相册/旧文件.jpg'),
    ], at: DateTime.now().subtract(const Duration(hours: 2)));
    serve(<String, List<DavItem>>{
      '相册': const [
        DavItem('/dav/相册/', isCollection: true),
        DavItem('/dav/相册/新文件.jpg', displayName: '新文件.jpg', size: 3),
      ],
    });

    final result = await service.searchSubtree(
      account,
      rootPath: '相册',
      query: '文件',
    );

    expect(result.fromSnapshot, isFalse);
    expect(result.snapshotDirs, 0);
    expect(result.snapshotNote(DateTime.now()), isNull);
    expect(result.entries.map((e) => e.name), <String>['新文件.jpg']);
    expect(transport.requests, isNotEmpty, reason: '过时了就得现场列');
  });

  test('useSnapshot: false：每个目录都现场列（用户点了"重新搜索"）', () async {
    final account = testAccount();
    store.seed(account.id, '相册', [
      _file('相册/旧文件.jpg'),
    ], at: DateTime.now());
    serve(<String, List<DavItem>>{
      '相册': const [
        DavItem('/dav/相册/', isCollection: true),
        DavItem('/dav/相册/新文件.jpg', displayName: '新文件.jpg', size: 3),
      ],
    });

    final result = await service.searchSubtree(
      account,
      rootPath: '相册',
      query: '文件',
      useSnapshot: false,
    );

    expect(transport.requests, isNotEmpty);
    expect(result.fromSnapshot, isFalse);
    expect(result.entries.map((e) => e.name), <String>['新文件.jpg']);
  });

  test('现场列过的目录会顺手存快照 → 下次搜索就能用上', () async {
    final account = testAccount();
    serve(<String, List<DavItem>>{
      '相册': const [
        DavItem('/dav/相册/', isCollection: true),
        DavItem('/dav/相册/a.jpg', displayName: 'a.jpg', size: 3),
      ],
    });

    await service.searchSubtree(account, rootPath: '相册', query: 'a');
    expect(store.savedPaths, contains('相册'));

    transport.requests.clear();
    final second = await service.searchSubtree(
      account,
      rootPath: '相册',
      query: 'a',
    );
    expect(transport.requests, isEmpty, reason: '第一次搜索留下的快照应该被复用');
    expect(second.fromSnapshot, isTrue);
  });

  test('搜索失败/没快照时行为不变：现场列，且结果与 D10 一致', () async {
    final account = testAccount();
    serve(<String, List<DavItem>>{
      '相册': const [
        DavItem('/dav/相册/', isCollection: true),
        DavItem('/dav/相册/2021-08-07.jpg', displayName: '2021-08-07.jpg', size: 5),
        DavItem('/dav/相册/@eaDir/', isCollection: true),
      ],
    });

    final result =
        await service.searchSubtree(account, rootPath: '相册', query: '2021');
    expect(result.entries.map((e) => e.name), <String>['2021-08-07.jpg']);
    expect(result.dirsScanned, 1);
    expect(result.fromSnapshot, isFalse);
  });
  group('snapshotNote：给界面用的缓存说明', () {
    SubtreeSearchResult result({
      required int snapshotDirs,
      required DateTime? oldest,
    }) =>
        SubtreeSearchResult(
          entries: const <RemoteStorageEntry>[],
          dirsScanned: 1,
          truncated: false,
          canceled: false,
          snapshotDirs: snapshotDirs,
          oldestSnapshotAt: oldest,
        );

    test('没用快照 / 时间未知 → 什么都不说', () {
      final now = DateTime(2026, 9, 25, 12);
      expect(result(snapshotDirs: 0, oldest: null).snapshotNote(now), isNull);
      expect(result(snapshotDirs: 3, oldest: null).snapshotNote(now), isNull,
          reason: '说有缓存却给不出时间，不如不说');
    });

    test('时间档位：刚刚 / 分钟 / 小时 / 天', () {
      final now = DateTime(2026, 9, 25, 12);
      String? note(Duration age) => result(
            snapshotDirs: 1,
            oldest: now.subtract(age),
          ).snapshotNote(now);
      expect(note(const Duration(seconds: 20)), contains('刚刚'));
      expect(note(const Duration(minutes: 12)), contains('12 分钟前'));
      expect(note(const Duration(minutes: 59)), contains('59 分钟前'));
      expect(note(const Duration(hours: 3)), contains('3 小时前'));
      expect(note(const Duration(days: 2)), contains('2 天前'));
    });

    test('文案里带上"刚新增的文件可能还没出现"——不让用户以为结果是实时的', () {
      final now = DateTime(2026, 9, 25, 12);
      final note = result(
        snapshotDirs: 2,
        oldest: now.subtract(const Duration(minutes: 5)),
      ).snapshotNote(now)!;
      expect(note, contains('2 个目录'));
      expect(note, contains('可能还没出现'));
    });
  });

}
