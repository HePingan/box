import 'dart:collection';

import 'package:flutter/painting.dart';

/// 一次分页所需的输入参数
class ReaderPaginationRequest {
  const ReaderPaginationRequest({
    required this.bookId,
    required this.chapterIndex,
    required this.content,
    required this.fitWidth,
    required this.firstPageHeight,
    required this.normalPageHeight,
    required this.fontSize,
    required this.lineHeight,
    this.letterSpacing = 0.6,
    this.fontFamily,
    this.textDirection = TextDirection.ltr,
    this.cacheSize = 16,
  });

  final String bookId;
  final int chapterIndex;
  final String content;

  /// 每页可用宽度
  final double fitWidth;

  /// 第一页可用高度
  final double firstPageHeight;

  /// 后续页可用高度
  final double normalPageHeight;

  final double fontSize;
  final double lineHeight;
  final double letterSpacing;

  /// 正文字体族。必须与渲染层 TextStyle.fontFamily 一致，
  /// 否则测量用的字形宽度与实际排版不符，会导致页底文字被裁。
  final String? fontFamily;

  final TextDirection textDirection;

  /// 内存缓存条数上限
  final int cacheSize;
}

// ──────────────────────────────────────────
// 增量分页结果
// ──────────────────────────────────────────

/// [paginateIncremental] 的返回值
class IncrementalPaginationResult {
  const IncrementalPaginationResult({
    required this.firstChunk,
    required this.remaining,
  });

  /// 首批可立即渲染的页面（≥ 1 页）
  final List<String> firstChunk;

  /// 异步迭代器，每次 moveNext() 返回一批后续页面
  final IncrementalPageIterator remaining;
}

/// 异步分页迭代器
class IncrementalPageIterator {
  final ReaderPaginationRequest _request;
  final int _chunkSize;
  final double _safeFirstH;
  final double _safeNormalH;
  TextStyle? _style;
  TextPainter? _painter;
  int _start;
  int _pagesProduced;

  IncrementalPageIterator({
    required ReaderPaginationRequest request,
    required int chunkSize,
    required double safeFirstH,
    required double safeNormalH,
    required int startOffset,
  })  : _request = request,
        _chunkSize = chunkSize,
        _safeFirstH = safeFirstH,
        _safeNormalH = safeNormalH,
        _start = startOffset,
        _pagesProduced = 0;

  /// 一个 always-done 的空迭代器
  IncrementalPageIterator.empty()
      : _request = const ReaderPaginationRequest(
          bookId: '',
          chapterIndex: 0,
          content: '',
          fitWidth: 0,
          firstPageHeight: 0,
          normalPageHeight: 0,
          fontSize: 14,
          lineHeight: 1.5,
        ),
        _chunkSize = 1,
        _safeFirstH = 0,
        _safeNormalH = 0,
        _start = 0,
        _pagesProduced = 0;

  /// 是否有更多页面
  bool get isDone => _start >= _request.content.length;

  /// 生成下一批页面（最多 [_chunkSize] 页）
  List<String> nextChunk() {
    if (_start >= _request.content.length) return const [];

    final text = _request.content;
    _style ??= TextStyle(
      fontSize: _request.fontSize,
      height: _request.lineHeight,
      letterSpacing: _request.letterSpacing,
      fontFamily: _request.fontFamily,
    );
    _painter ??= TextPainter(textDirection: _request.textDirection);

    final pages = <String>[];
    final painter = _painter!;
    final style = _style!;

    for (int i = 0; i < _chunkSize && _start < text.length; i++) {
      // 跳过开头连续换行，避免空白页
      while (_start < text.length && text[_start] == '\n') {
        _start++;
      }

      if (_start >= text.length) break;

      int low = _start;
      int high = text.length;
      int best = _start;

      final maxH = _pagesProduced == 0 ? _safeFirstH : _safeNormalH;

      while (low <= high) {
        final mid = low + ((high - low) ~/ 2);

        painter.text = TextSpan(text: text.substring(_start, mid), style: style);
        painter.layout(maxWidth: _request.fitWidth);

        if (painter.height <= maxH) {
          best = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }

      if (best <= _start) {
        best = _start + 1;
        if (best > text.length) best = text.length;
      }

      pages.add(text.substring(_start, best));
      _start = best;
      _pagesProduced++;
    }

    return pages;
  }
}

/// 阅读器分页工具
///
/// 职责：
/// - 将正文内容按当前字体/行距/宽高切成分页
/// - 内置一个简单的内存 LRU 缓存，避免重复计算
class ReaderPaginator {
  ReaderPaginator._();

  static final LinkedHashMap<String, List<String>> _cache =
      LinkedHashMap<String, List<String>>();

  /// 清空内存缓存，测试或切换大主题时可调用
  static void clearCache() {
    _cache.clear();
  }

  /// 执行全量分页（同步）
  static List<String> paginate(ReaderPaginationRequest request) {
    final key = _buildCacheKey(request);

    final cached = _cache.remove(key);
    if (cached != null) {
      // 重新插入，模拟 LRU 的“最近使用”
      _cache[key] = cached;
      return List<String>.from(cached);
    }

    final pages = _paginateAll(request);

    _cache[key] = List<String>.unmodifiable(pages);
    while (_cache.length > request.cacheSize) {
      _cache.remove(_cache.keys.first);
    }

    return List<String>.from(pages);
  }

  /// 增量分页：首批立即返回，后续通过 [IncrementalPageIterator] 异步获取
  ///
  /// [chunkSize] 控制每批生成的页数，默认 5。
  static IncrementalPaginationResult paginateIncremental(
    ReaderPaginationRequest request, {
    int chunkSize = 5,
  }) {
    final text = request.content;

    if (text.isEmpty) {
      return IncrementalPaginationResult(
        firstChunk: [''],
        remaining: IncrementalPageIterator.empty(),
      );
    }

    if (request.fitWidth <= 0 ||
        request.firstPageHeight <= 0 ||
        request.normalPageHeight <= 0) {
      return IncrementalPaginationResult(
        firstChunk: [text],
        remaining: IncrementalPageIterator.empty(),
      );
    }

    final safeFirstH =
        request.firstPageHeight < 80 ? 80.0 : request.firstPageHeight;
    final safeNormalH =
        request.normalPageHeight < 80 ? 80.0 : request.normalPageHeight;

    // 先取第一块
    final it = IncrementalPageIterator(
      request: request,
      chunkSize: chunkSize,
      safeFirstH: safeFirstH,
      safeNormalH: safeNormalH,
      startOffset: 0,
    );
    final firstChunk = it.nextChunk();

    return IncrementalPaginationResult(
      firstChunk: firstChunk,
      remaining: it,
    );
  }

  static String _buildCacheKey(ReaderPaginationRequest request) {
    // 使用稳定签名避免 hashCode 跨进程不一致（Dart 默认 hashCode 进程间随机）
    // 用 CRC32 替代内容片段，既稳定又抗碰撞
    final text = request.content;
    final signature = text.isEmpty ? 'empty' : 'crc32:${_crc32(text)}';

    return [
      request.bookId,
      request.chapterIndex.toString(),
      request.fitWidth.toStringAsFixed(1),
      request.firstPageHeight.toStringAsFixed(1),
      request.normalPageHeight.toStringAsFixed(1),
      request.fontSize.toStringAsFixed(1),
      request.lineHeight.toStringAsFixed(2),
      request.letterSpacing.toStringAsFixed(2),
      request.fontFamily ?? 'sysdefault',
      signature,
    ].join('|');
  }

  /// 简单 CRC32 实现（稳定、跨进程一致）
  static int _crc32(String text) {
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < text.length; i++) {
      var c = text.codeUnitAt(i);
      crc ^= c;
      for (var j = 0; j < 8; j++) {
        crc = (crc >>> 1) ^ (crc & 1 == 1 ? 0xEDB88320 : 0);
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// 全量计算（内部复用，供 [paginate] 使用）
  static List<String> _paginateAll(ReaderPaginationRequest request) {
    final text = request.content;

    if (text.isEmpty) {
      return <String>[''];
    }

    if (request.fitWidth <= 0 ||
        request.firstPageHeight <= 0 ||
        request.normalPageHeight <= 0) {
      return <String>[text];
    }

    final safeFirstH =
        request.firstPageHeight < 80 ? 80.0 : request.firstPageHeight;
    final safeNormalH =
        request.normalPageHeight < 80 ? 80.0 : request.normalPageHeight;

    final it = IncrementalPageIterator(
      request: request,
      chunkSize: 999999, // 一次性拿完
      safeFirstH: safeFirstH,
      safeNormalH: safeNormalH,
      startOffset: 0,
    );

    final pages = <String>[];
    while (!it.isDone) {
      pages.addAll(it.nextChunk());
    }

    if (pages.isEmpty) {
      pages.add(text);
    }

    return pages;
  }
}
