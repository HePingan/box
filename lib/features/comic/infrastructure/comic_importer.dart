import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/comic_book.dart';

/// 一次解压的产物：页面列表 + 封面。
class ComicExtraction {
  const ComicExtraction({required this.pages, this.coverPath});

  final List<String> pages;
  final String? coverPath;
}

/// 漫画导入器：CBZ/ZIP 解压、图片提取、文件夹扫描。
///
/// 实现要点（均有真实 zip 端到端测试锁住）：
/// - **自然序**排页：`2.jpg` 必须排在 `10.jpg` 之前，字典序会把页序排乱。
/// - 一本漫画只建**一个**临时目录，页文件带序号前缀；早先每页一个 temp 目录的
///   写法在几百页的大部头上会炸出上百个目录且无人清理。
/// - 解压目录落在**应用文档目录**（`comic_imported/时间戳`），不是系统临时目录：
///   路径会被记进 `ComicBook.pages` 长期使用，放临时目录的话系统清理后书会白页。
/// - 解压只做**一次**：封面和页面来自同一个 [ComicExtraction]。
class ComicImporter {
  const ComicImporter._();

  /// 解压产物落盘位置。
  ///
  /// 为什么不能留在系统临时目录：`ComicBook.pages` 里记的就是这些路径，
  /// 是**长期引用**而不是一次性中转。系统清临时目录（低存储、重启清理）之后，
  /// 书架上的书还在、点开全是白页，而且备份只存元数据、不存图片，等于丢了。
  ///
  /// 默认放 `应用文档目录/comic_imported/<时间戳-随机>/`。目录本身不自动清理：
  /// 一本书一份，粒度与书一致，用户删书时才有机会连带删（见 ComicImporter.disposePages）。
  static Future<Directory> Function() importRoot =
      _defaultImportRoot;

  static Future<Directory> _defaultImportRoot() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/comic_imported');
  }

  /// 单测/宿主注入用：恢复默认实现。
  static void resetImportRoot() {
    importRoot = _defaultImportRoot;
  }

  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
    '.gif',
    '.avif',
  };

  /// 解出的页文件名前缀宽度（`00007_ab12cd34.jpg`）。
  static const int _indexWidth = 5;

  /// 判断是否为支持的漫画压缩包格式。
  static bool isComicFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.cbz' || ext == '.zip';
  }

  /// 一次性解压：同时拿到页面列表与封面，避免重复解包。
  ///
  /// 损坏文件**必须抛出**而不是返回空列表：调用方对"空"的提示是
  /// 「文件中没有找到图片」，对"坏"的提示是「导入失败: ...」—— 两者对用户
  /// 是不同的事。archive 4.x 起 `decodeBytes` 对垃圾字节不再抛，而是返回一个
  /// 空归档，所以这里自己补一道校验（见下面的 `files.isEmpty`）。
  static Future<ComicExtraction> extract(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 损坏文件**必须抛出**而不是返回空列表：调用方对"空"的提示是
    // 「文件中没有找到图片」，对"坏"的提示是「导入失败: ...」—— 对用户是不同的事。
    //
    // 为什么不能只看 `archive.files.isEmpty`：**合法的空 zip** 也是空归档，
    // 那属于"没有图片"而不是"文件坏了"（有专门的用例锁着这个区别）。
    // archive 4.x 起 decodeBytes 对垃圾字节不再抛，所以这里按**压缩包签名**判：
    // zip 必须以 `PK\x03\x04`（或空归档的 `PK\x05\x06`）开头。
    if (!_looksLikeZip(bytes)) {
      throw const FormatException('这个文件不是有效的 CBZ/ZIP（读不出压缩包结构，可能已损坏）');
    }

    final imageEntries = archive.files
        .where((e) => e.isFile && _isImageName(e.name))
        .toList()
      ..sort((a, b) => compareNatural(a.name, b.name));

    if (imageEntries.isEmpty) {
      return const ComicExtraction(pages: <String>[], coverPath: null);
    }

    // 整本只用一个目录（不是每页一个），且落在文档目录下而不是系统临时目录。
    final root = await importRoot();
    if (!await root.exists()) await root.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final outDir = Directory(p.join(root.path, '$stamp'));
    await outDir.create(recursive: true);

    final pages = <String>[];
    String? coverPath;
    for (var i = 0; i < imageEntries.length; i++) {
      final entry = imageEntries[i];
      final ext = p.extension(entry.name).toLowerCase();
      final index = i.toString().padLeft(_indexWidth, '0');
      final name = '${index}_${_hash(entry.name)}$ext';
      final outPath = p.join(outDir.path, name);
      // archive 4.x 起 entry.content 已是 Uint8List（3.x 是 dynamic，需要强转）。
      await File(outPath).writeAsBytes(entry.content);
      pages.add(outPath);

      // 名字里带 cover / 封面的条目优先当封面（第一个命中的为准）。
      if (coverPath == null && _looksLikeCover(entry.name)) {
        final coverName = 'cover_${_hash(entry.name)}$ext';
        final coverOut = p.join(outDir.path, coverName);
        await File(coverOut).writeAsBytes(entry.content);
        coverPath = coverOut;
      }
    }

    return ComicExtraction(
      pages: pages,
      coverPath: coverPath ?? pages.first,
    );
  }

  /// 删除一本书的解压产物（只删落在 [importRoot] 里的目录）。
  ///
  /// **只删我们自己的解压目录**：`folder` 类型的书指向用户自己的文件夹、
  /// `file` 类型的原包也在用户选择的位置，这些一律不碰 —— 删除收藏永远不该
  /// 动用户的原件（界面文案就是这么承诺的）。
  ///
  /// 返回释放的字节数；目录已不在（老版本导出的书）时返回 0。
  static Future<int> disposePages(ComicBook book) async {
    if (book.pages.isEmpty) return 0;
    final roots = <String>{};
    for (final page in book.pages) {
      roots.add(p.dirname(page));
    }

    final importDir = (await importRoot()).path;
    var freed = 0;
    for (final dirPath in roots) {
      // isWithin 是按路径段判断的（不是字符串前缀）：/data/comic_importedX
      // 不会被当成 /data/comic_imported 的子目录，用户自己的文件夹也不会被删。
      if (!p.isWithin(importDir, p.normalize(dirPath))) continue;
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      await for (final item in dir.list(recursive: true)) {
        if (item is File) {
          try {
            freed += await item.length();
          } on FileSystemException {
            // 量不到就跳过，别让删除整个卡住。
          }
        }
      }
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // 被占用（正在阅读）：下次再说，不要因此让删除收藏失败。
      }
    }
    return freed;
  }

  /// 字节是否像 zip：以 `PK\x03\x04`（有条目）或 `PK\x05\x06`（空归档）开头。
  ///
  /// 只看签名、不做完整校验：目标是区分「垃圾字节」与「合法但没图片的包」，
  /// 后者必须保持"返回空列表"的既有语义（有测试锁着）。
  static bool _looksLikeZip(List<int> bytes) {
    const p1 = 0x50, p2 = 0x4B;
    if (bytes.length < 4) return false;
    if (bytes[0] != p1 || bytes[1] != p2) return false;
    final tag = bytes[2] << 8 | bytes[3];
    return tag == 0x0304 || tag == 0x0506 || tag == 0x0708 || tag == 0x0102;
  }

  /// 从 CBZ/ZIP 提取页面列表（自然序）。
  static Future<List<String>> extractPages(String filePath) async {
    return (await extract(filePath)).pages;
  }

  /// 提取封面：优先名字里带 cover/封面的条目，否则回落到第一页。
  static Future<String?> extractCover(String filePath) async {
    return (await extract(filePath)).coverPath;
  }

  /// 从文件夹导入（递归扫描图片，自然序）。
  static Future<List<String>> extractPagesFromFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return <String>[];

    final files = dir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) => _isImageName(f.path))
        .map((f) => f.path)
        .toList()
      ..sort(compareNatural);

    return files;
  }

  /// 自然序比较：把数字段按数值比，其余按字符比。
  ///
  /// `page2.jpg` < `page10.jpg`（字典序会反过来）。
  static int compareNatural(String a, String b) {
    final ax = _chunk(a.toLowerCase());
    final bx = _chunk(b.toLowerCase());

    for (var i = 0; i < ax.length && i < bx.length; i++) {
      final left = ax[i];
      final right = bx[i];
      final int cmp;
      if (left is int && right is int) {
        cmp = left.compareTo(right);
      } else {
        cmp = left.toString().compareTo(right.toString());
      }
      if (cmp != 0) return cmp;
    }
    return ax.length.compareTo(bx.length);
  }

  /// 把字符串切成「文字段 / 数字段」序列。
  static List<Object> _chunk(String input) {
    final chunks = <Object>[];
    final buffer = StringBuffer();
    bool? bufferIsDigit;

    void flush() {
      if (buffer.isEmpty) return;
      final text = buffer.toString();
      chunks.add(bufferIsDigit == true ? (int.tryParse(text) ?? 0) : text);
      buffer.clear();
    }

    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final isDigit = rune >= 0x30 && rune <= 0x39;
      if (bufferIsDigit != null && isDigit != bufferIsDigit) flush();
      bufferIsDigit = isDigit;
      buffer.write(ch);
    }
    flush();
    return chunks;
  }

  /// 测试辅助：从解出的页文件名读回它的排序序号（0 基）。
  static int debugPageOrderKey(String pagePath) {
    final name = p.basename(pagePath);
    final head = name.split('_').first;
    return int.tryParse(head) ?? -1;
  }

  static bool _isImageName(String name) =>
      _imageExtensions.contains(p.extension(name).toLowerCase());

  static bool _looksLikeCover(String name) {
    final lower = p.basename(name).toLowerCase();
    return lower.contains('cover') || lower.contains('封面');
  }

  static String _hash(String input) =>
      md5.convert(input.codeUnits).toString().substring(0, 8);
}
