import 'package:box/novel/pages/reader/reader_bookmark_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：loadForBook 的返回值必须可安全改动。
///
/// 缺陷：raw == null 与 catch 分支都 `return const []`，而调用方
/// `remove()` 直接 `bookmarks.removeWhere(...)` —— 对 const 列表做写操作
/// 抛 UnsupportedError。表现为对「没有任何书签的书」执行删除书签直接崩，
/// 以及书签 JSON 损坏后无法自愈（每次删除都炸）。
void main() {
  late SharedPreferencesReaderBookmarkService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = SharedPreferencesReaderBookmarkService(
      await SharedPreferences.getInstance(),
    );
  });

  test('对无书签的书调用 remove 不应抛异常（核心回归）', () async {
    await expectLater(
      service.remove('never-bookmarked', 'some-id'),
      completes,
    );
  });

  test('给一本从未有书签的书添加第一个书签不应抛异常（最常触发的路径）', () async {
    // add() 在 loadForBook 返回 const [] 时执行 bookmarks.add(...) → UnsupportedError
    await expectLater(service.add(_sample()), completion(isTrue));
    expect(service.loadForBook('b1'), hasLength(1));
  });

  test('loadForBook 空结果返回的列表可写', () {
    final list = service.loadForBook('never-bookmarked');
    // 这行在修复前抛 UnsupportedError
    expect(() => list.removeWhere((b) => true), returnsNormally);
  });

  test('JSON 损坏时返回的列表同样可写（catch 分支）', () async {
    SharedPreferences.setMockInitialValues({
      'bookmark_broken': '{not a json list',
    });
    final svc = SharedPreferencesReaderBookmarkService(
      await SharedPreferences.getInstance(),
    );

    final list = svc.loadForBook('broken');
    expect(list, isEmpty);
    expect(() => list.add(_sample()), returnsNormally,
        reason: '损坏数据不该让书签功能永久瘫痪');
    await expectLater(svc.remove('broken', 'x'), completes);
  });

  test('正常路径不受影响：加了再删能删掉', () async {
    final bm = _sample();
    expect(await service.add(bm), isTrue);
    expect(service.loadForBook('b1'), hasLength(1));

    await service.remove('b1', bm.id);
    expect(service.loadForBook('b1'), isEmpty);
  });

  test('重复书签不会被重复添加', () async {
    expect(await service.add(_sample()), isTrue);
    expect(await service.add(_sample()), isFalse,
        reason: '同章同位置的书签应判重');
    expect(service.loadForBook('b1'), hasLength(1));
  });
}

ReaderBookmark _sample() => ReaderBookmark(
      id: 'bm-1',
      bookId: 'b1',
      chapterIndex: 3,
      chapterTitle: '第三章',
      pageIndex: 5,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
