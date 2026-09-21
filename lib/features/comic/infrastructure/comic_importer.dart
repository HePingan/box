import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

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
/// - 解压只做**一次**：封面和页面来自同一个 [ComicExtraction]。
class ComicImporter {
  const ComicImporter._();

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
  static Future<ComicExtraction> extract(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final imageEntries = archive.files
        .where((e) => e.isFile && _isImageName(e.name))
        .toList()
      ..sort((a, b) => compareNatural(a.name, b.name));

    if (imageEntries.isEmpty) {
      return const ComicExtraction(pages: <String>[], coverPath: null);
    }

    // 整本只用一个临时目录。
    final outDir = await Directory.systemTemp.createTemp('comic_');

    final pages = <String>[];
    String? coverPath;
    for (var i = 0; i < imageEntries.length; i++) {
      final entry = imageEntries[i];
      final ext = p.extension(entry.name).toLowerCase();
      final index = i.toString().padLeft(_indexWidth, '0');
      final name = '${index}_${_hash(entry.name)}$ext';
      final outPath = p.join(outDir.path, name);
      await File(outPath).writeAsBytes(entry.content as Uint8List);
      pages.add(outPath);

      // 名字里带 cover / 封面的条目优先当封面（第一个命中的为准）。
      if (coverPath == null && _looksLikeCover(entry.name)) {
        final coverName = 'cover_${_hash(entry.name)}$ext';
        final coverOut = p.join(outDir.path, coverName);
        await File(coverOut).writeAsBytes(entry.content as Uint8List);
        coverPath = coverOut;
      }
    }

    return ComicExtraction(
      pages: pages,
      coverPath: coverPath ?? pages.first,
    );
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
