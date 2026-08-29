import 'package:box/novel/pages/reader/reader_bookmark_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A1：书签「空缓存」语义回归。
///
/// ReaderController.bookmarks 的实现是：
///   `_cachedBookmarks.isNotEmpty ? _cachedBookmarks : bookmarkService.loadForBook(...)`
/// 用 isNotEmpty 当缓存有效性判据 —— 「空」和「未加载」被混为一谈。
/// 删掉最后一条书签后 _cachedBookmarks 变空，getter 判定缓存无效并回落读磁盘，
/// 于是「刚删掉的最后一条书签又出现了」。
///
/// 本文件先在 service 层锁死删除的持久化语义（controller 层的乐观更新依赖它），
/// 再由 reader_controller_bookmark_test 覆盖 getter 本身。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesReaderBookmarkService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = SharedPreferencesReaderBookmarkService(
      await SharedPreferences.getInstance(),
    );
  });

  test('删掉唯一一条书签后，磁盘上必须真的是空', () async {
    final bm = _bm(id: 'only-one', chapterIndex: 1);
    expect(await service.add(bm), isTrue);

    await service.remove('b1', 'only-one');

    expect(
      service.loadForBook('b1'),
      isEmpty,
      reason: '若磁盘没清干净，controller 的空缓存回落读盘就会让书签复活',
    );
  });

  test('逐条删空：每一步磁盘状态都与预期一致', () async {
    for (var i = 0; i < 3; i++) {
      await service.add(_bm(id: 'bm-$i', chapterIndex: i));
    }
    expect(service.loadForBook('b1'), hasLength(3));

    // loadForBook 保持插入序，不排序
    await service.remove('b1', 'bm-1');
    expect(service.loadForBook('b1').map((b) => b.id), ['bm-0', 'bm-2']);

    await service.remove('b1', 'bm-0');
    expect(service.loadForBook('b1').map((b) => b.id), ['bm-2']);

    await service.remove('b1', 'bm-2');
    expect(service.loadForBook('b1'), isEmpty);
  });

  test('clear 之后 loadForBook 返回空且仍可写', () async {
    await service.add(_bm(id: 'x', chapterIndex: 0));
    await service.clear('b1');

    final after = service.loadForBook('b1');
    expect(after, isEmpty);
    // clear 走的是 prefs.remove → 之后 raw == null 分支，必须仍是可变列表
    expect(() => after.add(_bm(id: 'y', chapterIndex: 9)), returnsNormally);
  });

  test('删不存在的 id 是无操作，不影响其他书签', () async {
    await service.add(_bm(id: 'keep', chapterIndex: 0));

    await service.remove('b1', 'no-such-id');

    expect(service.loadForBook('b1').map((b) => b.id), ['keep']);
  });

  test('多本书互不干扰：删 A 书的书签不影响 B 书', () async {
    await service.add(_bm(id: 'a1', chapterIndex: 0, bookId: 'bookA'));
    await service.add(_bm(id: 'b1x', chapterIndex: 0, bookId: 'bookB'));

    await service.clear('bookA');

    expect(service.loadForBook('bookA'), isEmpty);
    expect(service.loadForBook('bookB'), hasLength(1));
  });

  test('loadAll 汇总多本书且按时间倒序', () async {
    await service.add(_bm(id: 'old', chapterIndex: 0, bookId: 'bookA', ms: 1000));
    await service.add(_bm(id: 'new', chapterIndex: 0, bookId: 'bookB', ms: 9000));

    final all = service.loadAll();
    expect(all.map((b) => b.id), ['new', 'old']);
  });

  test('同章不同页视为不同书签（pageIndex 参与判重）', () async {
    expect(await service.add(_bm(id: 'p1', chapterIndex: 5, pageIndex: 1)), isTrue);
    expect(await service.add(_bm(id: 'p2', chapterIndex: 5, pageIndex: 2)), isTrue);
    expect(
      await service.add(_bm(id: 'p2dup', chapterIndex: 5, pageIndex: 2)),
      isFalse,
      reason: '同章同页才算重复',
    );
    expect(service.loadForBook('b1'), hasLength(2));
  });
}

ReaderBookmark _bm({
  required String id,
  required int chapterIndex,
  String bookId = 'b1',
  int? pageIndex,
  int ms = 1700000000000,
}) =>
    ReaderBookmark(
      id: id,
      bookId: bookId,
      chapterIndex: chapterIndex,
      chapterTitle: '第${chapterIndex + 1}章',
      pageIndex: pageIndex,
      createdAt: DateTime.fromMillisecondsSinceEpoch(ms),
    );
