// 老版本导入的漫画：页文件还在不在。
//
// 背景（为什么要这个东西）：旧版解压落在**系统临时目录**，而 `ComicBook.pages`
// 记的是那些路径，属于长期引用。系统清临时目录之后，书架上的书还在、点开全是白页，
// 用户只会觉得"漫画坏了"。这里做的是启动时的一次体检：只看本地书、只探极少数页，
// 把"整本的页都没了"挑出来，交给上层去提示重新导入。
//
// 这一层刻意**不碰 UI、不弹窗、不改书**：它只回答"哪些书需要重新导入"。
// 为什么单独一个文件而不是塞进 ComicImporter：导入器依赖 archive / path_provider，
// 体检是纯判断，能脱离 Flutter 插件在单测里跑。
library;

import 'dart:io';

import 'package:box/core/storage/cache_store.dart';

import 'comic_book.dart';

/// 探一个路径是否存在。
///
/// 做成可注入的参数：单测里不该为了证明"页没了"去建真文件；真实运行时用
/// `File.exists()` 即可。
typedef ComicPageProbe = Future<bool> Function(String path);

/// 一次体检的结果。
///
/// 只有计数和书 id：这一层不知道该弹什么、弹几次，更不该替上层决定删书还是留书。
class ComicPageHealth {
  const ComicPageHealth({
    required this.total,
    required this.checked,
    required this.healthy,
    required this.missing,
    required this.missingBookIds,
  });

  /// 传进来的书总数。
  final int total;

  /// 真正被检查过的书数（本地书且 pages 非空）。
  final int checked;

  /// 页文件还在的书数。
  final int healthy;

  /// 页文件整本都没了的书数。
  final int missing;

  /// 需要重新导入的书 id（按传入顺序）。
  final List<String> missingBookIds;

  /// 没参与检查的书数。
  ///
  /// 两类：`online` 书页在站点上、本地根本没有文件；以及 pages 为空的本地书
  /// （没有页路径就无从判断，当成"没问题"比误报丢页安全）。
  int get skipped => total - checked;

  bool get hasMissing => missing > 0;

  bool isMissing(String bookId) => missingBookIds.contains(bookId);

  static const ComicPageHealth empty = ComicPageHealth(
    total: 0,
    checked: 0,
    healthy: 0,
    missing: 0,
    missingBookIds: <String>[],
  );
}

/// 体检器。
///
/// 采样而不是逐页检查，理由在 [samplePages] 上；探针可注入，采样数可注入。
class ComicPageHealthChecker {
  ComicPageHealthChecker({ComicPageProbe? probe, this.sampleCount = 3})
    : assert(sampleCount > 0, '至少探一页，否则永远判成"页没了"'),
      _probe = probe ?? _fileExists;

  /// 默认探针：真实文件系统。
  static Future<bool> _fileExists(String path) => File(path).exists();

  final ComicPageProbe _probe;

  /// 每本书最多探几页。
  final int sampleCount;

  Future<ComicPageHealth> check(List<ComicBook> books) async {
    final missingIds = <String>[];
    var checked = 0;
    var healthy = 0;

    for (final book in books) {
      // 在线书的页是读的时候现取的，本机没有对应文件，参与检查只会制造误报。
      if (book.sourceType == ComicSourceType.online) continue;

      final pages = book.pages
          .where((page) => page.isNotEmpty)
          .toList(growable: false);
      // 没有页路径就无从判断：老版本本身就没记页的书不该被催"重新导入"。
      if (pages.isEmpty) continue;

      checked++;
      if (await _anyPageAlive(pages)) {
        healthy++;
      } else {
        missingIds.add(book.id);
      }
    }

    return ComicPageHealth(
      total: books.length,
      checked: checked,
      healthy: healthy,
      missing: missingIds.length,
      missingBookIds: List<String>.unmodifiable(missingIds),
    );
  }

  /// 抽头 / 中 / 尾去探。
  ///
  /// 为什么采样就够：`ComicImporter.extract` 给**一本书只建一个目录**，所有页文件
  /// 都在同一个目录里下。系统清临时目录是整目录一起没的，不存在"第 7 页被单独删掉
  /// 而别的页还在"这种正常路径；所以头尾各探一页就足以区分"目录还在"和"目录没了"，
  /// 中间再补一页兜住目录被部分清理/迁移中途失败的少数情况。
  ///
  /// 为什么必须采样：一本 1000 页、书架 200 本，逐页探就是 20 万次 stat，
  /// 即便全是异步 IO，排队和回调开销也足够让启动多出一段可见的卡顿；而结果与探
  /// 3 页完全一致。采样是**有依据的省略**，不是偷懒。
  List<String> samplePages(List<String> pages) {
    if (pages.length <= sampleCount) return List<String>.of(pages);
    // 只探一页时上面的分支已经返回，这里 sampleCount >= 2，插值不会除以 0。
    if (sampleCount == 1) return <String>[pages.first];

    final lastIndex = pages.length - 1;
    final picked = <String>{};
    for (var i = 0; i < sampleCount; i++) {
      final index = (lastIndex * i / (sampleCount - 1)).round();
      picked.add(pages[index]);
    }
    return picked.toList(growable: false);
  }

  /// 抽到的页里只要有**任意一页**还在，就说明书的页目录还在。
  ///
  /// 为什么不要求"全部命中"：判定为 missing 会催用户重新导入一整本书，代价很高；
  /// 只要还有一页能读，就不该把他往"你的书丢了"那条路上推。
  Future<bool> _anyPageAlive(List<String> pages) async {
    for (final path in samplePages(pages)) {
      final bool exists;
      try {
        exists = await _probe(path);
      } catch (_) {
        // 探不动不等于文件没了（路径异常、权限问题都可能）。这种情况按"还在"处理：
        // 宁可漏报一次，也不要把用户好好的书报成丢页。
        return true;
      }
      if (exists) return true;
    }
    return false;
  }
}

/// 便捷入口：不关心采样细节的调用方用这个。
///
/// 书多的时候可以自己 `ComicPageHealthChecker(sampleCount: ...).check(...)`。
Future<ComicPageHealth> checkComicPageHealth(List<ComicBook> books) =>
    ComicPageHealthChecker().check(books);

/// 「这些书已经提醒过用户了」的持久化。
///
/// 为什么需要它：体检每次启动都会做（用户可能这次不处理、下次再启动），
/// 不记的话每次开 App 都弹一遍同一批书，那就从"提醒"变成了"骚扰"。
/// 记在 CacheStore 里而不是书对象上：这是**这台设备上弹过没有**的状态，
/// 不是书的属性；写进 ComicBook 还得改序列化、还得跟云备份兼容。
class ComicPageHealthNoticeStore {
  ComicPageHealthNoticeStore({CacheStore? cacheStore})
    : _cache = cacheStore ?? CacheStore(namespace: 'comic_page_health');

  final CacheStore _cache;

  static const String _keyNotified = 'notified_ids';

  /// 已提醒过的书 id。
  ///
  /// 存储被写坏 / 类型不对时返回空集合：宁可多提醒一次，也不要因为一条脏数据
  /// 让"书丢了"这件事永远不被说出来。
  Future<Set<String>> notifiedIds() async {
    final raw = await _cache.read(_keyNotified);
    if (raw is! List) return <String>{};

    return <String>{
      for (final item in raw)
        if (item is String && item.isNotEmpty) item,
    };
  }

  /// 记下这批书已经提醒过了。空集合直接返回，避免无意义的一次写盘。
  Future<void> markNotified(Iterable<String> bookIds) async {
    final added = bookIds.where((id) => id.isNotEmpty).toSet();
    if (added.isEmpty) return;

    final current = await notifiedIds();
    current.addAll(added);
    await _write(current);
  }

  /// 只保留仍然缺页的书 id。
  ///
  /// 书被删掉、或者用户重新导入修好了，旧 id 留着没有意义；不收敛的话集合只增不减，
  /// 每本书都要多读一截再也用不上的字符串。
  Future<void> retainOnly(Iterable<String> liveBookIds) async {
    final current = await notifiedIds();
    final kept = current.intersection(liveBookIds.toSet());
    if (kept.length == current.length) return;
    await _write(kept);
  }

  /// 这次启动真正该提示的书：缺页、而且没提示过。
  Future<List<String>> pendingForNotice(ComicPageHealth health) async {
    if (!health.hasMissing) return const <String>[];
    final notified = await notifiedIds();
    return health.missingBookIds
        .where((id) => !notified.contains(id))
        .toList(growable: false);
  }

  Future<void> clear() => _cache.remove(_keyNotified);

  Future<void> _write(Set<String> ids) =>
      _cache.write(_keyNotified, ids.toList(growable: false));
}
