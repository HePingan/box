// 离线漫画：用户主动"下载到本机"的漫画，落到**持久目录**里，断网也能读。
//
// 为什么不复用图片缓存那条路（`ComicImageCache` 落在系统临时目录）：
//   * 系统清缓存 / 用户清"漫画图片缓存"会把它一起清掉；
//   * 我们自己按 300MB / 4000 张的上限**按最旧的先删** —— 用户主动下的一整本漫画
//     被当成"最旧的缓存"删掉，是"离线"这两个字最不能接受的失败。
// 所以离线内容单独一棵目录 + 单独一份清单，那套上限与清理**不碰它**。
//
// 布局（都能从清单里重建，清单是关键）：
//   <appSupport>/comic_offline/<书哈希>/<话哈希>/<图哈希>          图片本体
//   <appSupport>/comic_offline/manifest/<书哈希>.json              一本书一份清单
//
// 清单同时是**断网时的元数据来源**：书名、封面、章节目录都存进去，所以断网进详情页
// 还能列出已经下好的话（不然"能读"只对记得地址的人成立）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// 一话的下载状态。
enum ComicOfflineState {
  /// 还没下（清单里只有目录信息）。
  none,

  /// 正在下（中断后重启会从这里继续）。
  running,

  /// 下完了：图片齐了（`done == images.length`）。
  done,

  /// 用户暂停。
  paused,

  /// 失败（`error` 里写了原因，重试就是把它改回 running）。
  failed,
}

/// 清单里的一话。
class ComicOfflineChapter {
  ComicOfflineChapter({
    required this.url,
    required this.title,
    List<String> images = const <String>[],
    this.done = 0,
    this.bytes = 0,
    this.state = ComicOfflineState.none,
    this.error = '',
  }) : images = List<String>.from(images);

  final String url;
  final String title;

  /// 这一话的图片地址（按顺序）。断网时靠它把阅读页排出来。
  final List<String> images;

  /// 已经落盘的张数（**下载进度就靠它**：中断后从这张接着下）。
  int done;

  /// 已占字节。
  int bytes;

  ComicOfflineState state;

  /// 失败原因（给人看的原话，来自图片下载那条路）。
  String error;

  bool get isDone => images.isNotEmpty && done >= images.length;

  int get total => images.length;

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'images': images,
    'done': done,
    'bytes': bytes,
    'state': state.name,
    'error': error,
  };

  static ComicOfflineChapter fromJson(Map<String, dynamic> m) => ComicOfflineChapter(
    url: '${m['url'] ?? ''}',
    title: '${m['title'] ?? ''}',
    images: (m['images'] as List?)?.map((e) => '$e').toList() ?? const <String>[],
    done: (m['done'] as num?)?.toInt() ?? 0,
    bytes: (m['bytes'] as num?)?.toInt() ?? 0,
    state: ComicOfflineState.values.firstWhere(
      (s) => s.name == m['state'],
      orElse: () => ComicOfflineState.none,
    ),
    error: '${m['error'] ?? ''}',
  );
}

/// 一本书的离线清单。
class ComicOfflineBook {
  ComicOfflineBook({
    required this.bookUrl,
    this.title = '',
    this.cover = '',
    List<ComicOfflineChapter> chapters = const <ComicOfflineChapter>[],
    DateTime? updatedAt,
  }) : chapters = List<ComicOfflineChapter>.from(chapters),
       updatedAt = updatedAt ?? DateTime.now();

  final String bookUrl;
  String title;
  String cover;
  final List<ComicOfflineChapter> chapters;
  DateTime updatedAt;

  /// 已经下完的那几话（断网时详情页只列这些也行）。
  List<ComicOfflineChapter> get doneChapters =>
      chapters.where((c) => c.isDone).toList();

  int get doneCount => doneChapters.length;

  int get bytes => chapters.fold<int>(0, (a, c) => a + c.bytes);

  Map<String, dynamic> toJson() => {
    'bookUrl': bookUrl,
    'title': title,
    'cover': cover,
    'updatedAt': updatedAt.toIso8601String(),
    'chapters': chapters.map((c) => c.toJson()).toList(),
  };

  static ComicOfflineBook fromJson(Map<String, dynamic> m) => ComicOfflineBook(
    bookUrl: '${m['bookUrl'] ?? ''}',
    title: '${m['title'] ?? ''}',
    cover: '${m['cover'] ?? ''}',
    chapters: (m['chapters'] as List?)
            ?.whereType<Map>()
            .map((e) => ComicOfflineChapter.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const <ComicOfflineChapter>[],
    updatedAt: DateTime.tryParse('${m['updatedAt'] ?? ''}') ?? DateTime.now(),
  );
}

/// 离线库：目录布局 + 清单读写 + 统计与删除。
///
/// 只做**存储**，不认识网络：下载由 `ComicOfflineDownloader` 驱动（它把图片交回这里落盘）。
class ComicOfflineStore {
  ComicOfflineStore({
    Future<Directory> Function()? dirProvider,
  }) : _dirProvider = dirProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _dirProvider;
  Directory? _root;

  /// 已经解析出来的根目录（还没解析过就是 null）。**同步**，见 [localFileIfReady]。
  Directory? get readyRoot => _root;

  /// 预热：把根目录解析一次（平台调用只做一次，之后就都是纯路径计算）。
  ///
  /// 为什么要它：`getApplicationSupportDirectory()` 是**平台通道往返**，而封面/阅读页
  /// 的取图路径上不该出现"每张图等一次平台调用"。预热之后用 [localFileIfReady] 同步问。
  Future<void> warmUp() async {
    try {
      await rootDir();
    } catch (_) {
      // 拿不到目录（没有平台实现/存储异常）就当没预热：界面会照旧走网络那条路。
      // **必须吞掉**：预热是加速用的，它把界面弄崩是最亏的。
    }
  }

  /// 根目录：`<appSupport>/comic_offline`。
  Future<Directory> rootDir() async {
    final cached = _root;
    if (cached != null) return cached;
    final base = await _dirProvider();
    final dir = Directory('${base.path}/comic_offline');
    if (!await dir.exists()) await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  /// 一本书的目录（书哈希）。
  Future<Directory> bookDir(String bookUrl) async {
    final root = await rootDir();
    final dir = Directory('${root.path}/${hash(bookUrl)}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 一话的目录（书哈希/话哈希）。
  Future<Directory> chapterDir(String bookUrl, String chapterUrl) async {
    final book = await bookDir(bookUrl);
    final dir = Directory('${book.path}/${hash(chapterUrl)}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 这张图在本机的文件（**用地址的哈希当文件名**：地址里带 `:` `/` `?`，不能直接当路径）。
  Future<File> fileFor(String bookUrl, String chapterUrl, String imageUrl) async {
    final dir = await chapterDir(bookUrl, chapterUrl);
    return File('${dir.path}/${hash(imageUrl)}');
  }

  static String hash(String value) =>
      sha1.convert(utf8.encode(value)).toString();

  // ── 清单 ──────────────────────────────────────────────────────

  Future<Directory> _manifestDir() async {
    final root = await rootDir();
    final dir = Directory('${root.path}/manifest');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _manifestFile(String bookUrl) async =>
      File('${(await _manifestDir()).path}/${hash(bookUrl)}.json');

  /// 读一本书的清单（没有就 null）。
  Future<ComicOfflineBook?> loadBook(String bookUrl) async {
    final f = await _manifestFile(bookUrl);
    if (!await f.exists()) return null;
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return null;
      return ComicOfflineBook.fromJson(Map<String, dynamic>.from(raw));
    } on FormatException {
      // 清单坏了：当作没下过（**不抛**：读清单失败不该让整个离线页打不开）。
      return null;
    }
  }

  /// 写清单（先写临时文件再改名：写一半被打断不会留下半份 JSON）。
  Future<void> saveBook(ComicOfflineBook book) async {
    book.updatedAt = DateTime.now();
    final f = await _manifestFile(book.bookUrl);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(book.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  /// 所有下载过的书（按下载时间新的在前）。
  Future<List<ComicOfflineBook>> books() async {
    final dir = await _manifestDir();
    final out = <ComicOfflineBook>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final raw = jsonDecode(await e.readAsString());
        if (raw is Map) {
          out.add(ComicOfflineBook.fromJson(Map<String, dynamic>.from(raw)));
        }
      } on FormatException {
        // 坏掉的清单跳过。
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  // ── 统计与删除 ────────────────────────────────────────────────

  Future<int> _bytesIn(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is! File) continue;
      try {
        total += await e.length();
      } on FileSystemException {
        // 量不到就当 0：统计不该把删除动作本身挡下来。
      }
    }
    return total;
  }

  /// 一本书占多少字节（传了 [chapterUrl] 就只算那一话）。
  Future<int> bytesOf(String bookUrl, {String? chapterUrl}) async {
    final dir = await bookDir(bookUrl);
    if (chapterUrl == null) return _bytesIn(dir);
    return _bytesIn(Directory('${dir.path}/${hash(chapterUrl)}'));
  }

  /// 所有离线内容占多少字节。
  Future<int> totalBytes() async => _bytesIn(await rootDir());

  /// 删一话（图片 + 清单状态一起改：留着 done 计数会让"已下载"是假的）。
  Future<void> deleteChapter(String bookUrl, String chapterUrl) async {
    final book = await loadBook(bookUrl);
    final dir = await chapterDir(bookUrl, chapterUrl);
    if (await dir.exists()) await dir.delete(recursive: true);
    if (book == null) return;
    for (final c in book.chapters) {
      if (c.url == chapterUrl) {
        c.done = 0;
        c.bytes = 0;
        c.state = ComicOfflineState.none;
        c.error = '';
      }
    }
    if (book.doneCount == 0) {
      // 一话都没下完：清单也删掉（否则离线库里留一堆空壳书）。
      await deleteBook(bookUrl);
      return;
    }
    await saveBook(book);
  }

  /// 删整本（目录 + 清单）。
  Future<void> deleteBook(String bookUrl) async {
    final dir = await bookDir(bookUrl);
    if (await dir.exists()) await dir.delete(recursive: true);
    final f = await _manifestFile(bookUrl);
    if (await f.exists()) await f.delete();
  }

  /// 清掉"下了一半"留下的残渣（`.part`），返回释放了多少字节。
  ///
  /// 为什么要它（2026-10-02 核对占用口径时发现）：图片是"先写 `.part` 再改名"，
  /// 所以被杀掉 / 失败时会在离线目录里留下半张图的 `.part`；而 [totalBytes] 是
  /// 整目录递归求和 —— 这些残渣**会被算进"离线占用"**，既不会自愈、界面上也没有
  /// 任何入口能删掉它，用户只会看到"我明明没下过这么多"。
  ///
  /// 只删 24 小时前的：刚失败的那一张，同一个 `.part` 名字可能正被写（时间窗避开它），
  /// 而且下次重试会重写这个名字、不需要复用它。
  Future<int> purgePartials({
    Duration olderThan = const Duration(hours: 24),
  }) async {
    var freed = 0;
    final root = await _rootForCleanup();
    if (root == null) return 0;
    final cutoff = DateTime.now().subtract(olderThan);
    try {
      await for (final e in root.list(recursive: true)) {
        if (e is! File || !e.path.endsWith('.part')) continue;
        try {
          final st = await e.stat();
          if (st.modified.isAfter(cutoff)) continue;
          freed += st.size;
          await e.delete();
        } on FileSystemException {
          // 删不掉（正在写 / 权限）就跳过，下次启动再来：清理不该把主流程带崩。
        }
      }
    } on FileSystemException {
      // 目录读不了同理。
    }
    return freed;
  }

  /// 根目录，但**拿不到就算了**（不创建、不抛）：清理类动作用它。
  Future<Directory?> _rootForCleanup() async {
    final cached = _root;
    if (cached != null) return cached;
    try {
      return await rootDir();
    } catch (_) {
      return null;
    }
  }

  /// 清空全部离线内容。
  Future<void> clearAll() async {
    final root = await rootDir();
    if (await root.exists()) await root.delete(recursive: true);
    _root = null;
  }

  // ── 给阅读侧用的一条：这张图本机有没有 ─────────────────────────

  /// 离线命中（阅读页/封面优先问它）。没有就 null，**不发请求**。
  ///
  /// 读离线库出任何问题（目录拿不到、权限、IO 错）都当"没有"：这条路只是**加速**，
  /// 让它把联网那条路一起弄挂是最亏的（曾经就是这么挂的：拿不到 appSupport 目录时
  /// 整个封面报错，而覆盖网络请求只需要在这里返回 null）。
  Future<File?> localFile(String bookUrl, String chapterUrl, String imageUrl) async {
    try {
      final f = await fileFor(bookUrl, chapterUrl, imageUrl);
      return await f.exists() ? f : null;
    } catch (_) {
      return null;
    }
  }

  /// **同步**版离线命中：根目录还没预热好就返回 null（调用方直接走网络，别在渲染路径上等）。
  ///
  /// 这条是给**界面**用的：命中就是本机读盘（不发请求、也不等平台通道）。
  File? localFileIfReady(String bookUrl, String chapterUrl, String imageUrl) {
    final root = _root;
    if (root == null || bookUrl.isEmpty) return null;
    final f = File(
      '${root.path}/${hash(bookUrl)}/${hash(chapterUrl)}/${hash(imageUrl)}',
    );
    return f.existsSync() ? f : null;
  }

  /// **同步**版离线封面命中（同上）。
  File? localCoverIfReady(String bookUrl, String coverUrl) {
    final root = _root;
    if (root == null || bookUrl.isEmpty || coverUrl.isEmpty) return null;
    final f = File('${root.path}/${hash(bookUrl)}/cover/${hash(coverUrl)}');
    return f.existsSync() ? f : null;
  }

  // ── 封面 ──────────────────────────────────────────────────────
  //
  // 封面不归任何一话，所以单独一层：`<书哈希>/cover/<图哈希>`。
  // 没有它，断网时书架与详情页只剩一排破图标 —— "断网也能看"就缺了一块。

  Future<File> coverFile(String bookUrl, String coverUrl) async {
    final book = await bookDir(bookUrl);
    final dir = Directory('${book.path}/cover');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/${hash(coverUrl)}');
  }

  /// 离线封面命中（书架/详情页优先问它）。同样：出错就当没有（见 [localFile]）。
  Future<File?> localCover(String bookUrl, String coverUrl) async {
    if (coverUrl.isEmpty) return null;
    try {
      final f = await coverFile(bookUrl, coverUrl);
      return await f.exists() ? f : null;
    } catch (_) {
      return null;
    }
  }
}
